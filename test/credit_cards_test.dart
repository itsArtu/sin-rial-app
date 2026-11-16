import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

Map<String, dynamic> card({String currency = 'USD'}) => {
  'id': 'credit',
  'kind': 'credit',
  'provider': '0102',
  'currency': currency,
  'label': 'Mi tarjeta',
  'cardNetwork': 'visa',
  'cardTier': 'Gold',
  'creditLimit': 1000.0,
  'balance': -100.0,
  'creditMinimumDue': 30.0,
  'cutDay': 15,
  'dueDay': 30,
  'lastFour': '1234',
};

Map<String, dynamic> payment({double amount = 20}) => {
  ...fixtures.movement('transfer', amount: amount),
  'targetAccountId': 'credit',
  'targetCurrency': 'USD',
  'targetAmount': amount,
  'feeAmount': 0.0,
  'feeMode': 'none',
  'rate': 1.0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['CAPTURE_CARDS'] != '1') return;
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final item in manifest.cast<Map>()) {
      final loader = FontLoader(item['family'] as String);
      for (final font in (item['fonts'] as List).cast<Map>()) {
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

  test('Card dates handle leap years and short months', () {
    expect(nextCardDate(31, DateTime(2028, 2, 2)), DateTime(2028, 2, 29));
    expect(nextCardDate(31, DateTime(2027, 2, 2)), DateTime(2027, 2, 28));
    expect(nextCardDate(15, DateTime(2026, 11, 16)), DateTime(2026, 12, 15));
    final overLimit = card()..['creditLimit'] = 50;
    validateCreditAccount(overLimit);
    expect(creditAvailable(overLimit), 0);
    expect(
      () => validateCreditAccount(card()..['lastFour'] = '123'),
      throwsFormatException,
    );
    expect(
      () => validateCreditAccount(card()..['creditMinimumDue'] = 101),
      throwsFormatException,
    );
  });

  test('Each franchise supports four tiers without changing account terms', () {
    for (final network in ['visa', 'mastercard']) {
      for (final tier in creditCardTiersForNetwork(network)) {
        final account = card()
          ..addAll({
            'cardNetwork': network,
            'cardTier': tier,
            'cardDesign': 'generic',
          });
        validateCreditAccount(account);
        final restored = withDefaults(
          jsonDecode(jsonEncode(defaultState()..['accounts'] = [account]))
              as Map<String, dynamic>,
        );
        expect(restored['accounts'][0]['cardTier'], tier);
        expect(restored['accounts'][0]['cardDesign'], 'generic');
        expect(restored['accounts'][0]['balance'], -100);
        expect(restored['accounts'][0]['creditLimit'], 1000);
        expect(resolveCardDesign(account), isNull);
      }
    }
    expect(
      creditNetworkColors('visa', 'Gold'),
      isNot(creditNetworkColors('mastercard', 'Gold')),
    );
    expect(
      creditNetworkColors('visa', 'Standard'),
      isNot(creditNetworkColors('visa', 'Platinum')),
    );
    expect(creditNetworkLight('visa', 'Signature'), isFalse);
    expect(creditNetworkLight('mastercard', 'Standard'), isTrue);
  });

  test('Visa uses Signature and legacy Black cards retain their finances', () {
    expect(creditCardTiersForNetwork('visa'), [
      'Standard',
      'Gold',
      'Platinum',
      'Signature',
    ]);
    expect(creditCardTiersForNetwork('mastercard'), [
      'Standard',
      'Gold',
      'Platinum',
      'Black',
    ]);
    final legacy = card()..['cardTier'] = 'Black';
    final before = jsonEncode(legacy);
    expect(creditTier(legacy), 'Signature');
    validateCreditAccount(legacy);
    expect(jsonEncode(legacy), before);
    expect(creditTierForNetwork('mastercard', 'Signature'), 'Black');
    expect(creditTierForNetwork('visa', 'Black'), 'Signature');
  });

  testWidgets('Legacy Visa Black opens as Signature in the editor', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.saveAccount(card()..['cardTier'] = 'Black');
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => CreditCardEditor(app: app, cardId: 'credit'),
    );
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('credit-tier-picker'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('Signature'), findsWidgets);
    expect(find.text('Black'), findsNothing);
    expect(app.accountById('credit')['balance'], -100);
    expect(app.accountById('credit')['creditLimit'], 1000);
  });

  testWidgets('Standard can be selected and previews the franchise artwork', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => CreditCardEditor(app: app),
    );
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('credit-tier-picker'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standard').last);
    await tester.pumpAndSettle();
    final editorScroll = find.descendant(
      of: find.byType(CreditCardEditor),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(editorScroll.first).position.jumpTo(0);
    await tester.pumpAndSettle();
    final face = tester.widget<CreditCardFace>(find.byType(CreditCardFace));
    expect(face.card['cardTier'], 'Standard');
    expect(face.card['cardDesign'], 'generic');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test(
    'Reload preserves zero-balance accounts and cards from the same bank',
    () {
      final accounts = [
        {
          'id': 'checking',
          'kind': 'national',
          'provider': '0102',
          'currency': 'USD',
          'balance': 50.0,
        },
        {
          'id': 'savings',
          'kind': 'national',
          'provider': '0102',
          'currency': 'USD',
          'balance': 0.0,
        },
        card()..addAll({'balance': 0.0, 'creditMinimumDue': 0.0}),
        card()..addAll({
          'id': 'second-card',
          'balance': 0.0,
          'creditMinimumDue': 0.0,
          'cardNetwork': 'mastercard',
        }),
      ];
      final restored = withDefaults(
        jsonDecode(jsonEncode(defaultState()..['accounts'] = accounts))
            as Map<String, dynamic>,
      );
      expect((restored['accounts'] as List).map((a) => a['id']), [
        'checking',
        'savings',
        'credit',
        'second-card',
      ]);
      expect(restored['accounts'][2]['cardNetwork'], 'visa');
    },
  );

  testWidgets(
    'Credit consumption, payment, edit, delete and undo stay coherent',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveAccount(card());
      app.saveMovement({
        ...fixtures.movement('expense'),
        'accountId': 'credit',
        'feeAmount': 0.0,
      });
      expect(creditDebt(app.accountById('credit')), 120);
      expect(creditAvailable(app.accountById('credit')), 880);
      expect(app.accountById('a')['balance'], 100);
      app.saveMovement(payment()..['id'] = 'pay');
      expect(app.accountById('a')['balance'], 80);
      expect(creditDebt(app.accountById('credit')), 100);
      expect(app.accountById('credit')['creditMinimumDue'], 10);
      expect(
        app.maps('movements').where((m) => m['type'] == 'expense'),
        hasLength(1),
      );
      app.saveMovement(payment(amount: 10), editingId: 'pay');
      expect(app.accountById('a')['balance'], 90);
      expect(creditDebt(app.accountById('credit')), 110);
      expect(app.accountById('credit')['creditMinimumDue'], 20);
      app.undoLastOperation();
      expect(app.accountById('a')['balance'], 80);
      expect(app.accountById('credit')['creditMinimumDue'], 10);
      app.deleteMovement(
        app.maps('movements').firstWhere((m) => m['id'] == 'pay'),
      );
      expect(app.accountById('a')['balance'], 100);
      expect(creditDebt(app.accountById('credit')), 120);
      expect(app.accountById('credit')['creditMinimumDue'], 30);
      expect(
        () => app.saveMovement(payment(amount: 121)),
        throwsFormatException,
      );
      expect(
        () => app.saveMovement({
          ...fixtures.movement('expense', amount: 1000),
          'accountId': 'credit',
        }),
        throwsFormatException,
      );
      expect(
        () => app.saveMovement({
          ...fixtures.movement('income'),
          'accountId': 'credit',
        }),
        throwsFormatException,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Deleting a card restores its linked bank payments', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.saveAccount(card());
    app.saveMovement(payment());
    app.deleteAccount(app.accountById('credit'));
    expect(app.accountById('a')['balance'], 100);
    expect(app.maps('movements'), isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('Multiple payments preserve minimum after out-of-order edits', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.saveAccount(card());
    app.saveMovement(payment()..['id'] = 'first');
    app.saveMovement(payment()..['id'] = 'second');
    expect(app.accountById('credit')['creditMinimumDue'], 0);
    app.deleteMovement(app.movementById('first'));
    expect(app.accountById('credit')['creditMinimumDue'], 10);
    app.undoLastOperation();
    expect(app.accountById('credit')['creditMinimumDue'], 0);
    app.saveMovement(payment(amount: 5), editingId: 'first');
    expect(app.accountById('credit')['creditMinimumDue'], 5);
    final updated = Map<String, dynamic>.from(app.accountById('credit'));
    updated['creditMinimumDue'] = 25.0;
    app.saveAccount(updated, editingId: 'credit');
    app.saveMovement(payment(amount: 10), editingId: 'second');
    expect(app.accountById('credit')['creditMinimumDue'], 25);
    app.deleteMovement(app.movementById('second'));
    expect(app.accountById('credit')['creditMinimumDue'], 25);
    app.saveMovement(payment(amount: 5)..['id'] = 'current-statement');
    expect(app.accountById('credit')['creditMinimumDue'], 20);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Changing payment to consumption validates the reversed balance',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveAccount(card()..['balance'] = -990.0);
      app.saveMovement(payment(amount: 100));
      expect(creditAvailable(app.accountById('credit')), 110);
      expect(
        () => app.saveMovement({
          ...fixtures.movement('expense', amount: 110),
          'accountId': 'credit',
        }, editingId: 'm'),
        throwsFormatException,
      );
      expect(creditDebt(app.accountById('credit')), 890);
      app.undoLastOperation();
      app.saveAccount(card(), editingId: 'credit');
      app.saveMovement({
        ...fixtures.movement('expense'),
        'accountId': 'credit',
      });
      expect(
        () => app.saveMovement(payment(amount: 110), editingId: 'm'),
        throwsFormatException,
      );
      expect(creditDebt(app.accountById('credit')), 120);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Editing legacy cash transfers preserves the original debit', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    final previous = {
      ...fixtures.movement('transfer'),
      'currency': 'VES',
      'targetCurrency': 'VES',
      'amount': 20.0,
      'targetAmount': 20.0,
      'feeAmount': 2.0,
      'feeTreatment': 'added',
    };
    app.mutate(() {
      app.accountById('a').addAll({
        'kind': 'national',
        'provider': '0102',
        'currency': 'VES',
        'balance': 78.0,
      });
      app.accountById('b').addAll({'kind': 'cash', 'balance': 120.0});
      app.rawList('movements').add(previous);
    });
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      movement: previous,
    );
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(MovementEditor));
    expect(parseAmount(editor.amount.text), 22);
    await editor.save();
    await tester.pumpAndSettle();
    expect(app.accountById('a')['balance'], 78);
    expect(app.accountById('b')['balance'], 120);
    expect(app.maps('movements').single['feeAmount'], 2);
  });

  testWidgets('Card payment composer saves the same amount in both accounts', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.saveAccount(card());
    app.mutate(
      () =>
          app.accountById('a').addAll({'kind': 'national', 'provider': '0102'}),
    );
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultType: 'transfer',
      defaultAccountId: 'a',
      defaultTargetAccountId: 'credit',
      defaultAmount: 20.0,
    );
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(MovementEditor));
    expect(editor.usesReceivedAmount, isFalse);
    expect(find.text('Deuda de la tarjeta'), findsOneWidget);
    await editor.save();
    await tester.pumpAndSettle();
    expect(find.byType(MovementEditor), findsNothing);
    expect(app.accountById('a')['balance'], 80);
    expect(creditDebt(app.accountById('credit')), 80);
    expect(app.maps('movements').single['feeAmount'], 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(412, 915),
    const Size(768, 1024),
    const Size(915, 412),
  ]) {
    testWidgets('Card editor, detail and payment adapt to $size', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => CreditCardEditor(app: app),
      );
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(find.byType(CreditCardEditor));
      editor.currency = 'USD';
      editor.limit.text = '1000.00';
      editor.debt.text = '100.00';
      editor.minimum.text = '30.00';
      editor.save();
      await tester.pumpAndSettle();
      final saved = app.maps('accounts').firstWhere((a) => isCreditCard(a));
      expect(saved['creditLimit'], 1000);
      final capture = GlobalKey();
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => RepaintBoundary(
          key: capture,
          child: CreditCardDetailPage(app: app, cardId: saved['id']),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_CARDS'] == '1' && size.width == 412) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/credit-qa').create(recursive: true);
          await File('build/credit-qa/detail.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      app.openMovementEditor(
        tester.element(find.byType(CreditCardDetailPage)),
        defaultType: 'transfer',
        defaultAccountId: 'a',
        defaultTargetAccountId: saved['id'],
        defaultAmount: 20.0,
      );
      await tester.pumpAndSettle();
      expect(find.text('Pagar tarjeta'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Cash received field is editable, bank to bank is not', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() {
      app.accountById('a').addAll({
        'kind': 'national',
        'provider': '0102',
        'currency': 'VES',
      });
      app.accountById('b')['kind'] = 'cash';
    });
    app.openMovementEditor(
      tester.element(find.byType(HomePage)),
      defaultType: 'transfer',
      defaultAccountId: 'a',
    );
    await tester.pumpAndSettle();
    final dynamic editor = tester.state(find.byType(MovementEditor));
    expect(editor.usesReceivedAmount, isTrue);
    editor.amount.text = '20.00';
    editor.receivedAmount.text = '18.00';
    await editor.save();
    await tester.pumpAndSettle();
    expect(app.accountById('a')['balance'], 80);
    expect(app.accountById('b')['balance'], 118);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cards do not inflate liquid balances or fund savings', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    final initial = HomeLedgerSnapshot(app, DateTime.now()).total;
    app.saveAccount(card());
    expect(HomeLedgerSnapshot(app, DateTime.now()).total, initial);
    expect(app.usableAccounts().any((a) => isCreditCard(a)), isFalse);
    expect(
      app.usableAccounts(includeCredit: true).any((a) => isCreditCard(a)),
      isTrue,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('Bolivar cash transfer derives fee without a second debit', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() {
      app.accountById('a').addAll({
        'kind': 'national',
        'provider': '0102',
        'currency': 'VES',
      });
      app.accountById('b')['kind'] = 'cash';
    });
    app.saveMovement({
      ...fixtures.movement('transfer'),
      'currency': 'VES',
      'amount': 20.0,
      'targetAmount': 18.0,
      'exchangeInput': 'received',
    });
    expect(app.accountById('a')['balance'], 80);
    expect(app.accountById('b')['balance'], 118);
    final saved = app.maps('movements').first;
    expect(saved['feeAmount'], 2);
    expect(saved['feePercent'], 10);
    expect(saved['feeTreatment'], 'deducted');
    app.undoLastOperation();
    expect(app.accountById('a')['balance'], 100);
    expect(app.accountById('b')['balance'], 100);
    app.mutate(() => app.accountById('b')['kind'] = 'national');
    expect(
      isCashBolivarTransfer(app.accountById('a'), app.accountById('b')),
      isFalse,
    );
    expect(
      () => app.saveMovement({
        ...fixtures.movement('transfer'),
        'amount': 20.0,
        'targetAmount': 18.0,
        'exchangeInput': 'received',
      }),
      throwsFormatException,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('Sequential expenses update the same account immediately', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    for (var i = 0; i < 10; i++) {
      app.saveMovement(
        fixtures.movement('expense', id: 'expense$i', amount: 1.01),
      );
      expect(
        app.accountById('a')['balance'],
        moneySubtract(100, (i + 1) * 1.01),
      );
    }
    expect(app.accountById('a')['balance'], 89.9);
    await tester.pumpAndSettle();
  });

  testWidgets('A delayed resume read cannot replace a newly saved expense', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    await tester.runAsync(() => NativeStateStore.flush());
    final stale = jsonEncode(app.state);
    final reading = Completer<void>(), response = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          if (call.method == 'stateChanged') return true;
          if (call.method == 'readState') {
            reading.complete();
            return response.future;
          }
          return null;
        });
    app.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.runAsync(() => reading.future);
    app.saveMovement(fixtures.movement('expense'));
    response.complete(stale);
    await tester.pumpAndSettle();
    expect(app.accountById('a')['balance'], 80);
    expect(app.maps('movements'), hasLength(1));
  });

  testWidgets('Card details respond to payments without reopening', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.saveAccount(card());
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => CreditCardDetailPage(app: app, cardId: 'credit'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Deuda ${money(100, 'USD')}'), findsOneWidget);
    app.saveMovement(payment());
    await tester.pumpAndSettle();
    expect(find.text('Deuda ${money(80, 'USD')}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(412, 915),
    const Size(768, 1024),
  ]) {
    testWidgets('Card faces adapt to $size and large text', (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      tester.view.physicalSize = size;
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
      final key = GlobalKey();
      for (final network in ['visa', 'mastercard']) {
        for (final tier in creditCardTiersForNetwork(network)) {
          await tester.pumpWidget(
            CupertinoApp(
              theme: const CupertinoThemeData(
                textTheme: CupertinoTextThemeData(
                  textStyle: TextStyle(fontFamily: 'Manrope'),
                ),
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(1.3),
                ),
                child: CupertinoPageScaffold(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: RepaintBoundary(
                        key: key,
                        child: CreditCardFace(
                          app: app,
                          card: card()
                            ..addAll({
                              'cardTier': tier,
                              'cardDesign': 'generic',
                              'cardNetwork': network,
                              'cardholderName':
                                  'Alejandra Maria Fernandez Rodriguez',
                              'label': 'Compras y viajes familiares',
                            }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (Platform.environment['CAPTURE_CARDS'] == '1' &&
              size.width == 412) {
            await tester.runAsync(() async {
              for (final element in find.byType(Image).evaluate()) {
                await precacheImage((element.widget as Image).image, element);
              }
            });
            await tester.pumpAndSettle();
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('build/credit-qa').create(recursive: true);
              await File('build/credit-qa/$network-$tier.png')
                  .writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
    });
  }
}
