import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart' as charts;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

Future<dynamic> fixture(WidgetTester tester, {int count = 0}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state = defaultState()
    ..addAll({
      'onboardingComplete': true,
      'securitySetupComplete': true,
      'rate': 10.0,
      'rateEffectiveDate': expectedRateDateKey(DateTime.now()),
      'homeShortcutButtons': ['movement'],
      'accounts': [
        {
          'id': 'a',
          'provider': 'cash',
          'label': 'Origen',
          'currency': 'USD',
          'balance': 100.0,
        },
        {
          'id': 'b',
          'provider': 'cash',
          'label': 'Destino',
          'currency': 'VES',
          'balance': 100.0,
        },
      ],
      'debts': [
        {
          'id': 'd',
          'kind': 'payable',
          'amount': 100.0,
          'paidAmount': 90.0,
          'currency': 'USD',
        },
      ],
      'movements': List.generate(
        count,
        (i) => <String, dynamic>{
          'id': 'test$i',
          'accountId': 'a',
          'type': 'expense',
          'amount': 1.0,
          'currency': 'USD',
          'category': 'Otro',
          'description': 'Compra $i',
          'date': formatDateTime(DateTime.now()),
        },
      ),
    });
  await tester.pumpWidget(RialApp(initialState: state));
  await tester.pumpAndSettle();
  return tester.state(find.byType(RialApp));
}

Map<String, dynamic> movement(
  String type, {
  String id = 'm',
  double amount = 20,
}) => {
  'id': id,
  'accountId': 'a',
  'type': type,
  'amount': amount,
  'feeAmount': .3,
  'currency': 'USD',
  'date': '16/09/2026 11:00 AM',
  'rate': 10.0,
  if (type == 'transfer') ...{
    'targetAccountId': 'b',
    'targetAmount': 200.0,
    'targetCurrency': 'VES',
  },
};

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
    'Native saves are ordered and an immediate reversal cannot be skipped',
    () async {
      final gate = Completer<void>();
      final calls = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            if (call.method == 'writeSplitState') {
              calls.add(call.arguments as Map);
              if (calls.length == 1) await gate.future;
            }
            return null;
          });
      final state = defaultState()..['userName'] = 'Ordered commit test';
      state['accounts'] = [
        {'id': 'ordered', 'balance': 10.0},
      ];
      final first = NativeStateStore.save(state);
      await Future<void>.delayed(Duration.zero);
      state['accounts'] = [
        {'id': 'ordered', 'balance': 20.0},
      ];
      final second = NativeStateStore.save(state);
      state['accounts'] = [
        {'id': 'ordered', 'balance': 10.0},
      ];
      final third = NativeStateStore.save(state);
      await Future<void>.delayed(Duration.zero);
      expect(calls.length, 1);
      gate.complete();
      await Future.wait([first, second, third]);
      expect(calls.length, 3);
      expect(
        calls.map(
          (c) => (jsonDecode(
            (c['parts'] as Map)['accounts'] as String,
          ) as List).first['balance'],
        ),
        [10, 20, 10],
      );
    },
  );

  for (final type in ['income', 'expense', 'transfer']) {
    testWidgets('Undo create, edit and delete $type restores exact balances', (
      tester,
    ) async {
      final dynamic app = await fixture(tester);
      final before = jsonEncode(app.maps('accounts'));
      app.saveMovement(movement(type));
      expect(app.accountById('a')['balance'], type == 'income' ? 119.7 : 79.7);
      if (type == 'transfer') expect(app.accountById('b')['balance'], 300);
      app.saveMovement(movement(type, amount: 30), editingId: 'm');
      expect(app.movementById('m')['amount'], 30);
      expect(app.undoLastOperation(), isTrue);
      expect(app.movementById('m')['amount'], 20);
      app.deleteMovement(app.movementById('m'));
      expect(app.movementById('m'), isNull);
      expect(app.accountById('a')['balance'], 100);
      expect(app.undoLastOperation(), isTrue);
      expect(app.movementById('m'), isNotNull);
      expect(app.undoLastOperation(), isTrue);
      expect(app.movementById('m'), isNull);
      expect(app.maps('accounts').map((a) => a['id']).toList(), ['a', 'b']);
      final restored = (app.maps('accounts') as List<Map<String, dynamic>>)
        ..sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
      expect(jsonEncode(restored), before);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'Linked payment reverses only the actual amount applied to debt',
    (tester) async {
      final dynamic app = await fixture(tester);
      app.saveMovement(movement('expense')..['debtId'] = 'd');
      expect(app.debtById('d')['paidAmount'], 100);
      expect(app.debtById('d')['status'], 'paid');
      expect(app.movementById('m')['debtAppliedAmount'], 10);
      app.deleteMovement(app.movementById('m'));
      expect(app.debtById('d')['paidAmount'], 90);
      expect(app.debtById('d')['status'], 'pending');
      expect(app.undoLastOperation(), isTrue);
      expect(app.debtById('d')['paidAmount'], 100);
      expect(app.undoLastOperation(), isTrue);
      expect(app.debtById('d')['paidAmount'], 90);
      expect(app.accountById('a')['balance'], 100);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Invalid amounts are atomic; duplicate IDs and undo conflicts are rejected',
    (tester) async {
      final dynamic app = await fixture(tester);
      final before = jsonEncode(app.state);
      expect(
        () => app.saveMovement(movement('expense', amount: double.infinity)),
        throwsFormatException,
      );
      expect(jsonEncode(app.state), before);
      app.saveMovement(movement('expense'));
      expect(
        () => app.saveMovement(movement('expense')),
        throwsFormatException,
      );
      app.mutate(() => app.state['rate'] = 12.0);
      expect(app.undoLastOperation(), isTrue);
      expect(app.state['rate'], 12.0);
      app.saveMovement(movement('expense'));
      app.mutate(() => app.accountById('a')['balance'] = 999.0);
      expect(app.undoLastOperation(), isFalse);
      expect(app.accountById('a')['balance'], 999.0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('History creates only visible rows and searches a large ledger', (
    tester,
  ) async {
    final dynamic app = await fixture(tester, count: 2000);
    await tester.ensureVisible(find.text('Movimientos').first);
    await tester.tap(find.text('Movimientos').first);
    await tester.pumpAndSettle();
    expect(find.byType(MovementHistoryPage), findsOneWidget);
    expect(find.byType(MovementTile).evaluate().length, lessThan(20));
    final search = tester.widget<CupertinoSearchTextField>(
      find.byType(CupertinoSearchTextField),
    );
    final selector = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(FilterChip).first,
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(search.decoration, selector.decoration);
    expect(search.style?.fontSize, 13);
    await tester.enterText(
      find.byType(CupertinoSearchTextField),
      'Compra 1999',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('1 operaciones'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MovementTile),
        matching: find.text('Compra 1999'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();
    expect(find.text('2000 operaciones'), findsOneWidget);
    expect(app.maps('movements').length, 2000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Chart shows tapped date and value and hides all values in privacy mode',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var period = 'day';
      final points = [
        BalancePoint(DateTime(2026, 9, 16, 10), 100),
        BalancePoint(DateTime(2026, 9, 16, 11), 120),
      ];
      Widget chart(bool hidden) => CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: BalanceTrend(
                points: points,
                theme: RTheme(true, 'green'),
                currency: 'USD',
                hidden: hidden,
                period: period,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(chart(false));
      await tester.pumpAndSettle();
      final line = find.byType(charts.LineChart);
      expect(find.text('Evolución'), findsNothing);
      expect(find.text('Día'), findsNothing);
      expect(find.text('Semana'), findsNothing);
      expect(find.text('Mes'), findsNothing);
      expect(find.text('Cuentas actuales · Tasa actual'), findsNothing);
      expect(
        tester.widget<charts.LineChart>(line).data.showingTooltipIndicators,
        isEmpty,
      );
      final rect = tester.getRect(line);
      await tester.tapAt(Offset(rect.left + 2, rect.bottom - 6));
      await tester.pumpAndSettle();
      final data = tester.widget<charts.LineChart>(line).data;
      final tooltip = data.lineTouchData.touchTooltipData
          .getTooltipItems(data.showingTooltipIndicators.single.showingSpots)
          .single!;
      expect(tooltip.text, contains('100,00'));
      expect(tooltip.text, contains(timeOnlyLabel(points.first.date)));
      expect(tester.getSize(line), rect.size);

      period = 'week';
      await tester.pumpWidget(chart(false));
      await tester.pumpAndSettle();
      expect(
        tester.widget<charts.LineChart>(line).data.showingTooltipIndicators,
        isEmpty,
      );
      await tester.tapAt(Offset(rect.left + 2, rect.bottom - 6));
      await tester.pumpAndSettle();
      final weeklyData = tester.widget<charts.LineChart>(line).data;
      expect(
        weeklyData.lineTouchData.touchTooltipData
            .getTooltipItems(
              weeklyData.showingTooltipIndicators.single.showingSpots,
            )
            .single!
            .text,
        contains(formatDate(points.first.date)),
      );
      await tester.pumpWidget(chart(true));
      await tester.pumpAndSettle();
      expect(find.byType(charts.LineChart), findsNothing);
      expect(find.text('Balance oculto'), findsOneWidget);
      expect(find.textContaining('100,00'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home chart follows the balance comparison setting', (
    tester,
  ) async {
    final dynamic app = await fixture(tester);
    for (final period in ['day', 'week', 'month']) {
      app.mutate(() => app.state['homeBalanceChangePeriod'] = period);
      await tester.pumpAndSettle();
      final chart = tester.widget<BalanceTrend>(find.byType(BalanceTrend));
      final hero = tester.widget<BalanceHero>(find.byType(BalanceHero));
      expect(chart.period, period);
      expect(hero.changePeriod, period);
      expect(
        chart.points.first.date,
        balancePeriodStart(DateTime.now(), period),
      );
      expect(find.text('Evolución'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
