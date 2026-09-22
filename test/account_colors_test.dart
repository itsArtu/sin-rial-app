import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

List<Map<String, dynamic>> collisionAccounts({String currency = 'VES'}) => [
  {
    'id': 'cash-account',
    'provider': 'CASH',
    'currency': currency,
    'balance': 2500.0,
  },
  {
    'id': 'bank-3',
    'provider': '0172',
    'currency': currency,
    'balance': 2104.98,
  },
  {'id': 'small', 'provider': '0102', 'currency': currency, 'balance': .45},
];

Map<String, int> colorsById(Iterable<Map<String, dynamic>> accounts) => {
  for (final account in accounts)
    account['id'] as String: accountColor(account).toARGB32(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final writes = <MethodCall>[];
  setUp(() {
    writes.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          if (call.method == 'writeSplitState') writes.add(call);
          return call.method == 'scheduleRateUpdate' ? true : null;
        });
  });

  test('Legacy colliding colors migrate without changing financial data', () {
    final accounts = collisionAccounts();
    expect(accountColor(accounts[0]), accountColor(accounts[1]));
    final before = jsonEncode(accounts);
    final state = withDefaults(defaultState()..['accounts'] = accounts);
    final migrated = (state['accounts'] as List).cast<Map<String, dynamic>>();
    expect(colorsById(migrated).values.toSet(), hasLength(3));
    final financial = migrated
        .map((a) => {...a}..remove('chartColor'))
        .toList();
    expect(jsonEncode(financial), before);
    final restored = withDefaults(
      jsonDecode(jsonEncode(state)) as Map<String, dynamic>,
    );
    expect(
      colorsById((restored['accounts'] as List).cast<Map<String, dynamic>>()),
      colorsById(migrated),
    );
  });

  test('Colors stay unique and stable beyond eight accounts and after reorder/delete/add', () {
    final accounts = List.generate(
      40,
      (i) => <String, dynamic>{
        'id': 'account-$i',
        'provider': 'cash',
        'currency': 'VES',
        'balance': i + 1.0,
      },
    );
    assignAccountColors(accounts);
    final before = colorsById(accounts);
    expect(before.values.toSet(), hasLength(40));
    accounts[0].addAll({
      'provider': '0172',
      'currency': 'USD',
      'balance': 999.0,
    });
    final changed = accounts.reversed.skip(1).toList()
      ..insert(0, {
        'id': 'new',
        'provider': 'cash',
        'currency': 'VES',
        'balance': 4.0,
      });
    assignAccountColors(changed);
    final after = colorsById(changed);
    expect(after.values.toSet(), hasLength(changed.length));
    for (final account in changed.where((a) => a['id'] != 'new')) {
      expect(after[account['id']], before[account['id']]);
    }
  });

  test(
    'Invalid and duplicate stored colors do not consume existing unique colors',
    () {
      final accounts = collisionAccounts()
        ..add({'id': 'duplicate', 'chartColor': 0xFFF28A68});
      accounts[0]['chartColor'] = 'invalid';
      accounts[1]['chartColor'] = 0xFFF28A68;
      accounts[2]['chartColor'] = 0x0058BE86;
      assignAccountColors(accounts);
      expect(accountColor(accounts[1]).toARGB32(), 0xFFF28A68);
      expect(colorsById(accounts).values.toSet(), hasLength(4));
      expect(colorsById(accounts).values.every((c) => c >= 0xFF000000), isTrue);
    },
  );

  testWidgets(
    'Account editing preserves color and adding an account persists a distinct one',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final original = accountColor(app.accountById('a'));
      app.saveAccount(<String, dynamic>{
        'provider': '0172',
        'currency': 'USD',
        'balance': 110.0,
      }, editingId: 'a');
      await tester.pumpAndSettle();
      expect(accountColor(app.accountById('a')), original);
      app.saveAccount(<String, dynamic>{
        'id': 'third',
        'provider': '0102',
        'currency': 'VES',
        'balance': .45,
      });
      await tester.pumpAndSettle();
      final accounts = app.maps('accounts') as List<Map<String, dynamic>>;
      expect(colorsById(accounts).values.toSet(), hasLength(3));
      final saved = jsonDecode(
        writes.last.arguments['parts']['accounts'] as String,
      ) as List;
      expect(
        colorsById(saved.cast<Map<String, dynamic>>()),
        colorsById(accounts),
      );
      expect(accountColor(app.accountById('a')), original);
    },
  );

  testWidgets(
    'Balances, account legends and monthly summaries share account colors',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      for (final currency in ['VES', 'USD']) {
        final accounts = collisionAccounts(currency: currency);
        assignAccountColors(accounts);
        for (final dark in [false, true]) {
          app.mutate(() {
            app.state['accounts'] = accounts;
            app.state['darkMode'] = dark;
          });
          app.pushPage(
            tester.element(find.byType(HomePage)),
            (_) => CurrencyAccountsPage(app: app, currency: currency),
          );
          await tester.pumpAndSettle();
          final ring = tester.widget<RingSummary>(find.byType(RingSummary));
          expect(ring.parts.map((p) => p.color), accounts.map(accountColor));
          expect(
            ring.parts.map((p) => p.value),
            accounts.map((a) => a['balance']),
          );
          expect(find.byType(AccountListLine), findsNWidgets(3));
          for (final element in find.byType(AccountListLine).evaluate()) {
            final line = element.widget as AccountListLine;
            expect(
              ring.parts.map((p) => p.color),
              contains(accountColor(line.account)),
            );
          }
          final movements = accounts
              .map(
                (a) => <String, dynamic>{
                  'accountId': a['id'],
                  'amount': a['balance'],
                  'currency': currency,
                  'type': 'expense',
                  'date': '17/09/2026 10:34 AM',
                },
              )
              .toList();
          final distribution = accountDistribution(app, accounts, movements);
          expect(distribution.map((e) => e.color), accounts.map(accountColor));
          final monthly = monthlyMovementSummaries(app, accounts, movements);
          expect(
            monthly.single.accounts.map((e) => e.color),
            accounts.map(accountColor),
          );
          expect(tester.takeException(), isNull);
          Navigator.of(tester.element(find.byType(CurrencyAccountsPage))).pop();
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'Separated bars handle empty, negative, tiny and many balances without overflow',
    (tester) async {
      for (final values in <List<double>>[
        [],
        [0, -1],
        [1],
        [2500, 2104.98, .45, 0, -10],
        List.filled(40, 1),
      ]) {
        for (final width in [0.0, 40.0, 320.0]) {
          await tester.pumpWidget(
            CupertinoApp(
              home: Center(
                child: SizedBox(
                  width: width,
                  child: RatioBar(
                    theme: RTheme(true, 'indigo'),
                    separateParts: true,
                    parts: values
                        .map(
                          (v) => RatioPart(
                            color: CupertinoColors.activeBlue,
                            value: v,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final segments = find.descendant(
            of: find.byType(RatioBar),
            matching: find.byWidgetPredicate(
              (w) => w is ColoredBox && w.key != null,
            ),
          );
          expect(segments, findsNWidgets(values.where((v) => v > 0).length));
          for (final segment in segments.evaluate()) {
            expect(
              tester.getSize(find.byWidget(segment.widget)).width.isFinite,
              isTrue,
            );
          }
        }
      }
    },
  );
}
