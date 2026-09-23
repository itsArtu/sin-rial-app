import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

const channel = MethodChannel('rial/native_state');
const lockKey = ValueKey('lock-pin');

Map<String, dynamic> protectedState({bool dark = true}) => defaultState()
  ..addAll({
    'onboardingComplete': true,
    'securitySetupComplete': true,
    'pinEnabled': true,
    'pinLength': 4,
    'pinSalt': 'test',
    'pinHash': 'test',
    'darkMode': dark,
    'userName': 'Private Name',
  });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    NativeStateStore.persistenceError.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test('An unavailable screen-off check requires locking again', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'CHANNEL_UNAVAILABLE');
        });
    expect(await NativeStateStore.consumeScreenOff(), true);
  });

  testWidgets(
    'Read failure is not replaced by onboarding or an empty account',
    (tester) async {
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'readState') {
              throw PlatformException(code: 'KEY_UNAVAILABLE');
            }
            if (call.method.startsWith('write')) writes++;
            return null;
          });
      await tester.pumpWidget(const RialBootstrap());
      await tester.pumpAndSettle();
      expect(find.byType(StorageFailurePage), findsOneWidget);
      expect(find.byType(RialApp), findsNothing);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(writes, 0);
    },
  );

  test('Save failure never falls back to an unprotected full write', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'writeSplitState') {
            throw PlatformException(code: 'KEY_UNAVAILABLE');
          }
          return null;
        });
    await NativeStateStore.save(defaultState()..['userName'] = 'Save failure');
    expect(NativeStateStore.persistenceError.value, isNotNull);
    expect(calls, ['writeSplitState']);
    await expectLater(NativeStateStore.flush(), throwsStateError);
    NativeStateStore.persistenceError.value = null;
  });

  testWidgets('PIN waits for native verification and cannot submit twice', (
    tester,
  ) async {
    final reply = Completer<Map<String, dynamic>>();
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'verifyPin') {
            attempts++;
            return reply.future;
          }
          return call.method == 'scheduleRateUpdate' ? true : null;
        });
    await tester.pumpWidget(RialApp(initialState: protectedState()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(lockKey), '1234');
    await tester.pump();
    expect(find.byType(LockScreen), findsOneWidget);
    await tester.tap(find.text('Verificando...'));
    await tester.pump();
    expect(attempts, 1);
    reply.complete({
      'accepted': true,
      'retryMillis': 0,
      'security': <String, dynamic>{},
    });
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('Native cooldown is shown and a rejected PIN keeps the lock', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'verifyPin') {
            return {'accepted': false, 'retryMillis': 30000};
          }
          return call.method == 'scheduleRateUpdate' ? true : null;
        });
    await tester.pumpWidget(RialApp(initialState: protectedState()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(lockKey), '0000');
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.textContaining('Espera 30 segundos'), findsOneWidget);
  });

  testWidgets(
    'Verification service failure and widget intent never bypass the lock',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'verifyPin') {
              throw PlatformException(code: 'KEY_UNAVAILABLE');
            }
            if (call.method == 'consumeLaunchAction') return 'income';
            return call.method == 'scheduleRateUpdate' ? true : null;
          });
      await tester.pumpWidget(RialApp(initialState: protectedState()));
      await tester.pumpAndSettle();
      final dynamic app = tester.state(find.byType(RialApp));
      expect(app.pendingLaunchAction, 'income');
      await tester.enterText(find.byKey(lockKey), '1234');
      await tester.pumpAndSettle();
      expect(app.locked, true);
      expect(app.pendingLaunchAction, 'income');
      expect(find.byType(MovementEditor), findsNothing);
      expect(find.textContaining('No se pudo verificar'), findsOneWidget);
    },
  );

  testWidgets('Resume conceals content until the security check finishes', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final privacy = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'verifyPin') return {'accepted': true};
          if (call.method == 'consumeScreenOff') return gate.future;
          if (call.method == 'setScreenPrivacy') {
            privacy.add((call.arguments as Map)['locked'] == true);
          }
          return call.method == 'scheduleRateUpdate' ? true : null;
        });
    await tester.pumpWidget(
      RialApp(initialState: protectedState()..['screenPrivacyEnabled'] = true),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(lockKey), '1234');
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const ValueKey('privacy-curtain')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    privacy.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const ValueKey('privacy-curtain')), findsOneWidget);
    expect(privacy.contains(false), false);
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
    expect(privacy.last, true);
  });

  test('Multitasking privacy defaults off and only accepts a boolean', () {
    expect(defaultState()['screenPrivacyEnabled'], false);
    expect(withDefaults({})['screenPrivacyEnabled'], false);
    expect(
      withDefaults({'screenPrivacyEnabled': 'true'})['screenPrivacyEnabled'],
      false,
    );
    expect(
      withDefaults({'screenPrivacyEnabled': true})['screenPrivacyEnabled'],
      true,
    );
  });

  for (final enabled in [false, true]) {
    testWidgets('Background visibility respects the opt-in: $enabled', (
      tester,
    ) async {
      final calls = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'verifyPin') return {'accepted': true};
            if (call.method == 'consumeScreenOff') return false;
            if (call.method == 'setScreenPrivacy')
              calls.add(call.arguments as Map);
            return call.method == 'scheduleRateUpdate' ? true : null;
          });
      await tester.pumpWidget(
        RialApp(
          initialState: protectedState()..['screenPrivacyEnabled'] = enabled,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(lockKey), '1234');
      await tester.pumpAndSettle();
      for (final lifecycle in [
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('privacy-curtain')),
          enabled ? findsOneWidget : findsNothing,
        );
        expect(calls.last['hideInBackground'], enabled);
        expect(calls.last['suspended'], true);
        expect(calls.last['locked'], false);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('privacy-curtain')), findsNothing);
      expect(find.byType(LockScreen), findsNothing);
      expect(calls.last['suspended'], false);
    });
  }

  testWidgets('Opting out does not bypass the PIN after the screen was off', (
    tester,
  ) async {
    final gate = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'verifyPin') return {'accepted': true};
          if (call.method == 'consumeScreenOff') return gate.future;
          return call.method == 'scheduleRateUpdate' ? true : null;
        });
    await tester.pumpWidget(RialApp(initialState: protectedState()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(lockKey), '1234');
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byKey(const ValueKey('privacy-curtain')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const ValueKey('privacy-curtain')), findsOneWidget);
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('A pending resume cannot undo a newer privacy curtain', (
    tester,
  ) async {
    final gate = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'verifyPin') return {'accepted': true};
          if (call.method == 'consumeScreenOff') return gate.future;
          return call.method == 'scheduleRateUpdate' ? true : null;
        });
    await tester.pumpWidget(
      RialApp(initialState: protectedState()..['screenPrivacyEnabled'] = true),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(lockKey), '1234');
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    gate.complete(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('privacy-curtain')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('privacy-curtain')), findsNothing);
  });

  for (final dark in [true, false])
    for (final width in [320.0, 390.0]) {
      testWidgets('Lock layout fits $width dark=$dark and keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          RialApp(initialState: protectedState(dark: dark)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(lockKey), findsOneWidget);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(LockScreen),
            matchesGoldenFile(
              'goldens/lock-${dark ? 'dark' : 'light'}-$width.png',
            ),
          );
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 290);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.text('Desbloquear');
        await tester.ensureVisible(button);
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(450));
      });
    }
}
