import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

const channel = MethodChannel('rial/native_state');

Map<String, dynamic> quickState({bool locked = false, bool dark = true}) =>
    defaultState()..addAll({
      'onboardingComplete': true,
      'securitySetupComplete': true,
      'rateCheckedDate': isoDate(caracasTime(DateTime.now())),
      'rateLastFetchAttemptMillis': DateTime.now().millisecondsSinceEpoch,
      'darkMode': dark,
      'pinEnabled': locked,
      'pinLength': locked ? 4 : 0,
      'pinSalt': locked ? 'test' : '',
      'pinHash': locked ? 'test' : '',
      'accounts': [
        {
          'id': 'cash',
          'kind': 'cash',
          'provider': 'CASH',
          'currency': 'USD',
          'balance': 100.0,
          'label': 'Efectivo',
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> stored;
  late int closes;
  late int writes;
  Completer<void>? writeGate;
  String? writeError;
  bool pinAccepted = false;
  bool externalChange = false;
  bool loseAcknowledgement = false;

  setUpAll(() async {
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final item in fonts.cast<Map>()) {
      final loader = FontLoader(item['family'] as String);
      for (final font in (item['fonts'] as List).cast<Map>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final name in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF Pro Display',
      'Roboto',
    ]) {
      await (FontLoader(name)..addFont(Future.value(bytes))).load();
    }
  });

  setUp(() {
    stored = quickState();
    closes = 0;
    writes = 0;
    writeGate = null;
    writeError = null;
    pinAccepted = false;
    externalChange = false;
    loseAcknowledgement = false;
    NativeStateStore.persistenceError.value = null;
    NativeStateStore.persistenceConflict = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'readState':
              return jsonEncode(stored);
            case 'readRateState':
              return jsonEncode(stored);
            case 'stateChanged':
              return externalChange;
            case 'writeSplitState':
              writes++;
              if (writeGate != null) await writeGate!.future;
              if (writeError != null)
                throw PlatformException(code: writeError!);
              final args = Map<String, dynamic>.from(call.arguments as Map);
              final next =
                  jsonDecode(args['state'] as String) as Map<String, dynamic>;
              for (final entry in (args['parts'] as Map).entries) {
                next[entry.key as String] = jsonDecode(entry.value as String);
              }
              stored.addAll(next);
              if (loseAcknowledgement)
                throw PlatformException(code: 'CHANNEL_INTERRUPTED');
              return null;
            case 'closeQuickAccess':
              closes++;
              return null;
            case 'verifyPin':
              return {'accepted': pinAccepted};
            case 'consumeScreenOff':
              return false;
            case 'scheduleRateUpdate':
              return true;
            default:
              return null;
          }
        });
  });

  Future<void> launch(WidgetTester tester, String action) async {
    await tester.pumpWidget(RialBootstrap(quickAction: action));
    await tester.pumpAndSettle();
  }

  testWidgets('Income saves once and closes only after SQLite confirms', (
    tester,
  ) async {
    await launch(tester, 'income');
    expect(find.byType(HomePage), findsNothing);
    expect(find.byType(BottomChrome), findsNothing);
    expect(find.textContaining('Comisi\u00f3n:'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('quick-amount')), '25,50');
    writeGate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('quick-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-save')));
    await tester.pump();
    expect(writes, 1);
    expect(closes, 0);
    writeGate!.complete();
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect((stored['movements'] as List).single['amount'], 25.5);
    expect((stored['movements'] as List).single['feeAmount'], 0);
    expect((stored['accounts'] as List).single['balance'], 125.5);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'A committed movement is recovered after a lost acknowledgement',
    (tester) async {
      await launch(tester, 'income');
      loseAcknowledgement = true;
      await tester.enterText(find.byKey(const ValueKey('quick-amount')), '10');
      await tester.tap(find.byKey(const ValueKey('quick-save')));
      await tester.pumpAndSettle();
      expect((stored['movements'] as List).length, 1);
      expect(stored['accounts'][0]['balance'], 110);
      expect(writes, 1);
      expect(closes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Cancel never writes a movement', (tester) async {
    await launch(tester, 'expense');
    await tester.enterText(find.byKey(const ValueKey('quick-amount')), '25');
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Failed commit preserves draft and retry cannot duplicate it', (
    tester,
  ) async {
    await launch(tester, 'expense');
    await tester.enterText(find.byKey(const ValueKey('quick-amount')), '10');
    await tester.enterText(
      find.byKey(const ValueKey('quick-description')),
      'Pasaje',
    );
    writeError = 'DISK_FULL';
    await tester.tap(find.byKey(const ValueKey('quick-save')));
    await tester.pumpAndSettle();
    expect(closes, 0);
    expect(stored['movements'], isEmpty);
    expect(find.text('No se pudo guardar'), findsOneWidget);
    // Dismiss the existing notice through its close action.
    final dynamic app = tester.state(find.byType(RialApp));
    app.rootNavigatorKey.currentState.pop();
    await tester.pumpAndSettle();
    writeError = null;
    await tester.tap(find.byKey(const ValueKey('quick-save')));
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect((stored['movements'] as List).length, 1);
    expect((stored['accounts'] as List).single['balance'], 90);
    expect((stored['movements'] as List).single['category'], 'Transporte');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Conflicting quick save reloads latest balances before retry', (
    tester,
  ) async {
    await launch(tester, 'income');
    await tester.enterText(find.byKey(const ValueKey('quick-amount')), '10');
    (stored['accounts'] as List).single['balance'] = 250.0;
    writeError = 'STATE_CONFLICT';
    await tester.tap(find.byKey(const ValueKey('quick-save')));
    await tester.pumpAndSettle();
    expect(closes, 0);
    final dynamic app = tester.state(find.byType(RialApp));
    expect(app.state['accounts'][0]['balance'], 250);
    app.rootNavigatorKey.currentState.pop();
    await tester.pumpAndSettle();
    writeError = null;
    await tester.tap(find.byKey(const ValueKey('quick-save')));
    await tester.pumpAndSettle();
    expect(stored['accounts'][0]['balance'], 260);
    expect((stored['movements'] as List).length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Quick actions require the configured PIN', (tester) async {
    stored = quickState(locked: true);
    await launch(tester, 'income');
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-amount')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('lock-pin')), '1234');
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
    expect(writes, 0);
    pinAccepted = true;
    await tester.enterText(find.byKey(const ValueKey('lock-pin')), '5678');
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byKey(const ValueKey('quick-amount')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Calculator opens without home or menu and can close', (
    tester,
  ) async {
    await launch(tester, 'calculator');
    expect(find.byType(CalculatorPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(find.byType(BottomChrome), findsNothing);
    await tester.tap(find.byTooltip('Cerrar calculadora'));
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('An empty ledger offers setup without writing or exposing home', (
    tester,
  ) async {
    stored['accounts'] = [];
    await launch(tester, 'expense');
    expect(find.text('Abrir Sin Rial'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-save')), findsNothing);
    expect(find.byType(HomePage), findsNothing);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Bank expense uses existing automatic commission rules', (
    tester,
  ) async {
    stored['accounts'] = [
      {
        'id': 'bank',
        'kind': 'national',
        'provider': '0102',
        'currency': 'VES',
        'balance': 1000.0,
      },
    ];
    await launch(tester, 'expense');
    await tester.enterText(find.byKey(const ValueKey('quick-amount')), '100');
    await tester.tap(find.byKey(const ValueKey('quick-save')));
    await tester.pumpAndSettle();
    final movement = (stored['movements'] as List).single;
    final expectedFee = estimatedBankFee(
      method: 'payment_mobile_p2p',
      amount: 100,
      type: 'expense',
    );
    expect(movement['feeAmount'], expectedFee);
    expect(stored['accounts'][0]['balance'], moneySubtract(900, expectedFee));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Selectors fit the compact window with the keyboard visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await launch(tester, 'expense');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Otro'));
    await tester.tap(find.text('Otro'));
    await tester.pumpAndSettle();
    expect(find.byType(ModernSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is CupertinoTextField && w.placeholder == 'Buscar',
      ),
      'Transporte',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ModernSheetTile, 'Transporte'));
    await tester.pumpAndSettle();
    expect(find.byType(ModernSheet), findsNothing);
    expect(find.text('Transporte'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('App resumes with movement committed by the other window', (
    tester,
  ) async {
    await tester.pumpWidget(const RialBootstrap());
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    stored['accounts'][0]['balance'] = 777.0;
    externalChange = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final dynamic app = tester.state(find.byType(RialApp));
    expect(app.state['accounts'][0]['balance'], 777);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 390.0]) {
    for (final dark in [true, false]) {
      testWidgets('Quick form fits $width dark=$dark with keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        stored = quickState(dark: dark);
        await launch(tester, 'expense');
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byKey(const ValueKey('quick-access-window')),
            matchesGoldenFile(
              'goldens/quick-${dark ? 'dark' : 'light'}-$width.png',
            ),
          );
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byKey(const ValueKey('quick-save'))).bottom,
          lessThan(480),
        );
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byKey(const ValueKey('quick-access-window')),
            matchesGoldenFile(
              'goldens/quick-keyboard-${dark ? 'dark' : 'light'}-$width.png',
            ),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
