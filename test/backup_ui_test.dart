import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> disk = {};
  bool failWrite = false;
  Completer<void>? writeGate;
  setUp(() {
    failWrite = false;
    writeGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          if (call.method == 'writeSplitState') {
            await writeGate?.future;
            if (failWrite) throw PlatformException(code: 'DISK_FULL');
            final args = call.arguments as Map;
            disk.addAll(
              (jsonDecode(args['state'] as String) as Map)
                  .cast<String, dynamic>(),
            );
            for (final entry in (args['parts'] as Map).entries) {
              disk[entry.key as String] = jsonDecode(entry.value as String);
            }
            return true;
          }
          if (call.method == 'readState') return jsonEncode(disk);
          return null;
        });
  });
  final imported = defaultState()
    ..addAll({
      'userName': 'Restored',
      'pinHash': 'foreign-hash',
      'pinEnabled': false,
      'themeColor': 'rose',
      'accounts': [
        {
          'id': 'restored',
          'provider': 'cash',
          'currency': 'USD',
          'balance': 42.67,
        },
      ],
      'movements': [
        {
          'id': 'restored-m',
          'accountId': 'restored',
          'currency': 'USD',
          'type': 'income',
          'amount': 42.67,
          'date': '02/11/2026 10:00 AM',
        },
      ],
    });

  testWidgets(
    'restore commits before updating live state and keeps destination security',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() {
        app.state['pinHash'] = 'destination-hash';
        app.state['pinSalt'] = 'destination-salt';
        app.state['nativeSecurityV1'] = true;
      });
      await NativeStateStore.flush();
      writeGate = Completer<void>();
      final Future<void> restore = app.restoreBackup(imported);
      await tester.pump();
      expect(app.accountById('a'), isNotNull);
      app.mutate(() => app.state['userName'] = 'Must not overwrite backup');
      writeGate!.complete();
      await restore;
      await tester.pumpAndSettle();
      expect(app.accountById('a'), isNull);
      expect(app.accountById('restored')['balance'], 42.67);
      expect(app.state['userName'], 'Restored');
      expect(app.state['pinHash'], 'destination-hash');
      expect(disk['pinHash'], 'destination-hash');
      expect(disk['movements'], imported['movements']);
      expect(app.canUndo, false);
    },
  );
  testWidgets('failed restore leaves current financial state untouched', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    await NativeStateStore.flush();
    disk = jsonDecode(jsonEncode(app.state)) as Map<String, dynamic>;
    failWrite = true;
    await expectLater(
      app.restoreBackup(imported) as Future<void>,
      throwsStateError,
    );
    expect(app.accountById('a')['balance'], 100.0);
    expect(app.accountById('restored'), isNull);
    expect((disk['accounts'] as List).first['id'], 'a');
    failWrite = false;
    await app.restoreBackup(imported);
    expect(app.accountById('restored')['balance'], 42.67);
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
      'Roboto',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });
  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    for (final dark in [true, false]) {
      testWidgets('backup layout and import mode $size dark=$dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = size;
        app.mutate(() => app.state['darkMode'] = dark);
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => BackupPage(app: app),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Tu copia protegida'), findsOneWidget);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/release99-qa/backup-${size.width}-$dark.png',
            ),
          );
        }
        await tester.tap(find.text('Importar'));
        await tester.pumpAndSettle();
        expect(find.text('Recuperar tus datos'), findsOneWidget);
        expect(find.text('Repite la contraseña'), findsNothing);
        final dynamic page = tester.state(find.byType(BackupPage));
        page.preview = {'state': imported, 'createdAt': '2026-11-02T15:00:00Z'};
        page.setState(() {});
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Restaurar esta copia'),
          160,
          scrollable: find
              .descendant(
                of: find.byType(BackupPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Restaurar esta copia'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Restaurar esta copia'));
        await tester.pumpAndSettle();
        expect(find.text('Reemplazar los datos'), findsOneWidget);
        expect(app.accountById('a'), isNotNull);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(app.accountById('a'), isNotNull);
      });
    }
  }
  testWidgets(
    'movement filters have comfortable touch targets and integrated search',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester, count: 30);
      app.mutate(() => app.state['themeColor'] = 'sky');
      await tester.tap(find.text('Movimientos').first);
      await tester.pumpAndSettle();
      final search = find.byType(CupertinoSearchTextField);
      expect(tester.getSize(search).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSize(find.byType(MovementFilterButton).first).height,
        greaterThanOrEqualTo(48),
      );
      if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
        await expectLater(
          find.byType(RialApp),
          matchesGoldenFile('../build/release99-qa/movements.png'),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
