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
  final capture = Platform.environment['CAPTURE_DESIGN'] == '1';

  setUpAll(() async {
    if (!capture) return;
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in fonts.cast<Map>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in (family['fonts'] as List).cast<Map>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  for (final width in [320.0, 412.0]) {
    testWidgets('Account designs and single row selector at $width', (
      tester,
    ) async {
      final dynamic original = await fixtures.fixture(tester);
      final state = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(original.state)) as Map,
      );
      tester.view.physicalSize = Size(width, 915);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const SizedBox.shrink());
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: RialApp(initialState: state),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic app = tester.state(find.byType(RialApp));
      app.setTab(1);
      await tester.pumpAndSettle();

      Future<void> screenshot(String name) async {
        expect(tester.takeException(), isNull, reason: name);
        if (!capture) return;
        await tester.runAsync(() async {
          for (final element in find.byType(Image).evaluate()) {
            await precacheImage((element.widget as Image).image, element);
          }
        });
        await tester.pumpAndSettle();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/design-qa').create(recursive: true);
          await File('build/design-qa/$name-${width.toInt()}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final entry in {
        'bancamiga': '0172',
        'bancamiga-usd': '0172',
        'wally': 'WALLY',
        'okx': 'OKX',
      }.entries) {
        final account = <String, dynamic>{
          'id': 'design-account',
          'kind': entry.value == '0172' ? 'national' : 'wallet',
          'provider': entry.value,
          'cardDesign': entry.key,
          'currency': entry.key == 'bancamiga' ? 'VES' : 'USD',
          'balance': 12345.67,
        };
        app.saveAccount(account, editingId: 'design-account');
        app.pushPage(
          tester.element(find.byType(BudgetPage)),
          (_) => AccountDetailPage(app: app, account: account),
        );
        await tester.pumpAndSettle();
        await screenshot('build110-${entry.key}');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
      }

      app.pushPage(
        tester.element(find.byType(BudgetPage)),
        (_) => AccountEditor(app: app, onSave: (_) {}),
      );
      await tester.pumpAndSettle();
      final labels = ['Banco', 'Billetera', 'Efectivo', 'Beneficios'];
      await screenshot('build111-account-selector');
      final centers = labels
          .map((label) => tester.getCenter(find.text(label)))
          .toList();
      for (final center in centers) {
        expect(center.dy, closeTo(centers.first.dy, 1));
        expect(center.dx, inExclusiveRange(0, width));
      }
      await screenshot('build110-account-selector');
      await tester.tap(find.text('Billetera'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
