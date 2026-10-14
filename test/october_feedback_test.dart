import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' as budgets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test(
    'TDC tokens and snack names infer their categories without substrings',
    () {
      for (final text in ['TDC', 'abono TDC octubre', 'pague tdc']) {
        expect(categoryFromDescription(text), 'Pago TDC');
      }
      expect(categoryFromDescription('xtdcx'), isNull);
      for (final text in [
        'Doritos',
        'Cheese Tris',
        'Chocolate',
        'dulces',
        'snacks',
        'galletas',
      ]) {
        expect(categoryFromDescription(text), 'Chucherías');
      }
      expect(
        categoryFromDescription(
          'Doritos',
          custom: [
            {
              'name': 'Mi compra',
              'keywords': ['doritos'],
            },
          ],
        ),
        'Mi compra',
      );
    },
  );

  test(
    'Installments preserve specific assignments and allocate legacy cents',
    () {
      final debt = <String, dynamic>{
        'amount': 110.5,
        'initialAmount': 11.05,
        'paidAmount': 27.63,
        'hasInstallments': true,
        'installments': 6,
        'installmentMode': 'auto',
        'installmentPayments': {
          'm': {'index': 5, 'amount': 16.58},
        },
      };
      expect(debtInstallmentPaidAmounts(debt), [0, 0, 0, 0, 0, 16.58]);
      expect(debtNextInstallmentIndex(debt), 0);
      debt['paidAmount'] = 44.20;
      expect(debtInstallmentPaidAmounts(debt), [16.57, 0, 0, 0, 0, 16.58]);
      expect(debtNextInstallmentIndex(debt), 1);
      debt['installmentPayments'] = {};
      expect(debtInstallmentPaidAmounts(debt), [16.57, 16.57, .01, 0, 0, 0]);
    },
  );

  testWidgets(
    'Specific cuota payment converts currency, edits, deletes and undoes',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() {
        app.debtById('d').addAll({
          'paidAmount': 0.0,
          'amount': 60.0,
          'hasInstallments': true,
          'installments': 3,
          'installmentMode': 'auto',
          'dueDate': '15/10/2026',
        });
        app.accountById('b')['balance'] = 1000.0;
      });
      final payment = <String, dynamic>{
        ...fixtures.movement('expense', amount: 200),
        'accountId': 'b',
        'currency': 'VES',
        'debtId': 'd',
        'debtExchangeRate': 10.0,
        'debtInstallmentIndex': 2,
        'feeAmount': 0.0,
      };
      app.saveMovement(payment);
      expect(app.debtById('d')['paidAmount'], 20);
      expect(debtInstallmentPaidAmounts(app.debtById('d')), [0, 0, 20]);
      expect(app.accountById('b')['balance'], 800);
      expect(
        () => app.saveMovement({...payment, 'id': 'over'}),
        throwsFormatException,
      );
      app.saveMovement({
        ...payment,
        'amount': 100.0,
        'debtInstallmentIndex': 1,
      }, editingId: 'm');
      expect(debtInstallmentPaidAmounts(app.debtById('d')), [0, 10, 0]);
      expect(app.accountById('b')['balance'], 900);
      app.deleteMovement(app.movementById('m'));
      expect(debtInstallmentPaidAmounts(app.debtById('d')), [0, 0, 0]);
      expect(app.accountById('b')['balance'], 1000);
      expect(app.undoLastOperation(), isTrue);
      expect(debtInstallmentPaidAmounts(app.debtById('d')), [0, 10, 0]);
      expect(app.undoLastOperation(), isTrue);
      expect(debtInstallmentPaidAmounts(app.debtById('d')), [0, 0, 20]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final currency in ['USD', 'VES']) {
    testWidgets('Loan receipt $currency is atomic and never pays the debt', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      final account = currency == 'USD' ? 'a' : 'b';
      final debt = <String, dynamic>{
        'id': 'loan',
        'title': 'Prestamo',
        'kind': 'payable',
        'currency': currency,
        'amount': 25.0,
        'paidAmount': 0.0,
        'partyType': 'Persona',
      };
      app.saveDebt(debt, depositAccountId: account);
      expect(app.accountById(account)['balance'], 125);
      expect(app.debtById('loan')['paidAmount'], 0);
      final receipt = app.maps('movements').single;
      expect(receipt['type'], 'income');
      expect(receipt['currency'], currency);
      expect(receipt['loanDebtId'], 'loan');
      expect(receipt['debtId'], isNull);
      final before = jsonEncode(app.state);
      expect(
        () => app.saveDebt(debt, editingId: 'loan', depositAccountId: account),
        throwsFormatException,
      );
      expect(jsonEncode(app.state), before);
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById(account)['balance'], 100);
      expect(app.debtById('loan'), isNull);
      expect(app.maps('movements'), isEmpty);
      expect(
        () => app.saveDebt({
          ...debt,
          'partyType': 'Cashea',
        }, depositAccountId: account),
        throwsFormatException,
      );
      expect(
        () => app.saveDebt(debt, depositAccountId: account == 'a' ? 'b' : 'a'),
        throwsFormatException,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final category in ['Recarga saldo', 'Pago TDC']) {
    testWidgets(
      '$category strips method and fee even on edited legacy movements',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        app.saveMovement({
          ...fixtures.movement('expense'),
          'accountId': 'b',
          'currency': 'VES',
          'category': category,
          'paymentMethod': 'payment_mobile_p2p',
          'feeAmount': 10.0,
          'feeMode': 'manual',
          'bankTransferScope': 'other',
        });
        expect(app.movementById('m')['paymentMethod'], '');
        expect(app.movementById('m')['feeAmount'], 0);
        expect(app.accountById('b')['balance'], 80);
        app.saveMovement(<String, dynamic>{
          ...app.movementById('m'),
          'amount': 30.0,
          'feeAmount': 5.0,
        }, editingId: 'm');
        expect(app.accountById('b')['balance'], 70);
        expect(app.movementById('m')['feeAmount'], 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Category projection preserves legacy limits and financial records',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() => app.state['eurRate'] = 11.2);
      budgets.plan(
        app,
        '2026-09',
        items: [
          {
            'category': 'Barberia',
            'name': 'Afeitada',
            'limit': 25.0,
            'currency': 'EUR',
          },
        ],
      );
      final items = budgetPlanItems(app, 'monthly:2026-09');
      app.saveMovement({
        ...fixtures.movement('expense', amount: 28),
        'category': 'Barberia',
      });
      final accounts = jsonEncode(app.maps('accounts'));
      final debts = jsonEncode(app.maps('debts'));
      final movements = jsonEncode(app.maps('movements'));
      final categories = budgetCategoryLimits(
        items,
        usdRate: app.rate,
        eurRate: app.eurRate,
      );
      final spending = summarizeBudgetSpending(
        app.maps('movements'),
        '2026-09',
        'monthly',
        usdRate: app.rate,
        eurRate: app.eurRate,
      );
      expect(categories.single['name'], '');
      expect(categories.single['currency'], 'EUR');
      expect(categories.single['limit'], 25);
      expect(spending.categories['Barberia'], 28);
      expect(spending.total, 28);
      expect(jsonEncode(app.maps('accounts')), accounts);
      expect(jsonEncode(app.maps('debts')), debts);
      expect(jsonEncode(app.maps('movements')), movements);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
