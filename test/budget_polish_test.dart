import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'budget_plans_test.dart' as budgets;
import 'finance_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test('Month navigation skips unsaved history but retains existing plans', () {
    final now = DateTime(2026, 10, 1);
    final plans = <Map<String, dynamic>>[
      {'period': '2026-07'},
      {'period': '2026-09-H1'},
    ];
    expect(adjacentBudgetMonth(plans, '2026-10', -1, now: now), '2026-09');
    expect(adjacentBudgetMonth(plans, '2026-09', -1, now: now), '2026-07');
    expect(adjacentBudgetMonth(plans, '2026-07', -1, now: now), isNull);
    expect(adjacentBudgetMonth(plans, '2026-07', 1, now: now), '2026-09');
    expect(adjacentBudgetMonth(plans, '2026-09', 1, now: now), '2026-10');
    expect(adjacentBudgetMonth(plans, '2026-12', 1, now: now), '2027-01');
    expect(adjacentBudgetMonth([], '2026-10', -1, now: now), isNull);
    expect(canCreateBudgetInMonth('2026-09', now: now), isFalse);
    expect(canCreateBudgetInMonth('2026-10', now: now), isTrue);
  });

  testWidgets(
    'Past creation is atomic and blocked, historical editing is allowed',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final october = DateTime(2026, 10, 1);
      budgets.plan(app, '2026-09', now: DateTime(2026, 9));
      final before = jsonEncode(app.state);
      for (final period in ['2026-08', '2026-09-H2']) {
        expect(
          () => budgets.plan(
            app,
            period,
            type: period.contains('-H') ? 'biweekly' : 'monthly',
            now: october,
          ),
          throwsFormatException,
        );
      }
      expect(jsonEncode(app.state), before);
      budgets.plan(
        app,
        '2026-09',
        salary: 750,
        editingId: 'monthly:2026-09',
        now: october,
      );
      expect(findBudgetPlan(app, 'monthly:2026-09')!['salary'], 750);
      budgets.plan(app, '2026-10-H1', type: 'biweekly', now: october);
      budgets.plan(app, '2026-10-H2', type: 'biweekly', now: october);
      budgets.plan(app, '2026-11', now: october);
      expect(app.maps('budgetPlans').length, 4);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Budget opens compact and reveals only the requested details', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    budgets.plan(app, currentMonthKey());
    app.mutate(
      () => app.state['movements'] = [
        budgets.expense(formatDateTime(DateTime.now()), amount: 100),
        budgets.expense(
          formatDateTime(DateTime.now()),
          category: 'Salud',
          amount: 25,
        ),
      ],
    );
    app.setTab(1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Te queda en este periodo'), findsOneWidget);
    expect(find.text('Gastado'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-spending-bar')), findsOneWidget);
    expect(find.text('Salud'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('budget-remaining'))).data,
      r'$150,00',
    );
    expect(find.byType(BudgetCategoryTile), findsNWidgets(2));
    expect(find.text('Fuera del plan'), findsNothing);
    expect(find.text('Ingresos'), findsNothing);
    await tester.ensureVisible(find.text('Detalles del plan'));
    await tester.tap(find.text('Detalles del plan'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresos'), findsOneWidget);
    expect(find.text('Salud'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Picker omits empty previous months and calendar cannot select them',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final now = DateTime.now();
      final previous = budgetPeriodKeyFor(
        DateTime(now.year, now.month - 1),
        'monthly',
      );
      budgets.plan(app, currentMonthKey());
      app.setTab(1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final previousButton = find.descendant(
        of: find.byTooltip('Mes anterior'),
        matching: find.byType(CupertinoButton),
      );
      expect(tester.widget<CupertinoButton>(previousButton).onPressed, isNull);
      await tester.tap(find.text('Mes'));
      await tester.pumpAndSettle();
      expect(find.text(monthLabelForKey(previous)), findsNothing);
      await tester.tap(find.text('Elegir otro mes'));
      await tester.pumpAndSettle();
      final calendarBack = find
          .ancestor(
            of: find.byIcon(CupertinoIcons.chevron_left).last,
            matching: find.byType(CupertinoButton),
          )
          .first;
      expect(tester.widget<CupertinoButton>(calendarBack).onPressed, isNull);
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
      budgets.plan(
        app,
        '$previous-H1',
        type: 'biweekly',
        now: DateTime(now.year, now.month - 1),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1ra quincena'));
      await tester.pumpAndSettle();
      expect(find.text('Te queda en este periodo'), findsOneWidget);
      await tester.tap(find.text('2da quincena'));
      await tester.pumpAndSettle();
      expect(find.text('S\u00ed, crear plan'), findsNothing);
      expect(
        find.text('No hay un plan guardado para este periodo'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Undo notice lasts exactly three seconds and history stays available',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveMovement(fixtures.movement('expense'));
      await tester.pump();
      expect(find.byType(UndoNotice), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(find.byType(UndoNotice), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(UndoNotice), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(UndoNotice), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 151));
      expect(find.byType(UndoNotice), findsNothing);
      expect(app.canUndo, isTrue);
      expect(app.undoLastOperation(), isTrue);
      expect(app.maps('movements'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'New operation resets notice lifetime and action undoes only the latest',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveMovement(fixtures.movement('expense'));
      await tester.pump(const Duration(seconds: 2));
      app.saveMovement(fixtures.movement('expense', id: 'm2'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(UndoNotice), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.byType(UndoNotice), findsNothing);
      expect(app.maps('movements').length, 1);
      expect(app.maps('movements').single['id'], 'm');
      expect(app.maps('accounts').first['balance'], 79.7);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
