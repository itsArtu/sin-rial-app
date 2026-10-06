import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  testWidgets('Covered routes defer work and refresh before returning', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    var builds = 0;
    app.pushPage(tester.element(find.byType(HomePage)), (_) {
      builds++;
      return CupertinoPageScaffold(
        child: Text('Balance ${app.accountById('a')['balance']}'),
      );
    });
    await tester.pumpAndSettle();
    app.pushPage(
      tester.element(find.text('Balance 100.0')),
      (_) => const CupertinoPageScaffold(child: Text('Cubierta')),
    );
    await tester.pumpAndSettle();
    final coveredBuilds = builds;
    app.saveMovement(fixtures.movement('income')..['feeAmount'] = 0.0);
    await tester.pumpAndSettle();
    expect(builds, coveredBuilds);
    app.rootNavigatorKey.currentState.pop();
    await tester.pumpAndSettle();
    expect(find.text('Balance 120.0'), findsOneWidget);
    app.undoLastOperation();
    await tester.pumpAndSettle();
    expect(find.text('Balance 100.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Unchanged system bars are not sent again on financial mutations',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            calls.add(call);
            return call.method == 'scheduleRateUpdate' ? true : null;
          });
      final dynamic app = await fixtures.fixture(tester);
      calls.clear();
      app.saveMovement(fixtures.movement('income'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'setSystemBars'), isEmpty);
      app.mutate(() => app.state['darkMode'] = !app.dark);
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'setSystemBars'), hasLength(1));
    },
  );

  Future<dynamic> openMenuPage(WidgetTester tester, String title) async {
    final dynamic app = await fixtures.fixture(tester);
    app.setTab(2);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(ModernMenu), matching: find.text(title)),
    );
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('Menu accounts reflect edits and movements without reopening', (
    tester,
  ) async {
    final dynamic app = await openMenuPage(tester, 'Cuentas');
    final page = find.byType(AccountsPage);
    final element = tester.element(page);
    app.saveAccount(<String, dynamic>{
      ...app.accountById('a') as Map<String, dynamic>,
      'label': 'Cuenta editada',
      'balance': 125.0,
    }, editingId: 'a');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: page, matching: find.text('Cuenta editada')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: page, matching: find.text(money(125, 'USD'))),
      findsOneWidget,
    );
    app.saveMovement(fixtures.movement('expense')..['feeAmount'] = 0.0);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: page, matching: find.text(money(105, 'USD'))),
      findsOneWidget,
    );
    app.undoLastOperation();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: page, matching: find.text(money(125, 'USD'))),
      findsOneWidget,
    );
    expect(tester.element(page), same(element));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Menu history refreshes records and keeps its filter state', (
    tester,
  ) async {
    final dynamic app = await openMenuPage(tester, 'Movimientos');
    final dynamic history = tester.state(find.byType(MovementHistoryPage));
    history.selectedMonth = '2026-09';
    history.showSummaries = true;
    app.saveMovement(
      fixtures.movement('expense')..['description'] = 'Compra nueva',
    );
    await tester.pumpAndSettle();
    expect(find.text('Compra nueva'), findsOneWidget);
    expect(history.selectedMonth, '2026-09');
    expect(history.showSummaries, isTrue);
    expect(tester.state(find.byType(MovementHistoryPage)), same(history));
    app.saveMovement(
      fixtures.movement('expense')..['description'] = 'Compra corregida',
      editingId: 'm',
    );
    await tester.pumpAndSettle();
    expect(find.text('Compra corregida'), findsOneWidget);
    expect(find.text('Compra nueva'), findsNothing);
    app.undoLastOperation();
    await tester.pumpAndSettle();
    expect(find.text('Compra nueva'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
