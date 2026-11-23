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

  test(
    'Ordinary accounts keep their bank identity across legacy design values',
    () {
      for (final oldDesign in [
        'plain',
        'generic',
        'r4-orange',
        'bancamiga-usd',
      ]) {
        expect(
          resolveCardDesign({
            'kind': 'national',
            'provider': '0102',
            'currency': 'VES',
            'cardDesign': oldDesign,
          })?.id,
          'venezuela',
        );
        expect(
          resolveCardDesign({
            'kind': 'national',
            'provider': '0172',
            'currency': 'USD',
            'cardDesign': oldDesign,
          })?.id,
          'bancamiga-usd',
        );
      }
      expect(
        resolveCardDesign({
          'kind': 'wallet',
          'provider': 'WALLY',
          'currency': 'USD',
          'cardDesign': 'plain',
        })?.id,
        'wally',
      );
      expect(
        resolveCardDesign({
          'kind': 'credit',
          'provider': '0102',
          'cardDesign': 'generic',
        }),
        isNull,
      );
      expect(
        resolveCardDesign({
          'kind': 'credit',
          'provider': '0102',
          'cardDesign': 'venezuela',
        })?.id,
        'venezuela',
      );
    },
  );

  for (final width in [320.0, 390.0, 412.0]) {
    testWidgets(
      'Bank card identity has centered chip and readable currency at $width',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('rial/native_state'),
              (_) async => null,
            );
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 915);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final boundary = GlobalKey();
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => CupertinoPageScaffold(
            child: SafeArea(
              child: SingleChildScrollView(
                child: RepaintBoundary(
                  key: boundary,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        AccountIdentitySurface(
                          account: {
                            'kind': 'national',
                            'provider': '0102',
                            'currency': 'VES',
                            'balance': 255.37,
                          },
                          app: app,
                        ),
                        const SizedBox(height: 16),
                        AccountIdentitySurface(
                          account: {
                            'kind': 'wallet',
                            'provider': 'OKX',
                            'currency': 'USD',
                            'balance': 0.0,
                          },
                          app: app,
                        ),
                        const SizedBox(height: 16),
                        BankCardFace(
                          account: {
                            'kind': 'credit',
                            'provider': '0102',
                            'currency': 'VES',
                            'balance': -2500.0,
                            'creditLimit': 10000.0,
                            'cardDesign': 'venezuela',
                            'cardNetwork': 'mastercard',
                            'cardTier': 'Gold',
                          },
                          app: app,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = find.byType(AccountIdentitySurface).first;
        expect(
          find.descendant(of: surface, matching: find.byType(LogoBadge)),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('bdv-card-wordmark')), findsNothing);
        expect(find.byKey(const ValueKey('okx-card-wordmark')), findsOneWidget);
        expect(find.byKey(const ValueKey('okx-visa-platinum')), findsNothing);
        expect(find.byKey(const ValueKey('bdv-maestro-mark')), findsNothing);
        expect(
          find.descendant(
            of: find.byType(BankCardFace),
            matching: find.byType(CardNetworkMark),
          ),
          findsNothing,
        );
        final card = find.descendant(
          of: surface,
          matching: find.byType(AspectRatio),
        );
        final chip = find.descendant(
          of: surface,
          matching: find.byKey(const ValueKey('card-chip')),
        );
        final contactless = find.descendant(
          of: surface,
          matching: find.byKey(const ValueKey('card-contactless')),
        );
        final bounds = tester.getRect(card);
        expect(
          tester.getCenter(chip).dy,
          inInclusiveRange(
            bounds.top + bounds.height * .40,
            bounds.top + bounds.height * .65,
          ),
        );
        expect(
          (tester.getCenter(chip).dy - tester.getCenter(contactless).dy).abs(),
          lessThan(1),
        );
        expect(
          find.descendant(of: surface, matching: find.text('Bolívares')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: surface, matching: find.text('VES')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        final creditCard = find.byType(BankCardFace);
        final creditChip = find.descendant(
          of: creditCard,
          matching: find.byKey(const ValueKey('card-chip')),
        );
        final creditContactless = find.descendant(
          of: creditCard,
          matching: find.byKey(const ValueKey('card-contactless')),
        );
        expect(
          (tester.getCenter(creditChip).dy -
                  tester.getCenter(creditContactless).dy)
              .abs(),
          lessThan(1),
        );
        final creditBounds = tester.getRect(creditCard);
        final clearContent = tester.getRect(
          find.byKey(const ValueKey('venezuela-credit-clear-content')),
        );
        expect(
          clearContent.right,
          lessThanOrEqualTo(creditBounds.left + creditBounds.width * .69),
        );
        if (capture) {
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
            await File(
              'build/design-qa/bank-references-113-${width.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}
