import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Profile synthetic ledger on an isolated Android package', (
    tester,
  ) async {
    const channel = MethodChannel('rial/native_state');
    // Never read or write personal data; Android uses a separate benchmark ID as well.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'scheduleRateUpdate' ? true : null,
    );
    final now = DateTime.now();
    const count = int.fromEnvironment(
      'BENCHMARK_MOVEMENTS',
      defaultValue: 10000,
    );
    final accounts = List.generate(
      4,
      (i) => <String, dynamic>{
        'id': 'a$i',
        'provider': 'CASH',
        'label': 'Prueba $i',
        'kind': 'cash',
        'currency': i.isEven ? 'USD' : 'VES',
        'balance': 50000.0,
      },
    );
    final movements = List.generate(
      count,
      (i) => <String, dynamic>{
        'id': 'm$i',
        'accountId': 'a${i % 4}',
        'type': i % 5 == 0 ? 'income' : 'expense',
        'currency': i.isEven ? 'USD' : 'VES',
        'amount': (i % 25 + 1).toDouble(),
        'feeAmount': 0.0,
        'description': 'Compra de prueba $i',
        'category': i.isEven ? 'Comida' : 'Pasaje',
        'date': formatDateTime(now.subtract(Duration(minutes: i * 5))),
      },
    );
    final fixture = defaultState()
      ..addAll({
        'onboardingComplete': true,
        'securitySetupComplete': true,
        'userName': 'Pruebas',
        'rate': 846.51,
        'eurRate': 977.18,
        'usdtRate': 956.28,
        'rateEffectiveDate': expectedRateDateKey(now),
        'lastRateMillis': now.millisecondsSinceEpoch,
        'homeShortcutButtons': ['movement', 'calculator'],
        'accounts': accounts,
        'movements': movements,
      });
    final results = <String, dynamic>{
      'movement_count': count,
      'label': const String.fromEnvironment(
        'BENCHMARK_LABEL',
        defaultValue: 'after',
      ),
    };
    binding.reportData ??= {};
    binding.reportData!['measurements'] = results;
    final load = Stopwatch()..start();
    await tester.pumpWidget(RialApp(initialState: fixture));
    await tester.pumpAndSettle();
    results['home_settled_ms'] = load.elapsedMilliseconds;
    results['rss_bytes'] = ProcessInfo.currentRss;
    final homeScroll = find
        .descendant(
          of: find.byType(HomePage),
          matching: find.byType(Scrollable),
        )
        .first;
    await binding.watchPerformance(() async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(homeScroll, Offset(0, i.isEven ? -500 : 500), 1200);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'home_scroll');

    final historyTime = Stopwatch()..start();
    await tester.ensureVisible(find.text('Movimientos').first);
    await tester.tap(find.text('Movimientos').first);
    await tester.pumpAndSettle();
    results['history_settled_ms'] = historyTime.elapsedMilliseconds;
    expect(find.byType(MovementHistoryPage), findsOneWidget);
    final historyScroll = find
        .descendant(
          of: find.byType(MovementHistoryPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await binding.watchPerformance(() async {
      for (var i = 0; i < 10; i++) {
        await tester.fling(historyScroll, const Offset(0, -600), 1400);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'history_scroll');
    results['visible_movement_tiles'] = find
        .byType(MovementTile)
        .evaluate()
        .length;
    results['rss_after_history_bytes'] = ProcessInfo.currentRss;
    tester.state<ScrollableState>(historyScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    final search = find.byType(CupertinoSearchTextField);
    if (search.evaluate().isNotEmpty) {
      await tester.ensureVisible(search);
      final searchTime = Stopwatch()..start();
      await tester.enterText(search, 'Compra de prueba 9999');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      // Device tests use real timers; wait for the debounced query to finish.
      while (find.text('1 operaciones').evaluate().isEmpty &&
          searchTime.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      results['search_settled_ms'] = searchTime.elapsedMilliseconds;
      expect(find.text('1 operaciones'), findsOneWidget);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('history');
    final dynamic app = tester.state(find.byType(RialApp));
    app.rootNavigatorKey.currentState.pop();
    await tester.pumpAndSettle();
    final homePosition = tester.state<ScrollableState>(homeScroll).position;
    homePosition.jumpTo(0);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('home');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
