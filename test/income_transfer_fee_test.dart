import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'payment_method_test.dart' as payment;

const source = <String, dynamic>{
  'id': 'source',
  'label': 'Origen',
  'kind': 'national',
  'currency': 'VES',
  'provider': '0102',
  'balance': 20000.0,
};
const other = <String, dynamic>{
  'id': 'other',
  'label': 'Otro banco',
  'kind': 'national',
  'currency': 'VES',
  'provider': '0172',
  'balance': 100.0,
};
const same = <String, dynamic>{
  'id': 'same',
  'label': 'Mismo banco',
  'kind': 'national',
  'currency': 'VES',
  'provider': '0102',
  'balance': 100.0,
};

Map<String, dynamic> movement(String type, {String targetId = 'other'}) => {
  'id': 'm',
  'type': type,
  'accountId': 'source',
  'amount': 10000.0,
  'currency': 'VES',
  'category': 'Otro',
  'date': formatDateTime(DateTime.now()),
  'rate': 846.51,
  'feeAmount': 75.0,
  'feeMode': 'manual',
  'bankTransferScope': 'same_bank',
  if (type == 'transfer') ...{
    'targetAccountId': targetId,
    'targetAmount': 10000.0,
    'targetCurrency': 'VES',
  },
};

Future<dynamic> fixture(
  WidgetTester tester, {
  Map<String, dynamic>? legacy,
  double width = 390,
  bool dark = true,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final accounts = [
    Map<String, dynamic>.from(source),
    Map<String, dynamic>.from(other),
    Map<String, dynamic>.from(same),
  ];
  if (legacy != null) {
    accounts.first['balance'] = legacy['type'] == 'income' ? 29925.0 : 9925.0;
    if (legacy['type'] == 'transfer') accounts[1]['balance'] = 10100.0;
  }
  await tester.pumpWidget(
    RialApp(
      initialState: defaultState()
        ..addAll({
          'onboardingComplete': true,
          'securitySetupComplete': true,
          'darkMode': dark,
          'rate': 846.51,
          'rateEffectiveDate': expectedRateDateKey(DateTime.now()),
          'accounts': accounts,
          'movements': [?legacy],
        }),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state(find.byType(RialApp));
}

Future<void> closeFixture(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Finder row(String label) => find.byWidgetPredicate(
  (widget) => widget is DebtDetailRow && widget.label == label,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        );
  });

  test('Income is fee-free for every payment method', () {
    for (final method in [
      'bank_transfer',
      'payment_mobile_p2p',
      'payment_mobile_c2p',
      'debit_card',
    ]) {
      expect(
        canConfigureBankFee(source, type: 'income', method: method),
        isFalse,
      );
      expect(
        estimatedBankFee(method: method, amount: 10000, type: 'income'),
        0,
      );
    }
  });

  test('Bank transfer fees use provider identity and existing tariff', () {
    expect(bankTransferFee(source, other, 10000), 30);
    expect(bankTransferFee(source, other, 1000), 14);
    expect(bankTransferFee(source, same, 10000), 0);
    expect(bankTransferFee(source, {...same, 'provider': ' 0102 '}, 10000), 0);
    expect(bankTransferFee(source, null, 10000), 0);
    expect(bankTransferFee(source, {...other, 'currency': 'USD'}, 10000), 0);
    expect(
      bankTransferFee(source, {
        ...other,
        'kind': 'cash',
        'provider': 'CASH',
      }, 10000),
      0,
    );
  });

  testWidgets('Saving income ignores stale fees without mutating input', (
    tester,
  ) async {
    final dynamic app = await fixture(tester);
    final input = movement('income');
    app.saveMovement(input);
    expect(input['feeAmount'], 75);
    expect(app.movementById('m')['feeAmount'], 0);
    expect(app.movementById('m')['feeMode'], 'none');
    expect(app.accountById('source')['balance'], 30000);
    app.deleteMovement(app.movementById('m'));
    expect(app.accountById('source')['balance'], 20000);
    expect(app.undoLastOperation(), isTrue);
    expect(app.accountById('source')['balance'], 30000);
    expect(app.undoLastOperation(), isTrue);
    expect(app.accountById('source')['balance'], 20000);
    await closeFixture(tester);
  });

  for (final target in ['other', 'same']) {
    testWidgets('Transfer to $target bank recalculates stale fees and scope', (
      tester,
    ) async {
      final dynamic app = await fixture(tester);
      final input = movement(
        'transfer',
        targetId: target,
      )..['bankTransferScope'] = target == 'other' ? 'same_bank' : 'other_bank';
      app.saveMovement(input);
      final expectedFee = target == 'other' ? 30 : 0;
      expect(app.movementById('m')['feeAmount'], expectedFee);
      expect(
        app.movementById('m')['bankTransferScope'],
        target == 'other' ? 'other_bank' : 'same_bank',
      );
      expect(app.accountById('source')['balance'], 10000 - expectedFee);
      expect(app.accountById(target)['balance'], 10100);
      app.deleteMovement(app.movementById('m'));
      expect(app.accountById('source')['balance'], 20000);
      expect(app.accountById(target)['balance'], 100);
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById('source')['balance'], 10000 - expectedFee);
      expect(app.accountById(target)['balance'], 10100);
      await closeFixture(tester);
    });
  }

  for (final type in ['income', 'transfer']) {
    testWidgets('Legacy $type fees survive deletion and editing undo', (
      tester,
    ) async {
      final legacy = movement(type);
      final dynamic app = await fixture(tester, legacy: legacy);
      final oldBalance = type == 'income' ? 29925 : 9925;
      expect(app.movementById('m')['feeAmount'], 75);
      expect(app.accountById('source')['balance'], oldBalance);
      app.deleteMovement(app.movementById('m'));
      expect(app.accountById('source')['balance'], 20000);
      expect(app.accountById('other')['balance'], 100);
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById('source')['balance'], oldBalance);
      expect(app.movementById('m')['feeAmount'], 75);
      app.saveMovement(Map<String, dynamic>.from(legacy), editingId: 'm');
      expect(app.movementById('m')['feeAmount'], type == 'income' ? 0 : 30);
      expect(
        app.accountById('source')['balance'],
        type == 'income' ? 30000 : 9970,
      );
      if (type == 'transfer') {
        expect(app.accountById('other')['balance'], 10100);
      }
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById('source')['balance'], oldBalance);
      expect(app.movementById('m')['feeAmount'], 75);
      await closeFixture(tester);
    });
  }

  testWidgets('Switching manual expense to income removes all fee fields', (
    tester,
  ) async {
    final dynamic app = await payment.openExpense(tester);
    await payment.choose(tester, 'Comisi\u00f3n', 'Manual');
    final manualFee = find.byWidgetPredicate(
      (widget) =>
          widget is CupertinoTextField &&
          widget.placeholder == 'Comisi\u00f3n manual',
    );
    await tester.ensureVisible(manualFee);
    await tester.enterText(manualFee, '75');
    await tester.tap(
      find.descendant(
        of: find.byType(KindSelector),
        matching: find.text('Ingreso'),
      ),
    );
    await tester.pumpAndSettle();
    expect(payment.option('Comisi\u00f3n'), findsNothing);
    expect(manualFee, findsNothing);
    expect(find.text('Comisi\u00f3n estimada'), findsNothing);
    expect(row('Comisi\u00f3n aplicada'), findsNothing);
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();
    expect(app.maps('movements').single['feeAmount'], 0);
    expect(app.accountById('bank')['balance'], 30000);
    await closeFixture(tester);
  });

  testWidgets(
    'Legacy income detail hides fees and editing previews full credit',
    (tester) async {
      final dynamic app = await fixture(tester, legacy: movement('income'));
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => MovementDetailPage(app: app, movementId: 'm'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Comisi\u00f3n'), findsNothing);
      expect(find.text('C\u00e1lculo de comisi\u00f3n'), findsNothing);
      expect(
        tester.widget<DebtDetailRow>(row('Total recibido')).value,
        'Bs. 9.925,00',
      );
      app.openMovementEditor(
        tester.element(find.byType(MovementDetailPage)),
        movement: app.movementById('m'),
      );
      await tester.pumpAndSettle();
      expect(payment.option('Comisi\u00f3n'), findsNothing);
      expect(row('Comisi\u00f3n aplicada'), findsNothing);
      expect(
        tester.widget<DebtDetailRow>(row('Ingreso neto')).value,
        'Bs. 10.000,00',
      );
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(app.movementById('m')['feeAmount'], 0);
      expect(app.accountById('source')['balance'], 30000);
      await closeFixture(tester);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('Transfer preview follows destination at width $width', (
      tester,
    ) async {
      final dynamic app = await fixture(
        tester,
        width: width,
        dark: width == 390,
      );
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        defaultType: 'transfer',
        defaultAccountId: 'source',
        defaultAmount: 10000.0,
      );
      await tester.pumpAndSettle();
      expect(payment.option('Transferencia bancaria'), findsNothing);
      expect(
        tester.widget<DebtDetailRow>(row('Transferencia bancaria')).value,
        'Otro banco',
      );
      expect(
        tester.widget<DebtDetailRow>(row('Comisi\u00f3n aplicada')).value,
        'Bs. 30,00',
      );
      await payment.choose(tester, 'Cuenta destino', 'Mismo banco');
      expect(
        tester.widget<DebtDetailRow>(row('Transferencia bancaria')).value,
        'Mismo banco',
      );
      expect(
        tester.widget<DebtDetailRow>(row('Comisi\u00f3n aplicada')).value,
        'Bs. 0,00',
      );
      await payment.choose(tester, 'Cuenta destino', 'Otro banco');
      expect(
        tester.widget<DebtDetailRow>(row('Comisi\u00f3n aplicada')).value,
        'Bs. 30,00',
      );
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.maps('movements').single['feeAmount'], 30);
      expect(app.accountById('source')['balance'], 9970);
      expect(app.accountById('other')['balance'], 10100);
      await closeFixture(tester);
    });
  }
}
