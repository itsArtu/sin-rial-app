import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        ),
  );
  setUpAll(() async {
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final item in manifest.cast<Map>()) {
      final loader = FontLoader(item['family'] as String);
      for (final font in (item['fonts'] as List).cast<Map>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final name in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF Pro Display',
      'Roboto',
    ]) {
      await (FontLoader(name)..addFont(Future.value(font))).load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    for (final element in find.byType(Image).evaluate().toList()) {
      await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element),
      );
    }
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(RialApp),
      matchesGoldenFile('../build/release97-qa/$name.png'),
    );
  }

  for (final period in ['day', 'week', 'month']) {
    test('$period retains a dip and recovery in the same minute', () {
      final points = buildBalanceTrend(
        accounts: [
          {'id': 'a', 'currency': 'USD', 'balance': 100.0},
        ],
        movements: [
          {
            'accountId': 'a',
            'type': 'expense',
            'amount': 20.0,
            'date': '22/10/2026 08:30 AM',
          },
          {
            'accountId': 'a',
            'type': 'income',
            'amount': 20.0,
            'date': '22/10/2026 08:30 AM',
          },
        ],
        convertValue: (value, _) => value,
        period: period,
        now: DateTime(2026, 10, 22, 9),
      );
      final events = points.where(
        (p) => p.date == DateTime(2026, 10, 22, 8, 30),
      );
      expect(events.map((p) => p.amount), [80.0, 100.0]);
      expect(points.first.amount, 100);
      expect(points.last.amount, 100);
    });
  }

  test(
    'Transfers do not introduce artificial peaks between their two legs',
    () {
      final points = buildBalanceTrend(
        accounts: [
          {'id': 'a', 'currency': 'USD', 'balance': 79.0},
          {'id': 'b', 'currency': 'VES', 'balance': 200.0},
        ],
        movements: [
          {
            'accountId': 'a',
            'targetAccountId': 'b',
            'type': 'transfer',
            'amount': 20.0,
            'feeAmount': 1.0,
            'targetAmount': 200.0,
            'date': '22/10/2026 08:30 AM',
          },
        ],
        convertValue: (value, currency) =>
            currency == 'VES' ? value / 10 : value,
        period: 'day',
        now: DateTime(2026, 10, 22, 9),
      );
      expect(points.first.amount, 100);
      expect(points.last.amount, 99);
      expect(
        points.every((point) => point.amount >= 99 && point.amount <= 100),
        true,
      );
    },
  );

  test('Opening funds precede a minute-rounded first expense', () {
    final points = buildBalanceTrend(
      accounts: [
        {
          'id': 'a',
          'currency': 'USD',
          'balance': 80.0,
          'createdAt': '2026-10-22T08:30:15',
        },
      ],
      movements: [
        {
          'accountId': 'a',
          'type': 'expense',
          'amount': 20.0,
          'date': '22/10/2026 08:30 AM',
        },
      ],
      convertValue: (value, _) => value,
      period: 'day',
      now: DateTime(2026, 10, 22, 9),
    );
    expect(
      points
          .where((p) => p.date == DateTime(2026, 10, 22, 8, 30))
          .map((p) => p.amount),
      [100.0, 80.0],
    );
    expect(points.every((p) => p.amount >= 0), true);
    expect(points.last.amount, 80);
  });

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    for (final dark in [true, false]) {
      testWidgets('Editors fit safe areas without scrolling $size dark=$dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = size;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPadding);
        app.mutate(() {
          app.state['darkMode'] = dark;
          app.state['accounts'] = [
            {
              'id': 'a',
              'kind': 'national',
              'provider': '0172',
              'currency': 'VES',
              'balance': 20000.0,
            },
            {
              'id': 'b',
              'kind': 'wallet',
              'provider': 'BINANCE',
              'currency': 'USD',
              'balance': 100.0,
            },
          ];
        });
        await tester.pumpAndSettle();
        for (final type in ['expense', 'income', 'transfer']) {
          app.openMovementEditor(
            tester.element(find.byType(HomePage)),
            defaultType: type,
            defaultAccountId: 'a',
            defaultAmount: 1200.0,
          );
          await tester.pumpAndSettle();
          final fields = find.byKey(const ValueKey('movement-editor-fields'));
          expect(
            tester
                .getRect(find.byKey(const ValueKey('movement-editor-type')))
                .top,
            greaterThanOrEqualTo(36),
          );
          ScrollPosition position() => tester
              .state<ScrollableState>(
                find
                    .descendant(of: fields, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          expect(
            position().maxScrollExtent,
            0,
            reason:
                '$type at $size: '
                '${[find.byType(ComposerAmount), find.byType(ComposerFacts), find.byType(OptionField), find.byType(ComposerOptionButton)].map((f) => f.evaluate().map((e) => "${e.widget.runtimeType} ${e.size}").join(", ")).join("; ")}',
          );
          final prefix = tester.getRect(
            find.byKey(const ValueKey('amount-prefix-Monto')),
          );
          final number = tester.getRect(
            find.byKey(const ValueKey('amount-input-Monto')),
          );
          expect(number.left - prefix.right, closeTo(6, .1));
          final amountInput = tester.widget<CupertinoTextField>(
            find.byKey(const ValueKey('amount-input-Monto')),
          );
          expect(amountInput.cursorHeight, lessThanOrEqualTo(number.height));
          final keypad = tester.getRect(find.byType(ComposerKeypad));
          expect(keypad.bottom, lessThanOrEqualTo(size.height - 24));
          if (type == 'transfer') {
            await tester.tap(
              find.byKey(const ValueKey('amount-input-Monto recibido')),
            );
            for (final key in ['2', '0']) {
              await tester.tap(find.byKey(ValueKey('keypad-$key')));
              await tester.pump();
            }
            await tester.pumpAndSettle();
            expect(position().maxScrollExtent, 0);
            expect(position().pixels, 0);
            expect(
              find.byKey(const ValueKey('composer-account')).hitTestable(),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('composer-target')).hitTestable(),
              findsOneWidget,
            );
          }
          await capture(tester, '$type-${size.width.toInt()}-$dark');
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        app.mutate(() => app.state['accounts'][1]['currency'] = 'VES');
        app.openMovementEditor(
          tester.element(find.byType(HomePage)),
          defaultType: 'transfer',
          defaultAccountId: 'a',
          defaultAmount: 1200.0,
        );
        await tester.pumpAndSettle();
        final sameCurrencyScroll = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('movement-editor-fields')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        expect(
          sameCurrencyScroll.maxScrollExtent,
          0,
          reason: 'Same-currency transfer at $size',
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('transfer-received-label')))
              .bottom,
          lessThan(
            tester
                .getRect(find.byKey(const ValueKey('transfer-received-value')))
                .top,
          ),
        );
        await capture(tester, 'transfer-ves-${size.width.toInt()}-$dark');
        await tester.pageBack();
        await tester.pumpAndSettle();
        app.openMovementEditor(tester.element(find.byType(HomePage)));
        await tester.pumpAndSettle();
        expect(
          (tester.state(find.byType(MovementEditor)) as dynamic).type,
          'expense',
        );
      });
    }
  }

  testWidgets(
    'History, accounts, categories, calendar and real trend stay compact',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester, count: 8);
      app.mutate(() {
        app.state['accounts'][0]['provider'] = 'BINANCE';
        app.state['accounts'][1]['provider'] = '0172';
        app.state['movements'][0]['type'] = 'income';
        app.state['movements'][0]['amount'] = 12.0;
        app.state['movements'][1]['amount'] = 20.0;
        app.state['movements'][2]['type'] = 'income';
        app.state['movements'][2]['amount'] = 15.0;
      });
      await capture(tester, 'home-curve');
      final pages = <String, WidgetBuilder>{
        'movements': (_) => MovementHistoryPage(app: app),
        'incomes': (_) =>
            MovementHistoryPage(app: app, mode: MovementHistoryMode.income),
        'expenses': (_) =>
            MovementHistoryPage(app: app, mode: MovementHistoryMode.expense),
        'accounts': (_) => AccountsPage(app: app),
        'categories': (_) => CategoriesPage(app: app),
        'debts': (_) => DebtOverview(app: app),
      };
      for (final page in pages.entries) {
        app.pushPage(tester.element(find.byType(HomePage)), page.value);
        await capture(tester, page.key);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    },
  );
}
