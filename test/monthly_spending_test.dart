import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

Map<String, dynamic> entry(
  String type,
  double amount, {
  String account = 'a',
  String currency = 'USD',
  String category = 'Comida',
  String date = '16/09/2026 11:00 AM',
  double fee = 0,
}) => {
  'id': '$type-$amount-$account',
  'type': type,
  'amount': amount,
  'accountId': account,
  'currency': currency,
  'category': category,
  'date': date,
  'feeAmount': fee,
};

List<Map<String, dynamic>> ledger() => [
  entry('income', 300),
  entry('expense', 1500, currency: 'VES', category: 'Pasaje')
    ..['bcvUsdRate'] = 100.0,
  entry('expense', 9000, currency: 'VES', account: 'b')..['bcvUsdRate'] = 100.0,
  entry('expense', 25, date: '01/10/2026 12:00 AM'),
  entry('income', 1000, date: '31/08/2026 11:59 PM'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });
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
    for (final family in [
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Ahem',
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Manrope-Medium.ttf'))).load();
    }
  });

  test(
    'Monthly native totals, category aliases and income shares reconcile',
    () {
      final state = defaultState()..['rate'] = 999.0;
      final movements = ledger();
      final before = jsonEncode(movements);
      final report = summarizeMonthlySpending(
        state: state,
        movements: movements,
        month: '2026-09',
      );
      expect(report.income.usd, 300);
      expect(report.expenses.usd, 105);
      expect(report.expenses.nativeAmounts, {'VES': 10500});
      expect(report.incomePercent(report.categories['Transporte']!), 5);
      expect(report.incomePercent(report.categories['Comida']!), 30);
      expect(report.accounts['a']!.usd, 15);
      expect(report.accounts['b']!.usd, 90);
      expect(report.categories.containsKey('Pasaje'), isFalse);
      expect(jsonEncode(movements), before);
    },
  );

  test(
    'An account filter does not remove monthly income in other accounts',
    () {
      final report = summarizeMonthlySpending(
        state: defaultState(),
        movements: ledger(),
        month: '2026-09',
        accountId: 'b',
      );
      expect(report.income.usd, 300);
      expect(report.expenses.usd, 90);
      expect(report.incomePercent(report.expenses), 30);
      expect(report.accounts.keys, ['b']);
      expect(report.categories.keys, ['Comida']);
    },
  );

  test('Transfer principal is excluded, fees are counted exactly once', () {
    final report = summarizeMonthlySpending(
      state: defaultState(),
      movements: [
        entry('income', 1000),
        entry('transfer', 800, fee: 2),
        entry('expense', 10, fee: .3),
        entry('expense', 1, category: 'Comisiones bancarias'),
        entry('adjustment', 10000),
      ],
      month: '2026-09',
    );
    expect(report.income.usd, 1000);
    expect(report.expenses.usd, 13.3);
    expect(report.categories['Comida']!.usd, 10);
    expect(report.categories['Comisiones bancarias']!.usd, 3.3);
    expect(report.accounts['a']!.usd, 13.3);
  });

  test('EUR uses dated BCV and USD/USDT keep parity', () {
    final report = summarizeMonthlySpending(
      state: defaultState(),
      movements: [
        entry('income', 100),
        entry('expense', 10, currency: 'EUR')
          ..addAll({'bcvUsdRate': 100, 'bcvEurRate': 120}),
        entry('expense', 10, currency: 'USDT'),
        entry('expense', 10),
      ],
      month: '2026-09',
    );
    expect(report.expenses.usd, 32);
    expect(report.categories['Comida']!.nativeAmounts, {
      'EUR': 10,
      'USDT': 10,
      'USD': 10,
    });
    expect(report.incomePercent(report.expenses), 32);
  });

  test(
    'Missing historic quotes retain originals and suppress incomplete shares',
    () {
      final report = summarizeMonthlySpending(
        state: defaultState()..['rate'] = 10,
        movements: [
          entry('income', 100),
          entry('expense', 2000, currency: 'VES'),
        ],
        month: '2026-09',
      );
      expect(report.expenses.nativeAmounts, {'VES': 2000});
      expect(report.expenses.missingRates, 1);
      expect(report.incomePercent(report.expenses), isNull);
      expect(report.expenses.usd, 0);
      final missingIncome = summarizeMonthlySpending(
        state: defaultState(),
        movements: [
          entry('income', 100, currency: 'VES'),
          entry('expense', 10),
        ],
        month: '2026-09',
      );
      expect(missingIncome.income.missingRates, 1);
      expect(missingIncome.incomePercent(missingIncome.expenses), isNull);
    },
  );

  test(
    'Zero income and spending over income do not invent or clamp percentages',
    () {
      final noIncome = summarizeMonthlySpending(
        state: defaultState(),
        movements: [entry('expense', 50)],
        month: '2026-09',
      );
      expect(noIncome.incomePercent(noIncome.expenses), isNull);
      final over = summarizeMonthlySpending(
        state: defaultState(),
        movements: [entry('income', 10), entry('expense', 15)],
        month: '2026-09',
      );
      expect(over.incomePercent(over.expenses), 150);
    },
  );

  test(
    'Legacy records resolve Friday advance without using a transfer quote',
    () {
      final state = defaultState()
        ..['bcvRateHistory'] = normalizeBcvHistory([
          {'date': '2026-09-25', 'USD': 100},
          {
            'date': '2026-09-28',
            'USD': 125,
            'updated_at': '2026-09-25T21:00:00Z',
          },
        ]);
      final report = summarizeMonthlySpending(
        state: state,
        movements: [
          entry('income', 100),
          entry('expense', 1000, currency: 'VES', date: '25/09/2026 06:15 PM')
            ..['rate'] = 999,
        ],
        month: '2026-09',
      );
      expect(report.expenses.usd, 8);
      expect(report.expenses.missingRates, 0);
    },
  );

  testWidgets('Menu and movement history both open the monthly report', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.setTab(2);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Resumen mensual'));
    await tester.tap(find.text('Resumen mensual'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthlySpendingPage), findsOneWidget);
    app.rootNavigatorKey.currentState.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movimientos').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Resumen mensual'));
    await tester.tap(find.text('Resumen mensual'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthlySpendingPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Monthly report navigates, filters and hides amounts at $width',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() => app.state['movements'] = ledger());
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (BuildContext context) =>
              MonthlySpendingPage(app: app, initialMonth: '2026-09'),
        );
        await tester.pumpAndSettle();
        expect(find.text('35,0% de los ingresos del mes'), findsOneWidget);
        final total = find.byKey(const ValueKey('monthly-spending-total'));
        expect(tester.widget<DebtDetailRow>(total).value, r'$105,00');
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/monthly-qa/report-${width.toInt()}.png',
            ),
          );
        }
        await tester.tap(
          find.byKey(const ValueKey('monthly-spending-account')),
        );
        await tester.pumpAndSettle();
        final action = find.descendant(
          of: find.byType(ModernSheet),
          matching: find.text(accountLabel(app.accountById('b'))),
        );
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(tester.widget<DebtDetailRow>(total).value, r'$90,00');
        expect(find.text('30,0% de los ingresos del mes'), findsOneWidget);
        await tester.tap(find.text('Cuentas').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('monthly-spending-account-b')),
          findsOneWidget,
        );
        app.mutate(() => app.state['hideAmounts'] = true);
        await tester.pumpAndSettle();
        expect(find.text('30,0% de los ingresos del mes'), findsNothing);
        expect(
          tester.widget<DebtDetailRow>(total).value,
          app.secureMoney(90.0, 'USD'),
        );
        await tester.tap(find.byKey(const ValueKey('monthly-spending-month')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(monthLabelForKey('2026-10')));
        await tester.pumpAndSettle();
        expect(
          find.text('Sin gastos en este mes para esta cuenta'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
