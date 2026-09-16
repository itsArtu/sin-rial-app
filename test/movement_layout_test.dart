import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

const editorFieldsKey = ValueKey('movement-editor-fields');
const editorTypeKey = ValueKey('movement-editor-type');
const editorSaveKey = ValueKey('movement-editor-save');
const historyMonthKey = ValueKey('movement-history-month');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets(
      'Editor actions stay fixed with scrolling and keyboard at $size',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetViewInsets);
        app.mutate(() {
          app.state['accounts'] = [
            {
              'id': 'a',
              'kind': 'national',
              'provider': '0102',
              'currency': 'VES',
              'balance': 20000.0,
            },
            {
              'id': 'b',
              'provider': 'cash',
              'currency': 'VES',
              'balance': 100.0,
            },
          ];
        });
        app.openMovementEditor(
          tester.element(find.byType(HomePage)),
          defaultAccountId: 'a',
          defaultAmount: 100.0,
        );
        await tester.pumpAndSettle();
        final fields = find.byKey(editorFieldsKey);
        final selector = find.byKey(editorTypeKey);
        final save = find.byKey(editorSaveKey);
        final selectorRect = tester.getRect(selector);
        final saveRect = tester.getRect(save);
        expect(find.text('Guardar movimiento').hitTestable(), findsOneWidget);
        expect(tester.getRect(fields).bottom, lessThanOrEqualTo(saveRect.top));
        await tester.drag(fields, const Offset(0, -1400));
        await tester.pumpAndSettle();
        expect(tester.getRect(selector), selectorRect);
        expect(tester.getRect(save), saveRect);

        for (final item in {
          'Ingreso': 'income',
          'Transferir': 'transfer',
          'Gasto': 'expense',
        }.entries) {
          await tester.tap(
            find.descendant(of: selector, matching: find.text(item.key)),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<KindSelector>(selector).value, item.value);
          expect(tester.getRect(selector), selectorRect);
          expect(tester.getRect(save), saveRect);
        }

        final description = find.byWidgetPredicate(
          (w) => w is CupertinoTextField && w.placeholder == 'Descripción',
        );
        await tester.scrollUntilVisible(
          description,
          -150,
          scrollable: find
              .descendant(of: fields, matching: find.byType(Scrollable))
              .first,
        );
        await tester.enterText(description, 'Prueba fija');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        final keyboardSaveRect = tester.getRect(save);
        expect(tester.getRect(selector), selectorRect);
        expect(keyboardSaveRect.bottom, lessThanOrEqualTo(size.height - 280));
        expect(tester.getRect(fields).height, greaterThan(50));
        await tester.drag(fields, const Offset(0, -1000));
        await tester.pumpAndSettle();
        expect(tester.getRect(selector), selectorRect);
        expect(tester.getRect(save), keyboardSaveRect);
        expect(find.text('Guardar movimiento').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Guardar movimiento'));
        await tester.pumpAndSettle();
        expect(app.maps('movements').single['description'], 'Prueba fija');
        expect(app.maps('movements').single['amount'], 100.0);
        expect(find.byType(MovementEditor), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final mode in MovementHistoryMode.values) {
    testWidgets('History selects one month and keeps filters for $mode', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      final now = DateTime.now();
      final prior = DateTime(now.year, now.month - 1, 15);
      final yearAgo = DateTime(now.year - 1, now.month, 15);
      Map<String, dynamic> record(
        String id,
        String type,
        DateTime date,
        double amount,
      ) => {
        'id': id,
        'accountId': 'a',
        'type': type,
        'amount': amount,
        'currency': 'USD',
        'category': 'Otro',
        'description': id,
        'date': formatDateTime(date),
      };
      app.mutate(
        () => app.state['movements'] = [
          record('Actual gasto', 'expense', now, 10),
          record('Actual ingreso', 'income', now, 20),
          record('Anterior gasto', 'expense', prior, 40),
          record('Anterior ingreso', 'income', prior, 50),
          record('Anual gasto', 'expense', yearAgo, 60),
          record('Anual ingreso', 'income', yearAgo, 70),
        ],
      );
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => MovementHistoryPage(app: app, mode: mode),
      );
      await tester.pumpAndSettle();
      final currentLabel = monthLabelForKey(currentMonthKey());
      final priorLabel = monthLabelForKey(
        monthKeyFromDate(formatDateTime(prior)),
      );
      final yearLabel = monthLabelForKey(
        monthKeyFromDate(formatDateTime(yearAgo)),
      );
      expect(
        tester.widget<OptionField>(find.byKey(historyMonthKey)).value,
        currentLabel,
      );
      final count = mode == MovementHistoryMode.all ? 2 : 1;
      expect(find.text('$count operaciones'), findsOneWidget);
      final currentTotal = mode == MovementHistoryMode.all
          ? 30.0
          : mode == MovementHistoryMode.income
          ? 20.0
          : 10.0;
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('filtered-total'))).data,
        money(currentTotal, 'USD'),
      );

      await tester.enterText(find.byType(CupertinoSearchTextField), 'Actual');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(historyMonthKey));
      await tester.tap(find.byKey(historyMonthKey));
      await tester.pumpAndSettle();
      final sheet = find.byType(ModernSheet);
      expect(
        find.descendant(of: sheet, matching: find.text(yearLabel)),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: sheet, matching: find.text(priorLabel)),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 operaciones'), findsOneWidget);
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();
      expect(find.text('$count operaciones'), findsOneWidget);
      final priorTotal = mode == MovementHistoryMode.all
          ? 90.0
          : mode == MovementHistoryMode.income
          ? 50.0
          : 40.0;
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('filtered-total'))).data,
        money(priorTotal, 'USD'),
      );
      await tester.tap(find.text('Totales del mes'));
      await tester.pumpAndSettle();
      final summary = tester.widget<MonthlyMovementSummaryCard>(
        find.byType(MonthlyMovementSummaryCard),
      );
      expect(summary.summary.totalUsd, priorTotal);
      expect(monthLabelForKey(summary.summary.monthKey), priorLabel);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
