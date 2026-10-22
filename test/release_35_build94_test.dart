import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'monthly_spending_test.dart' as reports;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        ),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
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
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final name in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF Pro Display',
      'Roboto',
    ]) {
      await (FontLoader(name)..addFont(Future.value(font))).load();
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
      matchesGoldenFile('../build/release97-qa/$name.png'),
    );
  }

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    for (final dark in [true, false]) {
      final suffix = '${size.width.toInt()}-$dark';
      testWidgets('Update pages stay stable, swipe and finish once $suffix', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = size;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPadding);
        app.mutate(() {
          app.state['darkMode'] = dark;
          app.state['seenFeatureTour'] = '3.5.0+93';
        });
        await capture(tester, 'news-first-$suffix');
        expect(find.byType(HomePage), findsNothing);
        final nextRect = tester.getRect(find.text('Siguiente'));
        await tester.drag(
          find.byKey(const ValueKey('release-pages')),
          const Offset(-400, 0),
        );
        await tester.pumpAndSettle();
        expect(find.text('Movimientos al instante'), findsOneWidget);
        expect(tester.getRect(find.text('Siguiente')), nextRect);
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('Siguiente'));
          await tester.pumpAndSettle();
        }
        await capture(tester, 'news-last-$suffix');
        await tester.tap(find.text('Empezar'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
        expect(app.state['seenFeatureTour'], currentFeatureTour);
        app.mutate(() => app.state['darkMode'] = !dark);
        await tester.pumpAndSettle();
        expect(find.byType(ReleaseTour), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets(
        'Monthly charts, account logos and custom debt pills $suffix',
        (tester) async {
          final dynamic app = await fixtures.fixture(tester);
          tester.view.physicalSize = size;
          app.mutate(() {
            app.state['darkMode'] = dark;
            app.state['accounts'][0]['provider'] = 'BINANCE';
            app.state['accounts'][1]['provider'] = '0172';
            app.state['movements'] = reports.ledger();
          });
          app.pushPage(
            tester.element(find.byType(HomePage)),
            (_) => MonthlySpendingPage(app: app, initialMonth: '2026-09'),
          );
          await capture(tester, 'monthly-$suffix');
          expect(find.byType(MonthlyDistributionChart), findsOneWidget);
          expect(find.text('35,0% de los ingresos del mes'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('monthly-spending-account')),
          );
          await capture(tester, 'monthly-accounts-$suffix');
          final logos = tester.widgetList<LogoBadge>(
            find.descendant(
              of: find.byType(ModernSheet),
              matching: find.byType(LogoBadge),
            ),
          );
          expect(
            logos.map((logo) => logo.provider),
            containsAll(['BINANCE', '0172']),
          );
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cuentas').last);
          await capture(tester, 'monthly-by-account-$suffix');
          app.mutate(() => app.state['hideAmounts'] = true);
          await tester.pumpAndSettle();
          expect(find.byType(MonthlyDistributionChart), findsNothing);
          await tester.pageBack();
          await tester.pumpAndSettle();
          app.pushPage(
            tester.element(find.byType(HomePage)),
            (_) => MovementHistoryPage(app: app),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cuenta').last);
          await capture(tester, 'history-accounts-$suffix');
          final filterLogos = tester.widgetList<LogoBadge>(
            find.descendant(
              of: find.byType(ModernSheet),
              matching: find.byType(LogoBadge),
            ),
          );
          expect(
            filterLogos.map((logo) => logo.provider),
            containsAll(['BINANCE', '0172']),
          );
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          app.mutate(() => app.state['hideAmounts'] = false);
          app.pushPage(
            tester.element(find.byType(HomePage)),
            (_) => DebtOverview(app: app),
          );
          await capture(tester, 'debt-tabs-$suffix');
          expect(
            find.byType(CupertinoSlidingSegmentedControl<bool>),
            findsNothing,
          );
          await tester.tap(find.text('Pagados'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<AppPillSelector>(
                  find.byKey(const ValueKey('debt-status-selector')),
                )
                .value,
            'paid',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('Update news respects reduced motion', (tester) async {
    final dynamic app = await fixtures.fixture(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    app.mutate(() => app.state['seenFeatureTour'] = '3.5.0+93');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siguiente'));
    await tester.pump();
    expect(find.text('Movimientos al instante'), findsOneWidget);
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
