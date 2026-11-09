import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  Map<String, dynamic> debt(double paid, {String status = 'pending'}) => {
    'id': 'settled',
    'amount': 29.19,
    'paidAmount': paid,
    'status': status,
    'paidAt': status == 'paid' ? '2026-10-01T10:00:00' : '',
    'hasInstallments': true,
    'installments': 3,
    'installmentMode': 'auto',
    'dueDate': '01/10/2026',
    'paymentFrequency': 'Mensual',
  };

  test('Binary residue never reopens a paid debt or its installments', () {
    final old = debt(29.189999999999998, status: 'paid');
    expect(debtRemainingAmount(old), 0);
    expect(debtInstallmentRemainingAmounts(old), [0, 0, 0]);
    expect(debtNextPaymentAmount(old), 0);
    expect(normalizeDebtMoney(old)['paidAmount'], 29.19);
  });

  test(
    'Historical paid status repairs a truncated cent without a new payment',
    () {
      final original = {
        'debts': [debt(29.18, status: 'paid')],
        'accounts': [
          {
            'id': 'a',
            'provider': 'bank',
            'balance': 50.01,
            'chartColor': 4283809213,
          },
        ],
        'movements': [
          {'id': 'm', 'amount': 29.189999999999998},
        ],
      };
      final before = jsonEncode(original);
      final normalized = withDefaults(original);
      final fixed =
          (normalized['debts'] as List).single as Map<String, dynamic>;
      expect(fixed['paidAmount'], 29.19);
      expect(fixed['paidAt'], '2026-10-01T10:00:00');
      expect(normalized['accounts'], original['accounts']);
      expect(normalized['movements'], original['movements']);
      expect(jsonEncode(original), before);
      expect(withDefaults(normalized)['debts'], normalized['debts']);
    },
  );

  test(
    'A genuine pending cent, invalid paid status and fractions are preserved',
    () {
      expect(debtRemainingAmount(debt(29.18)), .01);
      expect(debtRemainingAmount(debt(29.17, status: 'paid')), .02);
      expect(debtMoney(29.189), 29.18);
      expect(debtMoney(29.180000001), 29.18);
      expect(debtRemainingAmount(debt(29.189)), .01);
      // The requested truncation policy is unchanged outside historical debt precision.
      expect(moneyRound(889.579), 889.57);
      expect(moneyConvert(1, 889.579), 889.57);
    },
  );

  test('Installment allocations use repaired cents but retain selected installments', () {
    final partial = debt(9.729999999999999)
      ..['installmentPayments'] = {
        'm': {'index': 2, 'amount': 9.729999999999999},
      };
    expect(debtInstallmentPaidAmounts(partial), [0, 0, 9.73]);
    expect(debtInstallmentRemainingAmounts(partial), [9.73, 9.73, 0]);
    expect(
      normalizeDebtMoney(partial)['installmentPayments']['m']['amount'],
      9.73,
    );
  });

  test(
    'Installment validation and payment credit share the same conversion',
    () {
      final movement = {
        'currency': 'VES',
        'amount': 8833.91,
        'debtExchangeRate': 883.391,
      };
      expect(
        debtMovementValue(movement, {'currency': 'USD'}, 1),
        debtCreditForPayment(8833.91, 883.391),
      );
    },
  );
}
