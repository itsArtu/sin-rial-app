import 'composer_test_helpers.dart' as composer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'income_transfer_fee_test.dart' as bank;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        );
  });

  testWidgets('Bank to cash has no fee and receives the full amount', (
    tester,
  ) async {
    final dynamic app = await bank.fixture(tester);
    app.accountById('other')['kind'] = 'cash';
    app.accountById('other')['provider'] = 'CASH';
    app.saveMovement({
      ...bank.movement('transfer'),
      'feeTreatment': 'deducted',
    });
    expect(app.movementById('m')['feeAmount'], 0);
    expect(app.accountById('source')['balance'], 10000);
    expect(app.accountById('other')['balance'], 10100);
    await bank.closeFixture(tester);
  });

  testWidgets(
    'Editing an old deducted VES transfer corrects it without corrupting undo',
    (tester) async {
      final legacy = {
        ...bank.movement('transfer'),
        'feeAmount': 30.0,
        'targetAmount': 9970.0,
        'feeTreatment': 'deducted',
      };
      final dynamic app = await bank.fixture(tester, legacy: legacy);
      app.accountById('source')['balance'] = 10000.0;
      app.accountById('other')['balance'] = 10070.0;
      app.saveMovement(Map<String, dynamic>.from(legacy), editingId: 'm');
      expect(app.accountById('source')['balance'], 9970);
      expect(app.accountById('other')['balance'], 10100);
      expect(app.undoLastOperation(), true);
      expect(app.accountById('source')['balance'], 10000);
      expect(app.accountById('other')['balance'], 10070);
      expect(app.movementById('m')['feeTreatment'], 'deducted');
      app.deleteMovement(app.movementById('m'));
      expect(app.accountById('source')['balance'], 20000);
      expect(app.accountById('other')['balance'], 100);
      await bank.closeFixture(tester);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Movement type selector stays aligned and transfer uses an icon at $width',
      (tester) async {
        final dynamic app = await bank.fixture(tester, width: width);
        app.openMovementEditor(
          tester.element(find.byType(HomePage)),
          defaultAccountId: 'source',
        );
        await tester.pumpAndSettle();
        final selector = find.byKey(const ValueKey('movement-editor-type'));
        final initialRect = tester.getRect(selector);
        expect(initialRect.width, 64);
        expect(initialRect.height, 44);
        for (final label in ['Ingreso', 'Transferir', 'Gasto', 'Transferir']) {
          await composer.chooseType(tester, label);
          expect(tester.getRect(selector).top, initialRect.top);
          expect(tester.getRect(selector).right, initialRect.right);
          expect(tester.getRect(selector).width, 64);
          expect(
            find.descendant(of: selector, matching: find.text(label)),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
        expect(
          (tester.state(find.byType(MovementEditor)) as dynamic).type,
          'transfer',
        );
        await bank.closeFixture(tester);
      },
    );
  }
}
