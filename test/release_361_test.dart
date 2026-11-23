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
  final capture = Platform.environment['CAPTURE_CARDS'] == '1';
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

  test('BCV parsing selects current IDI, never USD or obsolete index', () {
    final quotes = parseCreditIndexTable('''
      <div class="view-id-nuevo_indicador"><table><tr>
      <td class="views-field-field-fecha-del-indicador">17-11-2026</td>
      <td class="views-field-field-tasa">915,74760000</td>
      <td class="views-field-nothing">4,47704199</td>
      <td class="views-field-nothing-1">4.477.041,99</td>
      </tr><tr><td class="views-field-field-fecha-del-indicador">31-02-2026</td>
      <td class="views-field-nothing">99,99</td></tr></table></div>''');
    expect(quotes, hasLength(1));
    expect(quotes.single['index'], '4.47704199');
    expect(creditIndexForDate(quotes, DateTime(2026, 11, 16)), isNull);
    expect(creditIndexForDate(quotes, DateTime(2026, 11, 18)), quotes.single);
    expect(
      () => parseCreditIndexTable('<html>Error</html>'),
      throwsFormatException,
    );
  });

  test('Official valuation preserves UVC units and uses no future quote', () {
    final card = credit.card(currency: 'VES')
      ..addAll({
        'creditBasis': 'uvc',
        'creditIndex': '2',
        'creditIndexDate': '2026-11-16',
      });
    setCreditUvcAmounts(card, '50', '450');
    expect(creditAvailable(card), 900);
    expect(
      applyOfficialCreditIndex(card, [
        {'date': '2026-11-17', 'index': '3'},
        {'date': '2026-11-18', 'index': '4'},
      ], DateTime(2026, 11, 17)),
      isTrue,
    );
    expect(card['balance'], -150);
    expect(card['creditLimit'], 1000);
    expect(creditAvailable(card), 850);
    expect(card['creditUnits'], '-50');
    expect(
      indexedCreditAvailableUnits(card).toDouble(),
      closeTo(850 / 3, 1e-10),
    );
    expect(card['creditIndex'], '3');
  });

  test('Payment category links only an explicit existing credit card', () {
    final movement = fixtures.movement('expense')..['category'] = 'Pago TDC';
    final accounts = <Map<String, dynamic>>[
      {'id': 'a', 'currency': 'USD', 'balance': 100},
      credit.card(),
    ];
    expect(
      () => linkCreditCardPayment({...movement}, accounts, ''),
      throwsFormatException,
    );
    final linked = {...movement};
    linkCreditCardPayment(linked, accounts, 'credit');
    expect(linked['type'], 'transfer');
    expect(linked['creditPayment'], true);
    expect(linked['targetAccountId'], 'credit');
    expect(linked['targetAmount'], 20);
    final legacy = {...movement};
    linkCreditCardPayment(legacy, accounts.take(1).toList(), '');
    expect(legacy['type'], 'expense');
  });

  testWidgets(
    'Home cards react to purchases/payments and open the selected card',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      expect(find.byKey(const ValueKey('home-credit-cards')), findsNothing);
      app.saveAccount(credit.card());
      app.saveAccount(
        credit.card()..addAll({
          'id': 'second',
          'label': 'Segunda',
          'cardNetwork': 'mastercard',
        }),
      );
      await tester.pumpAndSettle();
      final homeSection = find.byKey(const ValueKey('home-credit-cards'));
      await tester.scrollUntilVisible(
        homeSection,
        350,
        scrollable: find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('home-credit-available-credit'));
      expect(tester.widget<Text>(amount).data, contains('900'));
      app.saveMovement({
        ...fixtures.movement('expense'),
        'accountId': 'credit',
        'feeAmount': 0.0,
      });
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(amount).data, contains('880'));
      expect(app.accountById('a')['balance'], 100);
      final payment = fixtures.movement('expense', id: 'pay')
        ..['category'] = 'Pago TDC';
      linkCreditCardPayment(payment, app.maps('accounts'), 'credit');
      app.saveMovement(payment);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(amount).data, contains('900'));
      expect(app.accountById('a')['balance'], 80);
      final second = find.byKey(const ValueKey('home-credit-second'));
      await tester.ensureVisible(second);
      await tester.pumpAndSettle();
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CreditCardDetailPage>(find.byType(CreditCardDetailPage))
            .cardId,
        'second',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final currency in ['VES', 'USD']) {
    testWidgets('$currency overview excludes credit and opens bank account', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      final bankId = currency == 'USD' ? 'a' : 'b';
      app.saveAccount({
        ...Map<String, dynamic>.from(app.accountById(bankId)),
        'kind': 'national',
        'provider': '0102',
      }, editingId: bankId);
      app.saveAccount(credit.card(currency: currency));
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => AccountCurrencyOverview(app: app, currency: currency),
      );
      await tester.pumpAndSettle();
      final lines = tester.widgetList<AccountListLine>(
        find.byType(AccountListLine),
      );
      expect(lines, hasLength(1));
      expect(lines.single.account['id'], currency == 'USD' ? 'a' : 'b');
      expect(
        tester.widget<RingSummary>(find.byType(RingSummary)).total,
        contains('100'),
      );
      await tester.tap(find.byType(AccountListLine));
      await tester.pumpAndSettle();
      expect(find.byType(AccountDetailPage), findsOneWidget);
      expect(find.byType(CreditCardDetailPage), findsNothing);
      expect(
        tester
            .widget<AccountDetailPage>(find.byType(AccountDetailPage))
            .account['id'],
        bankId,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(320, 640),
    const Size(412, 915),
    const Size(768, 1024),
  ]) {
    for (final dark in [true, false]) {
      testWidgets('Compact credit cards fit $size dark=$dark with large text', (
        tester,
      ) async {
        final dynamic original = await fixtures.fixture(tester);
        final state = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(original.state)) as Map,
        );
        state['darkMode'] = dark;
        state['accounts'] = [
          credit.card()..addAll({
            'label': 'Compras personales y familiares',
            'creditLimit': 987654321.98,
          }),
          credit.card()..addAll({
            'id': 'partner',
            'provider': '0172',
            'cardDesign': 'bancamiga-rio',
            'cardNetwork': 'mastercard',
          }),
        ];
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(RialApp(initialState: state));
        await tester.pumpAndSettle();
        final dynamic app = tester.state(find.byType(RialApp));
        final boundary = GlobalKey();
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => CupertinoPageScaffold(
            backgroundColor: app.theme.bg,
            child: SafeArea(
              child: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: HomeCreditCardsSection(app: app),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
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
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('build/credit-qa').create(recursive: true);
            await File('build/credit-qa/home-${size.width.toInt()}-$dark.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        app.mutate(() => app.state['hideAmounts'] = true);
        await tester.pumpAndSettle();
        final amount = tester
            .widget<Text>(
              find.byKey(const ValueKey('home-credit-available-credit')),
            )
            .data!;
        expect(amount, isNot(contains('987')));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
