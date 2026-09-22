import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

Map<String, dynamic> sampleCircle({String frequency = 'weekly'}) => {
  'id': 'san',
  'name': 'Amigos',
  'quota': 10.0,
  'currency': 'USD',
  'frequency': frequency,
  'startDate': '2026-01-31',
  'selfMemberId': 'me',
  'members': [
    {'id': 'a', 'name': 'Ana'},
    {'id': 'me', 'name': 'Yo'},
    {'id': 'b', 'name': 'Luis'},
  ],
};

void couple(
  dynamic app,
  String type,
  double amount, {
  String member = 'self',
  String account = '',
  String currency = 'USD',
}) => recordSharedSaving(
  app,
  collection: 'sharedSavings',
  recordId: 'couple',
  memberId: member,
  type: type,
  currency: currency,
  amount: amount,
  accountId: account,
  date: '22/09/2026 10:00 AM',
);

void circlePayment(
  dynamic app,
  int round,
  String member,
  String type, {
  String account = '',
}) => recordSharedSaving(
  app,
  collection: 'savingsCircles',
  recordId: 'san',
  memberId: member,
  type: type,
  currency: 'USD',
  amount: type == 'payout' ? 30 : 10,
  accountId: account,
  round: round,
  date: '22/09/2026 10:00 AM',
);

Finder field(String placeholder) => find.byWidgetPredicate(
  (w) => w is CupertinoTextField && w.placeholder == placeholder,
);

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
    'Defaults and JSON roundtrip preserve legacy savings and new records',
    () {
      final old = defaultState()
        ..remove('sharedSavings')
        ..remove('savingsCircles');
      old['savingsFunds'] = {
        'general': {'saved': 70.0},
      };
      final state = withDefaults(old);
      expect((state['sharedSavings'] as List).length, 1);
      expect((state['savingsFunds'] as Map)['general']['saved'], 70);
      (state['savingsCircles'] as List).add({...sampleCircle(), 'history': []});
      final reloaded = withDefaults(
        jsonDecode(jsonEncode(state)) as Map<String, dynamic>,
      );
      expect(reloaded['sharedSavings'], state['sharedSavings']);
      expect(reloaded['savingsCircles'], state['savingsCircles']);
    },
  );

  test('Monthly rounds preserve day-of-month and clamp February', () {
    final circle = sampleCircle(frequency: 'monthly');
    expect(circleRoundDate(circle, 1), DateTime(2026, 2, 28));
    expect(circleRoundDate(circle, 2), DateTime(2026, 3, 31));
    expect(
      circleRoundDate({...circle, 'startDate': '2028-01-31'}, 1),
      DateTime(2028, 2, 29),
    );
    expect(circleRoundDate(sampleCircle(), 1), DateTime(2026, 2, 7));
    expect(
      circleRoundDate({...circle, 'frequency': 'fortnightly'}, 1),
      DateTime(2026, 2, 14),
    );
  });

  test('Shared savings persist in separate native collections', () async {
    final state = defaultState();
    (state['sharedSavings'] as List).single['history'] = [
      {
        'id': 'persisted',
        'memberId': 'partner',
        'type': 'deposit',
        'amountUsd': 25.0,
      },
    ];
    state['savingsCircles'] = [
      {...sampleCircle(), 'history': []},
    ];
    final writes = <Map>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          if (call.method == 'writeSplitState')
            writes.add(call.arguments as Map);
          return null;
        });
    await NativeStateStore.save(state);
    final raw = jsonDecode(writes.last['state'] as String) as Map;
    final parts = writes.last['parts'] as Map;
    expect(raw.containsKey('sharedSavings'), isFalse);
    expect(raw.containsKey('savingsCircles'), isFalse);
    expect(
      (jsonDecode(parts['sharedSavings'] as String) as List)
          .single['history'].length,
      1,
    );
    expect(
      (jsonDecode(parts['savingsCircles'] as String) as List).single['name'],
      'Amigos',
    );
  });

  testWidgets(
    'Couple contributions track both people without debiting external money',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      couple(app, 'deposit', 20, account: 'a');
      couple(app, 'deposit', 30, member: 'partner');
      expect(app.accountById('a')['balance'], 80);
      expect(coupleSaved(coupleSavings(app)), 50);
      couple(app, 'withdraw', 10, member: 'partner');
      expect(coupleSaved(coupleSavings(app)), 40);
      couple(app, 'withdraw', 100, account: 'b', currency: 'VES');
      expect(app.accountById('b')['balance'], 200);
      expect(coupleSaved(coupleSavings(app)), 30);
      expect(app.maps('balanceAdjustments').length, 2);
      final history = savingsEntries(coupleSavings(app));
      expect(history.map((e) => e['memberId']), [
        'self',
        'partner',
        'partner',
        'self',
      ]);
      final snapshot = jsonEncode(app.state);
      expect(() => couple(app, 'withdraw', 31), throwsFormatException);
      expect(
        () => couple(app, 'deposit', 1000, account: 'a'),
        throwsFormatException,
      );
      expect(() => couple(app, 'deposit', double.nan), throwsFormatException);
      expect(jsonEncode(app.state), snapshot);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Savings delete and undo preserve the original conversion and account adjustment',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      couple(app, 'deposit', 50, currency: 'VES', account: 'b');
      final id = savingsEntries(coupleSavings(app)).single['id'].toString();
      expect(coupleSaved(coupleSavings(app)), 5);
      app.mutate(() => app.state['rate'] = 20.0);
      deleteSharedSaving(app, 'sharedSavings', 'couple', id);
      expect(app.accountById('b')['balance'], 100);
      expect(app.maps('balanceAdjustments'), isEmpty);
      expect(coupleSaved(coupleSavings(app)), 0);
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById('b')['balance'], 50);
      expect(coupleSaved(coupleSavings(app)), 5);
      expect(app.maps('balanceAdjustments').length, 1);
      couple(app, 'withdraw', 2);
      expect(
        () => deleteSharedSaving(app, 'sharedSavings', 'couple', id),
        throwsFormatException,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Circle runs through all rounds, rejects duplicates and guards payouts',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      saveSavingsCircle(app, sampleCircle());
      expect(() => circlePayment(app, 0, 'a', 'payout'), throwsFormatException);
      expect(
        () => circlePayment(app, 0, 'a', 'contribution', account: 'a'),
        throwsFormatException,
      );
      for (var round = 0; round < 3; round++) {
        for (final member in ['a', 'me', 'b']) {
          circlePayment(
            app,
            round,
            member,
            'contribution',
            account: member == 'me' ? 'a' : '',
          );
        }
        expect(circleRoundFunded(savingsCircle(app, 'san')!, round), isTrue);
        final before = app.accountById('a')['balance'];
        expect(
          () => circlePayment(app, round, 'me', 'contribution', account: 'a'),
          throwsFormatException,
        );
        expect(app.accountById('a')['balance'], before);
        final recipient = ['a', 'me', 'b'][round];
        circlePayment(
          app,
          round,
          recipient,
          'payout',
          account: recipient == 'me' ? 'a' : '',
        );
        expect(
          () => circlePayment(app, round, recipient, 'payout'),
          throwsFormatException,
        );
      }
      final circle = savingsCircle(app, 'san')!;
      expect(circlePaidRounds(circle), 3);
      expect(savingsEntries(circle).length, 12);
      expect(app.accountById('a')['balance'], 100);
      expect(
        () => saveSavingsCircle(app, {...sampleCircle(), 'quota': 20.0}),
        throwsFormatException,
      );
      saveSavingsCircle(app, {...sampleCircle(), 'name': 'Amigos 2026'});
      expect(savingsEntries(savingsCircle(app, 'san')!).length, 12);
      final contribution = circleEntry(circle, 1, 'me', 'contribution')!;
      expect(
        () => deleteSharedSaving(
          app,
          'savingsCircles',
          'san',
          contribution['id'].toString(),
        ),
        throwsFormatException,
      );
      final payout = circleEntry(circle, 1, 'me', 'payout')!;
      deleteSharedSaving(app, 'savingsCircles', 'san', payout['id'].toString());
      expect(app.accountById('a')['balance'], 70);
      expect(circlePaidRounds(savingsCircle(app, 'san')!), 2);
      app.undoLastOperation();
      expect(app.accountById('a')['balance'], 100);
      expect(circlePaidRounds(savingsCircle(app, 'san')!), 3);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Savings USD/USDT parity and account conversions use the requested currency',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() => app.state['usdtRate'] = 20.0);
      couple(app, 'deposit', 10, currency: 'USDT', account: 'a');
      expect(app.accountById('a')['balance'], 90);
      expect(coupleSaved(coupleSavings(app)), 10);
      expect(savingsConversion(app, 10, 'USD', 'USDT'), 10);
      expect(savingsConversion(app, 10, 'USDT', 'VES'), 200);
      expect(
        () => savingsConversion(app, 10, 'EUR', 'USD'),
        throwsFormatException,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Invalid circles and reversals cannot corrupt linked balances', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    for (final changes in <Map<String, dynamic>>[
      {'name': ''},
      {'quota': 0},
      {'quota': double.infinity},
      {'currency': 'UNKNOWN'},
      {'startDate': '2026-02-31'},
      {'selfMemberId': 'unknown'},
      {
        'members': [
          {'id': 'me', 'name': 'Yo'},
        ],
      },
    ]) {
      expect(
        () => saveSavingsCircle(app, {...sampleCircle(), ...changes}),
        throwsFormatException,
      );
    }
    expect(app.maps('savingsCircles'), isEmpty);
    expect(
      () => savingsConversion(app, 10, 'UNKNOWN', 'UNKNOWN'),
      throwsFormatException,
    );
    couple(app, 'deposit', 20, account: 'a');
    final deposit = savingsEntries(coupleSavings(app)).single['id'].toString();
    app.mutate(() => app.accountById('a')['currency'] = 'VES');
    expect(
      () => deleteSharedSaving(app, 'sharedSavings', 'couple', deposit),
      throwsFormatException,
    );
    expect(app.accountById('a')['balance'], 80);
    app.mutate(() => app.accountById('a')['currency'] = 'USD');
    couple(app, 'withdraw', 10, account: 'a');
    final withdrawal = savingsEntries(coupleSavings(app)).last['id'].toString();
    app.mutate(() => app.accountById('a')['balance'] = 5.0);
    expect(
      () => deleteSharedSaving(app, 'sharedSavings', 'couple', withdrawal),
      throwsFormatException,
    );
    expect(coupleSaved(coupleSavings(app)), 10);
    app.mutate(() => app.rawList('accounts').clear());
    expect(
      () => deleteSharedSaving(app, 'sharedSavings', 'couple', withdrawal),
      throwsFormatException,
    );
    expect(savingsEntries(coupleSavings(app)).length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Couple UI registers a partner contribution outside personal accounts',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => CoupleSavingsPage(app: app),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aportar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Persona'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi pareja'));
      await tester.pumpAndSettle();
      expect(find.text('Fuera de mis cuentas'), findsOneWidget);
      await tester.enterText(field('Monto en D\u00f3lares'), '25');
      await tester.tap(find.text('Guardar registro'));
      await tester.pumpAndSettle();
      expect(coupleSaved(coupleSavings(app)), 25);
      expect(app.accountById('a')['balance'], 100);
      expect(savingsEntries(coupleSavings(app)).single['memberId'], 'partner');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Circle UI creates a group and records its first personal quota',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => SavingsCirclesPage(app: app),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo bolso'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Nombre del bolso'), 'Familia');
      await tester.enterText(field('Cuota por persona'), '10');
      await tester.tap(find.text('Guardar bolso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Familia'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Yo'));
      await tester.tap(find.text('Yo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar registro'));
      await tester.pumpAndSettle();
      expect(savingsEntries(app.maps('savingsCircles').single).length, 1);
      expect(app.accountById('a')['balance'], 90);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
