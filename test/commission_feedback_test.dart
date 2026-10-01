import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'patch_311_test.dart' as fixtures;
import 'payment_method_test.dart' as payment;

Map<String, dynamic> transfer({String? treatment = 'deducted'}) => {
  'id': 'transfer',
  'type': 'transfer',
  'accountId': 'usd',
  'targetAccountId': 'target',
  'currency': 'USD',
  'targetCurrency': 'USD',
  'amount': 382.0,
  'targetAmount': 382.0,
  'feeUnit': 'percent',
  'feeMode': 'manual',
  'feePercent': 5.6,
  'feeAmount': 21.39,
  'date': formatDateTime(DateTime.now()),
  if (treatment != null) 'feeTreatment': treatment,
};

Finder detail(String label) => find.byWidgetPredicate(
  (widget) => widget is DebtDetailRow && widget.label == label,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    final fallback = ByteData.sublistView(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
    );
    for (final family in [
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Ahem',
    ]) {
      await (FontLoader(family)..addFont(Future.value(fallback))).load();
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List).cast<Map>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        ),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        ),
  );

  test('Compact commission decimals retain precision without zero padding', () {
    expect(compactDecimal(5.60), '5.6');
    expect(compactDecimal(5), '5');
    expect(compactDecimal(0.125), '0.125');
  });

  test('Deduction happens in the source currency before conversion', () {
    expect(
      transferDestinationAmount(
        amount: 382,
        fee: 21.39,
        treatment: 'deducted',
        sourceCurrency: 'USD',
        targetCurrency: 'VES',
        rate: 100,
      ),
      36061,
    );
    expect(
      transferDestinationAmount(
        amount: 38200,
        fee: 2139,
        treatment: 'deducted',
        sourceCurrency: 'VES',
        targetCurrency: 'USD',
        rate: 100,
      ),
      360.61,
    );
    expect(
      transferDestinationAmount(
        amount: 382,
        fee: 21.39,
        treatment: 'added',
        sourceCurrency: 'USD',
        targetCurrency: 'USD',
        rate: 0,
      ),
      382,
    );
    for (final fee in [382.0, 400.0, -1.0]) {
      expect(
        () => transferDestinationAmount(
          amount: 382,
          fee: fee,
          treatment: 'deducted',
          sourceCurrency: 'USD',
          targetCurrency: 'USD',
          rate: 0,
        ),
        throwsFormatException,
      );
    }
  });

  testWidgets(
    'Deducted transfers preserve balances through edit delete and undo',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveMovement(transfer());
      expect(app.accountById('usd')['balance'], 618);
      expect(app.accountById('target')['balance'], 360.61);
      expect(app.movementById('transfer')['feeAmount'], 21.39);
      expect(app.homeLedgerCache.read(app).expenses, 21.39);
      final trend = buildBalanceTrend(
        accounts: List<Map<String, dynamic>>.from(app.maps('accounts')),
        movements: List<Map<String, dynamic>>.from(app.maps('movements')),
        convertValue: (value, currency) => value,
        period: 'day',
        now: DateTime.now(),
      );
      expect(trend.first.amount, 1000);
      expect(trend.last.amount, 978.61);
      app.saveMovement({...transfer(), 'amount': 200}, editingId: 'transfer');
      expect(app.accountById('usd')['balance'], 800);
      expect(app.accountById('target')['balance'], 188.8);
      expect(app.undoLastOperation(), true);
      expect(app.accountById('usd')['balance'], 618);
      expect(app.accountById('target')['balance'], 360.61);
      app.deleteMovement(app.movementById('transfer'));
      expect(app.accountById('usd')['balance'], 1000);
      expect(app.accountById('target')['balance'], 0);
      expect(app.undoLastOperation(), true);
      expect(app.accountById('usd')['balance'], 618);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (BuildContext context) =>
            MovementDetailPage(app: app, movementId: 'transfer'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DebtDetailRow>(detail('Total debitado')).value,
        r'$382,00',
      );
      expect(
        tester.widget<DebtDetailRow>(detail('Monto recibido en destino')).value,
        r'$360,61',
      );
      expect(
        tester
            .widget<DebtDetailRow>(detail('Porcentaje de comisi\u00f3n'))
            .value,
        '5.6%',
      );
      await fixtures.close(tester);
    },
  );

  testWidgets(
    'Old transfer semantics remain unchanged until explicitly edited',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.saveMovement(transfer(treatment: null));
      expect(app.accountById('usd')['balance'], 596.61);
      expect(app.accountById('target')['balance'], 382);
      app.saveMovement(transfer(), editingId: 'transfer');
      expect(app.accountById('usd')['balance'], 618);
      expect(app.accountById('target')['balance'], 360.61);
      expect(app.undoLastOperation(), true);
      expect(app.accountById('usd')['balance'], 596.61);
      expect(app.accountById('target')['balance'], 382);
      await fixtures.close(tester);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('Transfer preview and commission dialog fit $width', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      tester.view.physicalSize = Size(width, 844);
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        defaultType: 'transfer',
        defaultAccountId: 'usd',
        defaultAmount: 382.0,
      );
      await tester.pumpAndSettle();
      await payment.choose(tester, 'Comisi\u00f3n', 'Manual');
      await payment.editFee(tester, '5.60');
      expect(
        tester
            .widget<OptionField>(find.byKey(const ValueKey('commission-value')))
            .value,
        '5.6%',
      );
      expect(
        tester.widget<DebtDetailRow>(detail('Total a debitar')).value,
        r'$382,00',
      );
      expect(
        tester.widget<DebtDetailRow>(detail('Llega a destino')).value,
        r'$360,61',
      );
      final field = find.byKey(const ValueKey('commission-value'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('commission-input'));
      expect(tester.widget<CupertinoTextField>(input).controller!.text, '5.6');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(find.text('Aplicar').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
        await expectLater(
          find.byType(RialApp),
          matchesGoldenFile(
            '../build/finance-qa/commission-dialog-${width.toInt()}.png',
          ),
        );
      }
      await tester.enterText(input, '8');
      await tester.tap(find.text('Cancelar'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.widget<OptionField>(field).value, '5.6%');
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.accountById('usd')['balance'], 618);
      expect(app.accountById('target')['balance'], 360.61);
      await fixtures.close(tester);
    });
  }

  for (final mode in MovementHistoryMode.values) {
    testWidgets('History has spaced summary and signed totals for $mode', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      tester.view.physicalSize = const Size(320, 844);
      app.mutate(
        () => app.state['movements'] = [
          {
            ...transfer(),
            'id': 'income',
            'type': 'income',
            'amount': 100,
            'feeAmount': 0,
          },
          {
            ...transfer(),
            'id': 'expense',
            'type': 'expense',
            'amount': 20,
            'feeAmount': 1,
          },
          transfer(),
        ],
      );
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (BuildContext context) => MovementHistoryPage(app: app, mode: mode),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('movement-monthly-summary'));
      final totals = find.byKey(const ValueKey('movement-history-totals'));
      await tester.ensureVisible(totals);
      expect(
        tester.getTopLeft(totals).dy - tester.getBottomLeft(button).dy,
        greaterThanOrEqualTo(18),
      );
      if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
        await expectLater(
          find.byType(RialApp),
          matchesGoldenFile(
            '../build/finance-qa/movement-summary-${mode.name}.png',
          ),
        );
      }
      if (mode == MovementHistoryMode.all) {
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('filtered-income')))
              .data,
          r'Ingresos $100,00',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('filtered-expenses')))
              .data,
          r'Gastos $42,39',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('filtered-total')))
              .data,
          r'$57,61',
        );
        app.mutate(() => app.state['hideAmounts'] = true);
        await tester.pumpAndSettle();
        expect(find.text(r'Ingresos $100,00'), findsNothing);
        expect(find.text(r'Gastos $42,39'), findsNothing);
      }
      await fixtures.close(tester);
    });
  }
}
