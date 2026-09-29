import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

Map<String, dynamic> quote(
  String date,
  double usd, {
  double eur = 120,
  String? effective,
  String? published,
}) => {
  'date': date,
  'effective_date': effective ?? date,
  'USD': usd,
  'EUR': eur,
  'updated_at': published ?? '${date}T00:00:00Z',
};

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
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test('History preserves older USD-only dates and rejects invalid quotes', () {
    final history = normalizeBcvHistory([
      quote('2021-09-27', 4.2, eur: 0),
      quote('2026-09-29', 850),
      quote('2026-02-31', 100),
      quote('2026-09-28', double.nan),
      quote('2026-09-29', 900, published: '2026-09-28T00:00:00Z'),
    ]);
    expect(history.length, 2);
    expect(history['2021-09-27']['USD'], 4.2);
    expect(history['2021-09-27']['EUR'], 0);
    expect(history['2026-09-29']['USD'], 850);
  });

  test('Dated BCV honors midnight, Friday 18:00 and publication time', () {
    final state = defaultState()
      ..addAll({
        'rate': 999.0,
        'bcvRateHistory': normalizeBcvHistory([
          quote('2026-09-25', 100),
          quote('2026-09-26', 100, effective: '2026-09-25'),
          quote('2026-09-27', 100, effective: '2026-09-25'),
          quote('2026-09-28', 110, published: '2026-09-25T21:00:00Z'),
          quote('2026-09-29', 115, published: '2026-09-28T21:00:00Z'),
        ]),
      });
    double? at(int day, int hour, [int minute = 0]) =>
        movementBcvQuote(
              state,
              DateTime(2026, 9, day, hour, minute),
              now: DateTime.utc(2026, 10, 1, 12),
            )?['USD']
            as double?;
    expect(at(25, 17, 59), 100);
    expect(at(25, 18), 110);
    expect(at(26, 12), 110);
    expect(at(27, 12), 110);
    expect(at(28, 23, 59), 110);
    expect(at(29, 0), 115);
    expect(at(24, 12), isNull);
    expect(at(30, 12), isNull);
    (state['bcvRateHistory'] as Map)['2026-09-28']['updated_at'] =
        '2026-09-25T22:30:00Z';
    expect(at(25, 18), 100);
    expect(at(25, 18, 30), 110);
  });

  test(
    'An announced holiday quote remains active through the long weekend',
    () {
      final state = defaultState()
        ..['bcvRateHistory'] = normalizeBcvHistory([
          quote('2026-09-25', 100),
          quote('2026-09-28', 100, effective: '2026-09-25'),
          quote('2026-09-29', 120, published: '2026-09-25T21:00:00Z'),
        ]);
      expect(movementBcvQuote(state, DateTime(2026, 9, 28, 12))?['USD'], 120);
    },
  );

  test('Category migration keeps IDs, limits, currencies and transactions', () {
    final old = defaultState()
      ..addAll({
        'budgetPlansMigrated': true,
        'movements': [
          {'id': 'wifi', 'category': 'Wifi', 'amount': 120, 'currency': 'VES'},
          {
            'id': 'pasaje',
            'category': 'Pasaje',
            'amount': 5,
            'currency': 'USD',
          },
          {
            'id': 'cuotas',
            'category': 'Cuotas',
            'amount': 9,
            'currency': 'USD',
          },
        ],
        'budgets': [
          {
            'id': 'b1',
            'planId': 'p',
            'category': 'Wifi',
            'limit': 10,
            'currency': 'USD',
          },
          {
            'id': 'b2',
            'planId': 'p',
            'category': 'Servicios',
            'limit': 100,
            'currency': 'VES',
          },
        ],
      });
    final migrated = withDefaults(old);
    expect((migrated['movements'] as List).map((m) => m['category']), [
      'Servicios',
      'Transporte',
      'Deuda',
    ]);
    expect((migrated['movements'] as List).map((m) => m['amount']), [
      120,
      5,
      9,
    ]);
    expect((migrated['budgets'] as List).map((b) => b['id']), ['b1', 'b2']);
    expect((migrated['budgets'] as List).map((b) => b['category']), [
      'Servicios',
      'Servicios',
    ]);
    expect((migrated['budgets'] as List).map((b) => b['limit']), [10, 100]);
    expect((migrated['budgets'] as List).map((b) => b['currency']), [
      'USD',
      'VES',
    ]);
    final roundTrip = withDefaults(
      jsonDecode(jsonEncode(migrated)) as Map<String, dynamic>,
    );
    expect(roundTrip['movements'], migrated['movements']);
    expect(roundTrip['budgets'], migrated['budgets']);
    expect(budgetCategories, isNot(contains('Wifi')));
    expect(budgetCategories, isNot(contains('Pasaje')));
    expect(budgetCategories, isNot(contains('Cuotas')));
    expect(categoryFromDescription('Cuotas de Cashea'), 'Deuda');
  });

  test(
    'Budget and PDF use recorded BCV with fees despite later rate changes',
    () {
      final movement = <String, dynamic>{
        'type': 'expense',
        'amount': 1000.0,
        'feeAmount': 3.0,
        'currency': 'VES',
        'category': 'Servicios',
        'date': '22/09/2026 01:00 PM',
        ...movementBcvFields(quote('2026-09-22', 100)),
      };
      final restored = jsonDecode(jsonEncode(movement)) as Map<String, dynamic>;
      expect(movementBudgetUsd(restored, 1003, 900, 950), 10.03);
      final summary = summarizeBudgetSpending(
        [restored],
        '2026-09',
        'monthly',
        usdRate: 900,
        eurRate: 950,
        selectedCategories: {'Servicios'},
      );
      expect(summary.total, 10.03);
      final report = budgetReport(
        plan: {
          'id': 'p',
          'period': '2026-09',
          'periodType': 'monthly',
          'currency': 'USD',
        },
        items: [
          {
            'planId': 'p',
            'category': 'Servicios',
            'limit': 20,
            'currency': 'USD',
          },
        ],
        movements: [restored],
        usdRate: 900,
        eurRate: 950,
      );
      expect(report['spent'], r'$10,03');
      expect((report['details'] as List).single['totalValue'], 10.03);
    },
  );

  testWidgets('Calculator stays visible when account amounts are hidden', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() => app.state['hideAmounts'] = true);
    Navigator.of(
      tester.element(find.byType(HomePage)),
    ).push(CupertinoPageRoute<void>(builder: (_) => CalculatorPage(app: app)));
    await tester.pumpAndSettle();
    final input = find.byWidgetPredicate(
      (w) => w is CupertinoTextField && w.placeholder == '0,00',
    );
    await tester.enterText(input, '2000');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('calculator-copy')));
    expect(find.text('Bs. 20.000,00'), findsOneWidget);
    expect(app.state['hideAmounts'], true);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('Recent VES equivalent respects privacy at width $width', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      tester.view.physicalSize = Size(width, 844);
      app.mutate(() {
        app.state['homeSections'] = ['recent'];
        app.state['movements'] = [
          {
            'id': 'ves',
            'type': 'expense',
            'amount': 1000.0,
            'currency': 'VES',
            'accountId': 'b',
            'description': 'Internet de casa',
            'date': formatDateTime(DateTime.now()),
            ...movementBcvFields(quote('2026-09-22', 100)),
          },
          {
            'id': 'usd',
            'type': 'expense',
            'amount': 10.0,
            'currency': 'USD',
            'accountId': 'a',
            'description': 'Compra',
            'date': formatDateTime(DateTime.now()),
          },
        ];
      });
      await tester.pumpAndSettle();
      expect(find.text(r'$10,00 BCV'), findsOneWidget);
      expect(find.byKey(const ValueKey('movement-bcv-usd')), findsNothing);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
        await expectLater(
          find.byType(RialApp),
          matchesGoldenFile(
            '../build/date-rate-qa/recent-${width.toInt()}.png',
          ),
        );
      }
      app.mutate(() => app.state['hideAmounts'] = true);
      await tester.pumpAndSettle();
      expect(find.text(r'$10,00 BCV'), findsNothing);
      expect(find.text('-Bs. 1.000,00'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  Future<dynamic> openDatedEditor(
    WidgetTester tester, {
    String? debtCurrency,
  }) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() {
      app.state['rate'] = 150.0;
      app.state['eurRate'] = 180.0;
      app.state['bcvRateHistory'] = normalizeBcvHistory([
        quote('2026-09-21', 100, eur: 120),
        quote('2026-09-22', 110, eur: 130),
      ]);
      app.state['accounts'] = [
        {
          'id': 'cash',
          'provider': 'CASH',
          'currency': 'VES',
          'balance': 10000.0,
        },
        {'id': 'usd', 'provider': 'CASH', 'currency': 'USD', 'balance': 100.0},
      ];
      if (debtCurrency != null) {
        app.state['debts'] = [
          {
            'id': 'debt',
            'currency': debtCurrency,
            'kind': 'payable',
            'amount': 50.0,
            'paidAmount': 0.0,
          },
        ];
      }
    });
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultAccountId: 'cash',
      defaultAmount: 1000.0,
      defaultDebtId: debtCurrency == null ? null : 'debt',
    );
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('Save, edit and undo retain the chosen date rate', (
    tester,
  ) async {
    final dynamic app = await openDatedEditor(tester);
    dynamic editor = tester.state(find.byType(MovementEditor));
    editor.changeMovementDate(DateTime(2026, 9, 21, 12));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();
    final saved = app.maps('movements').single as Map<String, dynamic>;
    expect(saved['rate'], 100);
    expect(saved['bcvUsdRate'], 100);
    expect(app.movementToUsd(saved, 1000.0), 10);
    expect(app.accountById('cash')['balance'], 9000);
    app.mutate(() => app.state['rate'] = 999.0);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      movement: saved,
    );
    await tester.pumpAndSettle();
    editor = tester.state(find.byType(MovementEditor));
    editor.desc.text = 'Internet';
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(app.maps('movements').single['bcvUsdRate'], 100);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      movement: app.maps('movements').single,
    );
    await tester.pumpAndSettle();
    editor = tester.state(find.byType(MovementEditor));
    editor.changeMovementDate(DateTime(2026, 9, 22, 12));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(app.maps('movements').single['bcvUsdRate'], 110);
    expect(app.accountById('cash')['balance'], 9000);
    expect(app.undoLastOperation(), true);
    expect(app.maps('movements').single['bcvUsdRate'], 100);
    expect(tester.takeException(), isNull);
  });

  for (final currency in ['USD', 'EUR']) {
    testWidgets('Partial $currency debt payment follows selected date', (
      tester,
    ) async {
      final dynamic app = await openDatedEditor(tester, debtCurrency: currency);
      final dynamic editor = tester.state(find.byType(MovementEditor));
      final todayRate = currency == 'USD' ? 150.0 : 180.0;
      editor.amount.text = plain(5 * todayRate);
      editor.changeMovementDate(DateTime(2026, 9, 21, 12));
      await tester.pumpAndSettle();
      final historicalRate = currency == 'USD' ? 100.0 : 120.0;
      expect(parseAmount(editor.amount.text as String), 5 * historicalRate);
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.maps('movements').single['debtExchangeRate'], historicalRate);
      expect(app.debtById('debt')['paidAmount'], 5);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Missing historical rate cannot silently save with current BCV', (
    tester,
  ) async {
    final dynamic app = await openDatedEditor(tester);
    final dynamic editor = tester.state(find.byType(MovementEditor));
    editor.changeMovementDate(DateTime(1980, 1, 1, 12));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();
    expect(find.text('Tasa de la fecha no disponible'), findsOneWidget);
    expect(app.maps('movements'), isEmpty);
    expect(app.accountById('cash')['balance'], 10000);
  });

  testWidgets('USDT custom rate survives a change of date', (tester) async {
    final dynamic app = await openDatedEditor(tester, debtCurrency: 'USDT');
    final dynamic editor = tester.state(find.byType(MovementEditor));
    editor.debtExchangeRate.text = '200';
    editor.amount.text = '1000';
    editor.changeMovementDate(DateTime(2026, 9, 21, 12));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();
    final saved = app.maps('movements').single;
    expect(saved['bcvUsdRate'], 100);
    expect(saved['debtExchangeRate'], 200);
    expect(saved['amount'], 1000);
    expect(app.debtById('debt')['paidAmount'], 5);
  });

  testWidgets('Transfer custom rate is distinct from historical BCV', (
    tester,
  ) async {
    final dynamic app = await openDatedEditor(tester);
    final dynamic editor = tester.state(find.byType(MovementEditor));
    editor.type = 'transfer';
    editor.targetId = 'usd';
    editor.rate.text = '200';
    editor.changeMovementDate(DateTime(2026, 9, 21, 12));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();
    final saved = app.maps('movements').single;
    expect(saved['bcvUsdRate'], 100);
    expect(saved['rate'], 200);
    expect(saved['targetAmount'], 5);
    expect(app.accountById('usd')['balance'], 105);
  });
}
