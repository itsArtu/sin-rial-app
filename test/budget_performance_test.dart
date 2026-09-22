import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  testWidgets(
    'Measure budget and home calculations with 10000 synthetic movements',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('rial/native_state'),
            (call) async => call.method == 'scheduleRateUpdate' ? true : null,
          );
      final dynamic app = await fixtures.fixture(tester);
      final now = DateTime(2026, 9, 22, 12);
      final records = List.generate(
        10000,
        (i) => <String, dynamic>{
          'id': 'bench-$i',
          'accountId': i.isEven ? 'a' : 'b',
          'type': i % 7 == 0 ? 'income' : 'expense',
          'category': budgetCategories[i % budgetCategories.length],
          'currency': i.isEven ? 'USD' : 'VES',
          'amount': (i % 20 + 1).toDouble(),
          'feeAmount': 0.0,
          'date': formatDateTime(now.subtract(Duration(minutes: i))),
        },
      );
      app.mutate(() => app.state['movements'] = records);
      double oldSummary() => budgetCategories.fold<double>(
        0,
        (sum, category) =>
            sum +
            spentForCategory(
              records,
              category,
              'USD',
              10,
              period: '2026-09',
              periodType: 'monthly',
            ),
      );
      BudgetSpending newSummary() => summarizeBudgetSpending(
        records,
        '2026-09',
        'monthly',
        usdRate: 10,
        eurRate: 12,
      );
      for (var i = 0; i < 2; i++) {
        oldSummary();
        newSummary();
      }
      double measure(void Function() action, int repeats) {
        final watch = Stopwatch()..start();
        for (var i = 0; i < repeats; i++) {
          action();
        }
        return watch.elapsedMicroseconds / repeats / 1000;
      }

      expect(newSummary().total, closeTo(oldSummary(), .000001));
      final budgetCache = BudgetSpendingCache();
      budgetCache.read(app, '2026-09', 'monthly');
      final homeCache = HomeLedgerCache();
      final home = homeCache.read(app, now: now);
      final result = <String, dynamic>{
        'environment':
            'Flutter test host; synthetic data; not Android frame timings',
        'movements': records.length,
        'old_budget_category_scans_ms': measure(oldSummary, 5),
        'new_budget_single_pass_ms': measure(newSummary, 5),
        'cached_budget_read_ms': measure(
          () => budgetCache.read(app, '2026-09', 'monthly'),
          1000,
        ),
        'uncached_home_calculation_ms': measure(
          () => HomeLedgerSnapshot(app, now),
          5,
        ),
        'cached_home_read_ms': measure(
          () => homeCache.read(app, now: now),
          1000,
        ),
      };
      expect(identical(homeCache.read(app, now: now), home), isTrue);
      // Explicit opt-in measurements are reported separately from deterministic tests.
      print('BUDGET_PERFORMANCE ${jsonEncode(result)}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    skip: !const bool.fromEnvironment('RUN_FINANCE_BENCHMARK'),
  );
}
