import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

const bank = <String, dynamic>{
  'id': 'bank',
  'kind': 'national',
  'currency': 'VES',
  'provider': '0102',
  'balance': 20000.0,
};

Finder option(String label) => find.byWidgetPredicate(
  (widget) => widget is OptionField && widget.label == label,
);

Future<void> choose(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(option(label));
  await tester.tap(option(label));
  await tester.pumpAndSettle();
  final item = find.descendant(
    of: find.byType(ModernSheet),
    matching: find.text(value),
  );
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<dynamic> openExpense(WidgetTester tester) async {
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
          'rate': 846.51,
          'rateEffectiveDate': expectedRateDateKey(DateTime.now()),
          'accounts': [Map<String, dynamic>.from(bank)],
        }),
    ),
  );
  await tester.pumpAndSettle();
  final dynamic app = tester.state(find.byType(RialApp));
  app.openMovementEditor(
    tester.element(find.byType(HomePage)),
    defaultAccountId: 'bank',
    defaultAmount: 10000.0,
  );
  await tester.pumpAndSettle();
  return app;
}

void main() {
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

  test('Fee exceptions and existing transfer rules', () {
    for (final method in [
      'payment_mobile_c2p',
      'payment_mobile_p2c',
      'debit_card',
    ]) {
      expect(
        canConfigureBankFee(bank, type: 'expense', method: method),
        isFalse,
      );
      expect(
        estimatedBankFee(method: method, amount: 10000, type: 'expense'),
        0,
      );
    }
    for (final method in ['payment_mobile_p2p', 'bank_transfer']) {
      expect(
        canConfigureBankFee(bank, type: 'expense', method: method),
        isTrue,
      );
      expect(
        estimatedBankFee(method: method, amount: 10000, type: 'expense'),
        30,
      );
    }
    expect(
      estimatedBankFee(
        method: 'bank_transfer',
        amount: 10000,
        type: 'transfer',
        bankTransferScope: 'same_bank',
      ),
      0,
    );
    expect(
      canConfigureBankFee(bank, type: 'expense', category: 'Recarga saldo'),
      isFalse,
    );
    expect(
      estimatedBankFee(
        method: 'payment_mobile_p2p',
        amount: 10000,
        type: 'expense',
        category: 'Recarga saldo',
      ),
      0,
    );
    expect(paymentMethodLabel('payment_mobile_p2c'), 'Pago m\u00f3vil C2P');
  });

  for (final method in ['Pago m\u00f3vil C2P', 'Tarjeta']) {
    testWidgets('$method clears a previous manual fee on save', (tester) async {
      final dynamic app = await openExpense(tester);
      await tester.ensureVisible(option('Comisi\u00f3n'));
      expect(
        tester.getTopLeft(option('Forma de pago')).dy,
        lessThan(tester.getTopLeft(option('Comisi\u00f3n')).dy),
      );
      await choose(tester, 'Comisi\u00f3n', 'Manual');
      final manualFee = find.byWidgetPredicate(
        (widget) =>
            widget is CupertinoTextField &&
            widget.placeholder == 'Comisi\u00f3n manual',
      );
      await tester.ensureVisible(manualFee);
      await tester.enterText(manualFee, '75');
      await choose(tester, 'Forma de pago', method);
      expect(option('Forma de pago'), findsOneWidget);
      expect(option('Comisi\u00f3n'), findsNothing);
      expect(manualFee, findsNothing);
      expect(find.text('Comisi\u00f3n estimada'), findsNothing);
      final save = find.text('Guardar movimiento');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final movement = app.maps('movements').single;
      expect(movement['feeAmount'], 0.0);
      expect(movement['feeMode'], 'none');
      expect(movement['paymentMethod'], paymentMethodFromLabel(method));
      expect(app.accountById('bank')['balance'], 10000.0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Fee-free selection still allows changing payment method', (
    tester,
  ) async {
    final dynamic app = await openExpense(tester);
    await choose(tester, 'Comisi\u00f3n', 'Sin comisi\u00f3n');
    expect(option('Forma de pago'), findsOneWidget);
    await choose(tester, 'Forma de pago', 'Tarjeta');
    await choose(tester, 'Forma de pago', 'Pago m\u00f3vil');
    expect(option('Comisi\u00f3n'), findsOneWidget);
    final save = find.text('Guardar movimiento');
    await tester.scrollUntilVisible(
      save,
      250,
      scrollable: find
          .descendant(
            of: find.byType(MovementEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(app.maps('movements').single['feeAmount'], 30.0);
    expect(app.accountById('bank')['balance'], 9970.0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
