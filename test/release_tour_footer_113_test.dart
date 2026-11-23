import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.cast<Map>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in (family['fonts'] as List).cast<Map>()) {
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

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Release next stays centered through all pages at $size dark=$dark text160%',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final state = defaultState()
            ..['onboardingComplete'] = true
            ..['securitySetupComplete'] = true
            ..['darkMode'] = dark
            ..['seenFeatureTour'] = '3.5.1+100';
          final captureKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: RialApp(initialState: state),
            ),
          );
          await tester.pumpAndSettle();
          final dynamic app = tester.state(find.byType(RialApp));
          final dynamic tour = tester.state(find.byType(ReleaseTour));
          final count = (tour.pages as List).length;
          final next = find.byKey(const ValueKey('release-tour-next'));
          final back = find.byKey(const ValueKey('release-tour-back'));

          void expectCentered(String label) {
            final buttonRect = tester.getRect(next);
            final labelRect = tester.getRect(
              find.descendant(of: next, matching: find.text(label)),
            );
            expect(next.hitTestable(), findsOneWidget);
            expect(buttonRect.center.dx, closeTo(size.width / 2, .5));
            expect(labelRect.center.dx, closeTo(size.width / 2, .5));
            expect(buttonRect.left, closeTo(24, .5));
            expect(buttonRect.right, closeTo(size.width - 24, .5));
            expect(buttonRect.height, greaterThanOrEqualTo(48));
            expect(buttonRect.bottom, lessThanOrEqualTo(size.height - 24));
            expect(labelRect.top, greaterThan(buttonRect.top));
            expect(labelRect.bottom, lessThan(buttonRect.bottom));
            expect(tester.takeException(), isNull);
          }

          Future<void> capture(String page) async {
            if (Platform.environment['CAPTURE_DESIGN'] != '1') return;
            await tester.runAsync(() async {
              final render =
                  captureKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage(pixelRatio: 1.5);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('build/design-qa').create(recursive: true);
              await File(
                'build/design-qa/build113-release-$page-${size.width.toInt()}-$dark.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          expectCentered('Siguiente');
          expect(back, findsNothing);
          await capture('first');
          await tester.tap(next);
          await tester.pumpAndSettle();
          expectCentered('Siguiente');
          expect(back.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(back).bottom,
            lessThan(tester.getRect(next).top),
          );
          expect(tour.step, 1);
          await capture('second');
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(tour.step, 0);
          expectCentered('Siguiente');
          for (var page = 1; page < count; page++) {
            await tester.tap(next);
            await tester.pumpAndSettle();
            expect(tour.step, page);
            expectCentered(page == count - 1 ? 'Empezar' : 'Siguiente');
          }
          await capture('last');
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(find.byType(ReleaseTour), findsNothing);
          expect(find.byType(HomePage), findsOneWidget);
          expect(app.state['seenFeatureTour'], currentFeatureTour);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
