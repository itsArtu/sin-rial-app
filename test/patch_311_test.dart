import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'calculator_usdt_test.dart' as calculator;
import 'payment_method_test.dart' as payment;

const wallet = <String, dynamic>{
  'id': 'usd',
  'kind': 'wallet',
  'provider': 'OKX',
  'currency': 'USD',
  'balance': 1000.0,
};

Future<dynamic> fixture(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RialApp(
      initialState: defaultState()
        ..addAll({
          'onboardingComplete': true,
          'securitySetupComplete': true,
          'accounts': [
            Map<String, dynamic>.from(wallet),
            {...wallet, 'id': 'target', 'provider': 'ZINLI', 'balance': 0.0},
          ],
        }),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state(find.byType(RialApp));
}

Future<void> close(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        ),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        ),
  );

  test(
    'USD fees support percentages, amounts and none without VES minimums',
    () {
      expect(
        canConfigureBankFee(wallet, type: 'expense', method: 'debit_card'),
        false,
      );
      expect(
        canConfigureBankFee(wallet, type: 'transfer', target: wallet),
        true,
      );
      expect(canConfigureBankFee(wallet, type: 'income'), false);
      expect(
        canConfigureBankFee({...wallet, 'kind': 'cash'}, type: 'expense'),
        false,
      );
      expect(bankTransferFee(wallet, wallet, 100), 0);
      expect(
        dollarOperationFee(
          amount: 125,
          mode: 'manual',
          unit: 'percent',
          value: 2.5,
        ),
        3.13,
      );
      expect(
        dollarOperationFee(
          amount: 125,
          mode: 'manual',
          unit: 'amount',
          value: 1.5,
        ),
        1.5,
      );
      expect(
        dollarOperationFee(
          amount: 125,
          mode: 'none',
          unit: 'percent',
          value: 10,
        ),
        0,
      );
      expect(
        () => dollarOperationFee(
          amount: 10,
          mode: 'auto',
          unit: 'percent',
          value: 101,
        ),
        throwsFormatException,
      );
    },
  );

  for (final type in ['transfer']) {
    testWidgets('$type USD fee survives editing deletion and undo', (
      tester,
    ) async {
      final dynamic app = await fixture(tester);
      final movement = <String, dynamic>{
        'id': 'm',
        'type': type,
        'accountId': 'usd',
        'currency': 'USD',
        'amount': 100,
        'category': 'Otro',
        'date': formatDateTime(DateTime.now()),
        'paymentMethod': 'debit_card',
        'feeMode': 'auto',
        'feeUnit': 'percent',
        'feePercent': 2.5,
        'feeAmount': 2.5,
        if (type == 'transfer') ...{
          'targetAccountId': 'target',
          'targetCurrency': 'USD',
          'targetAmount': 100,
        },
      };
      app.saveMovement(movement);
      expect(app.accountById('usd')['balance'], 897.5);
      expect(
        app.accountById('target')['balance'],
        type == 'transfer' ? 100 : 0,
      );
      expect(
        app.accountById('usd')[type == 'transfer'
            ? 'transferFeePercent'
            : 'cardFeePercent'],
        2.5,
      );
      app.saveMovement({
        ...movement,
        'amount': 200,
        'targetAmount': type == 'transfer' ? 200 : 0,
      }, editingId: 'm');
      expect(app.accountById('usd')['balance'], 795);
      expect(app.movementById('m')['feeAmount'], 5);
      expect(app.undoLastOperation(), true);
      expect(app.accountById('usd')['balance'], 897.5);
      app.deleteMovement(app.movementById('m'));
      expect(app.accountById('usd')['balance'], 1000);
      expect(app.undoLastOperation(), true);
      expect(app.accountById('usd')['balance'], 897.5);
      await close(tester);
    });
  }

  test('Card presets are separate from editable transfer fees', () {
    for (final entry in {
      'WALLY': 2.85,
      'OKX': 0.0,
      'BINANCE': 0.0,
      'ZINLI': 0.0,
    }.entries) {
      final account = {...wallet, 'provider': entry.key};
      expect(
        dollarFeePercentForAccount(account, 'expense', 'debit_card'),
        entry.value,
      );
      expect(
        dollarFeePercentForAccount(account, 'transfer', 'bank_transfer'),
        isNull,
      );
      expect(
        dollarFeePercentForAccount(
          {...account, 'cardFeePercent': 1.5},
          'expense',
          'debit_card',
        ),
        1.5,
      );
    }
  });

  for (final legacyFee in [0.0, 1.5]) {
    testWidgets('Editing legacy USD expense preserves fee $legacyFee', (
      tester,
    ) async {
      final dynamic app = await fixture(tester);
      final legacy = <String, dynamic>{
        'id': 'legacy',
        'type': 'expense',
        'accountId': 'usd',
        'currency': 'USD',
        'amount': 100,
        'category': 'Otro',
        'date': formatDateTime(DateTime.now()),
        'paymentMethod': 'debit_card',
        'feeMode': 'auto',
        'feeAmount': legacyFee,
      };
      app.mutate(() {
        app.rawList('movements').add(legacy);
        app.accountById('usd')['balance'] = 900 - legacyFee;
      });
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        movement: app.movementById('legacy'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(app.maps('movements').single['feeAmount'], legacyFee);
      expect(app.accountById('usd')['balance'], 900 - legacyFee);
      await close(tester);
    });
  }

  testWidgets(
    'Monthly metrics exclude previous month and include transfer fee once',
    (tester) async {
      final dynamic app = await fixture(tester);
      app.mutate(
        () => app.state['movements'] = [
          {
            'id': 'a',
            'type': 'income',
            'currency': 'USD',
            'amount': 100,
            'date': '30/09/2026 10:00 AM',
          },
          {
            'id': 'b',
            'type': 'income',
            'currency': 'USD',
            'amount': 20,
            'date': '01/10/2026 10:00 AM',
          },
          {
            'id': 'c',
            'type': 'expense',
            'currency': 'USD',
            'amount': 5,
            'feeAmount': 1,
            'date': '01/10/2026 11:00 AM',
          },
          {
            'id': 'd',
            'type': 'transfer',
            'currency': 'USD',
            'amount': 50,
            'feeAmount': 2,
            'date': '01/10/2026 12:00 PM',
          },
        ],
      );
      final september = app.homeLedgerCache.read(
        app,
        now: DateTime(2026, 9, 30, 23, 59),
      );
      expect(september.income, 100);
      final october = app.homeLedgerCache.read(app, now: DateTime(2026, 10, 1));
      expect(october.income, 20);
      expect(october.expenses, 8);
      expect(october.movements.length, 4);
      final november = app.homeLedgerCache.read(
        app,
        now: DateTime(2026, 11, 1),
      );
      expect(november.income, 0);
      expect(november.expenses, 0);
      await close(tester);
    },
  );

  testWidgets(
    'Calculator formats amount and custom rate requires dialog confirmation',
    (tester) async {
      await calculator.openCalculator(tester);
      await tester.enterText(calculator.input('Monto'), '2000');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoTextField>(calculator.input('Monto'))
            .controller!
            .text,
        '2.000,00',
      );
      await tester.ensureVisible(find.text('Usar tasa personalizada'));
      await tester.tap(find.text('Usar tasa personalizada'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('custom-rate-input')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('custom-rate-input')),
        '1000',
      );
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('custom-rate-input')), findsNothing);
      expect(find.text('Bs. 2.000.000,00'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('Back dismisses keyboard without popping calculator', (
    tester,
  ) async {
    await calculator.openCalculator(tester);
    await tester.showKeyboard(calculator.input('Monto'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorPage), findsOneWidget);
    expect(tester.testTextInput.isVisible, false);
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorPage), findsNothing);
    await close(tester);
  });

  testWidgets('USD expense has payment options without commission controls', (
    tester,
  ) async {
    final dynamic app = await fixture(tester);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultAccountId: 'usd',
      defaultAmount: 100.0,
    );
    await tester.pumpAndSettle();
    await payment.choose(tester, 'Forma de pago', 'Pago');
    expect(payment.option('Comisión'), findsNothing);
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();
    expect(app.maps('movements').single['feeAmount'], 0);
    expect(app.maps('movements').single['paymentMethod'], 'wallet_payment');
    expect(app.accountById('usd')['balance'], 900);
    await close(tester);
  });

  testWidgets('All movements show VES historical BCV equivalent', (
    tester,
  ) async {
    final dynamic app = await fixture(tester);
    app.mutate(
      () => app.state['movements'] = [
        {
          'id': 'ves',
          'type': 'expense',
          'accountId': 'usd',
          'currency': 'VES',
          'amount': 2000.0,
          'date': formatDateTime(DateTime.now()),
          'bcvUsdRate': 1000.0,
          'bcvEffectiveDate': expectedRateDateKey(DateTime.now()),
        },
      ],
    );
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (BuildContext context) => MovementHistoryPage(app: app),
    );
    await tester.pumpAndSettle();
    final tiles = tester.widgetList<MovementTile>(find.byType(MovementTile));
    expect(tiles, isNotEmpty);
    expect(tiles.every((tile) => tile.showBcv), true);
    expect(find.textContaining('BCV'), findsWidgets);
    await close(tester);
  });
}
