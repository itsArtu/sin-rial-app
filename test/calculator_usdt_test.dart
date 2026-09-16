import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

Finder currencySelector(String label) => find.byWidgetPredicate(
  (widget) => widget is CurrencySelectorPill && widget.label == label,
);

Future<void> selectCurrency(
  WidgetTester tester,
  String label,
  String value,
) async {
  await tester.ensureVisible(currencySelector(label));
  await tester.tap(currencySelector(label));
  await tester.pumpAndSettle();
  final choice = find.descendant(
    of: find.byType(ModernSheet),
    matching: find.text(value),
  );
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

Future<void> expectCurrencyOptions(
  WidgetTester tester,
  String label,
  List<String> allowed,
) async {
  await tester.ensureVisible(currencySelector(label));
  await tester.tap(currencySelector(label));
  await tester.pumpAndSettle();
  for (final currency in ['D\u00f3lares', 'Bol\u00edvares', 'Euros', 'USDT']) {
    expect(
      find.descendant(
        of: find.byType(ModernSheet),
        matching: find.text(currency),
      ),
      allowed.contains(currency) ? findsOneWidget : findsNothing,
    );
  }
  await tester.tap(find.text('Cancelar'));
  await tester.pumpAndSettle();
}

Finder input(String placeholder) => find.byWidgetPredicate(
  (widget) => widget is CupertinoTextField && widget.placeholder == placeholder,
);

Future<void> openCalculator(
  WidgetTester tester, {
  double usdtRate = 960,
  double previousUsdtRate = 0,
}) async {
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
          'rate': 840.0,
          'eurRate': 980.0,
          'usdtRate': usdtRate,
          'previousUsdtRate': previousUsdtRate,
          'rateEffectiveDate': expectedRateDateKey(DateTime.now()),
          'homeShortcutButtons': ['calculator'],
        }),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Calculadora'));
  await tester.tap(find.text('Calculadora'));
  await tester.pumpAndSettle();
  expect(find.byType(CalculatorPage), findsOneWidget);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        );
  });

  test('Only permitted currency pairs convert through their own VES rates', () {
    const rates = {'VES': 1.0, 'USD': 840.0, 'EUR': 980.0, 'USDT': 960.0};
    for (final from in rates.keys) {
      for (final to in rates.keys) {
        final result = convertCurrencyAmount(
          12.5,
          from,
          to,
          usdVes: rates['USD']!,
          eurVes: rates['EUR']!,
          usdtVes: rates['USDT']!,
        );
        final blocked =
            (from == 'USDT' && ['USD', 'EUR'].contains(to)) ||
            (to == 'USDT' && ['USD', 'EUR'].contains(from));
        expect(
          result,
          blocked
              ? isNull
              : closeTo(12.5 * rates[from]! / rates[to]!, 0.000001),
        );
      }
      expect(
        currencyPickerLabels(except: from),
        isNot(contains(displayCurrency(from))),
      );
    }
    expect(currencyPickerLabels(except: 'USD'), ['Bol\u00edvares', 'Euros']);
    expect(currencyPickerLabels(except: 'EUR'), [
      'D\u00f3lares',
      'Bol\u00edvares',
    ]);
    expect(currencyPickerLabels(except: 'VES'), [
      'D\u00f3lares',
      'Euros',
      'USDT',
    ]);
    expect(currencyPickerLabels(except: 'USDT'), ['Bol\u00edvares']);
    expect(firstDifferentCurrency('USDT'), 'VES');
  });

  test('Missing or invalid USDT rate does not use USD as a substitute', () {
    for (final rate in [0.0, -1.0, double.nan, double.infinity]) {
      for (final pair in [
        ['USDT', 'VES'],
        ['VES', 'USDT'],
      ]) {
        expect(
          convertCurrencyAmount(
            10,
            pair[0],
            pair[1],
            usdVes: 840,
            eurVes: 980,
            usdtVes: rate,
          ),
          isNull,
        );
      }
    }
    expect(
      convertCurrencyAmount(
        10,
        'USDT',
        'VES',
        usdVes: 0,
        eurVes: 0,
        usdtVes: 960,
      ),
      9600,
    );
  });

  testWidgets(
    'USDT only offers VES in both directions and supports a custom rate',
    (tester) async {
      await openCalculator(tester);
      await expectCurrencyOptions(tester, 'Hacia', ['Bol\u00edvares', 'Euros']);
      await selectCurrency(tester, 'Desde', 'USDT');
      await expectCurrencyOptions(tester, 'Hacia', ['Bol\u00edvares']);
      await tester.enterText(input('Monto'), '10');
      await tester.pumpAndSettle();
      expect(find.text('Bs. 9.600,00'), findsOneWidget);
      expect(find.text('1\u20ae = Bs. 960,00'), findsOneWidget);
      expect(find.text('\u20ae'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_arrow_down));
      await tester.pumpAndSettle();
      await expectCurrencyOptions(tester, 'Desde', ['Bol\u00edvares']);
      await tester.enterText(input('Monto'), '9600');
      await tester.pumpAndSettle();
      expect(find.text('\u20ae10,00'), findsOneWidget);

      final toggle = find.text('Usar tasa personalizada');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final customRate = input('Tasa USDT/VES personalizada');
      await tester.ensureVisible(customRate);
      await tester.enterText(customRate, '1000');
      await tester.pumpAndSettle();
      expect(find.text('\u20ae9,60'), findsOneWidget);

      await selectCurrency(tester, 'Hacia', 'D\u00f3lares');
      expect(customRate, findsNothing);
      await selectCurrency(tester, 'Desde', 'Euros');
      await expectCurrencyOptions(tester, 'Hacia', [
        'D\u00f3lares',
        'Bol\u00edvares',
      ]);
      await tester.enterText(input('Monto'), '48');
      await tester.pumpAndSettle();
      expect(find.text(r'$56,00'), findsOneWidget);
      await selectCurrency(tester, 'Desde', 'Bol\u00edvares');
      await selectCurrency(tester, 'Hacia', 'USDT');
      expect(find.text('\u20ae0,05'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Unavailable USDT can be entered manually', (tester) async {
    await openCalculator(tester, usdtRate: 0);
    await selectCurrency(tester, 'Desde', 'USDT');
    await tester.enterText(input('Monto'), '10');
    await tester.pumpAndSettle();
    expect(find.text('Falta una tasa v\u00e1lida'), findsOneWidget);
    expect(find.text('Tasa USDT no disponible'), findsOneWidget);
    final toggle = find.text('Usar tasa personalizada');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final customRate = input('Tasa USDT/VES personalizada');
    await tester.ensureVisible(customRate);
    await tester.enterText(customRate, '1000');
    await tester.pumpAndSettle();
    expect(find.text('Bs. 10.000,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('USDT uses its last known rate when the current rate is absent', (
    tester,
  ) async {
    await openCalculator(tester, usdtRate: 0, previousUsdtRate: 950);
    await selectCurrency(tester, 'Desde', 'USDT');
    await tester.enterText(input('Monto'), '10');
    await tester.pumpAndSettle();
    expect(find.text('Bs. 9.500,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
