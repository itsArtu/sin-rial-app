import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'composer_test_helpers.dart' as composer;
import 'finance_workflow_test.dart' as fixtures;

Finder get hourInput => find.byType(material.TextField).first;
Finder get minuteInput => find.byType(material.TextField).last;
final _pickerCaptureKey = GlobalKey();

Future<void> capturePicker(WidgetTester tester, String name) async {
  if (Platform.environment['CAPTURE_DESIGN'] != '1') return;
  final boundary =
      _pickerCaptureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/design-qa').create(recursive: true);
    await File('build/design-qa/build112-time-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> openPicker(
  WidgetTester tester, {
  required ValueChanged<DateTime?> onSelected,
  DateTime? initial,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _pickerCaptureKey,
      child: material.MaterialApp(
        home: Builder(
          builder: (context) => material.Scaffold(
            body: Center(
              child: material.TextButton(
                onPressed: () async => onSelected(
                  await pickModernTime(
                    context: context,
                    theme: RTheme(true, 'emerald'),
                    initial: initial ?? DateTime(2026, 9, 22, 19, 30),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Future<void> enterInputMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(material.Icons.keyboard_outlined));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['CAPTURE_DESIGN'] != '1') return;
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
  testWidgets('Android clock opens on the dial without requesting a keyboard', (
    tester,
  ) async {
    await openPicker(tester, onSelected: (_) {});
    expect(find.byType(material.TimePickerDialog), findsOneWidget);
    expect(find.byType(material.TextField), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    await capturePicker(tester, 'dial');
    await enterInputMode(tester);
    await capturePicker(tester, 'input');
    for (final field in tester.widgetList<material.TextField>(
      find.byType(material.TextField),
    )) {
      expect(field.keyboardType, TextInputType.number);
    }
    await tester.tap(find.byIcon(material.Icons.access_time));
    await tester.pumpAndSettle();
    expect(find.byType(material.TextField), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final period in ['AM', 'PM']) {
    testWidgets('Native numeric time supports noon/midnight in $period', (
      tester,
    ) async {
      DateTime? selected;
      await openPicker(tester, onSelected: (value) => selected = value);
      await enterInputMode(tester);
      await tester.enterText(hourInput, '12');
      await tester.enterText(minuteInput, '05');
      await tester.tap(find.text(period));
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(selected?.hour, period == 'AM' ? 0 : 12);
      expect(selected?.minute, 5);
      expect([selected?.year, selected?.month, selected?.day], [2026, 9, 22]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Invalid numeric time stays in the dialog and cancel discards it',
    (tester) async {
      DateTime? selected = DateTime(2000);
      await openPicker(tester, onSelected: (value) => selected = value);
      await enterInputMode(tester);
      await tester.enterText(hourInput, '13');
      await tester.enterText(minuteInput, '60');
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(find.byType(material.TimePickerDialog), findsOneWidget);
      expect(selected, DateTime(2000));
      await capturePicker(tester, 'invalid');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets('Native time input fits above keyboard at $size', (
      tester,
    ) async {
      DateTime? selected;
      await openPicker(
        tester,
        size: size,
        onSelected: (value) => selected = value,
      );
      await enterInputMode(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(hourInput, '4');
      await tester.enterText(minuteInput, '45');
      await tester.ensureVisible(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('Aceptar')).dy,
        lessThan(size.height - 280),
      );
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect([selected?.hour, selected?.minute], [16, 45]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Movement saves selected time without changing its date', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
    final dynamic app = await fixtures.fixture(tester);
    app.saveMovement(fixtures.movement('income'));
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    final movement = app.movementById('m') as Map<String, dynamic>;
    final before = parseMovementDate(movement['date'] as String);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      movement: movement,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('composer-time')));
    await tester.tap(find.byKey(const ValueKey('composer-time')));
    await tester.pumpAndSettle();
    await enterInputMode(tester);
    await tester.enterText(hourInput, '8');
    await tester.enterText(minuteInput, '42');
    await tester.tap(find.text('PM'));
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    await tester.tap(composer.saveChanges());
    await tester.pumpAndSettle();
    final saved = parseMovementDate(app.movementById('m')['date'] as String);
    expect(
      [saved.year, saved.month, saved.day],
      [before.year, before.month, before.day],
    );
    expect([saved.hour, saved.minute], [20, 42]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
