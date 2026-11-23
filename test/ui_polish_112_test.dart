import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'credit_cards_test.dart' as credit;
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

  for (final dark in [false, true]) {
    testWidgets(
      'Home, menus and account controls stay coherent at 360 with large text dark=$dark',
      (tester) async {
        final dynamic original = await fixtures.fixture(tester);
        final state =
            Map<String, dynamic>.from(
                jsonDecode(jsonEncode(original.state)) as Map,
              )
              ..['darkMode'] = dark
              ..['userName'] = 'Arturo'
              ..['accounts'] = [
                {
                  'id': 'bank',
                  'kind': 'national',
                  'provider': '0172',
                  'currency': 'VES',
                  'balance': 255.37,
                  'accountType': 'current',
                },
                {
                  'id': 'wallet',
                  'kind': 'wallet',
                  'provider': 'BINANCE',
                  'currency': 'USD',
                  'balance': 96.09,
                },
                {...credit.card(currency: 'VES'), 'label': 'Crédito separado'},
              ];
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.physicalSize = const Size(360, 780);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: RialApp(initialState: state),
          ),
        );
        await tester.pumpAndSettle();
        final dynamic app = tester.state(find.byType(RialApp));

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
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('build/design-qa').create(recursive: true);
            await File(
              'build/design-qa/build112-$name-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await screenshot('home');
        app.setTab(2);
        await tester.pumpAndSettle();
        expect(find.byType(ModernMenu), findsOneWidget);
        await screenshot('menu');
        await tester.tap(find.text('Cuentas'));
        await tester.pumpAndSettle();
        final accountsPage = find.byType(AccountsPage);
        expect(accountsPage, findsOneWidget);
        final rows = tester.widgetList<AccountRow>(
          find.descendant(of: accountsPage, matching: find.byType(AccountRow)),
        );
        expect(rows.map((row) => row.account['id']), ['bank', 'wallet']);
        expect(
          find.descendant(
            of: accountsPage,
            matching: find.text('Tarjetas de crédito'),
          ),
          findsNothing,
        );
        expect(app.maps('accounts').where(isCreditCard), hasLength(1));
        await screenshot('accounts');

        app.pushPage(
          tester.element(accountsPage),
          (_) => AccountEditor(app: app, onSave: (_) {}),
        );
        await tester.pumpAndSettle();
        for (final label in [
          'Banco',
          'Billetera',
          'Efectivo',
          'Beneficios',
          'Banco',
        ]) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.byType(CardDesignPicker), findsNothing, reason: label);
          expect(tester.takeException(), isNull, reason: label);
          await screenshot('new-account-$label');
        }
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();

        app.openMovementEditor(
          tester.element(find.byType(AccountsPage)),
          defaultType: 'expense',
          defaultAccountId: 'bank',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ComposerModeButton));
        await tester.pumpAndSettle();
        final sheet = find.byType(ModernSheet);
        expect(sheet, findsOneWidget);
        expect(find.text('Tipo de movimiento'), findsOneWidget);
        expect(
          find.descendant(of: sheet, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        expect(
          find.descendant(of: sheet, matching: find.byType(ClipRRect)),
          findsWidgets,
        );
        final surfaces = tester.widgetList<Container>(
          find.descendant(of: sheet, matching: find.byType(Container)),
        );
        expect(
          surfaces.any(
            (surface) =>
                surface.decoration is BoxDecoration &&
                (surface.decoration as BoxDecoration).color == app.theme.card,
          ),
          isTrue,
        );
        await screenshot('movement-type-sheet');
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.byType(ModernSheet), findsNothing);
        expect(find.byType(MovementEditor), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
