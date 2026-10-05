import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' show field;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List).cast<Map>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('Named VES item, budget and debt spacing $width $dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() => app.state['darkMode'] = dark);
        Map<String, dynamic>? item;
        app
            .pushPage<Map<String, dynamic>>(
              tester.element(find.byType(HomePage)),
              (_) => BudgetCategoryEditorPage(
                app: app,
                siblings: const [
                  {'category': 'Deuda', 'name': 'Gabriel', 'limit': 50.0},
                ],
              ),
            )
            .then((dynamic value) => item = value as Map<String, dynamic>?);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Categor\u00eda'));
        await tester.pumpAndSettle();
        await tester.enterText(field('Buscar'), 'Deuda');
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ModernSheetTile),
            matching: find.text('Deuda'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(field('Nombre de la partida'), 'Arturo');
        await tester.tap(find.text('Moneda'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(displayCurrency('VES')));
        await tester.pumpAndSettle();
        await tester.enterText(
          field('L\u00edmite del periodo en VES'),
          '10000',
        );
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/feedback-qa/item-$width-$dark.png'),
          );
        }
        await tester.tap(find.text('Guardar partida'));
        await tester.pumpAndSettle();
        expect(item!['currency'], 'VES');
        expect(item!['limit'], 10000);
        expect(item!['category'], 'Deuda');
        expect(item!['name'], 'Arturo');
        saveBudgetPlan(
          app,
          period: currentMonthKey(),
          type: 'monthly',
          salary: 2000,
          savings: 20,
          items: [
            item!,
            {
              'category': 'Deuda',
              'name': 'Gabriel',
              'currency': 'USD',
              'limit': 50.0,
            },
          ],
        );
        await tester.pump(const Duration(seconds: 4));
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => BudgetPage(app: app),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Arturo'));
        expect(find.text('Gabriel'), findsOneWidget);
        expect(find.text('de Bs. 10.000,00'), findsOneWidget);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/feedback-qa/plan-$width-$dark.png'),
          );
        }
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        app.openDebtDetail(
          tester.element(find.byType(HomePage)),
          app.debtById('d'),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Editar registro'));
        final pay = tester.getRect(
          find.widgetWithText(PrimaryActionButton, 'Registrar pago'),
        );
        final partial = tester.getRect(
          find.byKey(const ValueKey('debt-partial-payment')),
        );
        expect(partial.top - pay.bottom, greaterThanOrEqualTo(12));
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/feedback-qa/debt-$width-$dark.png'),
          );
        }
        await tester.ensureVisible(find.text('Marcar como pagado'));
        await tester.tap(find.text('Marcar como pagado'));
        await tester.pumpAndSettle();
        expect(find.text('Liquidar toda la deuda'), findsOneWidget);
        expect(app.debtById('d')['paidAmount'], 90);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(app.debtById('d')['paidAmount'], 90);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
