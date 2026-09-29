import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

Map<String, dynamic> movementFixture(String type) => {
  'id': 'movement-test',
  'type': type,
  'description': 'Registro de prueba',
  'category': 'Otro',
  'amount': 50.0,
  'currency': 'USD',
  'feeAmount': 1.0,
  'feeCurrency': 'USD',
  'feeMode': 'manual',
  'accountId': 'source',
  'targetAccountId': type == 'transfer' ? 'target' : '',
  'targetAmount': 500.0,
  'targetCurrency': 'VES',
  'date': '16/09/2026 11:08 AM',
  'rate': 10.0,
  'debtId': type == 'transfer' ? '' : 'debt-test',
};

Future<dynamic> openFixture(WidgetTester tester, String type) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state = defaultState()
    ..addAll({
      'onboardingComplete': true,
      'securitySetupComplete': true,
      'userName': 'Prueba',
      'rate': 10.0,
      'rateEffectiveDate': expectedRateDateKey(DateTime.now()),
      'homeSections': ['recent'],
      'homeShortcutButtons': ['calculator'],
      'accounts': [
        {
          'id': 'source',
          'provider': 'cash',
          'label': 'Cuenta origen',
          'currency': 'USD',
          'balance': type == 'income' ? 249.0 : 149.0,
        },
        {
          'id': 'target',
          'provider': 'cash',
          'label': 'Cuenta destino',
          'currency': 'VES',
          'balance': type == 'transfer' ? 500.0 : 0.0,
        },
      ],
      'movements': [movementFixture(type)],
      'debts': [
        {
          'id': 'debt-test',
          'kind': type == 'income' ? 'receivable' : 'payable',
          'title': 'Cuotas de prueba',
          'amount': 100.0,
          'paidAmount': 50.0,
          'currency': 'USD',
          'status': 'pending',
        },
      ],
    });
  await tester.pumpWidget(RialApp(initialState: state));
  await tester.pumpAndSettle();
  final dynamic app = tester.state(find.byType(RialApp));
  await tester.ensureVisible(find.byType(MovementTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(MovementTile));
  await tester.pumpAndSettle();
  expect(find.byType(MovementDetailPage), findsOneWidget);
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List).cast<Map>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    for (final family in [
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Ahem',
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Manrope-Medium.ttf'))).load();
    }
  });
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

  for (final type in ['expense', 'income', 'transfer']) {
    testWidgets('Detail and confirmed deletion restore $type balances', (
      tester,
    ) async {
      final dynamic app = await openFixture(tester, type);
      expect(find.text('Registro de prueba'), findsOneWidget);
      expect(find.text('16/09/2026'), findsOneWidget);
      expect(find.text('11:08 AM'), findsOneWidget);
      expect(find.byKey(const ValueKey('movement-detail-bcv')), findsNothing);
      expect(
        find.text('Comisión'),
        type == 'income' ? findsNothing : findsOneWidget,
      );
      if (type == 'transfer') {
        final target = find.text('Cuenta destino');
        await tester.ensureVisible(target);
        expect(target, findsOneWidget);
        expect(find.text('Deuda vinculada'), findsNothing);
        expect(find.text('Cobro vinculado'), findsNothing);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('delete-movement')));
      await tester.tap(find.byKey(const ValueKey('delete-movement')));
      await tester.pumpAndSettle();
      expect(app.movementById('movement-test'), isNotNull);
      await tester.tap(
        find.descendant(
          of: find.byType(ModernConfirmDialog),
          matching: find.text('Cancelar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.movementById('movement-test'), isNotNull);
      await tester.tap(find.byKey(const ValueKey('delete-movement')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ModernConfirmDialog),
          matching: find.text('Eliminar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MovementDetailPage), findsNothing);
      expect(app.movementById('movement-test'), isNull);
      expect(app.accountById('source')['balance'], 200.0);
      expect(app.accountById('target')['balance'], 0.0);
      if (type != 'transfer') {
        expect(app.debtById('debt-test')['paidAmount'], 0.0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Editing from detail refreshes the record and linked debt', (
    tester,
  ) async {
    final dynamic app = await openFixture(tester, 'expense');
    await tester.tap(find.byKey(const ValueKey('edit-movement')));
    await tester.pumpAndSettle();
    expect(find.byType(MovementEditor), findsOneWidget);
    final amount = find.byWidgetPredicate(
      (widget) => widget is CupertinoTextField && widget.placeholder == 'Monto',
    );
    await tester.enterText(amount, '60');
    final save = find.text('Guardar cambios');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(MovementDetailPage), findsOneWidget);
    expect(app.movementById('movement-test')['amount'], 60.0);
    expect(app.debtById('debt-test')['paidAmount'], 60.0);
    expect(find.text('-\$60,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final width in [320.0, 390.0]) {
    for (final type in ['expense', 'income', 'transfer']) {
      testWidgets(
        'Detail $type shows recorded BCV and respects privacy at $width',
        (tester) async {
          final dynamic app = await openFixture(tester, type);
          tester.view.physicalSize = Size(width, 844);
          app.mutate(() {
            app.accountById('source')['currency'] = 'VES';
            app.movementById('movement-test').addAll({
              'currency': 'VES',
              'amount': 1000.0,
              'feeAmount': 3.0,
              'rate': 200.0,
              'bcvUsdRate': 100.0,
              'bcvEurRate': 120.0,
              'bcvEffectiveDate': '2026-09-16',
            });
            app.state['rate'] = 900.0;
          });
          await tester.pumpAndSettle();
          final equivalent = find.byKey(const ValueKey('movement-detail-bcv'));
          expect(tester.widget<DebtDetailRow>(equivalent).value, r'$10,00');
          expect(find.text('Equivalente BCV').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('FINANCE_GOLDENS') &&
              type == 'expense') {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile(
                '../build/detail-bcv-qa/detail-${width.toInt()}.png',
              ),
            );
          }
          app.mutate(() => app.state['rate'] = 1500.0);
          await tester.pumpAndSettle();
          expect(tester.widget<DebtDetailRow>(equivalent).value, r'$10,00');
          app.mutate(() => app.state['hideAmounts'] = true);
          await tester.pumpAndSettle();
          expect(
            tester.widget<DebtDetailRow>(equivalent).value,
            app.secureMoney(10.0, 'USD'),
          );
          expect(find.text(r'$10,00'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets('Legacy detail resolves dated BCV, not today or transfer rate', (
    tester,
  ) async {
    final dynamic app = await openFixture(tester, 'transfer');
    app.mutate(() {
      app.movementById('movement-test').addAll({
        'currency': 'VES',
        'amount': 1000.0,
        'rate': 200.0,
        'date': '25/09/2026 06:15 PM',
      });
      app.state['rate'] = 999.0;
      app.state['bcvRateHistory'] = normalizeBcvHistory([
        {'date': '2026-09-25', 'USD': 100.0, 'EUR': 120.0},
        {
          'date': '2026-09-28',
          'USD': 125.0,
          'EUR': 150.0,
          'updated_at': '2026-09-25T21:00:00Z',
        },
      ]);
    });
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('movement-detail-bcv'));
    expect(tester.widget<DebtDetailRow>(row).value, r'$8,00');
    app.mutate(
      () => app.movementById('movement-test')['date'] = '25/09/2026 05:59 PM',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<DebtDetailRow>(row).value, r'$10,00');
    app.mutate(
      () => app.movementById('movement-test')['date'] = '01/01/1980 12:00 PM',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<DebtDetailRow>(row).value,
      'No disponible para esta fecha',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
