import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart' as charts;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const fontPath = String.fromEnvironment('FINANCE_TEST_FONT');
    if (fontPath.isEmpty) return;
    final bytes = ByteData.sublistView(await File(fontPath).readAsBytes());
    for (final family in [
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List).cast<Map>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('Finance surfaces fit $width dark=$dark', (tester) async {
        final dynamic app = await fixtures.fixture(tester, count: 5);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() => app.state['darkMode'] = dark);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final suffix = '${width.toInt()}-${dark ? 'dark' : 'light'}';
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/home-$suffix.png'),
          );
        }
        final chart = find.byType(charts.LineChart);
        final beforeTouch = tester.getRect(chart);
        await tester.tap(chart);
        await tester.pumpAndSettle();
        expect(tester.getRect(chart), beforeTouch);
        expect(
          tester.widget<charts.LineChart>(chart).data.showingTooltipIndicators,
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/home-touch-$suffix.png'),
          );
        }
        await tester.ensureVisible(find.text('Movimientos').first);
        await tester.tap(find.text('Movimientos').first);
        await tester.pumpAndSettle();
        expect(find.byType(MovementHistoryPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/history-$suffix.png'),
          );
        }
        app.mutate(() {
          app.accountById('a').addAll({
            'provider': '0102',
            'kind': 'national',
            'currency': 'VES',
          });
        });
        app.openMovementEditor(
          tester.element(find.byType(MovementHistoryPage)),
          defaultAccountId: 'a',
          defaultAmount: 1000.0,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/editor-$suffix.png'),
          );
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('movement-editor-fields')),
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();
        expect(find.text('Guardar movimiento').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/finance-qa/editor-keyboard-$suffix.png',
            ),
          );
        }
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final description = find.byWidgetPredicate(
          (w) => w is CupertinoTextField && w.placeholder == 'Descripción',
        );
        await tester.scrollUntilVisible(
          description,
          -150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('movement-editor-fields')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        for (final entry in {
          'motorcycle': 'La mamalona',
          'bank-commission': 'Comisiones bancarias',
        }.entries) {
          await tester.enterText(description, entry.value);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile('../build/finance-qa/${entry.key}-$suffix.png'),
            );
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
