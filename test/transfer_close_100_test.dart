import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
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
          (_) async => null,
        );
  });
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
    final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final family in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF Pro Display',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });

  test(
    'dollar difference keeps cents and rejects invalid received amounts',
    () {
      expect(receivedDollarFee(100, 97.5), 2.5);
      expect(receivedDollarFee(.29, .28), .01);
      expect(receivedDollarFee(100, 100), 0);
      for (final value in [0.0, -1.0, 100.01, double.nan, double.infinity]) {
        expect(() => receivedDollarFee(100, value), throwsFormatException);
      }
      expect(nextMaintenanceMonth(DateTime.utc(2026, 10, 30, 16)), '2026-11');
      expect(nextMaintenanceMonth(DateTime.utc(2026, 10, 31, 16)), '2026-12');
      expect(nextMaintenanceMonth(DateTime.utc(2026, 12, 31, 16)), '2027-02');
    },
  );

  testWidgets(
    'received difference edits, deletes and undoes both balances exactly',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() => app.accountById('b')['currency'] = 'USD');
      final movement = <String, dynamic>{
        'id': 'dollar-transfer',
        'type': 'transfer',
        'accountId': 'a',
        'targetAccountId': 'b',
        'currency': 'USD',
        'targetCurrency': 'USD',
        'amount': 100.0,
        'targetAmount': 97.5,
        'exchangeInput': 'received',
        'feeAmount': 90,
        'feeTreatment': 'added',
        'date': formatDateTime(DateTime.now()),
      };
      app.saveMovement(movement);
      expect(app.accountById('a')['balance'], 0);
      expect(app.accountById('b')['balance'], 197.5);
      expect(app.movementById('dollar-transfer')['feeAmount'], 2.5);
      expect(app.movementById('dollar-transfer')['feePercent'], 2.5);
      expect(app.movementById('dollar-transfer')['feeTreatment'], 'deducted');
      expect(HomeLedgerSnapshot(app, DateTime.now()).expenses, 2.5);
      expect(HomeLedgerSnapshot(app, DateTime.now()).income, 0);
      app.saveMovement({
        ...movement,
        'amount': 50.0,
        'targetAmount': 49.0,
      }, editingId: 'dollar-transfer');
      expect(app.accountById('a')['balance'], 50);
      expect(app.accountById('b')['balance'], 149);
      expect(HomeLedgerSnapshot(app, DateTime.now()).expenses, 1);
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById('a')['balance'], 0);
      expect(app.accountById('b')['balance'], 197.5);
      app.deleteMovement(app.movementById('dollar-transfer'));
      expect(app.accountById('a')['balance'], 100);
      expect(app.accountById('b')['balance'], 100);
      expect(HomeLedgerSnapshot(app, DateTime.now()).expenses, 0);
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById('b')['balance'], 197.5);
      expect(
        () => app.saveMovement({...movement, 'id': 'bad', 'targetAmount': 101}),
        throwsFormatException,
      );
      expect(app.accountById('a')['balance'], 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets('dollar composer shows automatic fee without scrolling $size', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      tester.view.physicalSize = size;
      app.mutate(() => app.accountById('b')['currency'] = 'USD');
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        defaultType: 'transfer',
        defaultAccountId: 'a',
      );
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(find.byType(MovementEditor));
      editor.amount.text = '100';
      editor.receivedAmount.text = '97.5';
      editor.changeMovementDate(DateTime.now());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transfer-auto-commission')),
        findsOneWidget,
      );
      expect(find.textContaining('2,50%'), findsOneWidget);
      expect(find.textContaining('Tasa:'), findsNothing);
      expect(find.text('Aplicar comisión'), findsNothing);
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('movement-editor-fields')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, lessThanOrEqualTo(1));
      if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
        await expectLater(
          find.byType(RialApp),
          matchesGoldenFile(
            '../build/release100-qa/transfer-${size.width}.png',
          ),
        );
      }
      await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
      await tester.pumpAndSettle();
      expect(app.maps('movements').single['feeAmount'], 2.5);
      expect(app.accountById('a')['balance'], 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editing a legacy added fee keeps the original total debit', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() {
      app.accountById('b')['currency'] = 'USD';
      app.accountById('a')['balance'] = 198.0;
      app.accountById('b')['balance'] = 100.0;
      app.state['movements'] = [
        <String, dynamic>{
          'id': 'legacy',
          'type': 'transfer',
          'accountId': 'a',
          'targetAccountId': 'b',
          'currency': 'USD',
          'targetCurrency': 'USD',
          'amount': 100.0,
          'targetAmount': 100.0,
          'feeAmount': 2.0,
          'feeTreatment': 'added',
          'date': formatDateTime(DateTime.now()),
        },
      ];
    });
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      movement: app.movementById('legacy'),
    );
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(MovementEditor));
    expect(parseAmount(editor.amount.text), 102);
    expect(parseAmount(editor.receivedAmount.text), 100);
    await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
    await tester.pumpAndSettle();
    expect(app.accountById('a')['balance'], 198);
    expect(app.accountById('b')['balance'], 100);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'tab transition skips intermediate pages and retains scroll reduced=$reduced',
      (tester) async {
        final index = ValueNotifier(0);
        final controllers = List.generate(3, (_) => ScrollController());
        final builds = [0, 0, 0];
        await tester.pumpWidget(
          CupertinoApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: ValueListenableBuilder<int>(
                valueListenable: index,
                builder: (_, value, _) => RetainedTabTransition(
                  index: value,
                  children: List.generate(
                    3,
                    (i) => Builder(
                      builder: (_) {
                        builds[i]++;
                        return ListView(
                          controller: controllers[i],
                          children: List.generate(
                            40,
                            (n) => SizedBox(
                              height: 50,
                              child: Text('Tab $i item $n'),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(builds[1], 0);
        index.value = 2;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(builds[1], 0);
        await tester.pumpAndSettle();
        controllers[2].jumpTo(200);
        index.value = 0;
        await tester.pump();
        index.value = 2;
        await tester.pumpAndSettle();
        expect(controllers[2].offset, 200);
        expect(find.text('Tab 0 item 0'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        index.dispose();
        for (final controller in controllers) {
          controller.dispose();
        }
      },
    );
  }
}
