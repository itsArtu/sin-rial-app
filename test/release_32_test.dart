import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'payment_method_test.dart' as payments;
import 'finance_workflow_test.dart' as fixtures;

Finder field(String placeholder) => find.byWidgetPredicate(
  (w) => w is CupertinoTextField && w.placeholder == placeholder,
);

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
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          if (call.method == 'configureSecurity')
            return {
              'securitySetupComplete': true,
              'pinEnabled': true,
              'pinHash': 'test',
              'pinSalt': 'test',
              'pinLength': 6,
            };
          if (call.method == 'scheduleRateUpdate') return true;
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        ),
  );

  test('Category migration preserves identity, amounts, currencies and named lines', () {
    final state = withDefaults(
      defaultState()..addAll({
        'movements': [
          {
            'id': 'm',
            'category': 'La mamalona',
            'amount': 24.1,
            'currency': 'VES',
          },
        ],
        'budgets': [
          {
            'id': 'b',
            'category': 'La mamalona',
            'name': 'Moto',
            'limit': 200,
            'currency': 'VES',
          },
        ],
      }),
    );
    expect((state['movements'] as List).single, {
      'id': 'm',
      'category': 'Transporte',
      'amount': 24.1,
      'currency': 'VES',
    });
    expect((state['budgets'] as List).single['name'], 'Moto');
    expect(withDefaults(state)['budgets'], state['budgets']);
    for (final word in [
      'arbitraje',
      'deportes',
      'fútbol',
      'videojuegos',
      'cine',
      'gimnasio',
    ]) {
      expect(categoryFromDescription(word), 'Hobbys', reason: word);
    }
    expect(budgetCategories, isNot(contains('La mamalona')));
    expect(categoryFromDescription('arbitrariamente'), isNull);
  });

  testWidgets(
    'Same bank hides stale manual commission and another bank restores auto',
    (tester) async {
      final dynamic app = await payments.openExpense(tester);
      await payments.choose(tester, 'Forma de pago', 'Transferencia bancaria');
      await payments.choose(tester, 'Comisión', 'Manual');
      await payments.editFee(tester, '75');
      await payments.choose(tester, 'Transferencia bancaria', 'Mismo banco');
      expect(payments.option('Comisión'), findsNothing);
      expect(payments.option('Comisión manual'), findsNothing);
      await payments.choose(tester, 'Transferencia bancaria', 'Otro banco');
      expect(
        tester.widget<OptionField>(payments.option('Comisión')).value,
        'Automática',
      );
      await payments.choose(tester, 'Transferencia bancaria', 'Mismo banco');
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.maps('movements').single['feeAmount'], 0);
      expect(app.maps('movements').single['feeMode'], 'none');
      expect(app.accountById('bank')['balance'], 10000);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final provider in ['BINANCE', 'OKX', 'ZINLI', 'KONTIGO', 'WALLY']) {
    testWidgets('$provider expenses cannot charge a dollar commission', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(
        () => app.state['accounts'] = [
          {
            'id': 'wallet',
            'provider': provider,
            'kind': 'wallet',
            'currency': 'USD',
            'balance': 100.0,
          },
        ],
      );
      app.saveMovement({
        'id': 'new',
        'accountId': 'wallet',
        'type': 'expense',
        'currency': 'USD',
        'amount': 20,
        'feeAmount': 10,
        'feeMode': 'auto',
        'feeUnit': 'percent',
        'feePercent': 50,
        'date': formatDateTime(DateTime.now()),
        'category': 'Otro',
      });
      expect(app.accountById('wallet')['balance'], 80);
      expect(app.movementById('new')['feeAmount'], 0);
      expect(app.movementById('new')['feeUnit'], isNull);
      await tester.pump(const Duration(seconds: 9));
      app.openMovementEditor(
        tester.element(find.byType(HomePage)),
        defaultAccountId: 'wallet',
        defaultAmount: 10.0,
      );
      await tester.pumpAndSettle();
      await payments.choose(
        tester,
        'Forma de pago',
        provider == 'BINANCE' ? 'Binance Pay' : 'Pago',
      );
      expect(payments.option('Comisión'), findsNothing);
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.accountById('wallet')['balance'], 70);
      expect(
        app.maps('movements').last['paymentMethod'],
        provider == 'BINANCE' ? 'binance_pay' : 'wallet_payment',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'Custom categories retain icons, relationships and keywords after rename and archive',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      saveCustomCategory(app, {
        'name': 'Entradas',
        'icon': 'Cine',
        'keywords': ['cine local'],
      });
      final entry = app.maps('customCategories').single as Map<String, dynamic>;
      expect(
        categoryFromDescription('cine local', custom: [entry]),
        'Entradas',
      );
      expect(categoryFromDescription('cine', custom: [entry]), 'Hobbys');
      app.mutate(() {
        app.rawList('movements').add({
          'id': 'expense',
          'category': 'Entradas',
          'amount': 2,
          'currency': 'USD',
        });
        app.rawList('budgets').add({
          'id': 'line',
          'category': 'Entradas',
          'limit': 10,
          'currency': 'USD',
        });
      });
      saveCustomCategory(app, {
        ...entry,
        'name': 'Cine local',
      }, editingId: entry['id'].toString());
      expect(app.maps('movements').single['category'], 'Cine local');
      expect(app.maps('budgets').single['category'], 'Cine local');
      expect(
        () => saveCustomCategory(app, {'name': 'Comida', 'icon': 'Casa'}),
        throwsFormatException,
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(HomePage));
      expect(categoryChoices(context), contains('Cine local'));
      expect(categoryIcon('Cine local', context: context), CupertinoIcons.film);
      app.openMovementEditor(
        context,
        defaultAccountId: 'a',
        defaultAmount: 5.0,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(payments.option('Categoría'));
      await tester.tap(payments.option('Categoría'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Buscar'), 'Cine local');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ModernSheetTile),
          matching: find.text('Cine local'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      expect(app.maps('movements').last['category'], 'Cine local');
      final updated =
          app.maps('customCategories').single as Map<String, dynamic>;
      saveCustomCategory(app, {
        ...updated,
        'archived': true,
      }, editingId: entry['id'].toString());
      await tester.pumpAndSettle();
      expect(
        categoryChoices(tester.element(find.byType(HomePage))),
        isNot(contains('Cine local')),
      );
      expect(
        categoryChoices(
          tester.element(find.byType(HomePage)),
          selected: 'Cine local',
        ),
        contains('Cine local'),
      );
      final restored = withDefaults(
        jsonDecode(jsonEncode(app.state)) as Map<String, dynamic>,
      );
      expect((restored['customCategories'] as List).single['icon'], 'Cine');
      expect((restored['movements'] as List).length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final dark in [true, false]) {
      testWidgets('Paid and unpaid debts fit $width dark=$dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 740);
        app.mutate(() {
          app.state['darkMode'] = dark;
          app.state['debts'] = [
            {
              'id': 'pending',
              'title': 'Gabriel',
              'kind': 'payable',
              'currency': 'USD',
              'amount': 100.0,
              'paidAmount': 20.0,
            },
            {
              'id': 'paid',
              'title': 'Internet',
              'kind': 'payable',
              'currency': 'VES',
              'amount': 5000.0,
              'paidAmount': 5000.0,
            },
          ];
        });
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => DebtsPage(app: app),
        );
        await tester.pumpAndSettle();
        expect(find.text('Gabriel'), findsOneWidget);
        expect(find.text('Internet'), findsNothing);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(CupertinoApp),
            matchesGoldenFile('../build/release83-qa/debts-$width-$dark.png'),
          );
        }
        await tester.tap(find.text('Pagados'));
        await tester.pumpAndSettle();
        expect(find.text('Internet'), findsOneWidget);
        expect(find.text('Gabriel'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('Cestaticket and category editor fit $width dark=$dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 740);
        app.mutate(() => app.state['darkMode'] = dark);
        await tester.pumpAndSettle();
        app.openAccountEditor(tester.element(find.byType(HomePage)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Beneficios'));
        await tester.pumpAndSettle();
        expect(find.text('Cestaticket'), findsOneWidget);
        expect(payments.option('Moneda'), findsNothing);
        await tester.enterText(field('Saldo'), '10000');
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(CupertinoApp),
            matchesGoldenFile(
              '../build/release80-qa/cestaticket-$width-$dark.png',
            ),
          );
        }
        await tester.ensureVisible(find.text('Agregar cuenta'));
        await tester.tap(find.text('Agregar cuenta'));
        await tester.pumpAndSettle();
        final account = (app.maps('accounts') as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((entry) => entry['provider'] == 'CESTATICKET');
        expect(account['currency'], 'VES');
        expect(account['balance'], 10000);
        expect(account['kind'], 'benefit');
        expect(expensePaymentMethods(account), ['Tarjeta']);
        await tester.pump(const Duration(seconds: 9));
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => CustomCategoryEditor(app: app),
        );
        await tester.pumpAndSettle();
        await tester.enterText(field('Nombre'), 'Jardin');
        await tester.enterText(
          field('Palabras clave, separadas por comas'),
          'plantas',
        );
        await tester.tap(find.byKey(const ValueKey('category-icon-Casa')));
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(CupertinoApp),
            matchesGoldenFile(
              '../build/release80-qa/categories-$width-$dark.png',
            ),
          );
        }
        await tester.scrollUntilVisible(
          find.text('Guardar categoría'),
          180,
          scrollable: find
              .descendant(
                of: find.byType(CustomCategoryEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Guardar categoría'));
        await tester.pumpAndSettle();
        expect(app.maps('customCategories').single['icon'], 'Casa');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('New setup completes at $width dark=$dark without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RialApp(initialState: defaultState()..['darkMode'] = dark),
        );
        await tester.pumpAndSettle();
        await tester.enterText(field('Tu nombre'), 'Arturo');
        for (var step = 0; step < 3; step++) {
          if (step == 2) {
            await tester.enterText(field('PIN de 4 a 6 dígitos'), '123456');
            await tester.enterText(field('Repetir PIN'), '123456');
          }
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(CupertinoApp),
              matchesGoldenFile(
                '../build/release80-qa/setup-$step-$width-$dark.png',
              ),
            );
          }
          await tester.tap(find.text('Continuar'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('Todo listo'), findsOneWidget);
        await tester.tap(find.text('Ir al inicio'));
        await tester.pumpAndSettle();
        expect(find.text('Conoce Sin Rial'), findsOneWidget);
        for (var step = 0; step < 5; step++) {
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(CupertinoApp),
              matchesGoldenFile(
                '../build/release84-qa/introduction-$step-$width-$dark.png',
              ),
            );
          }
          if (step < 4) {
            await tester.tap(find.text('Siguiente'));
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.text('Omitir'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
        final dynamic app = tester.state(find.byType(RialApp));
        expect(app.state['userName'], 'Arturo');
        expect(app.state['securitySetupComplete'], true);
        expect(app.state['pinEnabled'], true);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
