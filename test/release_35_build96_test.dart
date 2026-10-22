import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  Map<String, dynamic> expense(double amount) => {
    'id': 'live',
    'accountId': 'a',
    'type': 'expense',
    'currency': 'USD',
    'amount': amount,
    'category': 'Comida',
    'description': 'Almuerzo',
    'date': formatDateTime(DateTime.now()),
  };

  for (final grouping in ['category', 'account']) {
    testWidgets(
      'Monthly $grouping drilldown, covered report and home follow edit/delete/undo',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        app.saveMovement(expense(10));
        await tester.pumpAndSettle();
        expect(
          tester.widget<BalanceHero>(find.byType(BalanceHero)).usdBalance,
          90,
        );
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => MonthlySpendingPage(app: app),
        );
        await tester.pumpAndSettle();
        final reportState = tester.state(find.byType(MonthlySpendingPage));
        app.pushPage(
          tester.element(find.byType(MonthlySpendingPage)),
          (_) => MonthlySpendingMovementsPage(
            app: app,
            month: currentMonthKey(),
            grouping: grouping,
            groupKey: grouping == 'category' ? 'Comida' : 'a',
            title: grouping == 'category' ? 'Comida' : 'Origen',
          ),
        );
        await tester.pumpAndSettle();
        String total() => tester
            .widget<Text>(find.byKey(const ValueKey('monthly-drill-total')))
            .data!;
        expect(total(), money(10, 'USD'));
        app.saveMovement(expense(25), editingId: 'live');
        await tester.pumpAndSettle();
        expect(total(), money(25, 'USD'));
        expect(app.accountById('a')['balance'], 75);
        app.deleteMovement(app.movementById('live'));
        await tester.pumpAndSettle();
        expect(total(), money(0, 'USD'));
        expect(find.byKey(const ValueKey('monthly-drill-live')), findsNothing);
        expect(app.undoLastOperation(), true);
        await tester.pumpAndSettle();
        expect(total(), money(25, 'USD'));
        expect(
          find.byKey(const ValueKey('monthly-drill-live')),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(MonthlySpendingPage)),
          same(reportState),
        );
        expect(find.text(money(25, 'USD')), findsWidgets);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester.widget<BalanceHero>(find.byType(BalanceHero)).usdBalance,
          75,
        );
        expect(app.undoLastOperation(), true);
        await tester.pumpAndSettle();
        expect(
          tester.widget<BalanceHero>(find.byType(BalanceHero)).usdBalance,
          90,
        );
        if (grouping == 'account') {
          app.pushPage(
            tester.element(find.byType(HomePage)),
            (_) => MonthlySpendingMovementsPage(
              app: app,
              month: currentMonthKey(),
              grouping: 'account',
              groupKey: 'a',
              title: 'Origen',
            ),
          );
          await tester.pumpAndSettle();
          app.mutate(() => app.accountById('a')['label'] = 'Cuenta renovada');
          await tester.pumpAndSettle();
          final heading =
              tester
                      .widget<CupertinoNavigationBar>(
                        find.byType(CupertinoNavigationBar),
                      )
                      .middle!
                  as Text;
          expect(heading.data, contains('Cuenta renovada'));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Open editor refreshes BCV and account without resetting input', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultAccountId: 'b',
      defaultAmount: 100.0,
    );
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(MovementEditor));
    String equivalent() => tester
        .widget<DebtDetailRow>(
          find.byKey(const ValueKey('movement-preview-bcv')),
        )
        .value;
    expect(equivalent(), money(10, 'USD'));
    app.mutate(() {
      app.state['rate'] = 20.0;
      app.accountById('b')['label'] = 'Actualizada';
    });
    await tester.pumpAndSettle();
    expect(equivalent(), money(5, 'USD'));
    expect(tester.state(find.byType(MovementEditor)), same(editor));
    expect(parseAmount(editor.amount.text), 100);
    expect(find.textContaining('Actualizada'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<BalanceHero>(find.byType(BalanceHero)).rate, 20);
    app.mutate(() => app.state['rate'] = 25.0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final targetCurrency in ['USD', 'VES']) {
    testWidgets(
      'Transfer to $targetCurrency details stay visible and saving refreshes both accounts',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        app.mutate(() => app.accountById('b')['currency'] = targetCurrency);
        app.openMovementEditor(
          tester.element(find.byType(HomePage)),
          defaultType: 'transfer',
          defaultAccountId: 'a',
          defaultAmount: 20.0,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('composer-details')), findsNothing);
        if (targetCurrency == 'USD') {
          expect(find.text('Total a debitar'), findsOneWidget);
          expect(find.text('Comisión aplicada'), findsOneWidget);
        }
        final dynamic editor = tester.state(find.byType(MovementEditor));
        editor.desc.text = 'Entre mis cuentas';
        if (targetCurrency == 'VES') editor.receivedAmount.text = '200';
        await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
        await tester.pumpAndSettle();
        expect(find.byType(MovementEditor), findsNothing);
        expect(app.accountById('a')['balance'], 80);
        expect(
          app.accountById('b')['balance'],
          targetCurrency == 'USD' ? 120 : 300,
        );
        expect(
          tester.widget<BalanceHero>(find.byType(BalanceHero)).usdBalance,
          targetCurrency == 'USD' ? 200 : 80,
        );
        expect(
          app.maps('movements').single['description'],
          'Entre mis cuentas',
        );
        expect(app.undoLastOperation(), true);
        await tester.pumpAndSettle();
        expect(app.accountById('a')['balance'], 100);
        expect(app.accountById('b')['balance'], 100);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
