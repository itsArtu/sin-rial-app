import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'credit_cards_test.dart' as cards;

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
  for (final size in [
    const Size(320, 640),
    const Size(412, 915),
    const Size(768, 1024),
  ]) {
    for (final dark in [true, false]) {
      testWidgets('Shared design and branded cards fit $size dark=$dark', (
        tester,
      ) async {
        final dynamic original = await fixtures.fixture(tester);
        final state = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(original.state)) as Map,
        );
        state['darkMode'] = dark;
        tester.view.physicalSize = size;
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
        await tester.runAsync(() async {
          for (final asset in [
            'assets/logos/card_visa.png',
            'assets/logos/card_mastercard_symbol.png',
          ]) {
            await precacheImage(
              ResizeImage(AssetImage(asset), width: 174),
              tester.element(find.byType(RialApp)),
            );
          }
        });
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
            await File('build/design-qa/$name-${size.width.toInt()}-$dark.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        await screenshot('home');
        app.setTab(2);
        await tester.pumpAndSettle();
        await screenshot('menu');
        app.setTab(1);
        await tester.pumpAndSettle();
        await screenshot('budget');
        app.pushPage(
          tester.element(find.byType(BudgetPage)),
          (_) => CalculatorPage(app: app),
        );
        await tester.pumpAndSettle();
        await screenshot('calculator');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        for (final design in bankCardDesigns) {
          if (design.partner.isEmpty) {
            final account = <String, dynamic>{
              'id': 'design-account',
              'kind': 'national',
              'provider': design.provider,
              'cardDesign': design.id,
              'currency': design.id.endsWith('-usd') ? 'USD' : 'VES',
              'balance': 12345.67,
            };
            app.saveAccount(account, editingId: 'design-account');
            app.pushPage(
              tester.element(find.byType(BudgetPage)),
              (_) => AccountDetailPage(app: app, account: account),
            );
            await tester.pumpAndSettle();
            await screenshot('account-${design.id}');
            app.rootNavigatorKey.currentState.pop();
            await tester.pumpAndSettle();
            continue;
          }
          app.saveAccount({
            ...cards.card(),
            'provider': design.provider,
            'cardDesign': design.id,
            'cardNetwork': design.network.isEmpty
                ? 'mastercard'
                : design.network,
          }, editingId: 'credit');
          app.pushPage(
            tester.element(find.byType(BudgetPage)),
            (_) => CreditCardDetailPage(app: app, cardId: 'credit'),
          );
          await tester.pumpAndSettle();
          await screenshot(design.id);
          app.rootNavigatorKey.currentState.pop();
          await tester.pumpAndSettle();
        }
        app.pushPage(
          tester.element(find.byType(BudgetPage)),
          (_) => AccountDetailPage(app: app, account: app.accountById('a')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cash-account-surface')),
          findsOneWidget,
        );
        expect(find.byType(CardNetworkMark), findsNothing);
        expect(find.textContaining('Abrir app de'), findsNothing);
        expect(find.textContaining('cash'), findsNothing);
        await screenshot('cash');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        app.pushPage(
          tester.element(find.byType(BudgetPage)),
          (_) => BackupPage(app: app),
        );
        await tester.pumpAndSettle();
        await screenshot('backups');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        app.openMovementEditor(
          tester.element(find.byType(BudgetPage)),
          defaultType: 'expense',
          defaultAccountId: 'a',
        );
        await tester.pumpAndSettle();
        await screenshot('expense');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
