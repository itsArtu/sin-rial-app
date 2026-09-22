import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'calculator_usdt_test.dart' as calculator;
import 'finance_workflow_test.dart' as fixtures;

Map<String, dynamic> quote(String date, double rate) => {
  'effective_date': date,
  'USD': rate,
  'EUR': rate * 1.2,
  'updated_at': '${date}T20:00:00Z',
};
DateTime caracas(String date) => DateTime.parse('$date-04:00');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test('Ubii keeps its identity but shares 0104 for commissions', () {
    final ubii = {'provider': 'UBII', 'kind': 'national', 'currency': 'VES'};
    final vdc = {...ubii, 'provider': '0104'};
    final other = {...ubii, 'provider': '0102'};
    expect(bankCodeForProvider('ubii'), '0104');
    expect(bankTransferScopeForAccounts(ubii, vdc), 'same_bank');
    expect(bankTransferFee(ubii, vdc, 10000), 0);
    expect(bankTransferFee(vdc, ubii, 10000), 0);
    expect(bankTransferFee(ubii, other, 10000), 30);
    expect(logoAsset('UBII'), 'assets/logos/logo_ubii.png');
    expect(banks.where((b) => b.first == 'UBII').single.last, 'Ubii');
  });

  test('Rates switch at Caracas midnight, not publication time', () {
    final rates = [quote('2026-09-21', 840), quote('2026-09-22', 850)];
    expect(
      activeBcvSnapshot(rates, caracas('2026-09-21T23:59:59'))?['USD'],
      840,
    );
    expect(
      activeBcvSnapshot(rates, caracas('2026-09-22T00:00:00'))?['USD'],
      850,
    );
    expect(nextBcvSnapshot(rates, caracas('2026-09-21T18:00:00'))?['USD'], 850);
  });

  test('Friday advance survives weekends and Monday holiday without invented dates', () {
    final rates = [quote('2026-09-25', 840), quote('2026-09-29', 855)];
    expect(
      activeBcvSnapshot(rates, caracas('2026-09-25T17:59:59'))?['USD'],
      840,
    );
    for (final time in [
      '2026-09-25T18:00:00',
      '2026-09-26T00:00:00',
      '2026-09-28T00:00:00',
      '2026-09-29T00:00:00',
    ]) {
      expect(activeBcvSnapshot(rates, caracas(time))?['USD'], 855);
    }
    expect(
      activeBcvSnapshot([rates.first], caracas('2026-09-25T18:00:00'))?['USD'],
      840,
    );
    expect(
      nextBcvSnapshot([rates.first], caracas('2026-09-25T18:00:00')),
      isNull,
    );
    final state = {
      'rate': 840.0,
      'eurRate': 1008.0,
      'rateEffectiveDate': '2026-09-25',
      'bcvRateSnapshots': rates,
    };
    expect(applyBcvSnapshot(state, caracas('2026-09-25T18:00:00')), isTrue);
    expect(state['previousRate'], 840);
    expect(applyBcvSnapshot(state, caracas('2026-09-26T00:00:00')), isFalse);
    expect(state['previousRate'], 840);
  });

  test('Cache validates dates/rates and prefers latest published revision', () {
    expect(
      nextBcvBoundary(caracas('2026-09-21T23:59:59')),
      caracas('2026-09-22T00:00:00'),
    );
    expect(
      nextBcvBoundary(caracas('2026-09-25T17:59:59')),
      caracas('2026-09-25T18:00:00'),
    );
    expect(
      bcvSnapshots([quote('2026-02-31', 10), quote('2026-09-21', -1)]),
      isEmpty,
    );
    final newer = {
      ...quote('2026-09-21', 850),
      'updated_at': '2026-09-21T21:00:00Z',
    };
    expect(bcvSnapshots([newer, quote('2026-09-21', 840)]).single['USD'], 850);
    expect(
      bcvSnapshots(
        List.generate(60, (i) => quote(isoDate(DateTime(2026, 1, 1 + i)), 10)),
      ).length,
      40,
    );
  });

  testWidgets(
    'Monetary inputs group digits, preserve cents and programmatic values',
    (tester) async {
      final controller = MoneyEditingController(text: '2000');
      addTearDown(controller.dispose);
      expect(controller.text, '2.000,00');
      await tester.pumpWidget(
        CupertinoApp(
          home: RField(
            theme: RTheme(true, 'emerald'),
            controller: controller,
            placeholder: 'Monto',
          ),
        ),
      );
      for (final input in ['2000', '2.345,67', '0,25', '-1200,50', '1234.56']) {
        await tester.enterText(find.byType(CupertinoTextField), input);
        await tester.pump();
        expect(parseAmount(controller.text), parseAmount(input));
        expect(controller.text, contains(','));
      }
      controller.text = '1234.56';
      expect(controller.text, '1.234,56');
      controller.clear();
      expect(controller.text, '');
    },
  );

  testWidgets('Calculator copies only numeric amount', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await calculator.openCalculator(tester);
    await tester.enterText(calculator.input('Monto'), '2000');
    await tester.pumpAndSettle();
    final copy = find.byKey(const ValueKey('calculator-copy'));
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    expect(copied, '1.680.000,00');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('USDT debt selects international wallet when present', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() {
      app.state['usdtRate'] = 960.0;
      app.state['accounts'].add(<String, dynamic>{
        'id': 'wallet',
        'kind': 'wallet',
        'provider': 'BINANCE',
        'currency': 'USD',
        'balance': 100.0,
      });
      app.state['debts'] = <dynamic>[
        <String, dynamic>{
          'id': 'usdt',
          'currency': 'USDT',
          'kind': 'payable',
          'amount': 10.0,
          'paidAmount': 0.0,
        },
      ];
    });
    app.openDebtMovement(
      tester.element(find.byType(HomePage)),
      app.debtById('usdt'),
    );
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(MovementEditor));
    expect(editor.accountId, 'wallet');
    expect(editor.debtExchangeRate.text, '1.0');
    expect(editor.amount.text, '10,00');
    expect(calculator.input('Tasa USDT/USD'), findsNothing);
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();
    expect(app.accountById('wallet')['balance'], 90.0);
    expect(app.debtById('usdt')['status'], 'paid');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Calculator shows one update timestamp and rate modes are exclusive',
    (tester) async {
      await calculator.openCalculator(tester);
      final dynamic app = tester.state(find.byType(RialApp));
      app.mutate(() {
        app.state['lastRateMillis'] = DateTime.now().millisecondsSinceEpoch;
        app.state['bcvRateSnapshots'] = [
          quote(
            isoDate(caracasTime(DateTime.now()).add(const Duration(days: 1))),
            850,
          ),
        ];
      });
      await tester.pumpAndSettle();
      final copy = find.byKey(const ValueKey('calculator-copy'));
      await tester.ensureVisible(copy);
      final stamp = rateTimestampText(app.state, 'USD');
      expect(find.text(stamp), findsOneWidget);
      expect(find.text('Actualizado $stamp'), findsNothing);
      final toggle = find.byKey(const ValueKey('calculator-next-rate'));
      await tester.ensureVisible(toggle);
      await tester.tap(find.text('Usar tasa del día siguiente'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Usar tasa personalizada'));
      await tester.tap(find.text('Usar tasa personalizada'));
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsSwitchTile>(toggle).value, false);
      expect(calculator.input('Tasa USD/VES personalizada'), findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(find.text('Usar tasa del día siguiente'));
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsSwitchTile>(toggle).value, true);
      expect(calculator.input('Tasa USD/VES personalizada'), findsNothing);
      await calculator.selectCurrency(tester, 'Desde', 'USDT');
      expect(toggle, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final currency in ['USD', 'EUR']) {
    for (final kind in ['payable', 'receivable']) {
      testWidgets(
        '$currency $kind uses an automatic rate and preserves it on edit',
        (tester) async {
          final dynamic app = await fixtures.fixture(tester);
          app.mutate(() {
            app.state['rate'] = 840.1234;
            app.state['eurRate'] = 980.1234;
            app.state['debts'] = <dynamic>[
              {
                'id': 'automatic',
                'currency': currency,
                'kind': kind,
                'amount': 10.0,
                'paidAmount': 0.0,
              },
            ];
          });
          final context = tester.element(find.byType(HomePage));
          app.openDebtMovement(context, app.debtById('automatic'));
          await tester.pumpAndSettle();
          final dynamic editor = tester.state(find.byType(MovementEditor));
          final rate = currency == 'USD' ? 840.1234 : 980.1234;
          expect(editor.accountId, 'b');
          expect(parseAmount(editor.amount.text), moneyConvert(10, rate));
          expect(calculator.input('Tasa $currency/VES'), findsNothing);
          await tester.tap(find.text('Guardar movimiento'));
          await tester.pumpAndSettle();
          final movement = app.maps('movements').last as Map<String, dynamic>;
          expect(movement['debtExchangeRate'], rate);
          expect(movement['type'], kind == 'payable' ? 'expense' : 'income');
          expect(app.debtById('automatic')['status'], 'paid');
          app.mutate(() {
            app.state['rate'] = 1000.0;
            app.state['eurRate'] = 1500.0;
          });
          app.openMovementEditor(context, movement: movement);
          await tester.pumpAndSettle();
          expect(calculator.input('Tasa $currency/VES'), findsNothing);
          await tester.tap(find.text('Guardar cambios'));
          await tester.pumpAndSettle();
          expect(app.maps('movements').last['debtExchangeRate'], rate);
          expect(app.debtById('automatic')['paidAmount'], 10);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'Missing EUR rate fills automatically when an official quote arrives',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() {
        app.debtById('d')['currency'] = 'EUR';
      });
      app.openDebtMovement(
        tester.element(find.byType(HomePage)),
        app.debtById('d'),
      );
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(find.byType(MovementEditor));
      expect(editor.amount.text, '');
      expect(calculator.input('Tasa EUR/VES'), findsNothing);
      await tester.ensureVisible(find.text('Tasa EUR/VES no disponible'));
      expect(find.text('Tasa EUR/VES no disponible'), findsOneWidget);
      app.mutate(() {
        app.state['eurRate'] = 980.1234;
      });
      await tester.pumpAndSettle();
      expect(editor.amount.text, '9.801,23');
      expect(find.text('Tasa EUR/VES no disponible'), findsNothing);
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.debtById('d')['status'], 'paid');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Home personalization persists bolivar total visibility', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    Navigator.of(tester.element(find.byType(HomePage))).push(
      CupertinoPageRoute<void>(builder: (_) => HomeCustomizePage(app: app)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Widgets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Total de bolívares'));
    await tester.tap(find.text('Guardar personalización'));
    await tester.pumpAndSettle();
    expect(app.state['homeShowVesTotal'], false);
    expect(find.byKey(const ValueKey('home-ves-total')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Calculator next-rate toggle requires publication and sits above custom rate',
    (tester) async {
      await calculator.openCalculator(tester);
      final dynamic app = tester.state(find.byType(RialApp));
      final toggle = find.byKey(const ValueKey('calculator-next-rate'));
      await tester.ensureVisible(toggle);
      expect(tester.widget<SettingsSwitchTile>(toggle).onTap, isNull);
      expect(tester.widget<SettingsSwitchTile>(toggle).value, false);
      expect(find.text('Actual'), findsNothing);
      expect(find.text('Próxima'), findsNothing);
      expect(
        tester.getTopLeft(toggle).dy,
        lessThan(tester.getTopLeft(find.text('Usar tasa personalizada')).dy),
      );
      await tester.tap(find.text('Usar tasa del día siguiente'));
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsSwitchTile>(toggle).value, false);
      final now = caracasTime(DateTime.now());
      final nextDate = isoDate(now.add(const Duration(days: 1)));
      app.mutate(() {
        app.state['bcvRateSnapshots'] = [quote(nextDate, 850.1234)];
      });
      await tester.ensureVisible(calculator.input('Monto'));
      await tester.enterText(calculator.input('Monto'), '10');
      await tester.pumpAndSettle();
      await tester.ensureVisible(toggle);
      await tester.tap(find.text('Usar tasa del día siguiente'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('calculator-copy')));
      expect(find.text('Bs. 8.501,23'), findsOneWidget);
      await tester.ensureVisible(toggle);
      expect(find.text('Vigente desde $nextDate'), findsOneWidget);
      await tester.tap(find.text('Usar tasa del día siguiente'));
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsSwitchTile>(toggle).value, false);
      await tester.ensureVisible(find.byKey(const ValueKey('calculator-copy')));
      expect(find.text('Bs. 8.400,00'), findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(find.text('Usar tasa del día siguiente'));
      await tester.pumpAndSettle();
      app.mutate(() {
        app.state['bcvRateSnapshots'] = <dynamic>[];
      });
      await tester.pumpAndSettle();
      expect(find.text('Tasa no publicada'), findsOneWidget);
      expect(tester.widget<SettingsSwitchTile>(toggle).onTap, isNull);
      expect(tester.widget<SettingsSwitchTile>(toggle).value, false);
      await tester.ensureVisible(find.byKey(const ValueKey('calculator-copy')));
      expect(find.text('Bs. 8.400,00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Debt EUR defaults to VES and USDT falls back to available account with custom quote',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() {
        app.state['eurRate'] = 980.1234;
        app.state['usdtRate'] = 960.0;
        app.state['debts'] = <dynamic>[
          <String, dynamic>{
            'id': 'eur',
            'currency': 'EUR',
            'kind': 'receivable',
            'amount': 20.0,
            'paidAmount': 0.0,
          },
          <String, dynamic>{
            'id': 'usdt',
            'currency': 'USDT',
            'kind': 'payable',
            'amount': 10.0,
            'paidAmount': 0.0,
          },
        ];
      });
      final context = tester.element(find.byType(HomePage));
      app.openDebtMovement(context, app.debtById('eur'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoTextField>(calculator.input('Monto'))
            .controller!
            .text,
        '19.602,47',
      );
      expect(calculator.input('Tasa EUR/VES'), findsNothing);
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.debtById('eur')['status'], 'paid');
      expect(app.maps('movements').last['type'], 'income');
      expect(app.maps('movements').last['debtExchangeRate'], 980.1234);

      app.openDebtMovement(context, app.debtById('usdt'));
      await tester.pumpAndSettle();
      final rate = calculator.input('Tasa USDT/VES');
      await tester.ensureVisible(rate);
      await tester.enterText(rate, '1000.5678');
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(find.byType(MovementEditor));
      expect(editor.amount.text, '10.005,68');
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.debtById('usdt')['status'], 'paid');
      expect(app.maps('movements').last['debtExchangeRate'], 1000.5678);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test('Monetary formatter handles typing, replacement and decimal separator deletion', () {
    final formatter = MoneyInputFormatter();
    TextEditingValue edit(String text, int caret) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    var value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      edit('2', 1),
    );
    expect(value.text, '2,00');
    expect(value.selection.extentOffset, 1);
    for (var i = 0; i < 3; i++) {
      final caret = value.selection.extentOffset;
      value = formatter.formatEditUpdate(
        value,
        edit(value.text.replaceRange(caret, caret, '0'), caret + 1),
      );
    }
    expect(value.text, '2.000,00');
    value = formatter.formatEditUpdate(
      value.copyWith(
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: value.text.length,
        ),
      ),
      edit('60', 2),
    );
    expect(value.text, '60,00');
    value = formatter.formatEditUpdate(value, edit('6000', 2));
    expect(value.text, '60,00');
    expect(formatNumber(-123), '-123,00');
  });

  testWidgets(
    'Home shows total equivalent VES in bold, hides it privately and limits recent items',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester, count: 9);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-ves-total')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('home-ves-total'))).data,
        'Bs. 1.100,00',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-ves-total')))
            .style!
            .fontWeight,
        FontWeight.w600,
      );
      app.mutate(() {
        app.state['homeSections'] = ['recent'];
      });
      await tester.pumpAndSettle();
      final homeScroll = tester.widget<AppScroll>(
        find.descendant(
          of: find.byType(HomePage),
          matching: find.byType(AppScroll),
        ),
      );
      expect(
        homeScroll.children
            .map((child) => child is Padding ? child.child : child)
            .whereType<MovementTile>()
            .length,
        5,
      );
      expect(app.maps('movements').length, 9);
      app.mutate(() {
        app.state['homeBalanceMode'] = 'vesOnly';
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('home-ves-total'))).data,
        'Bs. 100,00',
      );
      app.mutate(() {
        app.state['homeBalanceMode'] = 'total';
      });
      app.mutate(() {
        app.state['hideAmounts'] = true;
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('home-ves-total'))).data,
        isNot('Bs. 1.100,00'),
      );
      app.mutate(() {
        app.state['homeShowVesTotal'] = false;
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-ves-total')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'EUR and USDT abonos preserve custom quote through edit/delete/undo',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      for (final currency in ['EUR', 'USDT']) {
        app.mutate(() {
          app.state['debts'] = <dynamic>[
            {
              'id': 'd',
              'kind': 'payable',
              'currency': currency,
              'amount': 100.0,
              'paidAmount': 0.0,
            },
          ];
        });
        final movement = <String, dynamic>{
          ...fixtures.movement('expense'),
          'accountId': 'b',
          'currency': 'VES',
          'amount': 200.0,
          'feeAmount': 0.0,
          'debtId': 'd',
          'debtExchangeRate': 20.0,
        };
        app.saveMovement(movement);
        expect(app.debtById('d')['paidAmount'], 10);
        app.mutate(() {
          app.state['rate'] = 99.0;
        });
        app.saveMovement({...movement, 'amount': 400.0}, editingId: 'm');
        expect(app.debtById('d')['paidAmount'], 20);
        app.deleteMovement(app.movementById('m'));
        expect(app.debtById('d')['paidAmount'], 0);
        app.undoLastOperation();
        expect(app.debtById('d')['paidAmount'], 20);
        app.deleteMovement(app.movementById('m'));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
