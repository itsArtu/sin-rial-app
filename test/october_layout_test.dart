import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' as budgets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final item in manifest.cast<Map>()) {
      final loader = FontLoader(item['family'] as String);
      for (final font in (item['fonts'] as List).cast<Map>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final name in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF Pro Display',
      'Roboto',
    ]) {
      await (FontLoader(name)..addFont(Future.value(bytes))).load();
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  testWidgets(
    'Startup loader uses cached accent before loading protected state',
    (tester) async {
      final state = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            if (call.method == 'readAppearance')
              return {'darkMode': true, 'themeColor': 'violet'};
            if (call.method == 'readState') return state.future;
            return null;
          });
      await tester.pumpWidget(const RialBootstrap());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final loader = tester.widget<RialLoadingIndicator>(
        find.byType(RialLoadingIndicator),
      );
      expect(loader.color, RTheme(true, 'violet').accent);
      await tester.pumpWidget(const SizedBox.shrink());
      state.complete(jsonEncode(defaultState()));
      await tester.pump();
    },
  );

  testWidgets(
    'Category search always offers creation and selects the saved category',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      String? chosen;
      pickCategory(
        tester.element(find.byType(HomePage)),
        'Otro',
        (value) => chosen = value,
      );
      await tester.pumpAndSettle();
      await tester.enterText(budgets.field('Buscar'), 'categoria inexistente');
      await tester.pumpAndSettle();
      expect(find.text('Crear categoría'), findsOneWidget);
      await tester.tap(find.text('Crear categoría'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomCategoryEditor), findsOneWidget);
      await tester.enterText(budgets.field('Nombre'), 'Mi categoria nueva');
      await tester.ensureVisible(find.text('Guardar categoría'));
      await tester.tap(find.text('Guardar categoría'));
      await tester.pumpAndSettle();
      expect(chosen, 'Mi categoria nueva');
      expect(app.state['customCategories'], isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final dark in [true, false]) {
      testWidgets(
        'Appearance, accounts, installments and plan fit $width dark=$dark',
        (tester) async {
          final dynamic app = await fixtures.fixture(tester);
          tester.view.physicalSize = Size(width, 844);
          app.mutate(() {
            app.state['darkMode'] = dark;
            app.state['themeColor'] = 'cyan';
            app.state['eurRate'] = 11.2;
            app.debtById('d').addAll({
              'amount': 60.0,
              'paidAmount': 0.0,
              'hasInstallments': true,
              'hasDueDate': true,
              'installments': 3,
              'dueDate': '20/10/2026',
            });
          });
          Future<void> capture(String label) async {
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
              for (final element in find.byType(Image).evaluate().toList()) {
                await tester.runAsync(
                  () => precacheImage((element.widget as Image).image, element),
                );
              }
              await tester.pumpAndSettle();
              await expectLater(
                find.byType(RialApp),
                matchesGoldenFile(
                  '../build/october-qa/$label-$width-$dark.png',
                ),
              );
            }
          }

          final context = tester.element(find.byType(HomePage));
          app.pushPage(
            context,
            (_) => SettingsPage(app: app, section: 'Apariencia'),
          );
          await capture('appearance');
          expect(find.byType(ThemeColorSelector), findsOneWidget);
          final colorA = tester.getRect(find.text('Amarillo'));
          final colorB = tester.getRect(find.text('Azul'));
          final colorC = tester.getRect(find.text('Cian'));
          expect(colorA.top, colorB.top);
          expect(colorB.top, colorC.top);
          await tester.tap(find.text('Morado'));
          await tester.pumpAndSettle();
          expect(app.state['themeColor'], 'violet');
          app.rootNavigatorKey.currentState.pop();
          await tester.pumpAndSettle();
          app.pushPage(context, (_) => AccountsPage(app: app));
          await capture('accounts');
          final row = find.byWidgetPredicate(
            (w) => w is AccountRow && w.account['id'] == 'b',
          );
          final amount = find.descendant(
            of: row,
            matching: find.text('Bs. 100,00'),
          );
          expect(
            tester.getRect(row).right - tester.getRect(amount).right,
            lessThanOrEqualTo(20),
          );
          app.rootNavigatorKey.currentState.pop();
          await tester.pumpAndSettle();
          app.openDebtDetail(context, app.debtById('d'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('debt-installment-2')),
          );
          await capture('installments');
          await tester.tap(find.byKey(const ValueKey('debt-installment-2')));
          await tester.pumpAndSettle();
          final dynamic editor = tester.state(find.byType(MovementEditor));
          expect(editor.debtInstallmentIndex, 2);
          expect(parseAmount(editor.amount.text), 200);
          app.rootNavigatorKey.currentState.pop();
          await tester.pumpAndSettle();
          app.rootNavigatorKey.currentState.pop();
          await tester.pumpAndSettle();
          budgets.plan(
            app,
            currentMonthKey(),
            items: [
              {
                'category': 'Barbería',
                'name': 'Afeitada',
                'limit': 25.0,
                'currency': 'EUR',
              },
            ],
          );
          app.saveMovement({
            ...fixtures.movement('expense', amount: 28),
            'category': 'Barbería',
            'date': formatDateTime(DateTime.now()),
          });
          await tester.pump(const Duration(seconds: 5));
          app.setTab(1);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(BudgetCategoryTile));
          await capture('planning');
          expect(find.byType(BudgetCategoryTile), findsOneWidget);
          expect(find.text('Afeitada'), findsNothing);
          expect(find.text('Asignar'), findsNothing);
          app.pushPage(
            tester.element(find.byType(BudgetPage)),
            (_) => BudgetCategoryEditorPage(app: app),
          );
          await capture('category-limit');
          await tester.tap(find.text('Categor\u00eda'));
          await tester.pumpAndSettle();
          await tester.enterText(budgets.field('Buscar'), 'inexistente');
          await capture('category-search');
          expect(find.text('Crear categor\u00eda'), findsOneWidget);
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          app.rootNavigatorKey.currentState.pop();
          await tester.pumpAndSettle();
          app.mutate(() => app.state['seenFeatureTour'] = '');
          await capture('tour');
          expect(find.text('Omitir'), findsOneWidget);
          await tester.tap(find.text('Omitir'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
