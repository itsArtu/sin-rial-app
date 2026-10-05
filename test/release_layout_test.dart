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
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          if (call.method == 'installApkUpdate')
            return {'status': 'permission'};
          if (call.method == 'startApkUpdate') return {'status': 'ready'};
          if (call.method == 'scheduleRateUpdate') return true;
          return null;
        });
  });

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('Version and installer copy are centered at $width / $dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() => app.state['darkMode'] = dark);
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => SettingsPage(app: app),
        );
        await tester.pumpAndSettle();
        final title = find.text('Sin Rial');
        final version = find.byKey(const ValueKey('app-version'));
        for (final text in [title, version]) {
          expect(tester.widget<Text>(text).textAlign, TextAlign.center);
          expect(tester.getCenter(text).dx, closeTo(width / 2, .5));
        }
        expect(tester.widget<Text>(version).data, 'Versi\u00f3n 3.1.3');
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/release78-qa/settings-$width-$dark.png',
            ),
          );
        }
        await tester.tap(version);
        await tester.pumpAndSettle();
        expect(find.textContaining('Gracias a los testers'), findsOneWidget);
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        app.pushPage(
          tester.element(find.byType(SettingsPage)),
          (_) => AppUpdatePage(
            update: UpdateInfo(
              version: '3.1.3',
              build: 79,
              apkUrl: 'app.apk',
              sha256: 'a' * 64,
              size: 1000,
            ),
            theme: app.theme,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Instalar actualizacion'));
        await tester.pumpAndSettle();
        final message = find.text(
          'Android necesita que permitas instalar actualizaciones desde Sin Rial.',
        );
        expect(tester.widget<Text>(message).textAlign, TextAlign.center);
        expect(tester.getCenter(message).dx, closeTo(width / 2, .5));
        expect(
          tester
              .widget<Text>(find.text('Abrir permiso de instalacion'))
              .textAlign,
          TextAlign.center,
        );
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/release78-qa/permission-$width-$dark.png',
            ),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
