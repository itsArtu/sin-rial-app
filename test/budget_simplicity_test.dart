import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' as budgets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        );
  });

  test('Old named limits merge by category without mutating source data', () {
    final original = [
      {
        'id': 'a',
        'category': 'Deuda',
        'name': 'Ana',
        'limit': 20.0,
        'currency': 'USD',
      },
      {
        'id': 'b',
        'category': 'Deuda',
        'name': 'Luis',
        'limit': 100.0,
        'currency': 'VES',
      },
      {'id': 'c', 'category': 'Transporte', 'limit': 100.0, 'currency': 'VES'},
      {'id': 'd', 'category': 'Transporte', 'limit': 200.0, 'currency': 'VES'},
    ];
    final before = jsonEncode(original);
    final rows = budgetCategoryLimits(original, usdRate: 10, eurRate: 12);
    expect(rows.length, 2);
    expect(rows.first['limit'], 30);
    expect(rows.first['currency'], 'USD');
    expect(rows.first['name'], '');
    expect(rows.last['limit'], 300);
    expect(rows.last['currency'], 'VES');
    expect(jsonEncode(original), before);
  });

  testWidgets(
    'Budget selector creates a category even with no search results',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      Map<String, dynamic>? saved;
      app
          .pushPage<Map<String, dynamic>>(
            tester.element(find.byType(HomePage)),
            (_) => BudgetCategoryEditorPage(
              app: app,
              siblings: const [
                {'category': 'Deuda', 'limit': 50.0},
              ],
            ),
          )
          .then((dynamic result) => saved = result as Map<String, dynamic>?);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Categor\u00eda'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ModernSheetTile, 'Deuda'), findsNothing);
      await tester.enterText(budgets.field('Buscar'), 'No existe');
      await tester.pumpAndSettle();
      expect(find.text('Crear categor\u00eda'), findsOneWidget);
      await tester.tap(find.text('Crear categor\u00eda'));
      await tester.pumpAndSettle();
      await tester.enterText(budgets.field('Nombre'), 'Mi actividad');
      await tester.ensureVisible(find.text('Guardar categor\u00eda'));
      await tester.tap(find.text('Guardar categor\u00eda'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OptionField, 'Mi actividad'), findsOneWidget);
      expect(budgets.field('Nombre de la partida'), findsNothing);
      await tester.enterText(
        budgets.field('L\u00edmite del periodo en USD'),
        '25',
      );
      await tester.tap(find.text('Guardar categor\u00eda'));
      await tester.pumpAndSettle();
      expect(saved!['category'], 'Mi actividad');
      expect(saved!['name'], '');
      expect(saved!['limit'], 25);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Editing legacy plan merges limits without changing ledger', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    budgets.plan(
      app,
      currentMonthKey(),
      items: [
        {'category': 'Deuda', 'name': 'Ana', 'limit': 20.0, 'currency': 'USD'},
        {'category': 'Deuda', 'name': 'Luis', 'limit': 30.0, 'currency': 'USD'},
      ],
    );
    final before = jsonEncode(app.maps('movements'));
    final accounts = jsonEncode(app.maps('accounts'));
    final plan = app.maps('budgetPlans').single;
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => BudgetPlanEditorPage(
        app: app,
        plan: plan,
        initialPeriod: currentMonthKey(),
        initialType: 'monthly',
        initialStep: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BudgetCategoryTile), findsOneWidget);
    final tile = tester.widget<BudgetCategoryTile>(
      find.byType(BudgetCategoryTile),
    );
    expect(tile.category, 'Deuda');
    expect(tile.limit, 50);
    expect(find.textContaining('Ana'), findsNothing);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar presupuesto'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(budgetPlanItems(app, plan['id']).single['limit'], 50);
    expect(budgetPlanItems(app, plan['id']).single['name'], '');
    expect(jsonEncode(app.maps('movements')), before);
    expect(jsonEncode(app.maps('accounts')), accounts);
    app.undoLastOperation();
    expect(budgetPlanItems(app, plan['id']).length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (var page = 0; page < 5; page++) {
    testWidgets(
      'Upgrade tour can be skipped on page $page and does not repeat',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        app.mutate(() => app.state['seenFeatureTour'] = '3.2.1+85');
        await tester.pumpAndSettle();
        for (var i = 0; i < page; i++) {
          await tester.tap(find.text('Siguiente'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Omitir'), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.tap(find.text('Omitir'));
        await tester.pumpAndSettle();
        expect(app.state['seenFeatureTour'], currentFeatureTour);
        expect(find.byType(ReleaseTour), findsNothing);
        final state = withDefaults(Map<String, dynamic>.from(app.state));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(RialApp(initialState: state));
        await tester.pumpAndSettle();
        expect(find.byType(ReleaseTour), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Tour artwork respects reduced motion', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: TourArtwork(
            theme: RTheme(true, 'cyan'),
            icon: CupertinoIcons.tag,
          ),
        ),
      ),
    );
    final animation = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(animation.duration, Duration.zero);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Budget and all tour pages fit small screens with large text', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    budgets.plan(
      app,
      currentMonthKey(),
      items: [
        {
          'category': 'Actividades deportivas y entretenimiento',
          'limit': 999999.0,
        },
      ],
    );
    app.setTab(1);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(BudgetCategoryTile));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
    app.mutate(() => app.state['seenFeatureTour'] = '');
    await tester.pumpAndSettle();
    for (var page = 0; page < 5; page++) {
      expect(find.text('Omitir').hitTestable(), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Página ${page + 1} de 5',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (page < 4) {
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
