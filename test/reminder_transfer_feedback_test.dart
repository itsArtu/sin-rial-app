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
      'Movement tabs keep spacing and dimensions during rapid switching at $width',
      (tester) async {
        final dynamic app = await bank.fixture(tester, width: width);
        app.openMovementEditor(
          tester.element(find.byType(HomePage)),
          defaultAccountId: 'source',
        );
        await tester.pumpAndSettle();
        final selector = find.byKey(const ValueKey('movement-editor-type'));
        final initial = tester.getRect(selector);
        final buttons = find.descendant(
          of: selector,
          matching: find.byType(CupertinoButton),
        );
        expect(buttons, findsNWidgets(3));
        for (var i = 1; i < 3; i++) {
          expect(
            tester.getRect(buttons.at(i)).left -
                tester.getRect(buttons.at(i - 1)).right,
            closeTo(8, .01),
          );
        }
        for (final label in ['Ingreso', 'Transferir', 'Gasto', 'Transferir']) {
          await tester.tap(
            find.descendant(of: selector, matching: find.text(label)),
          );
          await tester.pump(const Duration(milliseconds: 60));
          expect(tester.getRect(selector), initial);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        expect(tester.widget<KindSelector>(selector).value, 'transfer');
        await bank.closeFixture(tester);
      },
    );
  }
}
