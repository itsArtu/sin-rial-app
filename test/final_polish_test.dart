import 'composer_test_helpers.dart' as composer;

import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart' as charts;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' show field;
import 'appearance_polish_test.dart' show capture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        ),
  );

  Future<dynamic> income(WidgetTester tester, {required bool ask}) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() => app.state['askExpenseReference'] = ask);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultType: 'income',
      defaultAccountId: 'a',
      defaultAmount: 10.0,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('Income does not ask for a reference when disabled', (
    tester,
  ) async {
    final dynamic app = await income(tester, ask: false);
    expect(find.byType(MovementReferenceDialog), findsNothing);
    expect(app.maps('movements').single['reference'], '');
    expect(app.accountById('a')['balance'], 110);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Opted-in income waits for No and is saved exactly once', (
    tester,
  ) async {
    final dynamic app = await income(tester, ask: true);
    expect(find.byType(MovementReferenceDialog), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(app.maps('movements'), isEmpty);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(app.maps('movements').length, 1);
    expect(app.maps('movements').single['reference'], '');
    expect(app.accountById('a')['balance'], 110);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Income reference preserves zeros and can be edited without asking again',
    (tester) async {
      final dynamic app = await income(tester, ask: true);
      await tester.tap(find.text('S\u00ed'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar ingreso'), findsOneWidget);
      await capture(tester, find.byType(RialApp), 'income-reference-build88');
      await tester.enterText(field('N\u00famero de referencia'), '000987');
      await tester.tap(find.text('Guardar ingreso'));
      await tester.pumpAndSettle();
      final movement = app.maps('movements').single as Map<String, dynamic>;
      expect(movement['type'], 'income');
      expect(movement['reference'], '000987');
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        movement: movement,
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Referencia (opcional)'), '000123');
      await tester.tap(composer.saveChanges());
      await tester.pumpAndSettle();
      expect(find.byType(MovementReferenceDialog), findsNothing);
      expect(app.maps('movements').length, 1);
      expect(app.maps('movements').single['reference'], '000123');
      expect(app.accountById('a')['balance'], 110);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Movement colors have an amount list, not the theme color grid', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => SettingsPage(app: app, section: 'Apariencia'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('expense-color')));
    await tester.tap(find.byKey(const ValueKey('expense-color')));
    await tester.pumpAndSettle();
    final picker = find.byType(MovementColorPicker);
    await capture(tester, find.byType(RialApp), 'expense-colors-build88');
    expect(
      find.descendant(of: picker, matching: find.byType(ThemeColorSelector)),
      findsNothing,
    );
    expect(
      find.descendant(of: picker, matching: find.text('-100,00')),
      findsNWidgets(themeColorOptions.length),
    );
    final color = find.byKey(const ValueKey('movement-swatch-coral'));
    await tester.ensureVisible(color);
    await tester.tap(color);
    await tester.pumpAndSettle();
    expect(app.state['expenseColor'], 'coral');
    expect(app.state['themeColor'], 'emerald');
    expect(app.state['incomeColor'], 'default');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('About credit stays centered with large text', (tester) async {
    final dynamic app = await fixtures.fixture(tester);
    tester.view.physicalSize = const Size(320, 640);
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.6),
        ),
        child: SettingsPage(app: app, section: 'Acerca de'),
      ),
    );
    await tester.pumpAndSettle();
    final credit = find.text('Hecha por Arturo el siuuuu');
    expect(tester.widget<Text>(credit).textAlign, TextAlign.center);
    expect(tester.getCenter(credit).dx, closeTo(160, .1));
    expect(tester.takeException(), isNull);
    await capture(tester, find.byType(RialApp), 'about-build88');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final currency in ['USDT', 'USD', 'EUR']) {
    for (final count in [1, 2, 7]) {
      testWidgets('$currency chart is touchable between $count observations', (
        tester,
      ) async {
        final points = [
          for (var i = 0; i < count; i++)
            RateObservation(
              DateTime.utc(2026, 10, 10 + i, 12),
              100 + (count == 7 ? i.toDouble() : 0),
            ),
        ];
        await tester.pumpWidget(
          CupertinoApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 70,
                child: RateSparkline(
                  points: points,
                  theme: RTheme(true, 'cyan'),
                  currency: currency,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final chart = find.byKey(ValueKey('rate-chart-$currency'));
        final rect = tester.getRect(chart);
        await tester.tapAt(Offset(rect.left + 120, rect.center.dy));
        await tester.pumpAndSettle();
        var data = tester.widget<charts.LineChart>(chart).data;
        expect(data.showingTooltipIndicators, hasLength(1));
        expect(data.lineBarsData.single.spots, hasLength(count));
        await tester.tapAt(Offset(rect.right - 40, rect.center.dy));
        await tester.pumpAndSettle();
        data = tester.widget<charts.LineChart>(chart).data;
        expect(
          data.showingTooltipIndicators.single.showingSpots.single.spotIndex,
          count == 7 ? 5 : count - 1,
        );
        expect(tester.getRect(chart), rect);
        if (currency == 'USDT') {
          await capture(
            tester,
            find.byType(CupertinoApp),
            'usdt-$count-build88',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'USDT empty history is explicit and new history clears a stale tooltip',
    (tester) async {
      Widget chart(List<RateObservation> points) => CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 70,
            child: RateSparkline(
              points: points,
              theme: RTheme(true, 'cyan'),
              currency: 'USDT',
            ),
          ),
        ),
      );
      await tester.pumpWidget(chart([]));
      expect(find.text('Sin historial disponible'), findsOneWidget);
      expect(find.byType(charts.LineChart), findsNothing);
      final points = [RateObservation(DateTime.utc(2026, 10, 14, 1), 100)];
      await tester.pumpWidget(chart(points));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(charts.LineChart));
      await tester.pumpAndSettle();
      var data = tester
          .widget<charts.LineChart>(find.byType(charts.LineChart))
          .data;
      final spots = data.showingTooltipIndicators.single.showingSpots;
      expect(
        data.lineTouchData.touchTooltipData.getTooltipItems(spots).single!.text,
        '13/10/2026\nBs. 100,00',
      );
      await tester.pumpWidget(
        chart([RateObservation(DateTime.utc(2026, 10, 15, 12), 101)]),
      );
      await tester.pumpAndSettle();
      data = tester
          .widget<charts.LineChart>(find.byType(charts.LineChart))
          .data;
      expect(data.showingTooltipIndicators, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
