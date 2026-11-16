import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'credit_cards_test.dart' as cards;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });
  test('A limit increase changes neither debt nor bank funds', () {
    final before = cards.card();
    final after = cardWithNewLimit(before, 2000, DateTime(2026, 11, 16));
    expect(before['creditLimit'], 1000);
    expect(after['creditLimit'], 2000);
    expect(creditDebt(after), 100);
    expect(creditAvailable(after), 1900);
    expect(after['creditLimitHistory'], hasLength(1));
    expect(
      cardWithNewLimit(after, 2000, DateTime.now())['creditLimitHistory'],
      hasLength(1),
    );
    expect(
      () => cardWithNewLimit(before, double.nan, DateTime.now()),
      throwsFormatException,
    );
    expect(
      () => cardWithNewLimit(before, 0, DateTime.now()),
      throwsFormatException,
    );
  });
  testWidgets(
    'Ubii receives net money; card owes gross; fee is not added twice',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveAccount({
        ...cards.card(currency: 'VES'),
        'creditLimit': 50000.0,
        'balance': 0.0,
        'creditMinimumDue': 0.0,
      });
      app.saveAccount({
        'id': 'ubii',
        'kind': 'wallet',
        'provider': 'UBII',
        'currency': 'VES',
        'balance': 0.0,
      });
      Map<String, dynamic> topup(double sent, double received) => {
        ...fixtures.movement('transfer', id: 'topup', amount: sent),
        'accountId': 'credit',
        'currency': 'VES',
        'targetAccountId': 'ubii',
        'targetCurrency': 'VES',
        'targetAmount': received,
        'exchangeInput': 'received',
        'feeTreatment': 'deducted',
      };
      app.saveMovement(topup(10000, 9650));
      expect(creditDebt(app.accountById('credit')), 10000);
      expect(app.accountById('ubii')['balance'], 9650);
      expect(app.movementById('topup')['feeAmount'], 350);
      expect(app.movementById('topup')['feePercent'], 3.5);
      expect(movementDebitAmount(app.movementById('topup')), 10000);
      app.saveMovement(topup(5000, 4900), editingId: 'topup');
      expect(creditDebt(app.accountById('credit')), 5000);
      expect(app.accountById('ubii')['balance'], 4900);
      expect(app.movementById('topup')['feeAmount'], 100);
      app.deleteMovement(app.movementById('topup'));
      expect(creditDebt(app.accountById('credit')), 0);
      expect(app.accountById('ubii')['balance'], 0);
      expect(() => app.saveMovement(topup(100, 101)), throwsFormatException);
      expect(() => app.saveMovement(topup(100, 0)), throwsFormatException);
      expect(
        () => app.saveMovement(topup(100, 99)..['targetAccountId'] = 'b'),
        throwsFormatException,
      );
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'Indexed credit preserves units when IDI changes and reverses original units',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      const stamp = '2026-09-16T00:00:00.000';
      app.saveAccount({
        ...cards.card(currency: 'VES'),
        'creditBasis': 'uvc',
        'creditIndex': 2.0,
        'creditIndexDate': stamp,
      });
      expect(app.accountById('credit')['creditUnits'], '-50');
      final expense = {
        ...fixtures.movement('expense', id: 'uvc', amount: 20),
        'accountId': 'credit',
        'currency': 'VES',
        'feeAmount': 0.0,
      };
      app.saveMovement(expense);
      expect(creditDebt(app.accountById('credit')), 120);
      expect(app.movementById('uvc')['creditSourceUnits'], '-10');
      app.saveAccount({
        ...Map<String, dynamic>.from(app.accountById('credit')),
        'creditIndex': 3.0,
      }, editingId: 'credit');
      expect(creditDebt(app.accountById('credit')), 180);
      expect(creditAvailable(app.accountById('credit')), 820);
      expect(app.maps('movements'), hasLength(1));
      app.saveMovement({...expense, 'amount': 10.0}, editingId: 'uvc');
      expect(creditDebt(app.accountById('credit')), 165);
      app.deleteMovement(app.movementById('uvc'));
      expect(creditDebt(app.accountById('credit')), 150);
      app.saveMovement({
        ...cards.payment(amount: 30),
        'id': 'pay-uvc',
        'accountId': 'b',
        'currency': 'VES',
        'targetCurrency': 'VES',
      });
      expect(creditDebt(app.accountById('credit')), 120);
      expect(app.accountById('b')['balance'], 70);
      app.deleteMovement(app.movementById('pay-uvc'));
      expect(creditDebt(app.accountById('credit')), 150);
      expect(app.accountById('b')['balance'], 100);
      expect(
        () => app.saveMovement({...expense, 'date': '17/09/2026 11:00 AM'}),
        throwsFormatException,
      );
      await tester.pumpAndSettle();
    },
  );
  test('IDI validation never substitutes the USD exchange rate', () {
    expect(() => creditUnitsFor(100, 0), throwsFormatException);
    expect(() => creditUnitsFor(100, double.nan), throwsFormatException);
    final card = {
      ...cards.card(),
      'creditBasis': 'uvc',
      'creditIndex': 2.0,
      'creditIndexDate': '2026-11-16',
    };
    expect(() => validateCreditAccount(card), throwsFormatException);
    expect(isIndexedCredit(cards.card(currency: 'VES')), isFalse);
  });
  testWidgets(
    'Full UVC settlement clears fractional units and can be reversed',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveAccount({
        ...cards.card(currency: 'VES'),
        'balance': -1.0,
        'creditMinimumDue': 0.0,
        'creditBasis': 'uvc',
        'creditIndex': 3.0,
        'creditIndexDate': '2026-09-16',
      });
      app.saveAccount({
        ...Map<String, dynamic>.from(app.accountById('credit')),
        'creditIndex': 4.0,
      }, editingId: 'credit');
      expect(creditDebt(app.accountById('credit')), 1.33);
      app.saveMovement({
        ...cards.payment(amount: 1.33),
        'id': 'full',
        'accountId': 'b',
        'currency': 'VES',
        'targetCurrency': 'VES',
      });
      expect(app.accountById('credit')['creditUnits'], '0');
      app.saveAccount({
        ...Map<String, dynamic>.from(app.accountById('credit')),
        'creditIndex': 5.0,
      }, editingId: 'credit');
      expect(creditDebt(app.accountById('credit')), 0);
      app.deleteMovement(app.movementById('full'));
      expect(creditDebt(app.accountById('credit')), 1.66);
      expect(app.accountById('b')['balance'], 100);
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'An existing nominal card can be indexed without losing reversibility',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveAccount({
        ...cards.card(currency: 'VES'),
        'creditMinimumDue': 0.0,
      });
      final expense = {
        ...fixtures.movement('expense', id: 'legacy', amount: 20),
        'accountId': 'credit',
        'currency': 'VES',
      };
      app.saveMovement(expense);
      app.saveAccount({
        ...Map<String, dynamic>.from(app.accountById('credit')),
        'creditBasis': 'uvc',
        'creditIndex': 2.0,
        'creditIndexDate': '2026-09-16',
      }, editingId: 'credit');
      app.saveAccount({
        ...Map<String, dynamic>.from(app.accountById('credit')),
        'creditIndex': 3.0,
      }, editingId: 'credit');
      app.saveMovement({...expense, 'amount': 15.0}, editingId: 'legacy');
      expect(creditDebt(app.accountById('credit')), 165);
      app.deleteMovement(app.movementById('legacy'));
      expect(creditDebt(app.accountById('credit')), 150);
      await tester.pumpAndSettle();
    },
  );
  test('SoyTechno never enables a direct advance through an imported flag', () {
    expect(
      allowsDirectCreditAdvance({
        ...cards.card(),
        'cardDesign': 'bnc-soytechno',
        'creditCashAdvance': true,
      }),
      isFalse,
    );
    expect(
      allowsDirectCreditAdvance({...cards.card(), 'creditCashAdvance': true}),
      isTrue,
    );
  });
  test('Suggestions separate operation types and normalize descriptions', () {
    final index = MovementSuggestionIndex([
      {
        ...fixtures.movement('expense', id: 'one'),
        'description': '  Super Mercado ',
        'category': 'Comida',
      },
      {
        ...fixtures.movement('income', id: 'two'),
        'description': 'super mercado',
        'accountId': 'b',
      },
    ]);
    expect(index.find('expense', 'SUPER   MERCADO')?.category, 'Comida');
    expect(index.find('income', 'super mercado')?.accountId, 'b');
    expect(index.find('transfer', 'super mercado'), isNull);
    expect(index.find('expense', 'Su'), isNull);
  });
  test(
    'Duplicates require same account, cents, date and transfer destination',
    () {
      final movement = {...fixtures.movement('expense'), 'description': 'Café'};
      expect(
        possibleDuplicateMovement({...movement, 'id': 'new'}, [movement]),
        isNotNull,
      );
      for (final change in [
        {'accountId': 'b'},
        {'amount': 20.01},
        {'date': '17/09/2026 11:00 AM'},
        {'type': 'income'},
      ]) {
        expect(
          possibleDuplicateMovement({...movement, ...change}, [movement]),
          isNull,
        );
      }
      expect(
        possibleDuplicateMovement(movement, [movement], editingId: 'm'),
        isNull,
      );
      final transfer = fixtures.movement('transfer');
      expect(
        possibleDuplicateMovement(
          {...transfer, 'targetAccountId': 'other'},
          [transfer],
        ),
        isNull,
      );
    },
  );
  test(
    'Periodic backups need an explicit protected destination and schedule',
    () {
      final now = DateTime(2026, 11, 16);
      final state = <String, dynamic>{
        'automaticBackupEnabled': true,
        'automaticBackupFolder': 'content://chosen/tree/backup',
        'automaticBackupPassword': 'long-password',
        'automaticBackupFrequency': 'daily',
      };
      expect(automaticBackupDue(state, now), isTrue);
      expect(
        automaticBackupDue({
          ...state,
          'automaticBackupLast': now
              .subtract(const Duration(hours: 23))
              .toIso8601String(),
        }, now),
        isFalse,
      );
      expect(
        automaticBackupDue({
          ...state,
          'automaticBackupLast': now
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        }, now),
        isTrue,
      );
      expect(
        automaticBackupDue({
          ...state,
          'automaticBackupFrequency': 'weekly',
          'automaticBackupLast': now
              .subtract(const Duration(days: 6))
              .toIso8601String(),
        }, now),
        isFalse,
      );
      expect(
        automaticBackupDue({
          ...state,
          'automaticBackupFrequency': 'weekly',
          'automaticBackupLast': now
              .subtract(const Duration(days: 7))
              .toIso8601String(),
        }, now),
        isTrue,
      );
      expect(
        automaticBackupDue({...state, 'automaticBackupEnabled': false}, now),
        isFalse,
      );
      expect(
        automaticBackupDue({...state, 'automaticBackupFolder': ''}, now),
        isFalse,
      );
      expect(
        automaticBackupDue({...state, 'automaticBackupPassword': ''}, now),
        isFalse,
      );
    },
  );
  test('Designs do not leak between issuers or to debit accounts', () {
    expect(
      designsForBank('0172', credit: true).where((d) => d.partner.isNotEmpty),
      hasLength(2),
    );
    expect(
      designsForBank('0172', credit: false).where((d) => d.partner.isNotEmpty),
      isEmpty,
    );
  });
  testWidgets(
    'Credit-to-Ubii composer keeps net amount editable and saves fee once',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveAccount({
        ...cards.card(currency: 'VES'),
        'balance': 0.0,
        'creditMinimumDue': 0.0,
        'creditLimit': 50000.0,
      });
      app.mutate(
        () => app.accountById('b').addAll({
          'provider': 'UBII',
          'kind': 'wallet',
          'balance': 0.0,
        }),
      );
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        defaultType: 'transfer',
        defaultAccountId: 'credit',
        defaultTargetAccountId: 'b',
        lockAccount: true,
      );
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(find.byType(MovementEditor));
      expect(editor.usesReceivedAmount, isTrue);
      editor.amount.text = '10000.00';
      editor.receivedAmount.text = '9650.00';
      await editor.save();
      await tester.pumpAndSettle();
      expect(creditDebt(app.accountById('credit')), 10000);
      expect(app.accountById('b')['balance'], 9650);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Duplicate prompt cancels by default and supports explicit override',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final context = tester.element(find.byType(HomePage));
      bool? answer;
      unawaited(
        confirmPossibleDuplicate(context, app.theme).then((v) => answer = v),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volver y revisar'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
      unawaited(
        confirmPossibleDuplicate(context, app.theme).then((v) => answer = v),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar de todos modos'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
      expect(app.maps('movements'), isEmpty);
    },
  );
  testWidgets(
    'Budget suggestion opens an editable draft without saving or changing funds',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final now = DateTime.now();
      final previous = DateTime(now.year, now.month - 1, 10);
      app.saveMovement({
        ...fixtures.movement('expense', amount: 12.34),
        'date': formatDate(previous),
        'category': 'Comida',
      });
      final accounts = jsonEncode(app.maps('accounts'));
      app.setTab(1);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('budget-suggest')));
      await tester.tap(find.byKey(const ValueKey('budget-suggest')));
      await tester.pumpAndSettle();
      final page = tester.widget<BudgetPlanEditorPage>(
        find.byType(BudgetPlanEditorPage),
      );
      expect(page.suggestedItems.single['limit'], 12.34);
      expect(page.suggestedItems.single['category'], 'Comida');
      expect(app.maps('budgetPlans'), isEmpty);
      expect(jsonEncode(app.maps('accounts')), accounts);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
