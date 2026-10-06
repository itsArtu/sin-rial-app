import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'payment_method_test.dart' as payments;

Finder field(String placeholder) => find.byWidgetPredicate(
  (w) => w is CupertinoTextField && w.placeholder == placeholder,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          if (call.method == 'disableSecurity')
            return {
              'nativeSecurityV1': true,
              'securitySetupComplete': true,
              'pinEnabled': false,
              'biometricEnabled': false,
              'pinHash': '',
              'pinSalt': '',
              'pinLength': 0,
            };
          if (call.method == 'scheduleRateUpdate') return true;
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        ),
  );

  test('Maintenance activation is next calendar month including December', () {
    expect(nextMaintenanceMonth(DateTime(2026, 10, 31)), '2026-11');
    expect(nextMaintenanceMonth(DateTime(2026, 12, 31)), '2027-01');
    final previous = defaultState()..['onboardingComplete'] = true;
    previous.remove('seenFeatureTour');
    expect(withDefaults(previous)['seenFeatureTour'], '');
    previous['seenFeatureTour'] = '3.2';
    expect(withDefaults(previous)['seenFeatureTour'], '3.2');
  });

  testWidgets('Initial setup saves surname and can finish without PIN', (
    tester,
  ) async {
    await tester.pumpWidget(RialApp(initialState: defaultState()));
    await tester.pumpAndSettle();
    await tester.enterText(field('Tu nombre'), 'Ana');
    await tester.enterText(field('Apellido'), 'Perez');
    expect(find.text('Fecha de nacimiento'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proteger con PIN'));
    await tester.pumpAndSettle();
    expect(field('PIN de 4 a 6 dígitos'), findsNothing);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ir al inicio'));
    await tester.pumpAndSettle();
    expect(find.text('Conoce Sin Rial'), findsOneWidget);
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    final dynamic app = tester.state(find.byType(RialApp));
    expect(app.state['userLastName'], 'Perez');
    expect(app.securityEnabled, false);
    expect(app.securitySetupRequired, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Update tour is skippable and persists completion', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() => app.state['seenFeatureTour'] = '');
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseTour), findsOneWidget);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Cada cuenta, a tu medida'), findsOneWidget);
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(app.state['seenFeatureTour'], '3.2');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<dynamic> expense(WidgetTester tester, {bool ask = true}) async {
    final dynamic app = await fixtures.fixture(tester);
    if (ask) app.mutate(() => app.state['askExpenseReference'] = true);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultAccountId: 'a',
      defaultAmount: 10.0,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    return app;
  }

  testWidgets('Reference is disabled by default', (tester) async {
    final dynamic app = await expense(tester, ask: false);
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseReferenceDialog), findsNothing);
    expect(app.maps('movements').length, 1);
    expect(app.maps('movements').single['reference'], '');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Reference waits indefinitely and only saves once on No', (
    tester,
  ) async {
    final dynamic app = await expense(tester);
    expect(find.byType(ExpenseReferenceDialog), findsOneWidget);
    expect(app.maps('movements'), isEmpty);
    await tester.pump(const Duration(seconds: 30));
    expect(app.maps('movements'), isEmpty);
    expect(find.byType(ExpenseReferenceDialog), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(app.maps('movements').length, 1);
    expect(app.maps('movements').single['reference'], '');
    expect(app.accountById('a')['balance'], 90);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Reference preserves leading zeros and remains editable', (
    tester,
  ) async {
    final dynamic app = await expense(tester);
    await tester.tap(find.text('Sí'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(app.maps('movements'), isEmpty);
    await tester.enterText(field('Número de referencia'), '00123456');
    await tester.tap(find.text('Guardar gasto'));
    await tester.pumpAndSettle();
    final movement = app.maps('movements').single as Map<String, dynamic>;
    expect(movement['reference'], '00123456');
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      movement: movement,
    );
    await tester.pumpAndSettle();
    await tester.enterText(field('Referencia (opcional)'), '009876');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseReferenceDialog), findsNothing);
    expect(app.maps('movements').single['reference'], '009876');
    expect(app.accountById('a')['balance'], 90);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Screen reader reference prompt does not time out', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final dynamic app = await expense(tester);
    await tester.pump(const Duration(seconds: 8));
    expect(app.maps('movements'), isEmpty);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(app.maps('movements').length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Cestaticket variants coexist and only Integral can transfer', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    final food = <String, dynamic>{
      'id': 'food',
      'provider': 'CESTATICKET',
      'kind': 'benefit',
      'currency': 'VES',
      'balance': 1000,
    };
    final integral = {...food, 'id': 'integral', 'benefitType': 'integral'};
    app.mutate(
      () => app.state['accounts'] = [
        food,
        integral,
        {
          'id': 'cash',
          'provider': 'CASH',
          'kind': 'cash',
          'currency': 'VES',
          'balance': 0,
        },
      ],
    );
    expect(
      app.hasDuplicateAccount(
        'CESTATICKET',
        'VES',
        ignoreId: 'integral',
        benefitType: 'integral',
      ),
      false,
    );
    final movement = {
      'id': 'transfer',
      'type': 'transfer',
      'accountId': 'food',
      'targetAccountId': 'cash',
      'amount': 100,
      'targetAmount': 95,
      'currency': 'VES',
      'targetCurrency': 'VES',
      'feeAmount': 5,
      'feeMode': 'manual',
      'feeUnit': 'percent',
      'feePercent': 5,
      'feeTreatment': 'deducted',
      'date': formatDateTime(DateTime.now()),
    };
    expect(() => app.saveMovement(movement), throwsFormatException);
    movement['accountId'] = 'integral';
    app.saveMovement(movement);
    expect(app.accountById('integral')['balance'], 900);
    expect(app.accountById('cash')['balance'], 95);
    expect(app.maps('movements').single['feeAmount'], 5);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Current VES bank setup automatically schedules 684 next month', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.openAccountEditor(tester.element(find.byType(HomePage)));
    await tester.pumpAndSettle();
    await payments.choose(tester, 'Tipo de cuenta', 'Corriente');
    await tester.enterText(field('Saldo'), '1000');
    await tester.ensureVisible(find.text('Mantenimiento mensual'));
    expect(find.text('Bs. 684,00'), findsOneWidget);
    expect(field('Comisión mensual en Bs.'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Agregar cuenta'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(AccountEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Agregar cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar cuenta'));
    await tester.pumpAndSettle();
    final a = (app.maps('accounts') as List).singleWhere(
      (a) => a['provider'] == '0102',
    );
    expect(a['maintenanceAmount'], 684);
    expect(a['maintenancePolicy'], bankMaintenancePolicy);
    expect(a['maintenanceEnabled'], true);
    expect(a['maintenanceNextMonth'], nextMaintenanceMonth());
    expect(app.maps('movements'), isEmpty);
    app.saveAccount({
      'id': a['id'],
      'balance': 1000.0,
      'name': 'Renamed',
    }, editingId: a['id']);
    expect(
      app.accountById(a['id'])['maintenanceNextMonth'],
      nextMaintenanceMonth(),
    );
    expect(app.accountById(a['id'])['bankAccountType'], 'current');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
