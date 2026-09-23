import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
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
    for (final scale in [1.0, 1.8]) {
      testWidgets('Balance cards have compact spacing at $width / $scale', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        app.mutate(() => app.state['homeSections'] = ['accounts']);
        await tester.pumpAndSettle();
        for (final currency in ['VES', 'USD']) {
          final heading = tester.getRect(
            find.byKey(ValueKey('balance-heading-$currency')),
          );
          final amount = tester.getRect(
            find.byKey(ValueKey('balance-amount-$currency')),
          );
          final card = tester.getRect(
            find.byKey(ValueKey('balance-group-$currency')),
          );
          expect(amount.top - heading.bottom, closeTo(8, .1));
          expect(card.width, lessThanOrEqualTo(width - 32));
          expect(amount.right, lessThanOrEqualTo(card.right - 15));
          if (scale == 1) expect(card.height, lessThan(150));
        }
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('balance-group-VES')),
          );
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/balances-privacy-qa/balances-$width-$scale.png',
            ),
          );
        }
      });
    }
  }

  testWidgets(
    'Privacy option persists independently from PIN and amount visibility',
    (tester) async {
      Map<String, dynamic>? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            if (call.method == 'writeSplitState') {
              saved = jsonDecode((call.arguments as Map)['state'] as String);
            }
            return call.method == 'scheduleRateUpdate' ? true : null;
          });
      final dynamic app = await fixtures.fixture(tester);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => SettingsPage(app: app, section: 'Seguridad'),
      );
      await tester.pumpAndSettle();
      final beforePin = app.state['pinEnabled'];
      final beforeAmounts = app.hideAmounts;
      expect(app.screenPrivacyEnabled, false);
      await tester.tap(find.text('Privacidad en multitarea'));
      await tester.pumpAndSettle();
      await NativeStateStore.flush();
      expect(app.screenPrivacyEnabled, true);
      expect(saved?['screenPrivacyEnabled'], true);
      expect(app.state['pinEnabled'], beforePin);
      expect(app.hideAmounts, beforeAmounts);
      if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
        await expectLater(
          find.byType(RialApp),
          matchesGoldenFile('../build/balances-privacy-qa/security-option.png'),
        );
      }
      await tester.tap(find.text('Privacidad en multitarea'));
      await tester.pumpAndSettle();
      await NativeStateStore.flush();
      expect(saved?['screenPrivacyEnabled'], false);
      expect(tester.takeException(), isNull);
    },
  );
}
