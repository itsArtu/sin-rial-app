import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

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

  for (final partial in [false, true]) {
    for (final kind in ['payable', 'receivable']) {
      testWidgets(
        'Typed 20 becomes USD 20 after selecting dollars: $kind partial=$partial',
        (tester) async {
          final dynamic app = await fixtures.fixture(tester);
          app.mutate(
            () => app.debtById('d').addAll({'paidAmount': 0.0, 'kind': kind}),
          );
          app.openDebtMovement(
            tester.element(find.byType(HomePage)),
            app.debtById('d'),
            partial: partial,
          );
          await tester.pumpAndSettle();
          final dynamic editor = tester.state(find.byType(MovementEditor));
          expect(editor.accountId, 'b');
          await tester.enterText(field('Monto'), '20');
          final account = find.byWidgetPredicate(
            (w) => w is OptionField && w.label == 'Cuenta',
          );
          await tester.ensureVisible(account);
          await tester.tap(account);
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(ModernSheet),
              matching: find.text(accountPrimaryName(app.accountById('a'))),
            ),
          );
          await tester.pumpAndSettle();
          expect(parseAmount(editor.amount.text), 20);
          expect(parseAmount(editor.debtExchangeRate.text), 1);
          await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
          await tester.pumpAndSettle();
          expect(app.debtById('d')['paidAmount'], 20);
          expect(app.debtById('d')['status'], 'pending');
          expect(debtRemainingAmount(app.debtById('d')), 80);
          expect(app.accountById('a')['balance'], kind == 'payable' ? 80 : 120);
          expect(app.maps('movements').single['currency'], 'USD');
          expect(app.maps('movements').single['debtAppliedAmount'], 20);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'Budget item identity, currencies, allocation, edits, deletion and undo',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final period = currentMonthKey(),
          planId = budgetPlanId(period, 'monthly');
      void save(List<Map<String, dynamic>> items, {bool edit = false}) =>
          saveBudgetPlan(
            app,
            period: period,
            type: 'monthly',
            salary: 500,
            savings: 20,
            items: items,
            editingId: edit ? planId : null,
          );
      save([
        {
          'category': 'Deuda',
          'name': 'Gabriel',
          'limit': 50.0,
          'currency': 'USD',
        },
        {
          'category': 'Deuda',
          'name': 'Arturo',
          'limit': 200.0,
          'currency': 'VES',
        },
      ]);
      var items = budgetPlanItems(app, planId);
      final gabriel = items[0], arturo = items[1];
      Map<String, dynamic> expense(
        String id,
        double amount, {
        Map<String, dynamic>? item,
        String account = 'a',
      }) => {
        'id': id,
        'type': 'expense',
        'amount': amount,
        'currency': account == 'a' ? 'USD' : 'VES',
        'accountId': account,
        'date': formatDateTime(DateTime.now()),
        'category': 'Deuda',
        'rate': 10.0,
        'feeMode': 'none',
        if (item != null) ...{
          'budgetItemId': item['id'],
          'budgetPlanId': planId,
        },
      };
      app.saveMovement(expense('g', 20, item: gabriel));
      app.saveMovement(expense('a', 150, item: arturo, account: 'b'));
      app.saveMovement(expense('u', 3));
      BudgetSpending summary() => summarizeBudgetSpending(
        app.maps('movements'),
        period,
        'monthly',
        usdRate: app.rate,
        eurRate: app.eurRate,
        selectedCategories: {'Deuda'},
        items: budgetPlanItems(app, planId),
      );
      expect(summary().total, 38);
      expect(summary().items, {gabriel['id']: 20.0, arturo['id']: 15.0});
      expect(summary().itemCurrencies[arturo['id']], 150);
      expect(summary().unassigned['Deuda'], 3);
      save([
        {...gabriel, 'limit': 60.0},
        arturo,
      ], edit: true);
      expect(budgetPlanItems(app, planId).first['id'], gabriel['id']);
      expect(summary().items[gabriel['id']], 20);
      expect(app.movementById('g')['budgetItemName'], 'Gabriel');
      final report = budgetReport(
        plan: findBudgetPlan(app, planId)!,
        items: budgetPlanItems(app, planId),
        movements: app.maps('movements'),
        usdRate: app.rate,
        eurRate: app.eurRate,
      );
      expect((report['items'] as List).last['spent'], 'Bs. 150,00');
      expect(
        (report['details'] as List).any(
          (m) => m['budgetItemName'] == 'Gabriel',
        ),
        isTrue,
      );
      expect(await renderBudgetPdf(report), isNotEmpty);
      final before = jsonEncode(app.state);
      expect(
        () => app.saveMovement({
          ...expense('wrong', 2, item: gabriel),
          'category': 'Salud',
        }),
        throwsFormatException,
      );
      expect(jsonEncode(app.state), before);
      save([arturo], edit: true);
      expect(app.movementById('g')['amount'], 20);
      expect(summary().unassigned['Deuda'], 23);
      app.saveMovement(<String, dynamic>{
        ...app.movementById('g'),
        'description': 'Historic',
      }, editingId: 'g');
      expect(app.movementById('g')['budgetItemName'], 'Gabriel');
      expect(app.undoLastOperation(), isTrue);
      expect(app.undoLastOperation(), isTrue);
      expect(summary().items[gabriel['id']], 20);
      final restored = withDefaults(
        jsonDecode(jsonEncode(app.state)) as Map<String, dynamic>,
      );
      expect(restored['budgets'], app.state['budgets']);
      expect(restored['movements'], app.state['movements']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'A movement selects the named item and preserves it when edited',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final period = currentMonthKey(),
          planId = budgetPlanId(period, 'monthly');
      saveBudgetPlan(
        app,
        period: period,
        type: 'monthly',
        salary: 200,
        savings: 0,
        items: [
          {'category': 'Deuda', 'name': 'Gabriel', 'limit': 50.0},
          {'category': 'Deuda', 'name': 'Arturo', 'limit': 30.0},
        ],
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        defaultType: 'expense',
        defaultAccountId: 'a',
        defaultCategory: 'Deuda',
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Monto'), '20');
      final itemField = find.byWidgetPredicate(
        (w) => w is OptionField && w.label == 'Partida del presupuesto',
      );
      await tester.ensureVisible(itemField);
      await tester.tap(itemField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arturo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
      await tester.pumpAndSettle();
      final movement = app.maps('movements').single as Map<String, dynamic>;
      expect(movement['budgetItemId'], budgetPlanItems(app, planId).last['id']);
      expect(movement['budgetItemName'], 'Arturo');
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        movement: movement,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(itemField);
      expect(find.text('Arturo'), findsOneWidget);
      final dynamic editor = tester.state(find.byType(MovementEditor));
      final now = DateTime.now();
      editor.changeMovementDate(DateTime(now.year, now.month + 1, 1, 12));
      await tester.pumpAndSettle();
      expect(editor.budgetItemId, isEmpty);
      expect(editor.budgetLinkFields(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
