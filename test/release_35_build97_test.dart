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
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
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
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final family in [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF Pro Display',
      'Roboto',
    ]) {
      await (FontLoader(family)..addFont(Future.value(font))).load();
    }
  });

  final fields = find.byKey(const ValueKey('movement-editor-fields'));
  final amount = find.byKey(const ValueKey('amount-input-Monto'));
  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: fields, matching: find.byType(Scrollable)).first,
      )
      .position;

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    for (final element in find.byType(Image).evaluate().toList()) {
      await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element),
      );
    }
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(RialApp),
      matchesGoldenFile('../build/release97-qa/$name.png'),
    );
  }

  for (final size in [
    const Size(320, 640),
    const Size(360, 780),
    const Size(390, 844),
    const Size(412, 915),
  ]) {
    for (final currency in ['USD', 'VES']) {
      testWidgets('Adaptive composer uses available height $size $currency', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = size;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPadding);
        app.mutate(() {
          app.state['darkMode'] = true;
          app.accountById('a')['provider'] = 'BINANCE';
          app.accountById('b')['provider'] = '0172';
          app.state['rate'] = 884.74;
        });
        for (final type in ['income', 'expense', 'transfer']) {
          app.openMovementEditor(
            tester.element(find.byType(HomePage)),
            defaultType: type,
            defaultAccountId: currency == 'USD' ? 'a' : 'b',
            defaultAmount: 20020.0,
          );
          await tester.pumpAndSettle();
          if (type == 'transfer') {
            await tester.enterText(
              find.byKey(const ValueKey('amount-input-Monto recibido')),
              '20,00',
            );
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          expect(
            position(tester).maxScrollExtent,
            0,
            reason: '$size $currency $type',
          );
          final keypad = tester.getRect(find.byType(ComposerKeypad));
          final form = tester.getRect(fields);
          expect(keypad.bottom, lessThanOrEqualTo(size.height - 24));
          expect(keypad.top, greaterThanOrEqualTo(form.bottom));
          expect(
            keypad.top - form.bottom,
            lessThan(90),
            reason: '$size $currency $type gap',
          );
          final key = tester.getRect(find.byKey(const ValueKey('keypad-1')));
          expect(key.height, inInclusiveRange(44, 72));
          if (size.height >= 780 && type == 'income') {
            expect(key.height, greaterThan(44));
            expect(tester.getSize(amount).height, greaterThanOrEqualTo(88));
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('composer-date')))
                  .height,
              greaterThanOrEqualTo(56),
            );
          }
          expect(
            find.byKey(const ValueKey('composer-account')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('movement-editor-save')).hitTestable(),
            findsOneWidget,
          );
          await capture(
            tester,
            'adaptive-${size.width.toInt()}-$currency-$type',
          );
          await tester.enterText(amount, '999999999999,99');
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(ComposerKeypad)), keypad);
          final input = tester.widget<CupertinoTextField>(amount);
          final painter = TextPainter(
            text: TextSpan(text: input.controller!.text, style: input.style),
            textDirection: TextDirection.ltr,
          )..layout();
          expect(
            painter.width,
            lessThanOrEqualTo(tester.getSize(amount).width + .01),
          );
          painter.dispose();
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
      });
    }
  }

  testWidgets('Larger accessibility text preserves fields and save access', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    tester.view.physicalSize = const Size(320, 640);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultAccountId: 'b',
      defaultAmount: 1200.0,
    );
    await tester.pumpAndSettle();
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('movement-editor-save')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('BCV de la fecha'), findsOneWidget);
    await tester.dragFrom(
      tester.getTopLeft(fields) + const Offset(2, 4),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(position(tester).pixels, position(tester).maxScrollExtent);
    expect(find.byType(ComposerKeypad), findsOneWidget);
    await capture(tester, 'adaptive-large-text-320');
  });

  testWidgets('Resize and native keyboard keep note and save accessible', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultType: 'income',
      defaultAccountId: 'a',
    );
    await tester.pumpAndSettle();
    await tester.enterText(amount, '120,50');
    final note = find.byWidgetPredicate(
      (w) => w is CupertinoTextField && w.placeholder == 'Descripción',
    );
    await tester.tap(note);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.byType(ComposerKeypad), findsNothing);
    await tester.enterText(note, 'Prueba adaptable');
    expect(
      find.byKey(const ValueKey('movement-editor-save')).hitTestable(),
      findsOneWidget,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(position(tester).maxScrollExtent, greaterThan(0));
    expect(
      find.byKey(const ValueKey('movement-editor-save')).hitTestable(),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(position(tester).maxScrollExtent, 0);
    expect(
      tester.widget<CupertinoTextField>(amount).controller!.text,
      '120,50',
    );
    expect(
      tester.widget<CupertinoTextField>(note).controller!.text,
      'Prueba adaptable',
    );
  });
}
