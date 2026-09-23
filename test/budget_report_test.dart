import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final plan = <String, dynamic>{
    'id': 'september',
    'period': '2026-09',
    'periodType': 'monthly',
    'salary': 300,
    'savings': 50,
    'incomeMode': 'fixed',
    'currency': 'USD',
  };
  final items = <Map<String, dynamic>>[
    {
      'planId': 'september',
      'category': 'Comida',
      'limit': 100,
      'currency': 'USD',
    },
    {
      'planId': 'september',
      'category': 'Salud',
      'limit': 40,
      'currency': 'USD',
    },
    {
      'planId': 'september',
      'category': 'Transporte',
      'limit': 20,
      'currency': 'USD',
    },
  ];
  final accounts = <Map<String, dynamic>>[
    {'id': 'bank', 'name': 'Bancamiga', 'currency': 'VES'},
    {
      'id': 'cash',
      'name': 'Efectivo',
      'label': 'Billetera personal',
      'currency': 'USD',
    },
  ];
  Map<String, dynamic> expense(
    int day,
    String category,
    double amount, {
    String currency = 'USD',
    double fee = 0,
    String accountId = 'cash',
    String description = 'Compra',
  }) => {
    'date': formatDateTime(DateTime(2026, 9, day, 10, 30)),
    'type': 'expense',
    'category': category,
    'amount': amount,
    'currency': currency,
    'feeAmount': fee,
    'accountId': accountId,
    'description': description,
  };
  Map<String, dynamic> report(List<Map<String, dynamic>> movements) =>
      budgetReport(
        plan: plan,
        items: items,
        movements: movements,
        accounts: accounts,
        usdRate: 10,
        eurRate: 12,
        now: DateTime(2026, 10, 1, 8),
      );

  test('PDF details reconcile with the scoped summary including fees and conversion', () {
    final movements = [
      expense(30, 'Salud', 10, currency: 'EUR', fee: .5, accountId: 'deleted'),
      expense(16, 'Comida', 125, currency: 'VES', fee: 5, accountId: 'bank'),
      {...expense(17, 'Salud', 2), 'type': 'debt-payment'},
      expense(1, 'Comida', 10, currency: 'USDT'),
      expense(2, 'Transporte', 5),
      expense(0, 'Comida', 999),
      expense(31, 'Comida', 999),
      expense(5, 'Otro', 999),
      {...expense(5, 'Comida', 999), 'type': 'income'},
      {...expense(5, 'Comida', 999), 'type': 'transfer'},
    ];
    final before = jsonEncode([plan, items, accounts, movements]);
    final result = report(movements);
    final details = (result['details'] as List).cast<Map>();
    expect(details, hasLength(5));
    expect(details.first['date'], '01/09/2026 10:30 AM');
    expect(details.first['total'], r'$10,00');
    expect(details.first['account'], 'Billetera personal');
    expect(details.last['account'], 'Cuenta no disponible');
    expect(details.last['fee'], '0,50');
    expect(details.last['total'], r'$12,60');
    expect(details[2]['account'], 'Bancamiga');
    expect(details[2]['amount'], '125,00');
    final sum = details.fold<double>(
      0,
      (sum, row) => moneyAdd(sum, row['totalValue'] as double),
    );
    expect(result['spent'], money(sum, 'USD'));
    expect(result['spent'], r'$42,60');
    expect(result['remaining'], r'$117,40');
    expect(result['unassigned'], r'$90,00');
    expect(result['rateNote'], contains('no tasas hist'));
    expect(jsonEncode([plan, items, accounts, movements]), before);
  });

  test('PDF states usage and category excess even while the whole plan is within budget', () {
    final result = report([expense(20, 'Salud', 60)]);
    final row = (result['rows'] as List).first as Map;
    expect(row['name'], 'Salud');
    expect(row['usage'], '150,00%');
    expect(row['share'], '100,00%');
    expect(row['excess'], r'$20,00');
    expect(row['remaining'], r'-$20,00');
    expect(result['exceededCategories'], 1);
    expect(result['over'], false);
    expect(result['usage'], '37,50%');
  });

  test('PDF handles empty plans, zero limits and variable income without invalid percentages', () {
    final empty = budgetReport(
      plan: {...plan, 'incomeMode': 'variable'},
      items: [],
      movements: [],
      usdRate: 0,
      eurRate: 0,
    );
    expect(empty['usage'], '--');
    expect(empty['unassigned'], null);
    expect(empty['rows'], isEmpty);
    expect(empty['spent'], r'$0,00');
    final zero = budgetReport(
      plan: plan,
      items: [
        {
          'planId': 'september',
          'category': 'Comida',
          'limit': 0,
          'currency': 'USD',
        },
      ],
      movements: [expense(1, 'Comida', 1)],
      usdRate: 0,
      eurRate: 0,
    );
    expect(zero['usage'], '--');
    expect((zero['rows'] as List).first['excess'], r'$1,00');
  });

  test('PDF converts combined fee and amount with the same cent rounding as the plan', () {
    final result = budgetReport(
      plan: plan,
      items: items,
      movements: [expense(1, 'Comida', .01, currency: 'VES', fee: .01)],
      usdRate: 3,
      eurRate: 4,
    );
    expect(result['spent'], r'$0,01');
    expect((result['details'] as List).single['total'], r'$0,01');
  });

  test('PDF renders a realistic summary, empty report and a multi-page movement ledger', () async {
    final font = await rootBundle.load('assets/fonts/Manrope-Medium.ttf');
    final dir = Directory('build/budget-report-qa')
      ..createSync(recursive: true);
    for (final count in [0, 8, 120]) {
      final result = report(
        List.generate(
          count,
          (i) => expense(
            i % 30 + 1,
            ['Comida', 'Salud', 'Transporte'][i % 3],
            [125.0, 35.0, 10.0][i % 3],
            currency: i % 3 == 0 ? 'VES' : 'USD',
            fee: i % 3 == 0 ? .38 : 0,
            accountId: i % 3 == 0 ? 'bank' : 'cash',
            description: [
              'Mercado de la semana',
              'Medicamentos y consulta m\u00e9dica',
              'Pasaje al trabajo',
            ][i % 3],
          ),
        ),
      );
      final bytes = await renderBudgetPdf({...result, 'font': font});
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(5000));
      await File('${dir.path}/budget-$count.pdf').writeAsBytes(bytes);
    }
  });
}
