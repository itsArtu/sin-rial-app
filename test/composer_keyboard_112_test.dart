import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  setUpAll(() async {
    // The real line metrics matter: the old 60px footer hid part of the text.
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

  for (final dark in [false, true]) {
    for (final type in ['expense', 'income', 'transfer']) {
      testWidgets(
        'Save label stays complete with keyboard, text 130%, $type dark=$dark',
        (tester) async {
          final dynamic app = await fixtures.fixture(tester);
          tester.view.physicalSize = const Size(360, 780);
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          app.mutate(() => app.state['darkMode'] = dark);
          app.openMovementEditor(
            tester.element(find.byType(HomePage)),
            defaultType: type,
            defaultAccountId: 'a',
          );
          await tester.pumpAndSettle();
          final dynamic editor = tester.state(find.byType(MovementEditor));
          editor.descriptionFocus.requestFocus();
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();

          final save = find.byKey(const ValueKey('movement-editor-save'));
          final label = find.descendant(
            of: save,
            matching: find.text('Guardar movimiento'),
          );
          final saveRect = tester.getRect(save);
          final labelRect = tester.getRect(label);
          expect(save.hitTestable(), findsOneWidget);
          expect(saveRect.bottom, lessThanOrEqualTo(460));
          expect(saveRect.height, greaterThanOrEqualTo(56));
          expect(labelRect.top - saveRect.top, greaterThanOrEqualTo(10));
          expect(saveRect.bottom - labelRect.bottom, greaterThanOrEqualTo(18));
          final scrollable = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('movement-editor-fields')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(scrollable.position.viewportDimension, greaterThan(100));
          expect(tester.takeException(), isNull);
          if (Platform.environment['CAPTURE_DESIGN'] == '1') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first,
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1.5);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('build/design-qa').create(recursive: true);
              await File('build/design-qa/build112-keyboard-$type-$dark.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
