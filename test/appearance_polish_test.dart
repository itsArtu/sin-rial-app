import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'security_test.dart' as security;

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

  test('Legacy and malformed color preferences keep the default roles', () {
    for (final value in [null, '', 'invalid', 99, {}]) {
      final state = withDefaults({'incomeColor': value, 'expenseColor': value});
      expect(state['incomeColor'], 'default');
      expect(state['expenseColor'], 'default');
    }
    for (final dark in [true, false]) {
      final t = RTheme(dark, 'cyan');
      expect(t.income, t.green);
      expect(t.expense, t.red);
      final custom = RTheme(
        dark,
        'cyan',
        incomeColorKey: 'indigo',
        expenseColorKey: 'coral',
      );
      expect(custom.income, themeColorByKey('indigo').colorFor(dark));
      expect(custom.expense, themeColorByKey('coral').colorFor(dark));
      expect(custom.red, t.red);
      expect(custom.green, t.green);
      expect(custom.accent, t.accent);
    }
  });

  test(
    'All movement color choices survive normalization and native saves',
    () async {
      Map<String, dynamic>? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            if (call.method == 'writeSplitState') {
              saved = jsonDecode(
                (call.arguments as Map)['state'] as String,
              ) as Map<String, dynamic>;
            }
            return null;
          });
      for (final option in themeColorOptions) {
        final state = withDefaults({
          'incomeColor': option.key,
          'expenseColor': option.key,
        });
        await NativeStateStore.save(state);
        expect(saved?['incomeColor'], option.key);
        expect(saved?['expenseColor'], option.key);
      }
    },
  );

  testWidgets(
    'Appearance changes income and expense independently and can reset',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => SettingsPage(app: app, section: 'Apariencia'),
      );
      await tester.pumpAndSettle();
      for (final (key, label, value) in [
        ('income-color', 'Azul', 'indigo'),
        ('expense-color', 'Naranja', 'coral'),
      ]) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        final picker = find.byType(MovementColorPicker);
        await tester.ensureVisible(
          find.descendant(of: picker, matching: find.text(label)),
        );
        await tester.tap(
          find.descendant(of: picker, matching: find.text(label)),
        );
        await tester.pumpAndSettle();
        expect(
          app.state[key == 'income-color' ? 'incomeColor' : 'expenseColor'],
          value,
        );
      }
      expect(app.theme.income, themeColorByKey('indigo').colorFor(true));
      expect(app.theme.expense, themeColorByKey('coral').colorFor(true));
      app.resetAllData();
      await tester.pumpAndSettle();
      expect(app.state['incomeColor'], 'indigo');
      expect(app.state['expenseColor'], 'coral');
      await tester.ensureVisible(find.byKey(const ValueKey('income-color')));
      await tester.tap(find.byKey(const ValueKey('income-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('movement-color-default')));
      await tester.pumpAndSettle();
      expect(app.state['incomeColor'], 'default');
      expect(app.state['expenseColor'], 'coral');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Movement rows use their role while transfer retains the accent',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() {
        app.state['incomeColor'] = 'indigo';
        app.state['expenseColor'] = 'coral';
      });
      for (final type in ['income', 'expense', 'transfer']) {
        final data = fixtures.movement(type);
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => CupertinoPageScaffold(
            child: SafeArea(
              child: MovementTile(app: app, movement: data),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byType(MovementTile);
        final colors = tester
            .widgetList<Text>(
              find.descendant(of: row, matching: find.byType(Text)),
            )
            .map((text) => text.style?.color);
        expect(
          colors,
          contains(
            type == 'income'
                ? app.theme.income
                : type == 'expense'
                ? app.theme.expense
                : app.theme.accent,
          ),
        );
        Navigator.of(tester.element(row)).pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Lock logo does not resize or restart when entering the PIN', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(RialApp(initialState: security.protectedState()));
    await tester.pumpAndSettle();
    final logo = find.byKey(const ValueKey('lock-logo-size'));
    final before = tester.getRect(logo);
    expect(before.top, greaterThan(150));
    await capture(tester, find.byType(RialApp), 'lock-centered');
    for (final height in [280.0, 0.0, 310.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: height);
      await tester.pumpAndSettle();
      expect(tester.getRect(logo).size, before.size);
      final positioned = tester.getRect(logo);
      await tester.enterText(find.byKey(security.lockKey), '12');
      await tester.pumpAndSettle();
      expect(tester.getRect(logo), positioned);
      expect(tester.takeException(), isNull);
    }
    await capture(tester, find.byType(RialApp), 'lock-keyboard');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Tour icon animates on entry, settles, and stops with reduced motion',
    (tester) async {
      Widget art(bool reduced, IconData icon) => CupertinoApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: TourArtwork(theme: RTheme(true, 'cyan'), icon: icon),
          ),
        ),
      );
      await tester.pumpWidget(art(false, CupertinoIcons.tag));
      final icon = find.byType(TourFeatureIcon);
      final opacity = find.descendant(of: icon, matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      await tester.pump(const Duration(milliseconds: 350));
      final intermediate = tester.widget<Opacity>(opacity).opacity;
      expect(intermediate, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(art(false, CupertinoIcons.chart_pie));
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(art(true, CupertinoIcons.chart_pie));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dark in [true, false]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('Logos and picker fit $width dark=$dark with large text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final t = RTheme(dark, 'cyan');
        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              backgroundColor: t.bg,
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final code in [
                      '0102',
                      '0134',
                      '0172',
                      'BINANCE',
                      'OKX',
                      'ZINLI',
                      'WALLY',
                      'CASH',
                      'OTHER',
                      'CESTATICKET',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            LogoBadge(
                              provider: code,
                              theme: t,
                              benefitType: code == 'CESTATICKET'
                                  ? 'food'
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                shortProviderName(code),
                                style: TextStyle(color: t.ink),
                              ),
                            ),
                            if (code == 'CESTATICKET')
                              LogoBadge(
                                provider: code,
                                theme: t,
                                benefitType: 'integral',
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(material.Icons.payments_outlined), findsOneWidget);
        expect(find.byIcon(material.Icons.restaurant_outlined), findsOneWidget);
        expect(find.byIcon(material.Icons.swap_horiz), findsOneWidget);
        for (final badge in tester.widgetList<Image>(find.byType(Image))) {
          expect(badge.image, isA<ResizeImage>());
          expect((badge.image as ResizeImage).width, lessThanOrEqualTo(256));
        }
        await capture(tester, find.byType(CupertinoApp), 'logos-$width-$dark');
        await tester.pumpWidget(
          CupertinoApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(1.6),
              ),
              child: MovementColorPicker(theme: t, income: true, value: 'cyan'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          find.byType(CupertinoApp),
          'color-picker-$width-$dark',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

Future<void> capture(WidgetTester tester, Finder finder, String name) async {
  if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
  for (final element in find.byType(Image).evaluate().toList()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await expectLater(
    finder,
    matchesGoldenFile('../build/appearance-qa/$name.png'),
  );
}
