import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final update = UpdateInfo(
    version: '3.1.2',
    build: 76,
    apkUrl: 'https://github.com/itsArtu/sin-rial-app/releases/download/v3.1.2%2B76/sin-rial.apk',
    sha256: 'a' * 64,
    size: 1000,
  );
  final calls = <String>[];
  setUp(() => calls.clear());
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        ),
  );

  test('Downloads require digest, build and bounded size', () {
    expect(hasVerifiedUpdateMetadata(update), true);
    expect(
      hasVerifiedUpdateMetadata(
        const UpdateInfo(version: '9', build: 90, apkUrl: 'file.apk'),
      ),
      false,
    );
    expect(
      hasVerifiedUpdateMetadata(
        UpdateInfo(
          version: '9',
          build: 90,
          apkUrl: 'file.apk',
          sha256: 'b' * 64,
          size: 300 * 1024 * 1024,
        ),
      ),
      false,
    );
  });

  testWidgets('Download progress and cancel never launch browser', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          calls.add(call.method);
          return call.method == 'cancelApkUpdate'
              ? {'status': 'idle'}
              : {'status': 'downloading', 'received': 250, 'total': 1000};
        });
    await tester.pumpWidget(
      CupertinoApp(
        home: AppUpdatePage(update: update, theme: RTheme(true, 'emerald')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Descargando 25%'), findsOneWidget);
    await tester.tap(find.text('Cancelar descarga'));
    await tester.pumpAndSettle();
    expect(find.text('Descarga cancelada'), findsOneWidget);
    expect(calls, contains('cancelApkUpdate'));
    expect(calls, isNot(contains('openUrl')));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Permission required before installation and denied permission can retry',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            calls.add(call.method);
            if (call.method == 'installApkUpdate')
              return {'status': 'permission'};
            if (call.method == 'allowApkUpdates') return true;
            return {'status': 'ready'};
          });
      await tester.pumpWidget(
        CupertinoApp(
          home: AppUpdatePage(update: update, theme: RTheme(true, 'emerald')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar actualizacion'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir permiso de instalacion'), findsOneWidget);
      await tester.tap(find.text('Abrir permiso de instalacion'));
      await tester.pumpAndSettle();
      expect(calls, contains('allowApkUpdates'));
      expect(find.text('Instalar actualizacion'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Verification failure stays visible and permits retry', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => {
            'status': 'failed',
            'message': 'La firma no coincide',
          },
        );
    await tester.pumpWidget(
      CupertinoApp(
        home: AppUpdatePage(update: update, theme: RTheme(true, 'emerald')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('La firma no coincide'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Instalar actualizacion'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
