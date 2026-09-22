import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

final hourInput = find.byKey(const ValueKey('time-input-hour'));
final minuteInput = find.byKey(const ValueKey('time-input-minute'));

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
    CupertinoApp(
      home: Builder(
        builder: (context) => CupertinoPageScaffold(
          child: Center(
            child: CupertinoButton(
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
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Finder adjusterButton(String label, IconData icon) => find.descendant(
  of: find.byWidgetPredicate((w) => w is TimeAdjuster && w.label == label),
  matching: find.byIcon(icon),
);

void main() {
  for (final period in ['AM', 'PM']) {
    testWidgets(
      'Manual hour and minutes preserve $period and support noon/midnight',
      (tester) async {
        DateTime? selected;
        await openPicker(tester, onSelected: (value) => selected = value);
        await tester.enterText(hourInput, '1');
        await tester.pumpAndSettle();
        expect(
          tester.widget<CupertinoTextField>(hourInput).controller!.text,
          '1',
        );
        await tester.enterText(hourInput, '12');
        await tester.enterText(minuteInput, '05');
        await tester.tap(find.text(period));
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(selected?.hour, period == 'AM' ? 0 : 12);
        expect(selected?.minute, 5);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Invalid or blank manual times cannot be saved', (tester) async {
    await openPicker(tester, onSelected: (_) {});
    bool canSave() =>
        tester
            .widget<CupertinoButton>(
              find.widgetWithText(CupertinoButton, 'Guardar'),
            )
            .onPressed !=
        null;
    for (final invalid in ['', '0', '13', '99']) {
      await tester.enterText(hourInput, invalid);
      await tester.pumpAndSettle();
      expect(canSave(), false);
    }
    await tester.enterText(hourInput, '9');
    for (final invalid in ['', '60', '99']) {
      await tester.enterText(minuteInput, invalid);
      await tester.pumpAndSettle();
      expect(canSave(), false);
    }
    await tester.enterText(minuteInput, '59');
    await tester.pumpAndSettle();
    expect(canSave(), true);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Plus and minus stay in sync after manual entry and wrap correctly',
    (tester) async {
      DateTime? selected;
      await openPicker(tester, onSelected: (value) => selected = value);
      await tester.enterText(hourInput, '12');
      await tester.enterText(minuteInput, '59');
      await tester.tap(adjusterButton('Hora', CupertinoIcons.plus));
      await tester.tap(adjusterButton('Minutos', CupertinoIcons.plus));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(hourInput).controller!.text,
        '01',
      );
      expect(
        tester.widget<CupertinoTextField>(minuteInput).controller!.text,
        '00',
      );
      await tester.tap(adjusterButton('Hora', CupertinoIcons.minus));
      await tester.tap(adjusterButton('Minutos', CupertinoIcons.minus));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(hourInput).controller!.text,
        '12',
      );
      expect(
        tester.widget<CupertinoTextField>(minuteInput).controller!.text,
        '59',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(selected?.hour, 12);
      expect(selected?.minute, 59);
    },
  );

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets(
      'Time input fits with keyboard at $size and cancellation discards edits',
      (tester) async {
        DateTime? selected = DateTime(2000);
        await openPicker(
          tester,
          size: size,
          onSelected: (value) => selected = value,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.ensureVisible(hourInput);
        await tester.enterText(hourInput, '4');
        await tester.ensureVisible(minuteInput);
        await tester.enterText(minuteInput, '45');
        await tester.ensureVisible(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(
          tester.getBottomLeft(find.text('Guardar')).dy,
          lessThan(size.height - 280),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(selected, isNull);
      },
    );
  }

  testWidgets(
    'Movement saves the typed time without changing its selected date',
    (tester) async {
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
      await tester.ensureVisible(find.text('Fecha'));
      await tester.tap(find.text('Fecha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.enterText(hourInput, '8');
      await tester.enterText(minuteInput, '42');
      await tester.tap(find.text('PM'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      final saved = parseMovementDate(app.movementById('m')['date'] as String);
      expect(
        [saved.year, saved.month, saved.day],
        [before.year, before.month, before.day],
      );
      expect([saved.hour, saved.minute], [20, 42]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
