import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

Map<String, dynamic> movementFixture(String type) => {
  'id': 'movement-test',
  'type': type,
  'description': 'Registro de prueba',
  'category': 'Otro',
  'amount': 50.0,
  'currency': 'USD',
  'feeAmount': 1.0,
  'feeCurrency': 'USD',
  'feeMode': 'manual',
  'accountId': 'source',
  'targetAccountId': type == 'transfer' ? 'target' : '',
  'targetAmount': 500.0,
  'targetCurrency': 'VES',
  'date': '16/09/2026 11:08 AM',
  'rate': 10.0,
  'debtId': type == 'transfer' ? '' : 'debt-test',
};

Future<dynamic> openFixture(WidgetTester tester, String type) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state = defaultState()
    ..addAll({
      'onboardingComplete': true,
      'securitySetupComplete': true,
      'userName': 'Prueba',
      'rate': 10.0,
      'rateEffectiveDate': expectedRateDateKey(DateTime.now()),
      'homeSections': ['recent'],
      'homeShortcutButtons': ['calculator'],
      'accounts': [
        {
          'id': 'source',
          'provider': 'cash',
          'label': 'Cuenta origen',
          'currency': 'USD',
          'balance': type == 'income' ? 249.0 : 149.0,
        },
        {
          'id': 'target',
          'provider': 'cash',
          'label': 'Cuenta destino',
          'currency': 'VES',
          'balance': type == 'transfer' ? 500.0 : 0.0,
        },
      ],
      'movements': [movementFixture(type)],
      'debts': [
        {
          'id': 'debt-test',
          'kind': type == 'income' ? 'receivable' : 'payable',
          'title': 'Cuotas de prueba',
          'amount': 100.0,
          'paidAmount': 50.0,
          'currency': 'USD',
          'status': 'pending',
        },
      ],
    });
  await tester.pumpWidget(RialApp(initialState: state));
  await tester.pumpAndSettle();
  final dynamic app = tester.state(find.byType(RialApp));
  await tester.ensureVisible(find.byType(MovementTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(MovementTile));
  await tester.pumpAndSettle();
  expect(find.byType(MovementDetailPage), findsOneWidget);
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

  for (final type in ['expense', 'income', 'transfer']) {
    testWidgets('Detail and confirmed deletion restore $type balances', (
      tester,
    ) async {
      final dynamic app = await openFixture(tester, type);
      expect(find.text('Registro de prueba'), findsOneWidget);
      expect(find.text('16/09/2026'), findsOneWidget);
      expect(find.text('11:08 AM'), findsOneWidget);
      expect(find.text('Comisión'), findsOneWidget);
      if (type == 'transfer') {
        final target = find.text('Cuenta destino');
        await tester.ensureVisible(target);
        expect(target, findsOneWidget);
        expect(find.text('Deuda vinculada'), findsNothing);
        expect(find.text('Cobro vinculado'), findsNothing);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('delete-movement')));
      await tester.tap(find.byKey(const ValueKey('delete-movement')));
      await tester.pumpAndSettle();
      expect(app.movementById('movement-test'), isNotNull);
      await tester.tap(
        find.descendant(
          of: find.byType(ModernConfirmDialog),
          matching: find.text('Cancelar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.movementById('movement-test'), isNotNull);
      await tester.tap(find.byKey(const ValueKey('delete-movement')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ModernConfirmDialog),
          matching: find.text('Eliminar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MovementDetailPage), findsNothing);
      expect(app.movementById('movement-test'), isNull);
      expect(app.accountById('source')['balance'], 200.0);
      expect(app.accountById('target')['balance'], 0.0);
      if (type != 'transfer') {
        expect(app.debtById('debt-test')['paidAmount'], 0.0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Editing from detail refreshes the record and linked debt', (
    tester,
  ) async {
    final dynamic app = await openFixture(tester, 'expense');
    await tester.tap(find.byKey(const ValueKey('edit-movement')));
    await tester.pumpAndSettle();
    expect(find.byType(MovementEditor), findsOneWidget);
    final amount = find.byWidgetPredicate(
      (widget) => widget is CupertinoTextField && widget.placeholder == 'Monto',
    );
    await tester.enterText(amount, '60');
    final save = find.text('Guardar cambios');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(MovementDetailPage), findsOneWidget);
    expect(app.movementById('movement-test')['amount'], 60.0);
    expect(app.debtById('debt-test')['paidAmount'], 60.0);
    expect(find.text('-\$60,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
