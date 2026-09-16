import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('Compact balance fits at $width with large amounts', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = RTheme(true, 'green');
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  BalanceHero(
                    theme: theme,
                    total: 987654321.23,
                    totalVes: 0,
                    usdBalance: 0,
                    vesBalance: 0,
                    currency: 'USDT',
                    rate: 846.51,
                    eurRate: 977.18,
                    usdtRate: 956.28,
                    hideAmounts: false,
                    changePercent: 2,
                    changePeriod: 'day',
                    loadingRate: false,
                    onRefreshRate: () {},
                    onCurrencyChanged: (_) {},
                    onCustomize: () {},
                    onTogglePrivacy: () {},
                  ),
                  CurrencyBadgeCircle(theme: theme, currency: 'VES'),
                  CurrencyBadgeCircle(theme: theme, currency: 'USD'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(BalanceHero)).height, lessThan(340));
      expect(find.text('\u20ae987.654.321,23'), findsOneWidget);
      expect(find.text('Bs'), findsOneWidget);
      expect(find.text(r'$'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Balance names include flags and badges keep currency symbols', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('rial/native_state'),
            null,
          ),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RialApp(
        initialState: defaultState()
          ..addAll({
            'onboardingComplete': true,
            'securitySetupComplete': true,
            'rate': 846.51,
            'rateEffectiveDate': expectedRateDateKey(DateTime.now()),
            'homeSections': ['accounts'],
            'accounts': [
              {
                'id': 'bs',
                'provider': 'cash',
                'kind': 'cash',
                'currency': 'VES',
                'balance': 100.0,
              },
              {
                'id': 'usd',
                'provider': 'cash',
                'kind': 'cash',
                'currency': 'USD',
                'balance': 100.0,
              },
            ],
          }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(BalanceGroupCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Bol\u00edvares \u{1F1FB}\u{1F1EA}'), findsOneWidget);
    expect(find.text('D\u00f3lares \u{1F1FA}\u{1F1F8}'), findsOneWidget);
    for (final symbol in ['Bs', r'$']) {
      expect(
        find.descendant(
          of: find.byType(CurrencyBadgeCircle),
          matching: find.text(symbol),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('Retired themes migrate without resetting the selected palette', () {
    for (final entry in {
      'navy': 'indigo',
      'sky': 'indigo',
      'magenta': 'violet',
      'orange': 'coral',
      'mint': 'emerald',
    }.entries) {
      final state = withDefaults(defaultState()..['themeColor'] = entry.key);
      expect(state['themeColor'], entry.value);
    }
    expect(
      themeColorOptions.where((color) => color.label == 'Naranja').length,
      1,
    );
    expect(themeColorByKey('coral').label, 'Naranja');
    expect(themeColorByKey('violet').label, 'Morado');
    expect(themeColorByKey('unknown').key, 'emerald');
    expect(themeColorByKey('').key, 'emerald');
  });

  test('Theme colors are alphabetical without retired labels', () {
    final labels = themeColorOptions.map((option) => option.label).toList();
    expect(labels, [...labels]..sort());
    expect(labels, isNot(contains('Menta')));
    expect(labels, isNot(contains('Violeta')));
    expect(labels, contains('Morado'));
  });
}
