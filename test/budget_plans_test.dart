import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void plan(
  dynamic app,
  String period, {
  String type = 'monthly',
  double salary = 1000,
  double savings = 100,
  List<Map<String, dynamic>>? items,
  String? editingId,
  DateTime? now,
}) => saveBudgetPlan(
  app,
  period: period,
  type: type,
  salary: salary,
  savings: savings,
  editingId: editingId,
  now: now ?? DateTime(2026, 1),
  items:
      items ??
      [
        {'category': 'Comida', 'limit': 200.0},
        {'category': 'Transporte', 'limit': 50.0},
      ],
);

Map<String, dynamic> expense(
  String date, {
  String category = 'Comida',
  double amount = 10,
  String currency = 'USD',
  double fee = 0,
  String type = 'expense',
}) => {
  'id': '$date-$category',
  'accountId': 'a',
  'date': date,
  'category': category,
  'amount': amount,
  'currency': currency,
  'feeAmount': fee,
  'type': type,
};

Finder field(String hint) => find.byWidgetPredicate(
  (w) => w is CupertinoTextField && w.placeholder == hint,
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

  test('Legacy monthly and half-month budgets migrate once without losing categories', () {
    final old = defaultState()..remove('budgetPlansMigrated');
    old['budgetSalary'] = 500.0;
    old['budgetSavingsValue'] = 10.0;
    old['budgetSavingsMode'] = 'percent';
    old['budgets'] = [
      {
        'id': 'a',
        'month': '2026-08',
        'category': 'Comida',
        'limit': 80.0,
        'currency': 'USD',
      },
      {
        'id': 'b',
        'period': '2026-09-H2',
        'periodType': 'biweekly',
        'category': 'Wifi',
        'limit': 200.0,
        'currency': 'VES',
      },
    ];
    final migrated = withDefaults(old);
    expect((migrated['budgetPlans'] as List).map((p) => p['id']), [
      'monthly:2026-08',
      'biweekly:2026-09-H2',
    ]);
    expect((migrated['budgetPlans'] as List).first['savings'], 50);
    expect((migrated['budgets'] as List).last['currency'], 'VES');
    expect((migrated['budgets'] as List).first['planId'], 'monthly:2026-08');
    final restored = withDefaults(
      jsonDecode(jsonEncode(migrated)) as Map<String, dynamic>,
    );
    expect(restored['budgetPlans'], migrated['budgetPlans']);
    expect(restored['budgets'], migrated['budgets']);
    expect((old['budgets'] as List).first.containsKey('planId'), isFalse);
    final salaryOnly = defaultState()
      ..remove('budgetPlansMigrated')
      ..['budgetSalary'] = 300.0;
    expect((withDefaults(salaryOnly)['budgetPlans'] as List).length, 1);
    expect((withDefaults({})['budgetPlans'] as List), isEmpty);
  });

  test('Plans persist alongside split budget items', () async {
    final state = defaultState();
    state['budgetPlans'] = [
      {
        'id': 'monthly:2026-09',
        'period': '2026-09',
        'periodType': 'monthly',
        'salary': 100,
      },
    ];
    state['budgets'] = [
      {
        'id': 'item',
        'planId': 'monthly:2026-09',
        'category': 'Comida',
        'limit': 50,
      },
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
    expect(
      (jsonDecode(writes.last['state'] as String) as Map)
          .containsKey('budgetPlans'),
      isFalse,
    );
    expect(
      (jsonDecode(writes.last['parts']['budgetPlans'] as String) as List)
          .single['salary'],
      100,
    );
    expect(
      (jsonDecode(
        writes.last['parts']['budgets'] as String,
      ) as List).single['planId'],
      'monthly:2026-09',
    );
  });

  test('Period boundaries include the entire last day and preserve calendar halves', () {
    expect(budgetPeriodDateRange('2028-02-H2', 'biweekly'), [
      DateTime(2028, 2, 16),
      DateTime(2028, 2, 29),
    ]);
    expect(budgetPeriodDateRange('2026-02-H2', 'biweekly').last.day, 28);
    expect(nextBudgetPeriod('2026-09-H1', 'biweekly'), '2026-09-H2');
    expect(nextBudgetPeriod('2026-12-H2', 'biweekly'), '2027-01-H1');
    expect(nextBudgetPeriod('2026-12', 'monthly'), '2027-01');
    expect(validBudgetPeriod('2026-13', 'monthly'), isFalse);
    final records = [
      expense('15/09/2026 11:59 PM'),
      expense('16/09/2026 12:00 AM', amount: 20),
      expense('30/09/2026 11:59 PM', amount: 30),
      expense('01/10/2026 12:00 AM', amount: 40),
    ];
    expect(
      summarizeBudgetSpending(
        records,
        '2026-09-H1',
        'biweekly',
        usdRate: 10,
        eurRate: 12,
      ).total,
      10,
    );
    expect(
      summarizeBudgetSpending(
        records,
        '2026-09-H2',
        'biweekly',
        usdRate: 10,
        eurRate: 12,
      ).total,
      50,
    );
    expect(
      summarizeBudgetSpending(
        records,
        '2026-10',
        'monthly',
        usdRate: 10,
        eurRate: 12,
      ).total,
      40,
    );
  });

  test('Spending ranks real expenses, includes fees and excludes transfers and income', () {
    final records = [
      expense('20/09/2026 10:00 AM', amount: 50, category: 'Servicios'),
      expense('20/09/2026 10:00 AM', amount: 200, fee: 10, currency: 'VES'),
      expense(
        '20/09/2026 10:00 AM',
        amount: 10,
        currency: 'EUR',
        type: 'debt-payment',
      ),
      expense('20/09/2026 10:00 AM', amount: 5, currency: 'USDT'),
      expense('20/09/2026 10:00 AM', amount: 1000, type: 'income'),
      expense('20/09/2026 10:00 AM', amount: 1000, type: 'transfer'),
      expense('invalid', amount: 900),
    ];
    final summary = summarizeBudgetSpending(
      records,
      '2026-09',
      'monthly',
      usdRate: 10,
      eurRate: 12,
    );
    expect(summary.categories, {'Servicios': 50, 'Comida': 38});
    expect(summary.total, 88);
    expect(summary.ranked.first.key, 'Servicios');
    final noRate = summarizeBudgetSpending(
      records,
      '2026-09',
      'monthly',
      usdRate: 0,
      eurRate: 0,
    );
    expect(noRate.missingRates, 2);
    expect(noRate.total, 55);
    final colors = budgetCategories
        .map((c) => budgetCategoryColor(c, RTheme(true, 'indigo')))
        .toSet();
    expect(colors.length, budgetCategories.length);
  });

  testWidgets(
    'Editing, copying, deleting and undo keep independent period plans',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      plan(app, '2026-09');
      plan(app, '2026-10', salary: 2000);
      expect(findBudgetPlan(app, 'monthly:2026-09')!['salary'], 1000);
      final septemberItems = jsonEncode(
        budgetPlanItems(app, 'monthly:2026-09'),
      );
      plan(app, '2026-10', salary: 1800, editingId: 'monthly:2026-10');
      expect(
        jsonEncode(budgetPlanItems(app, 'monthly:2026-09')),
        septemberItems,
      );
      expect(findBudgetPlan(app, 'monthly:2026-10')!['salary'], 1800);
      app.undoLastOperation();
      expect(findBudgetPlan(app, 'monthly:2026-10')!['salary'], 2000);
      final movements = jsonEncode(app.maps('movements'));
      deleteBudgetPlan(app, 'monthly:2026-09');
      expect(findBudgetPlan(app, 'monthly:2026-09'), isNull);
      expect(budgetPlanItems(app, 'monthly:2026-09'), isEmpty);
      expect(findBudgetPlan(app, 'monthly:2026-10'), isNotNull);
      expect(jsonEncode(app.maps('movements')), movements);
      app.undoLastOperation();
      expect(
        jsonEncode(budgetPlanItems(app, 'monthly:2026-09')),
        septemberItems,
      );
      expect(findBudgetPlan(app, 'monthly:2026-09'), isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Duplicate and overlapping periods and invalid category limits are rejected',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      plan(app, '2026-09-H1', type: 'biweekly');
      plan(app, '2026-09-H2', type: 'biweekly');
      final before = jsonEncode(app.state);
      expect(() => plan(app, '2026-09'), throwsFormatException);
      expect(
        () => plan(app, '2026-09-H2', type: 'biweekly'),
        throwsFormatException,
      );
      expect(
        () => plan(app, '2026-10', salary: double.nan),
        throwsFormatException,
      );
      expect(() => plan(app, '2026-10', savings: 1001), throwsFormatException);
      expect(
        () => plan(
          app,
          '2026-10',
          items: [
            {'category': 'Comida', 'limit': -10},
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => plan(
          app,
          '2026-10',
          items: [
            {'category': 'Comida', 'limit': 10},
            {'category': 'Comida', 'limit': 20},
          ],
        ),
        throwsFormatException,
      );
      expect(jsonEncode(app.state), before);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Empty state launches a cancellable wizard and saves all steps atomically',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => BudgetPage(app: app),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('\u00bfQuieres crear un plan de presupuestos?'),
        findsOneWidget,
      );
      expect(find.text('Ingreso del periodo'), findsNothing);
      expect(find.text('Mes'), findsNothing);
      await tester.tap(find.text('S\u00ed, crear plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quincenal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16 a fin de mes'));
      await tester.ensureVisible(find.text('Seleccionar ingresos'));
      await tester.tap(find.text('Seleccionar ingresos'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Monto en USD').first, '1000');
      await tester.tap(find.byTooltip('Confirmar ingresos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Ahorro previsto en USD'), '100');
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seleccionar egresos'));
      await tester.pumpAndSettle();
      await tester.enterText(field('L\u00edmite del periodo en USD'), '150');
      await tester.tap(find.text('Guardar categor\u00eda'));
      await tester.pumpAndSettle();
      expect(app.maps('budgetPlans'), isEmpty);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Resumen del presupuesto'), findsOneWidget);
      await tester.tap(find.text('Confirmar presupuesto'));
      await tester.pumpAndSettle();
      expect(find.text('\u00a1Presupuesto creado!'), findsOneWidget);
      await tester.tap(find.text('Ir a presupuestos'));
      await tester.pumpAndSettle();
      expect(app.maps('budgetPlans').length, 1);
      expect(
        app.maps('budgetPlans').single['period'],
        '${currentMonthKey()}-H2',
      );
      expect(app.maps('budgets').single['limit'], 150);
      expect(find.text('Te queda en este periodo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Months and half-months select only their own plans and cache invalidates on edits',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      plan(app, '2026-09-H1', type: 'biweekly');
      plan(app, '2026-09-H2', type: 'biweekly', salary: 2000);
      plan(app, '2026-10', salary: 3000);
      final cache = BudgetSpendingCache();
      final initial = cache.read(app, '2026-09-H2', 'biweekly');
      expect(
        identical(cache.read(app, '2026-09-H2', 'biweekly'), initial),
        isTrue,
      );
      app.mutate(
        () => app
            .rawList('movements')
            .add(expense('20/09/2026 10:00 AM', amount: 40)),
      );
      expect(cache.read(app, '2026-09-H2', 'biweekly').total, 40);
      expect(cache.read(app, '2026-10', 'monthly').total, 0);
      await tester.pump(const Duration(seconds: 9));
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => BudgetPage(app: app),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mes'));
      await tester.pumpAndSettle();
      final october = find.descendant(
        of: find.byType(ModernSheetTile),
        matching: find.text('octubre de 2026'),
      );
      await tester.tap(october);
      await tester.pumpAndSettle();
      expect(find.text('\$250,00'), findsOneWidget);
      await tester.tap(find.text('Mes'));
      await tester.pumpAndSettle();
      final september = find.descendant(
        of: find.byType(ModernSheetTile),
        matching: find.text('septiembre de 2026'),
      );
      await tester.tap(september);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2da quincena'));
      await tester.pumpAndSettle();
      expect(find.text('\$210,00'), findsOneWidget);
      await tester.tap(find.text('1ra quincena'));
      await tester.pumpAndSettle();
      expect(find.text('\$250,00'), findsOneWidget);
      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('\$250,00'), findsOneWidget);
      expect(find.text('1ra quincena'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Copy wizard advances calendar dates, keeps source intact and cancel writes nothing',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      plan(app, '2026-12-H2', type: 'biweekly');
      final source = findBudgetPlan(app, 'biweekly:2026-12-H2')!;
      final before = jsonEncode(app.state);
      await tester.pump(const Duration(seconds: 9));
      final context = tester.element(find.byType(HomePage));
      app.pushPage(
        context,
        (_) => BudgetPlanEditorPage(
          app: app,
          plan: source,
          copy: true,
          initialPeriod: nextBudgetPeriod('2026-12-H2', 'biweekly'),
          initialType: 'biweekly',
        ),
      );
      await tester.pumpAndSettle();
      final dates = tester
          .widget<Text>(find.byKey(const ValueKey('budget-plan-dates')))
          .data!;
      expect(dates, contains('01/01/2027'));
      expect(dates, contains('15/01/2027'));
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('\$1.000,00'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Comida'), findsOneWidget);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(jsonEncode(app.state), before);
      app.pushPage(
        context,
        (_) => BudgetPlanEditorPage(
          app: app,
          plan: source,
          copy: true,
          initialPeriod: '2027-01-H1',
          initialType: 'biweekly',
          initialStep: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Resumen del presupuesto'), findsOneWidget);
      await tester.tap(find.text('Confirmar presupuesto'));
      await tester.pumpAndSettle();
      expect(find.text('\u00a1Presupuesto creado!'), findsOneWidget);
      await tester.tap(find.text('Ir a presupuestos'));
      await tester.pumpAndSettle();
      expect(findBudgetPlan(app, 'biweekly:2027-01-H1')!['salary'], 1000);
      expect(budgetPlanItems(app, 'biweekly:2027-01-H1').length, 2);
      expect(findBudgetPlan(app, 'biweekly:2026-12-H2'), source);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Legacy overlapping monthly and biweekly plans remain accessible',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final month = currentMonthKey();
      app.mutate(
        () => app.state['budgetPlans'] = [
          {
            'id': 'monthly:$month',
            'period': month,
            'periodType': 'monthly',
            'salary': 900.0,
            'savings': 0.0,
            'currency': 'USD',
          },
          {
            'id': 'biweekly:$month-H1',
            'period': '$month-H1',
            'periodType': 'biweekly',
            'salary': 450.0,
            'savings': 0.0,
            'currency': 'USD',
          },
        ],
      );
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => BudgetPage(app: app),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('budget-remaining')), findsOneWidget);
      await tester.tap(find.text('Quincenal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1ra quincena'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('budget-remaining')), findsOneWidget);
      expect(find.text('Mensual'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Home cache reuses work but refreshes changes, rates, undo and clock boundaries',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final cache = HomeLedgerCache();
      final now = DateTime(2026, 9, 30, 23, 59);
      final first = cache.read(app, now: now);
      expect(
        identical(
          first,
          cache.read(app, now: now.add(const Duration(seconds: 30))),
        ),
        isTrue,
      );
      expect(first.total, 110);
      app.mutate(() => app.state['rate'] = 20.0);
      final changed = cache.read(app, now: now);
      expect(changed.total, 105);
      expect(identical(first, changed), isFalse);
      final nextDay = cache.read(app, now: now.add(const Duration(minutes: 1)));
      expect(nextDay.trend.first.date, DateTime(2026, 10, 1));
      app.saveMovement(fixtures.movement('expense', amount: 10));
      expect(cache.read(app, now: now).expenses, 10.3);
      app.undoLastOperation();
      expect(cache.read(app, now: now).expenses, 0);
      app.mutate(() {
        app.state['homeBalanceCurrency'] = 'USDT';
        app.state['usdtRate'] = 25.0;
      });
      expect(cache.read(app, now: now).total, 104);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
