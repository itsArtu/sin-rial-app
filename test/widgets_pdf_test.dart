import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' as budgets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const fontPath = String.fromEnvironment('FINANCE_TEST_FONT');
    if (fontPath.isEmpty) return;
    final data = ByteData.sublistView(await File(fontPath).readAsBytes());
    for (final family in [
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Ahem',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
  });
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        ),
  );

  final plan = <String, dynamic>{
    'id': 'p',
    'period': '2026-09-H2',
    'periodType': 'biweekly',
    'salary': 100,
    'savings': 10,
    'currency': 'USD',
  };
  final items = <Map<String, dynamic>>[
    {'planId': 'p', 'category': 'Comida', 'limit': 40, 'currency': 'USD'},
    {'planId': 'p', 'category': 'Transporte', 'limit': 10, 'currency': 'USD'},
    {'planId': 'other', 'category': 'Salud', 'limit': 500, 'currency': 'USD'},
  ];
  test('PDF snapshot contains selected categories and exact fortnight including fees', () {
    final report = budgetReport(
      plan: plan,
      items: items,
      usdRate: 10,
      eurRate: 12,
      movements: [
        budgets.expense('15/09/2026 11:59 PM', amount: 999),
        budgets.expense('16/09/2026 12:00 AM', amount: 5, fee: 1),
        budgets.expense('30/09/2026 11:59 PM', amount: 100, currency: 'VES'),
        budgets.expense('01/10/2026 12:00 AM', amount: 999),
        budgets.expense('22/09/2026 10:00 AM', amount: 999, category: 'Salud'),
      ],
    );
    expect(report['spent'], r'$16,00');
    expect(report['remaining'], r'$34,00');
    expect((report['rows'] as List).map((r) => r['name']), [
      'Comida',
      'Transporte',
    ]);
    expect(report['range'], '16/09/2026 - 30/09/2026');
  });
  test(
    'PDF refuses partial conversion instead of reporting incomplete totals',
    () {
      expect(
        () => budgetReport(
          plan: plan,
          items: items,
          usdRate: 0,
          eurRate: 0,
          movements: [budgets.expense('22/09/2026 10:00 AM', currency: 'VES')],
        ),
        throwsFormatException,
      );
    },
  );
  test('PDF monthly report and variable income preserve plan data', () {
    final monthly = {
      ...plan,
      'period': '2026-09',
      'periodType': 'monthly',
      'incomeMode': 'variable',
    };
    final before = jsonEncode(monthly);
    final report = budgetReport(
      plan: monthly,
      items: items,
      usdRate: 10,
      eurRate: 12,
      movements: [budgets.expense('01/09/2026 12:00 AM', amount: 60)],
    );
    expect(report['spent'], r'$60,00');
    expect(report['over'], true);
    expect(report['income'], 'Variable');
    expect(jsonEncode(monthly), before);
  });
  test('PDF channel preserves snapshot and distinguishes cancel, success, and errors', () async {
    final report = budgetReport(
      plan: {...plan, 'period': '2026-09', 'periodType': 'monthly'},
      items: items,
      movements: [],
      usdRate: 10,
      eurRate: 12,
    );
    for (final result in [false, true]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            expect(call.method, 'exportBudgetPdf');
            expect(
              (call.arguments as Map)['name'],
              'Sin-Rial-presupuesto-2026-09.pdf',
            );
            expect(
              ascii.decode(
                ((call.arguments as Map)['bytes'] as List<int>)
                    .take(5)
                    .toList(),
              ),
              '%PDF-',
            );
            return result;
          });
      expect(await saveBudgetPdf(report), result);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          _,
        ) async {
          throw PlatformException(code: 'PDF_SAVE_FAILED');
        });
    await expectLater(saveBudgetPdf(report), throwsA(isA<PlatformException>()));
  });

  test('PDF renders many categories, accented names, and large amounts over multiple pages', () async {
    final report = budgetReport(
      plan: plan,
      items: items,
      movements: [],
      usdRate: 10,
      eurRate: 12,
    );
    report['font'] = await rootBundle.load('assets/fonts/Manrope-Medium.ttf');
    report['rows'] = List.generate(
      55,
      (i) => {
        'name': 'Educaci\u00f3n y formaci\u00f3n profesional $i',
        'limit': r'$999.999.999,00',
        'spent': r'$60,00',
        'remaining': r'$999.999.939,00',
        'fraction': .6,
        'over': false,
        'color': 0xff247b7b,
      },
    );
    final bytes = await renderBudgetPdf(report);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(10000));
    final dir = Directory('build/widgets-pdf-qa')..createSync(recursive: true);
    await File(dir.path + '/budget-sample.pdf').writeAsBytes(bytes);
  });

  testWidgets(
    'Add widgets is last, only for missing sections, and opens the widgets tab',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      expect(find.byType(HomeWidgetsButton), findsNothing);
      app.mutate(
        () => app.state['homeSections'] = ['metrics', 'accounts', 'recent'],
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-add-widgets')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final button = tester
          .getTopLeft(find.byKey(const ValueKey('home-add-widgets')))
          .dy;
      expect(
        button,
        greaterThan(tester.getTopLeft(find.text('MOVIMIENTOS RECIENTES')).dy),
      );
      await tester.drag(
        find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-add-widgets')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeCustomizePage), findsOneWidget);
      expect(
        tester
            .widget<CupertinoSlidingSegmentedControl<int>>(
              find.byType(CupertinoSlidingSegmentedControl<int>),
            )
            .groupValue,
        1,
      );
      app.rootNavigatorKey.currentState.pop();
      app.mutate(
        () => app.state['homeSections'] = [
          'metrics',
          'accounts',
          'upcoming',
          'recent',
        ],
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeWidgetsButton), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Birth date direct year and month selection validates leap days and future dates',
    (tester) async {
      DateTime? selected;
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              child: const Text('Abrir'),
              onPressed: () async {
                selected = await appBirthDatePicker(
                  context,
                  RTheme(true, 'teal'),
                  DateTime(2000, 2, 29),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('birth-year')), '2001');
      await tester.tap(find.text('Confirmar fecha'));
      await tester.pumpAndSettle();
      expect(find.text('Revisa la fecha de nacimiento.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('birth-year')), '2999');
      await tester.tap(find.text('Confirmar fecha'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.enterText(find.byKey(const ValueKey('birth-year')), '1994');
      await tester.enterText(find.byKey(const ValueKey('birth-day')), '12');
      await tester.tap(find.text('Febrero'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Mayo'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Mayo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar fecha'));
      await tester.pumpAndSettle();
      expect(selected, DateTime(1994, 5, 12));
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final dark in [true, false]) {
      testWidgets('Birth date dialog fits $width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          CupertinoApp(
            home: Builder(
              builder: (context) => CupertinoButton(
                child: const Text('Abrir'),
                onPressed: () => appBirthDatePicker(
                  context,
                  RTheme(dark, 'teal'),
                  DateTime(1994, 5, 12),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(CupertinoApp),
            matchesGoldenFile(
              '../build/widgets-pdf-qa/birthday-$width-$dark.png',
            ),
          );
        }
        final bounds = tester.getRect(find.byType(BirthDateDialog));
        expect(bounds.left, greaterThanOrEqualTo(0));
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('Notice has a real intermediate fade on dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            child: const Text('Abrir'),
            onPressed: () =>
                showModernNotice(context, title: 'Testers', message: 'Gracias'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Testers'));
    Navigator.pop(context);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(find.text('Testers'), findsOneWidget);
    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.text('Testers'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades.any((f) => f.opacity.value > 0 && f.opacity.value < 1), true);
    await tester.pumpAndSettle();
    expect(find.text('Testers'), findsNothing);
  });
}
