import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' as budgets;

Finder field(String hint) => find.byWidgetPredicate(
  (w) =>
      w is CupertinoTextField &&
      (w.placeholder == hint || w.key == ValueKey('amount-input-${hint}')),
);

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
    final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final name in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF Pro Display',
      'Roboto',
    ]) {
      await (FontLoader(name)..addFont(Future.value(bytes))).load();
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
      matchesGoldenFile('../build/release92-qa/$name.png'),
    );
  }

  testWidgets(
    'Action button rotates, dismisses and resets without pending callbacks',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final rotation = find.byKey(const ValueKey('home-action-rotation'));
      app.showQuickActions(tester.element(find.byType(HomePage)));
      await tester.pump();
      expect(tester.widget<AnimatedRotation>(rotation).turns, .125);
      await tester.pumpAndSettle();
      await capture(tester, 'actions-open');
      await tester.tapAt(tester.getCenter(rotation));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedRotation>(rotation).turns, 0);
      expect(app.quickActionsOpen, false);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'Numeric keypad edits decimal amounts, backspaces and saves once',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        defaultAccountId: 'a',
      );
      await tester.pumpAndSettle();
      for (final key in ['1', '2', ',', '3', '4', '5']) {
        await tester.tap(find.byKey(ValueKey('keypad-$key')));
        await tester.pump();
      }
      expect(
        tester.widget<CupertinoTextField>(field('Monto')).controller!.text,
        '12,34',
      );
      await tester.tap(find.byKey(const ValueKey('keypad-back')));
      await tester.pump();
      expect(
        tester.widget<CupertinoTextField>(field('Monto')).controller!.text,
        '12,30',
      );
      await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
      await tester.pumpAndSettle();
      expect(app.maps('movements').single['amount'], 12.3);
      expect(app.accountById('a')['balance'], 87.7);
    },
  );

  testWidgets('Received amount keypad and swap preserve the transfer amounts', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultType: 'transfer',
      defaultAccountId: 'a',
      defaultAmount: 10.0,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(field('Monto recibido'));
    await tester.tap(field('Monto recibido'));
    for (final key in ['1', '0', '0']) {
      await tester.tap(find.byKey(ValueKey('keypad-$key')));
      await tester.pump();
    }
    expect(
      tester.widget<CupertinoTextField>(field('Monto')).controller!.text,
      '10,00',
    );
    expect(
      tester
          .widget<CupertinoTextField>(field('Monto recibido'))
          .controller!
          .text,
      '100,00',
    );
    await tester.ensureVisible(find.byTooltip('Intercambiar cuentas'));
    await tester.tap(find.byTooltip('Intercambiar cuentas'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoTextField>(field('Monto')).controller!.text,
      '100,00',
    );
    expect(
      tester
          .widget<CupertinoTextField>(field('Monto recibido'))
          .controller!
          .text,
      '10,00',
    );
    await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
    await tester.pumpAndSettle();
    final movement = app.maps('movements').single;
    expect(movement['amount'], 100);
    expect(movement['targetAmount'], 10);
    expect(movement['rate'], 10);
    expect(movement['feeAmount'], 0);
  });

  testWidgets('Clock and numeric time selection preserve the movement date', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultAccountId: 'a',
    );
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(MovementEditor));
    final original = parseMovementDate(editor.date);
    await tester.ensureVisible(find.byKey(const ValueKey('composer-time')));
    await tester.tap(find.byKey(const ValueKey('composer-time')));
    await tester.pumpAndSettle();
    await capture(tester, 'time-numeric');
    await tester.tap(find.byTooltip('Usar reloj'));
    await tester.pumpAndSettle();
    await capture(tester, 'time-clock');
    expect(find.byType(material.TimePickerDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(material.TimePickerDialog)))
        .pop(const material.TimeOfDay(hour: 17, minute: 42));
    await tester.pumpAndSettle();
    final selected = parseMovementDate(editor.date);
    expect(selected.hour, 17);
    expect(selected.minute, 42);
    expect(isSameDate(original, selected), true);
  });

  testWidgets(
    'Amount paste, clearing and zero validation do not create movements',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        defaultAccountId: 'a',
      );
      await tester.pumpAndSettle();
      await capture(tester, 'expense-empty');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async =>
                call.method == 'Clipboard.getData' ? {'text': '12,34'} : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.tap(find.byKey(const ValueKey('keypad-paste')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(field('Monto')).controller!.text,
        '12,34',
      );
      await tester.tap(find.byKey(const ValueKey('keypad-clear')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(field('Monto')).controller!.text,
        '',
      );
      await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
      await tester.pumpAndSettle();
      expect(app.maps('movements'), isEmpty);
      expect(find.byType(MovementEditor), findsOneWidget);
    },
  );

  testWidgets(
    'Reduced motion disables menu rotation duration and reveal transitions',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final dynamic app = await fixtures.fixture(tester);
      app.showQuickActions(tester.element(find.byType(HomePage)));
      await tester.pumpAndSettle();
      final rotation = tester.widget<AnimatedRotation>(
        find.byKey(const ValueKey('home-action-rotation')),
      );
      expect(rotation.duration, Duration.zero);
      expect(rotation.turns, .125);
      await tester.tapAt(const Offset(10, 300));
      await tester.pumpAndSettle();
      app.setTab(1);
      await tester.pumpAndSettle();
      expect(find.text('Sin presupuesto'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('Long amount stays contained without moving the keypad', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    tester.view.physicalSize = const Size(320, 640);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultAccountId: 'a',
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(ComposerKeypad));
    await tester.enterText(field('Monto'), '999999999999,99');
    await tester.pumpAndSettle();
    final input = tester.widget<CupertinoTextField>(field('Monto'));
    final width = tester.getSize(field('Monto')).width;
    final painter = TextPainter(
      text: TextSpan(text: input.controller!.text, style: input.style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(painter.width, lessThanOrEqualTo(width + .01));
    painter.dispose();
    expect(tester.getRect(find.byType(ComposerKeypad)), before);
    await capture(tester, 'amount-long-320');
  });

  testWidgets('Copy previous month selects the matching fortnight', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    final now = DateTime.now();
    final previousDate = DateTime(now.year, now.month - 1);
    final previous = budgetPeriodKeyFor(previousDate, 'monthly');
    for (final half in [1, 2]) {
      budgets.plan(
        app,
        '$previous-H$half',
        type: 'biweekly',
        salary: half * 300.0,
        now: previousDate,
      );
    }
    app.setTab(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copiar del mes anterior'));
    await tester.pumpAndSettle();
    final editor = tester.widget<BudgetPlanEditorPage>(
      find.byType(BudgetPlanEditorPage),
    );
    final half = now.day <= 15 ? 1 : 2;
    expect(editor.plan!['period'], '$previous-H$half');
    expect(editor.initialPeriod, '${currentMonthKey()}-H$half');
  });

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        '3.5 composer, transfer, budget and menu fit $width dark=$dark',
        (tester) async {
          final dynamic app = await fixtures.fixture(tester);
          tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
          app.mutate(() => app.state['darkMode'] = dark);
          await capture(tester, 'home-$width-$dark');
          app.openMovementEditor(
            tester.element(find.byType(HomePage)),
            defaultAccountId: 'b',
            defaultAmount: 12.34,
          );
          await tester.pumpAndSettle();
          await capture(tester, 'expense-$width-$dark');
          expect(
            tester.getSize(find.byType(ComposerKeypad)).height,
            inInclusiveRange(194, 330),
          );
          final dynamic editor = tester.state(find.byType(MovementEditor));
          editor.changeType('income');
          await capture(tester, 'income-$width-$dark');
          editor.changeType('transfer');
          await tester.pumpAndSettle();
          await tester.enterText(field('Monto recibido'), '123,45');
          await capture(tester, 'transfer-$width-$dark');
          Navigator.of(tester.element(find.byType(MovementEditor))).pop();
          await tester.pumpAndSettle();
          app.setTab(1);
          await tester.pumpAndSettle();
          await capture(tester, 'budget-$width-$dark');
          expect(find.text('Sin presupuesto'), findsOneWidget);
          await tester.tap(find.text('Comenzar a planificar'));
          await tester.pumpAndSettle();
          expect(find.byType(BudgetPlanEditorPage), findsOneWidget);
          Navigator.of(tester.element(find.byType(BudgetPlanEditorPage))).pop();
          await tester.pumpAndSettle();
          app.setTab(2);
          await capture(tester, 'menu-$width-$dark');
        },
      );
    }
  }

  testWidgets(
    'Copy previous budget opens a new current-period plan without changing original',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final now = DateTime.now();
      final previous = budgetPeriodKeyFor(
        DateTime(now.year, now.month - 1),
        'monthly',
      );
      budgets.plan(
        app,
        previous,
        salary: 530,
        now: DateTime(now.year, now.month - 1),
      );
      final before = jsonEncode(app.maps('budgetPlans'));
      app.setTab(1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar del mes anterior'));
      await tester.pumpAndSettle();
      final editor = tester.widget<BudgetPlanEditorPage>(
        find.byType(BudgetPlanEditorPage),
      );
      expect(editor.copy, true);
      expect(editor.initialPeriod, currentMonthKey());
      expect(editor.plan!['salary'], 530);
      expect(jsonEncode(app.maps('budgetPlans')), before);
    },
  );
}
