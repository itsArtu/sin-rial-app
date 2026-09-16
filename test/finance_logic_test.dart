import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  group('Decimal money', () {
    test('cent arithmetic does not accumulate binary drift', () {
      var balance = 0.0;
      for (var i = 0; i < 1000; i++) {
        balance = moneyAdd(balance, .01);
      }
      expect(balance, 10);
      expect(moneyAdd(.1, .2), .3);
      expect(moneySubtract(.3, .2), .1);
      expect(moneyRound(1.005), 1.01);
      expect(moneyConvert(100, .003), .3);
      expect(moneyConvert(2, 842.2067), 1684.41);
      expect(parseAmount('842.2067'), 842.2067);
      expect(parseAmount('1.234,56'), 1234.56);
      expect(() => moneyRound(double.nan), throwsFormatException);
      expect(() => moneyConvert(10, 1, 0), throwsFormatException);
    });

    test('installments preserve total and absorb the remainder', () {
      expect(splitInstallments(100, 3), [33.33, 33.33, 33.34]);
      expect(splitInstallments(50, 2), [25, 25]);
      final debt = <String, dynamic>{
        'amount': 100.0,
        'paidAmount': 66.66,
        'initialAmount': 0.0,
        'hasInstallments': true,
        'installments': 3,
        'installmentMode': 'auto',
        'installmentAmount': 33.33,
      };
      expect(debtNextInstallmentIndex(debt), 2);
      expect(debtNextPaymentAmount(debt), 33.34);
      debt['paidAmount'] = 10.0;
      expect(debtNextInstallmentIndex(debt), 0);
      expect(debtNextPaymentAmount(debt), 23.33);
      debt.addAll({
        'initialAmount': 50.0,
        'paidAmount': 50.0,
        'installments': 2,
      });
      expect(debtNextPaymentAmount(debt), 25);
      debt['paidAmount'] = 100.0;
      expect(debtNextPaymentAmount(debt), 0);
    });
  });

  group('Balance reconstruction', () {
    final now = DateTime(2026, 9, 16, 12, 30);
    final accounts = <Map<String, dynamic>>[
      {'id': 'a', 'currency': 'USD', 'balance': 138.0},
    ];
    final movements = <Map<String, dynamic>>[
      {
        'accountId': 'a',
        'type': 'income',
        'amount': 50.0,
        'date': '16/09/2026 10:00 AM',
      },
      {
        'accountId': 'a',
        'type': 'expense',
        'amount': 10.0,
        'feeAmount': 2.0,
        'date': '16/09/2026 11:00 AM',
      },
    ];

    test('day includes real incomes, expenses and fees', () {
      final points = buildBalanceTrend(
        accounts: accounts,
        movements: movements,
        convertValue: (v, _) => v,
        period: 'day',
        now: now,
      );
      expect(points.first.amount, 100);
      expect(points[10].amount, 150);
      expect(points[11].amount, 138);
      expect(points.last.date, now);
      expect(points.last.amount, 138);
    });

    test('week and month have calendar boundaries', () {
      for (final period in ['week', 'month']) {
        final points = buildBalanceTrend(
          accounts: accounts,
          movements: movements,
          convertValue: (v, _) => v,
          period: period,
          now: now,
        );
        expect(points.first.date, DateTime(2026, 9, period == 'week' ? 10 : 1));
        expect(points.first.amount, 100);
        expect(points.last.amount, 138);
      }
      expect(
        balancePeriodStart(DateTime(2027, 1, 2), 'week'),
        DateTime(2026, 12, 27),
      );
    });

    test(
      'internal transfers cancel except fees and selected scope matters',
      () {
        final accounts = <Map<String, dynamic>>[
          {'id': 'a', 'currency': 'USD', 'balance': 89.0},
          {'id': 'b', 'currency': 'VES', 'balance': 600.0},
        ];
        final transfers = <Map<String, dynamic>>[
          {
            'accountId': 'a',
            'targetAccountId': 'b',
            'type': 'transfer',
            'amount': 10.0,
            'feeAmount': 1.0,
            'targetAmount': 100.0,
            'date': '16/09/2026 10:00 AM',
          },
        ];
        double value(double v, String c) => c == 'VES' ? v / 10 : v;
        final all = buildBalanceTrend(
          accounts: accounts,
          movements: transfers,
          convertValue: value,
          period: 'day',
          now: now,
        );
        expect(all.first.amount, 150);
        expect(all.last.amount, 149);
        final ves = buildBalanceTrend(
          accounts: [accounts.last],
          movements: transfers,
          convertValue: value,
          period: 'day',
          now: now,
        );
        expect(ves.first.amount, 50);
        expect(ves.last.amount, 60);
      },
    );

    test('new accounts and explicit balance adjustments are dated', () {
      final points = buildBalanceTrend(
        accounts: [
          {
            'id': 'a',
            'balance': 125.0,
            'currency': 'USD',
            'createdAt': '2026-09-16T09:00:00',
          },
        ],
        movements: [],
        adjustments: [
          {'accountId': 'a', 'amount': 25.0, 'date': '2026-09-16T11:00:00'},
        ],
        convertValue: (v, _) => v,
        period: 'day',
        now: now,
      );
      expect(points.first.amount, 0);
      expect(points[9].amount, 100);
      expect(points.last.amount, 125);
      expect(
        parseMovementDate('2026-09-16T11:00:00'),
        DateTime(2026, 9, 16, 11),
      );
    });
  });

  group('Combined movement filters', () {
    final accounts = <String, Map<String, dynamic>>{
      'a': {'id': 'a', 'provider': 'cash', 'label': 'Efectivo personal'},
      'b': {'id': 'b', 'provider': 'cash', 'label': 'Ahorro'},
    };
    final movement = <String, dynamic>{
      'type': 'transfer',
      'accountId': 'a',
      'targetAccountId': 'b',
      'currency': 'USD',
      'targetCurrency': 'VES',
      'category': 'Otro',
      'amount': 280.0,
      'description': 'Depósito de José',
      'date': '16/09/2026 11:59 PM',
    };
    test('accent insensitive token search and destination account', () {
      final filter = MovementFilter(
        query: 'jose deposito ahorro',
        accountId: 'b',
        type: 'transfer',
        currency: 'VES',
        category: 'Otro',
        start: DateTime(2026, 9, 16),
        end: DateTime(2026, 9, 16),
      );
      expect(filter.matches(movement, accounts), isTrue);
      expect(
        const MovementFilter(query: 'missing').matches(movement, accounts),
        isFalse,
      );
      expect(
        const MovementFilter(type: 'income').matches(movement, accounts),
        isFalse,
      );
      expect(
        const MovementFilter(category: 'Comida').matches(movement, accounts),
        isFalse,
      );
      expect(
        MovementFilter(end: DateTime(2026, 9, 15)).matches(movement, accounts),
        isFalse,
      );
    });
    test('sort is descending and stable for identical dates', () {
      final records = [
        {'id': 'a', 'date': '16/09/2026 10:00 AM'},
        {'id': 'b', 'date': '16/09/2026 11:00 AM'},
        {'id': 'c', 'date': '16/09/2026 11:00 AM'},
      ];
      expect(sortedMovements(records).map((m) => m['id']), ['b', 'c', 'a']);
      expect(records.first['id'], 'a');
    });
  });

  test('rate status distinguishes currency, freshness and failed attempts', () {
    final now = DateTime(2026, 9, 16, 12);
    final state = <String, dynamic>{
      'rate': 842.2067,
      'rateEffectiveDate': expectedRateDateKey(now),
      'rateFetchStatus': 'ok',
    };
    expect(rateStatusText(state, 'USD', now: now), 'Actualizada');
    expect(rateStatusText(state, 'EUR', now: now), 'Tasa no disponible');
    state['rateFetchStatus'] = 'offline';
    expect(rateStatusText(state, 'USD', now: now), contains('Sin conexión'));
    expect(state['rate'], 842.2067);
    expect(rateStatusText(state, 'USD', loading: true), 'Actualizando');
    state['rateFetchStatus'] = 'error';
    expect(
      rateStatusText(state, 'USD', now: now),
      contains('Error al actualizar'),
    );
    state.addAll({
      'usdtRate': 900.0,
      'usdtLastRateMillis': now
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
    });
    expect(rateStatusText(state, 'USDT', now: now), 'Última tasa guardada');
    state['usdtLastRateMillis'] = now.millisecondsSinceEpoch;
    expect(rateStatusText(state, 'USDT', now: now), 'Actualizada');
  });
}
