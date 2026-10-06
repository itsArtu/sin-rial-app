import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'security_test.dart' as security;

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

  test('Paid and upcoming classifications use the same cent-safe balance', () {
    final partial = <String, dynamic>{
      'id': 'partial',
      'amount': 100,
      'paidAmount': 20,
      'status': 'paid',
    };
    final settled = <String, dynamic>{
      'id': 'settled',
      'amount': .3,
      'paidAmount': .1 + .2,
      'status': 'pending',
    };
    expect(debtIsPaid(partial), false);
    expect(debtIsPaid(settled), true);
    expect(upcomingDebtItems([partial, settled]).map((d) => d['id']), [
      'partial',
    ]);
  });

  testWidgets('Debt tabs default to unpaid, update live on payment and undo', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => DebtsPage(app: app),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DebtTile), findsOneWidget);
    expect(
      tester.widget<KindSelector>(find.byType(KindSelector)).value,
      'unpaid',
    );
    app.saveMovement(fixtures.movement('expense', amount: 5)..['debtId'] = 'd');
    await tester.pumpAndSettle();
    expect(find.byType(DebtTile), findsOneWidget);
    expect(upcomingDebtItems(app.maps('debts')), hasLength(1));
    app.saveMovement(
      fixtures.movement('expense', id: 'finish', amount: 5)..['debtId'] = 'd',
    );
    await tester.pumpAndSettle();
    expect(find.byType(DebtTile), findsNothing);
    expect(upcomingDebtItems(app.maps('debts')), isEmpty);
    await tester.tap(find.text('Pagados'));
    await tester.pumpAndSettle();
    expect(find.byType(DebtTile), findsOneWidget);
    app.undoLastOperation();
    await tester.pumpAndSettle();
    expect(find.byType(DebtTile), findsNothing);
    await tester.tap(find.text('No pagados'));
    await tester.pumpAndSettle();
    expect(find.byType(DebtTile), findsOneWidget);
    expect(upcomingDebtItems(app.maps('debts')), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Reference prompt preference is available under Settings movements',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      expect(app.state['askExpenseReference'], false);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => SettingsPage(app: app, section: 'Movimientos'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Referencia bancaria'));
      await tester.pumpAndSettle();
      expect(app.state['askExpenseReference'], true);
      expect(
        withDefaults(
          Map<String, dynamic>.from(app.state),
        )['askExpenseReference'],
        true,
      );
      await tester.tap(find.text('Referencia bancaria'));
      await tester.pumpAndSettle();
      expect(app.state['askExpenseReference'], false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Cestaticket food only offers card and Integral preserves transfer expenses',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final food = <String, dynamic>{
        'id': 'food',
        'provider': 'CESTATICKET',
        'kind': 'benefit',
        'currency': 'VES',
        'balance': 1000.0,
        'benefitType': 'food',
      };
      final integral = {...food, 'id': 'integral', 'benefitType': 'integral'};
      expect(expensePaymentMethods(food), ['Tarjeta']);
      expect(expensePaymentMethods(integral), [
        'Tarjeta',
        'Transferencia bancaria',
      ]);
      app.mutate(() => app.state['accounts'] = [food, integral]);
      app.saveMovement({
        ...fixtures.movement('expense', amount: 100),
        'accountId': 'integral',
        'currency': 'VES',
        'paymentMethod': 'bank_transfer',
      });
      expect(app.maps('movements').single['paymentMethod'], 'bank_transfer');
      expect(app.accountById('integral')['balance'], 900);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Tour fades out before switching to the home page', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() => app.state['seenFeatureTour'] = '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Omitir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(ReleaseTour), findsOneWidget);
    expect(app.state['seenFeatureTour'], '');
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(app.state['seenFeatureTour'], '3.2');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Lock logo interpolates its height and keeps a stable decoded image',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(RialApp(initialState: security.protectedState()));
      await tester.pumpAndSettle();
      final logo = find.byKey(const ValueKey('lock-logo-size'));
      expect(tester.getSize(logo).height, 64);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.getSize(logo).height, inExclusiveRange(40, 64));
      expect(tester.widget<SinRialLogo>(find.byType(SinRialLogo)).height, 64);
      await tester.pumpAndSettle();
      expect(tester.getSize(logo).height, 40);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
