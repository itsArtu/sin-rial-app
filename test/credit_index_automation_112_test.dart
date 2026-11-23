import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'credit_index_refresh_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test('Malformed imported quotes do not stop a valid IDI valuation', () {
    final card = fixtures.indexedCard(DateTime(2026, 11, 22));
    final today = DateTime(2026, 11, 23);
    expect(
      applyOfficialCreditIndex(card, [
        {'date': 'invalid-date', 'index': '99'},
        {'date': null, 'index': '99'},
        {'date': '2026-11-23', 'index': '-2'},
        {'date': '2026-11-23', 'index': 'NaN'},
        fixtures.quote(today, '3'),
        fixtures.quote(today.add(const Duration(days: 1)), '4'),
      ], today),
      isTrue,
    );
    expect(card['creditUnits'], '-50');
    expect(card['balance'], -150);
    expect(card['creditLimit'], 1000);
    expect(card['creditIndexHistory'], [fixtures.quote(today, '3')]);
  });

  test(
    'Unavailable or future-only IDI leaves the saved valuation untouched',
    () {
      final today = DateTime(2026, 11, 23);
      final card = fixtures.indexedCard(today);
      final before = jsonEncode(card);
      expect(applyOfficialCreditIndex(card, [], today), isFalse);
      expect(
        applyOfficialCreditIndex(card, [
          fixtures.quote(today.add(const Duration(days: 1)), '4'),
        ], today),
        isFalse,
      );
      expect(jsonEncode(card), before);
    },
  );

  testWidgets('Unlock immediately revalues cached IDI without a bank debit', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester, index: '2');
    app.state['creditIndexQuotes'] = [fixtures.quote(DateTime.now(), '3')];
    app.locked = true;
    app.unlockApp();
    await tester.pumpAndSettle();
    expect(app.accountById('credit')['balance'], -150);
    expect(app.accountById('credit')['creditUnits'], '-50');
    expect(app.accountById('credit')['creditLimit'], 1000);
    expect(app.accountById('bank')['balance'], 500);
    expect(app.maps('movements'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Active periodic refresh applies cached IDI without user action',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester, index: '2');
      app.state['creditIndexQuotes'] = [fixtures.quote(DateTime.now(), '3')];
      await tester.pump(const Duration(minutes: 30));
      await tester.pumpAndSettle();
      expect(app.accountById('credit')['balance'], -150);
      expect(app.accountById('bank')['balance'], 500);
      expect(app.maps('movements'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
