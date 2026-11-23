import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'credit_cards_test.dart' as cards;

Map<String, dynamic> indexedCard(DateTime date) => cards.card(currency: 'VES')
  ..addAll({
    'provider': '0172',
    'cardNetwork': 'mastercard',
    'creditBasis': 'uvc',
    'creditIndex': '2',
    'creditIndexDate': date.toIso8601String(),
    'creditUnits': '-50',
    'creditLimitUnits': '500',
    'creditLimit': 1000.0,
    'balance': -100.0,
  });

Map<String, dynamic> quote(DateTime date, String index) => {
  'date': DateTime(date.year, date.month, date.day).toIso8601String(),
  'index': index,
};

Future<dynamic> fixture(WidgetTester tester, {String index = '3'}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final now = DateTime.now();
  final state = defaultState()
    ..addAll({
      'onboardingComplete': true,
      'securitySetupComplete': true,
      'rate': 10.0,
      'rateEffectiveDate': expectedRateDateKey(now),
      'creditIndexQuotes': [quote(now, index)],
      'creditIndexCheckedAt': now.toIso8601String(),
      'accounts': [
        {
          'id': 'bank',
          'kind': 'national',
          'provider': '0172',
          'currency': 'VES',
          'balance': 500.0,
        },
        indexedCard(DateTime(now.year, now.month, now.day - 1)),
      ],
      'movements': <Map<String, dynamic>>[],
    });
  await tester.pumpWidget(RialApp(initialState: state));
  await tester.pumpAndSettle();
  return tester.state(find.byType(RialApp));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test('Daily IDI revalues only debt, keeping the approved VES limit', () {
    final card = indexedCard(DateTime(2026, 11, 17))
      ..addAll({
        'creditLimit': 357000.0,
        'creditLimitUnits': '78934.36',
        'creditUnits': '-71391.15',
        'creditIndex': '4.47704199',
        'balance': -319621.17,
      });
    final quotes = [quote(DateTime(2026, 11, 18), '4.48144253')];
    expect(
      applyOfficialCreditIndex(card, quotes, DateTime(2026, 11, 18)),
      true,
    );
    expect(card['creditLimit'], 357000);
    expect(card['balance'], -319935.33);
    expect(card['creditUnits'], '-71391.15');
    expect(creditAvailable(card), 37064.67);
    expect(
      indexedCreditAvailableUnits(card).toDouble(),
      closeTo(357000 / 4.48144253 - 71391.15, 1e-8),
    );
    final snapshot = jsonEncode(card);
    expect(
      applyOfficialCreditIndex(card, quotes, DateTime(2026, 11, 18)),
      false,
    );
    expect(jsonEncode(card), snapshot);
    expect(
      applyOfficialCreditIndex(card, [
        quote(DateTime(2026, 11, 17), '4.47704199'),
      ], DateTime(2026, 11, 18)),
      false,
    );
    expect(jsonEncode(card), snapshot);
  });

  test('November 17 adjustment uses November 16 debt valuation', () {
    final card = indexedCard(DateTime(2026, 11, 16))
      ..addAll({
        'creditLimit': 357000.0,
        'creditUnits': '-71391.15',
        'creditIndex': '4.46860465',
        'balance': -319018.82,
      });
    final before = creditDebt(card);
    applyOfficialCreditIndex(card, [
      quote(DateTime(2026, 11, 17), '4.47704199'),
    ], DateTime(2026, 11, 17));
    expect(card['creditLimit'], 357000);
    expect(card['balance'], -319621.17);
    expect(moneySubtract(creditDebt(card), before), 602.35);
    expect(creditAvailable(card), 37378.83);
  });

  test(
    'Cached future quote activates on its date and does not mint credit',
    () {
      final card = indexedCard(DateTime(2026, 11, 17));
      final quotes = [
        quote(DateTime(2026, 11, 17), '2'),
        quote(DateTime(2026, 11, 18), '3'),
      ];
      applyOfficialCreditIndex(card, quotes, DateTime(2026, 11, 17, 23, 59));
      expect(creditAvailable(card), 900);
      applyOfficialCreditIndex(card, quotes, DateTime(2026, 11, 18));
      expect(creditAvailable(card), 850);
      expect(card['creditLimit'], 1000);
      expect(card['creditUnits'], '-50');
    },
  );

  test('Only an explicit limit increase changes approved credit', () {
    final card = indexedCard(DateTime(2026, 11, 17));
    applyOfficialCreditIndex(card, [
      quote(DateTime(2026, 11, 18), '3'),
    ], DateTime(2026, 11, 18));
    final increased = cardWithNewLimit(card, 2000, DateTime(2026, 11, 18));
    expect(increased['creditLimit'], 2000);
    expect(increased['creditUnits'], '-50');
    expect(creditAvailable(increased), 1850);
    applyOfficialCreditIndex(increased, [
      quote(DateTime(2026, 11, 19), '4'),
    ], DateTime(2026, 11, 19));
    expect(increased['creditLimit'], 2000);
    expect(creditAvailable(increased), 1800);
  });

  test('An exhausted limit never displays negative available UVC', () {
    final card = indexedCard(DateTime(2026, 11, 17))..['creditUnits'] = '-600';
    refreshIndexedCreditBalance(card);
    expect(card['balance'], -1200);
    expect(creditAvailable(card), 0);
    expect(indexedCreditAvailableUnits(card).toString(), '0');
  });

  test(
    'UVC reconciliation requires a valid index and anchors nominal limit',
    () {
      final card = indexedCard(DateTime(2026, 11, 17));
      setCreditUvcAmounts(card, '50', '450');
      expect(card['creditLimit'], 1000);
      expect(card['balance'], -100);
      for (final invalid in [0, -1, double.nan, double.infinity]) {
        final broken = {...card, 'creditIndex': invalid};
        expect(
          () => setCreditUvcAmounts(broken, '50', '450'),
          throwsFormatException,
        );
      }
    },
  );

  test('An early stale IDI response can be retried later the same day', () {
    final now = DateTime(2026, 11, 18, 9);
    final quotes = [quote(DateTime(2026, 11, 17), '2')];
    expect(
      shouldFetchCreditIndex(now: now, quotes: quotes, checkedAt: now),
      true,
    );
    expect(
      shouldFetchCreditIndex(
        now: now,
        quotes: quotes,
        checkedAt: now,
        lastAttempt: now.subtract(const Duration(minutes: 4)),
      ),
      false,
    );
    expect(
      shouldFetchCreditIndex(
        now: now,
        quotes: quotes,
        checkedAt: now,
        lastAttempt: now.subtract(const Duration(minutes: 5)),
      ),
      true,
    );
    expect(
      shouldFetchCreditIndex(
        now: now,
        quotes: quotes,
        checkedAt: now,
        lastAttempt: now.add(const Duration(hours: 1)),
      ),
      true,
    );
  });

  test('A current quote avoids duplicate fetches until the next day', () {
    final now = DateTime(2026, 11, 18, 9);
    final quotes = [quote(now, '3')];
    expect(
      shouldFetchCreditIndex(now: now, quotes: quotes, checkedAt: now),
      false,
    );
    expect(
      shouldFetchCreditIndex(
        now: now,
        quotes: quotes,
        checkedAt: now,
        lastAttempt: now,
        force: true,
      ),
      true,
    );
    expect(
      shouldFetchCreditIndex(
        now: now.add(const Duration(days: 1)),
        quotes: quotes,
        checkedAt: now,
        lastAttempt: now,
      ),
      true,
    );
  });

  testWidgets(
    'Startup applies cached IDI to home and persists without expenses',
    (tester) async {
      final writes = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            if (call.method == 'writeSplitState')
              writes.add(call.arguments as Map);
            return call.method == 'scheduleRateUpdate' ? true : null;
          });
      final dynamic app = await fixture(tester);
      expect(app.accountById('credit')['balance'], -150);
      expect(app.accountById('credit')['creditLimit'], 1000);
      expect(app.accountById('bank')['balance'], 500);
      expect(app.maps('movements'), isEmpty);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-credit-cards')),
        350,
        scrollable: find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('home-credit-available-credit')),
            )
            .data,
        money(850, 'VES'),
      );
      await tester.runAsync(() => NativeStateStore.flush());
      final accountsWrite = writes.lastWhere(
        (w) => (w['parts'] as Map).containsKey('accounts'),
      );
      final saved =
          jsonDecode(accountsWrite['parts']['accounts'] as String) as List;
      expect(saved.singleWhere((a) => a['id'] == 'credit')['balance'], -150);
      expect(saved.singleWhere((a) => a['id'] == 'bank')['balance'], 500);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Resume updates the open detail using cached quote without a debit',
    (tester) async {
      final dynamic app = await fixture(tester, index: '2');
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => CreditCardDetailPage(app: app, cardId: 'credit'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Deuda ${money(100, 'VES')}'), findsOneWidget);
      app.state['creditIndexQuotes'] = [quote(DateTime.now(), '3')];
      app.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Deuda ${money(150, 'VES')}'), findsOneWidget);
      expect(creditAvailable(app.accountById('credit')), 850);
      expect(app.accountById('bank')['balance'], 500);
      expect(app.maps('movements'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cosmetic edit preserves live UVC, approved limit and minimum', (
    tester,
  ) async {
    final dynamic app = await fixture(tester, index: '2');
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => CreditCardEditor(app: app, cardId: 'credit'),
    );
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(CreditCardEditor));
    editor.label.text = 'Personal';
    app.state['creditIndexQuotes'] = [quote(DateTime.now(), '3')];
    app.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    app.saveMovement({
      'id': 'payment',
      'type': 'transfer',
      'accountId': 'bank',
      'targetAccountId': 'credit',
      'currency': 'VES',
      'targetCurrency': 'VES',
      'amount': 30.0,
      'targetAmount': 30.0,
      'feeAmount': 0.0,
      'category': 'Pago TDC',
      'creditPayment': true,
      'date': DateTime.now().toIso8601String(),
      'rate': 10.0,
    });
    await tester.pumpAndSettle();
    final before = Map<String, dynamic>.from(app.accountById('credit'));
    editor.save();
    await tester.pumpAndSettle();
    final saved = app.accountById('credit');
    expect(saved['label'], 'Personal');
    for (final key in [
      'creditLimit',
      'creditUnits',
      'balance',
      'creditIndex',
      'creditMinimumDue',
    ]) {
      expect(saved[key], before[key], reason: key);
    }
    expect(saved['creditLimit'], 1000);
    expect(saved['balance'], -120);
    expect(app.accountById('bank')['balance'], 470);
    expect(app.maps('movements'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
