import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  test('display truncates two decimals toward zero, without binary drift', () {
    for (final value in [889.579, 889.579999, 889.57]) {
      expect(formatNumber(value), '889,57');
      expect(formatNumberTruncated(value, decimals: 2), '889,57');
      expect(plain(value), '889.57');
    }
    expect(formatNumber(-1.999), '-1,99');
    expect(formatNumber(.29), '0,29');
    expect(formatNumber(1234567.999), '1.234.567,99');
    expect(formatNumber(.009), '0,00');
  });
  test('new conversions and cent arithmetic truncate without changing stored source', () {
    expect(moneyConvert(1, 889.579), 889.57);
    expect(moneyConvert(20, 1, 3), 6.66);
    expect(moneyConvert(-20, 1, 3), -6.66);
    expect(moneyRound(1.999), 1.99);
    expect(moneyAdd(.1, .2), .3);
    expect(moneySubtract(10, .29), 9.71);
    expect(moneyConvert(.29, 100), 29);
    expect(List.filled(100, .29).fold<double>(0, moneyAdd), 29);
    expect(
      convertCurrencyAmount(.29, 'USD', 'VES', usdVes: 100, eurVes: 110),
      29,
    );
    final source = {'amount': 10.999};
    formatNumber(source['amount']!);
    expect(source['amount'], 10.999);
  });
  test('category totals do not lose a cent after repeated additions', () {
    final movements = List.generate(
      100,
      (_) => <String, dynamic>{
        'type': 'expense',
        'category': 'Otro',
        'currency': 'USD',
        'amount': .29,
        'date': '02/11/2026 10:00 AM',
      },
    );
    expect(
      spentForCategory(movements, 'Otro', 'USD', 889.57, month: '2026-11'),
      29,
    );
  });
}
