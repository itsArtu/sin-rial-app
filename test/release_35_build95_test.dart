import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart' as charts;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'monthly_spending_test.dart' as reports;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        ),
  );

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
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final name in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF Pro Display',
      'Roboto',
    ]) {
      await (FontLoader(name)..addFont(Future.value(font))).load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    for (final element in find.byType(Image).evaluate().toList()) {
      await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element),
      );
    }
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(RialApp),
      matchesGoldenFile('../build/release97-qa/$name.png'),
    );
  }

  test('Drilldown contributions reconcile categories, fees and accounts', () {
    final expense = reports.entry('expense', 10, fee: .3);
    final transfer = reports.entry('transfer', 800, fee: 2);
    final fee = reports.entry(
      'expense',
      1,
      category: 'Comisiones bancarias',
      fee: .2,
    );
    final report = summarizeMonthlySpending(
      state: defaultState(),
      month: '2026-09',
      movements: [
        expense,
        transfer,
        fee,
        reports.entry('income', 100),
        reports.entry('expense', 50, date: '01/10/2026 12:00 AM'),
      ],
    );
    expect(report.categories['Comida']!.movementAmounts, {expense: 10});
    expect(report.categories['Comisiones bancarias']!.movementAmounts, {
      expense: .3,
      transfer: 2,
      fee: 1.2,
    });
    expect(report.accounts['a']!.movementAmounts, {
      expense: 10.3,
      transfer: 2,
      fee: 1.2,
    });
    for (final group in [
      ...report.categories.values,
      ...report.accounts.values,
    ]) {
      expect(
        group.movementAmounts.values.fold(0.0, (a, b) => a + b),
        closeTo(group.usd, .001),
      );
    }
    final filtered = summarizeMonthlySpending(
      state: defaultState(),
      month: '2026-09',
      accountId: 'b',
      movements: [expense, transfer, fee],
    );
    expect(filtered.categories, isEmpty);
  });

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    for (final dark in [true, false]) {
      final suffix = '${size.width.toInt()}-$dark';
      testWidgets(
        'Account controls, visible facts and swapped keypad $suffix',
        (tester) async {
          final dynamic app = await fixtures.fixture(tester);
          tester.view.physicalSize = size;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          addTearDown(tester.view.resetPadding);
          app.mutate(() {
            app.state['darkMode'] = dark;
            app.state['accounts'][0].addAll({
              'kind': 'national',
              'provider': '0172',
              'currency': 'VES',
              'balance': 20000.0,
            });
            app.state['accounts'][1].addAll({
              'kind': 'wallet',
              'provider': 'BINANCE',
              'currency': 'USD',
            });
          });
          app.openMovementEditor(
            tester.element(find.byType(HomePage)),
            defaultAccountId: 'a',
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('composer-currency-selector')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('composer-details')), findsNothing);
          expect(find.text('Equivalente BCV'), findsOneWidget);
          expect(find.text('Total a debitar'), findsOneWidget);
          final dynamic editor = tester.state(find.byType(MovementEditor));
          for (final digit in ['1', '2', '3']) {
            await tester.tap(find.byKey(ValueKey('keypad-$digit')));
            await tester.pump();
          }
          await tester.tap(find.byKey(const ValueKey('keypad-back')));
          await tester.pumpAndSettle();
          expect(parseAmount(editor.amount.text), 12);
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('keypad-back'))).dy,
            tester.getTopLeft(find.byKey(const ValueKey('keypad-1'))).dy,
          );
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('keypad-clear'))).dy,
            tester.getTopLeft(find.byKey(const ValueKey('keypad-0'))).dy,
          );
          final scroll = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byKey(const ValueKey('movement-editor-fields')),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          expect(scroll.maxScrollExtent, 0);
          await capture(tester, 'visible-expense-$suffix');
          await tester.tap(find.byKey(const ValueKey('keypad-clear')));
          await tester.pump();
          expect(parseAmount(editor.amount.text), 0);
          await tester.tap(find.byKey(const ValueKey('composer-account')));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ModernSheetTile).last);
          await tester.pumpAndSettle();
          expect(editor.accountId, 'b');
          expect(
            tester.widget<ComposerAmount>(find.byType(ComposerAmount)).currency,
            'USD',
          );
          expect(find.text('Equivalente BCV'), findsNothing);
          editor.changeType('income');
          await tester.pumpAndSettle();
          expect(find.text('Ingreso neto'), findsOneWidget);
          expect(find.byKey(const ValueKey('composer-details')), findsNothing);
          await capture(tester, 'visible-income-$suffix');
          await tester.pageBack();
          await tester.pumpAndSettle();
          app.setTab(2);
          await tester.pumpAndSettle();
          final heading = tester.widget<Text>(find.text('Gestión financiera'));
          expect(heading.style!.fontSize, 18);
          expect(heading.style!.fontWeight, FontWeight.w700);
          await capture(tester, 'menu-headings-$suffix');
          app.pushPage(
            tester.element(find.byType(ModernMenu)),
            (_) => CategoriesPage(app: app),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('create-category')).hitTestable(),
            findsOneWidget,
          );
          await capture(tester, 'category-catalog-$suffix');
          final search = find.descendant(
            of: find.byKey(const ValueKey('categories-search')),
            matching: find.byType(EditableText),
          );
          await tester.enterText(search, 'educacion');
          await tester.pumpAndSettle();
          expect(find.text('Educación'), findsOneWidget);
          expect(find.text('Comida'), findsNothing);
          await tester.enterText(search, 'no existe');
          await tester.pumpAndSettle();
          expect(find.text('Sin resultados'), findsOneWidget);
          await tester.enterText(search, '');
          await tester.tap(find.byKey(const ValueKey('create-category')));
          await tester.pumpAndSettle();
          expect(find.byType(CustomCategoryEditor), findsOneWidget);
          await tester.enterText(
            find.byWidgetPredicate(
              (w) => w is CupertinoTextField && w.placeholder == 'Nombre',
            ),
            'Estudio',
          );
          await tester.scrollUntilVisible(
            find.text('Guardar categoría'),
            250,
            scrollable: find
                .descendant(
                  of: find.byType(CustomCategoryEditor),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.drag(
            find.descendant(
              of: find.byType(CustomCategoryEditor),
              matching: find.byType(ListView),
            ),
            const Offset(0, -160),
          );
          await tester.pumpAndSettle();
          expect(find.text('Guardar categoría').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Guardar categoría'));
          await tester.pumpAndSettle();
          expect(find.text('Estudio'), findsOneWidget);
          await capture(tester, 'category-created-$suffix');
          await tester.tap(find.text('Estudio'));
          await tester.pumpAndSettle();
          expect(find.text('Editar categoría'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'Pie, category and account open only corresponding monthly movements',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() {
        app.state['movements'] = reports.ledger();
        app.state['accounts'][0]['provider'] = 'BINANCE';
        app.state['accounts'][1]['provider'] = '0172';
      });
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => MonthlySpendingPage(app: app, initialMonth: '2026-09'),
      );
      await tester.pumpAndSettle();
      final pie = find.byType(charts.PieChart);
      await tester.ensureVisible(pie);
      await tester.pumpAndSettle();
      final data = tester.widget<charts.PieChart>(pie).data;
      final total = data.sections.fold(0.0, (sum, s) => sum + s.value);
      final angle =
          (-90 + data.sections.first.value / total * 180) * math.pi / 180;
      await tester.tapAt(
        tester.getCenter(pie) +
            Offset(math.cos(angle) * 57, math.sin(angle) * 57),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MonthlySpendingMovementsPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('monthly-drill-expense-9000.0-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('monthly-drill-expense-1500.0-a')),
        findsNothing,
      );
      await capture(tester, 'monthly-pie-drill');
      await tester.tap(
        find.byKey(const ValueKey('monthly-drill-expense-9000.0-b')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MovementDetailPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final category = find.byKey(
        const ValueKey('monthly-spending-category-Transporte'),
      );
      await tester.scrollUntilVisible(
        category,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('monthly-spending-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(category);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('monthly-drill-expense-1500.0-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('monthly-drill-expense-9000.0-b')),
        findsNothing,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      final selector = find.byType(AppPillSelector);
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      tester.widget<AppPillSelector>(selector).onChanged('account');
      await tester.pumpAndSettle();
      final account = find.byKey(const ValueKey('monthly-spending-account-b'));
      await tester.ensureVisible(account);
      await tester.pumpAndSettle();
      await tester.tap(account);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('monthly-drill-expense-9000.0-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('monthly-drill-income-300.0-a')),
        findsNothing,
      );
      await capture(tester, 'monthly-account-drill');
      app.mutate(() => app.state['hideAmounts'] = true);
      await tester.pumpAndSettle();
      expect(find.text(money(90, 'USD')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Identical pie labels keep their distinct account index', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 340,
            child: MonthlyDistributionChart(
              theme: RTheme(true, 'mint'),
              entries: const [
                ('Cuenta', 0, CupertinoColors.activeBlue),
                ('Cuenta', 10, CupertinoColors.activeBlue),
                ('Cuenta', 10, CupertinoColors.activeBlue),
              ],
              onSelected: (index) => selected = index,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(charts.PieChart));
    await tester.tapAt(center + const Offset(-57, 0));
    await tester.pumpAndSettle();
    expect(selected, 2);
    await tester.tapAt(center + const Offset(57, 0));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });
}
