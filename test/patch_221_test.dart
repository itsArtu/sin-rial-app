import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var exactAllowed = false;
  var notificationsAllowed = false;
  setUp(() {
    calls.clear();
    exactAllowed = false;
    notificationsAllowed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'dailyReminderStatus') {
            return {
              'exactAllowed': exactAllowed,
              'notificationsAllowed': notificationsAllowed,
            };
          }
          if (call.method == 'openReminderSettings' ||
              call.method == 'scheduleRateUpdate') {
            return true;
          }
          return null;
        });
  });

  test(
    'AMOLED background and bottom navigation are opaque black in every palette',
    () {
      for (final option in themeColorOptions) {
        final t = RTheme(true, option.key);
        expect(t.bg.toARGB32(), 0xFF000000);
        expect(t.nav.toARGB32(), 0xFF000000);
        expect(t.card, isNot(t.bg));
      }
    },
  );

  for (final dark in [false, true]) {
    testWidgets('Balance controls have readable contrast dark=$dark', (
      tester,
    ) async {
      for (final option in themeColorOptions) {
        final t = RTheme(dark, option.key);
        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              backgroundColor: t.bg,
              child: Column(
                children: [
                  HeroPrivacyButton(theme: t, hidden: false, onTap: () {}),
                  BalanceCurrencyChip(
                    theme: t,
                    label: 'EUR',
                    value: '',
                    onTap: () {},
                  ),
                  BalanceCurrencyChip(
                    theme: t,
                    label: 'USD',
                    value: '',
                    selected: true,
                    onTap: () {},
                  ),
                  BalanceChangeBadge(theme: t, percent: -5.4),
                  BalanceChangeBadge(theme: t, percent: 5.4),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heroBg = Color.alphaBlend(
          t.accent.withValues(alpha: dark ? .42 : .24),
          t.bg,
        );
        for (final label in ['EUR', 'USD']) {
          final finder = find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          );
          final decoration =
              tester.widget<AnimatedContainer>(finder).decoration!
                  as BoxDecoration;
          final text = tester.widget<Text>(find.text(label));
          final bg = Color.alphaBlend(decoration.color!, heroBg);
          expect(
            contrast(text.style!.color!, bg),
            greaterThanOrEqualTo(4.5),
            reason: '${option.key} $label dark=$dark',
          );
        }
        expect(
          tester.widget<Icon>(find.byIcon(CupertinoIcons.eye_fill)).color,
          t.ink,
        );
        expect(
          contrast(t.ink, Color.alphaBlend(t.heroControl, heroBg)),
          greaterThanOrEqualTo(4.5),
        );
        for (final badge in find.byType(BalanceChangeBadge).evaluate()) {
          final within = find.byWidget(badge.widget);
          final text = tester.widget<Text>(
            find.descendant(of: within, matching: find.byType(Text)),
          );
          final color = text.style!.color!;
          final box = tester.widget<Container>(
            find.descendant(of: within, matching: find.byType(Container)),
          );
          final bg = (box.decoration! as BoxDecoration).color!;
          expect(
            contrast(color, bg),
            greaterThanOrEqualTo(4.5),
            reason: '${option.key} ${text.data} dark=$dark',
          );
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('Shortcut order saves, hides and restores at 320 and 390', (
    tester,
  ) async {
    for (final width in [320.0, 390.0]) {
      calls.clear();
      final dynamic app = await fixtures.fixture(tester);
      tester.view.physicalSize = Size(width, 844);
      app.mutate(
        () => app.state['homeShortcutButtons'] = [
          'settings',
          'calculator',
          'debts',
        ],
      );
      await tester.pumpAndSettle();
      List<String> order() => tester
          .widgetList<HomeShortcutButton>(find.byType(HomeShortcutButton))
          .map((w) => (w.key! as ValueKey<String>).value)
          .toList();
      expect(order().first, 'home-shortcut-settings');
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => HomeCustomizePage(app: app),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('move-shortcut-settings--1')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('move-shortcut-calculator--1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hide-shortcut-debts')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar personalizaci\u00f3n'));
      await tester.pumpAndSettle();
      expect(app.state['homeShortcutButtons'], ['calculator', 'settings']);
      expect(order(), [
        'home-shortcut-calculator',
        'home-shortcut-settings',
        'home-customize',
      ]);
      final writes = calls.where((call) => call.method == 'writeSplitState');
      final saved = jsonDecode(writes.last.arguments['state'] as String) as Map;
      expect(saved['homeShortcutButtons'], ['calculator', 'settings']);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => HomeCustomizePage(app: app),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('customize-shortcut-debts')),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Por cobrar / pagar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Por cobrar / pagar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar personalizaci\u00f3n'));
      await tester.pumpAndSettle();
      expect(app.state['homeShortcutButtons'], [
        'calculator',
        'settings',
        'debts',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'Reminder permission status updates on return from Android settings',
    (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ReminderPermissions(theme: RTheme(false, 'indigo')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bloqueadas en Android'), findsOneWidget);
      expect(find.textContaining('Android puede retrasar'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder-exact')));
      await tester.pumpAndSettle();
      expect(
        calls.lastWhere((c) => c.method == 'openReminderSettings').arguments,
        {'exact': true},
      );
      await tester.tap(find.byKey(const ValueKey('reminder-notifications')));
      await tester.pumpAndSettle();
      expect(
        calls.lastWhere((c) => c.method == 'openReminderSettings').arguments,
        {'exact': false},
      );
      exactAllowed = true;
      notificationsAllowed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Permitidas'), findsOneWidget);
      expect(find.textContaining('recordatorios activo'), findsOneWidget);
      expect(find.textContaining('Android puede retrasar'), findsNothing);
    },
  );
}
