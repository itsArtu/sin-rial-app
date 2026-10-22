import 'composer_test_helpers.dart' as composer;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' as budgets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Money input accepts pasted Venezuelan amounts', () {
    for (final amount in ['20,00', '17.668,15']) {
      expect(
        MoneyInputFormatter()
            .formatEditUpdate(
              TextEditingValue.empty,
              TextEditingValue(
                text: amount,
                selection: TextSelection.collapsed(offset: amount.length),
              ),
            )
            .text,
        amount,
      );
    }
  });
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        ),
  );

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

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (!const bool.fromEnvironment('FINANCE_GOLDENS')) return;
    for (final element in find.byType(Image).evaluate().toList()) {
      await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element),
      );
    }
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(RialApp),
      matchesGoldenFile('../build/release91-qa/$name.png'),
    );
  }

  testWidgets(
    'Received exchange preserves exact cents across edit delete and undo',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.accountById('a').addAll({
        'provider': 'BINANCE',
        'kind': 'wallet',
        'transferFeePercent': 2,
      });
      final before = jsonEncode(app.maps('accounts'));
      final data = fixtures.movement('transfer')
        ..addAll({
          'exchangeInput': 'received',
          'amount': 19.99,
          'targetAmount': 17512.49,
          'feeAmount': 3.0,
          'feeMode': 'auto',
          'feeUnit': 'percent',
          'feePercent': 2,
          'feeTreatment': 'added',
          'rate': 0,
        });
      app.saveMovement(data);
      expect(app.accountById('a')['balance'], 80.01);
      expect(app.accountById('b')['balance'], 17612.49);
      final saved = app.movementById('m');
      expect(saved['rate'], closeTo(17512.49 / 19.99, .00000001));
      expect(saved['feeAmount'], 0.0);
      expect(saved.containsKey('feeUnit'), false);
      app.saveMovement({
        ...data,
        'amount': 20.01,
        'targetAmount': 17600.13,
      }, editingId: 'm');
      expect(app.accountById('a')['balance'], 79.99);
      expect(app.accountById('b')['balance'], 17700.13);
      app.undoLastOperation();
      expect(app.accountById('b')['balance'], 17612.49);
      app.deleteMovement(app.movementById('m'));
      expect(jsonEncode(app.maps('accounts')), before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Received exchange rejects incorrect currencies without mutating balances',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.accountById('b')['currency'] = 'EUR';
      final before = jsonEncode(app.maps('accounts'));
      expect(
        () => app.saveMovement({
          ...fixtures.movement('transfer'),
          'exchangeInput': 'received',
          'accountId': 'b',
          'targetAccountId': 'a',
        }),
        throwsFormatException,
      );
      expect(jsonEncode(app.maps('accounts')), before);
      expect(app.maps('movements'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'USD to VES form asks only for received amount and computes rate',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      Map<String, dynamic>? saved;
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (_) => MovementEditor(
          app: app,
          defaultType: 'transfer',
          defaultAccountId: 'a',
          onSave: (value) {
            saved = value;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(budgets.field('Descripción'), findsOneWidget);
      expect(budgets.field('Tasa personalizada'), findsNothing);
      expect(find.text('Comisión'), findsNothing);
      await tester.enterText(budgets.field('Monto'), '20,00');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoTextField>(budgets.field('Monto'))
            .controller!
            .text,
        '20,00',
      );
      await tester.enterText(budgets.field('Monto recibido'), '17.668,15');
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('movement-editor-save')),
      );
      await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
      await tester.pumpAndSettle();
      expect(
        saved,
        isNotNull,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(' | '),
      );
      expect(saved?['targetAmount'], 17668.15);
      expect(saved?['feeAmount'], 0);
      expect(saved?['exchangeInput'], 'received');
      expect(saved?['rate'], closeTo(883.4075, .000001));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('Calendar includes every unpaid installment, not just the next', () {
    final debt = <String, dynamic>{
      'kind': 'payable',
      'amount': 90,
      'paidAmount': 30,
      'hasDueDate': true,
      'hasInstallments': true,
      'installments': 3,
      'installmentMode': 'auto',
      'dueDate': '01/10/2026',
      'installmentDates': ['01/10/2026', '01/11/2026', '01/12/2026'],
      'installmentPayments': {
        'm': {'index': 1, 'amount': 30},
      },
    };
    expect(debtCalendarDates(debt), [
      DateTime(2026, 10, 1),
      DateTime(2026, 12, 1),
    ]);
    expect(debtCalendarDates({...debt, 'hasDueDate': false}), isEmpty);
  });

  testWidgets('Editing a historical USD transfer preserves its commission', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.accountById('a').addAll({'provider': 'BINANCE', 'kind': 'wallet'});
    final previous = fixtures.movement(
      'transfer',
    )..addAll({'feeAmount': 2.0, 'feeMode': 'manual', 'feeTreatment': 'added'});
    Map<String, dynamic>? saved;
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => MovementEditor(
        app: app,
        movement: previous,
        onSave: (value) => saved = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(budgets.field('Monto recibido en bolívares'), findsNothing);
    expect(budgets.field('Tasa personalizada'), findsOneWidget);
    await tester.ensureVisible(composer.saveChanges());
    await tester.tap(composer.saveChanges());
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved?['feeAmount'], 2.0);
    expect(saved?['feeTreatment'], 'added');
    expect(saved?['targetAmount'], 200.0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Calendar supports legacy installments and completed fixed debts', () {
    final legacy = <String, dynamic>{
      'amount': 90,
      'paidAmount': 30,
      'hasInstallments': true,
      'installments': 3,
      'dueDate': '01/10/2026',
      'paymentFrequency': 'Mensual',
    };
    expect(debtScheduleDates(legacy), [
      '01/10/2026',
      '01/11/2026',
      '01/12/2026',
    ]);
    expect(debtCalendarDates(legacy), [
      DateTime(2026, 11, 1),
      DateTime(2026, 12, 1),
    ]);
    expect(
      debtCalendarDates({
        'amount': 25,
        'paidAmount': 25,
        'dueDate': '01/10/2026',
      }),
      [DateTime(2026, 10, 1)],
    );
  });

  testWidgets(
    'VES to USD keeps received cents and canonical rate through undo',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.accountById('b')['balance'] = 30000.0;
      app.accountById('b')['kind'] = 'national';
      app.accountById('b')['provider'] = '0172';
      final before = jsonEncode(app.maps('accounts'));
      final data = {
        ...fixtures.movement('transfer'),
        'exchangeInput': 'received',
        'accountId': 'b',
        'targetAccountId': 'a',
        'amount': 17668.15,
        'targetAmount': 19.99,
        'feeMode': 'auto',
      };
      app.saveMovement(data);
      expect(app.accountById('b')['balance'], 12331.85);
      expect(app.accountById('a')['balance'], 119.99);
      expect(app.movementById('m')['currency'], 'VES');
      expect(app.movementById('m')['targetCurrency'], 'USD');
      expect(app.movementById('m')['feeAmount'], 0);
      expect(
        app.movementById('m')['rate'],
        closeTo(17668.15 / 19.99, .0000001),
      );
      app.saveMovement({...data, 'targetAmount': 20.01}, editingId: 'm');
      expect(app.accountById('a')['balance'], 120.01);
      app.undoLastOperation();
      expect(app.accountById('a')['balance'], 119.99);
      app.deleteMovement(app.movementById('m'));
      expect(jsonEncode(app.maps('accounts')), before);
      expect(
        () => app.saveMovement({...data, 'targetAmount': 0}),
        throwsFormatException,
      );
      expect(jsonEncode(app.maps('accounts')), before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Reverse exchange form labels and automatic rate', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    Map<String, dynamic>? saved;
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => MovementEditor(
        app: app,
        defaultType: 'transfer',
        defaultAccountId: 'b',
        onSave: (value) => saved = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Monto en bolívares'), findsOneWidget);
    expect(budgets.field('Descripción'), findsOneWidget);
    expect(budgets.field('Tasa personalizada'), findsNothing);
    expect(find.text('Comisión'), findsNothing);
    await tester.enterText(budgets.field('Monto'), '17.668,15');
    await tester.enterText(budgets.field('Monto recibido'), '20,00');
    await capture(tester, 'reverse-transfer');
    await tester.ensureVisible(
      find.byKey(const ValueKey('movement-editor-save')),
    );
    await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
    await tester.pumpAndSettle();
    expect(saved?['targetAmount'], 20.0);
    expect(saved?['amount'], 17668.15);
    expect(saved?['rate'], closeTo(883.4075, .000001));
    expect(saved?['feeAmount'], 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Outgoing loan is optional, atomic and not a repayment', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    final data = <String, dynamic>{
      'id': 'lent',
      'kind': 'receivable',
      'originType': 'lent',
      'currency': 'USD',
      'amount': 25.05,
      'paidAmount': 0,
      'partyType': 'Alguien',
      'creditor': 'Ana',
    };
    app.saveDebt(data, withdrawAccountId: 'a');
    expect(app.accountById('a')['balance'], 74.95);
    expect(app.debtById('lent')['paidAmount'], 0);
    final movement = app.maps('movements').single;
    expect(movement['type'], 'expense');
    expect(movement['loanDebtId'], 'lent');
    expect(movement['debtId'], isNull);
    expect(
      () => app.saveDebt(data, editingId: 'lent', withdrawAccountId: 'a'),
      throwsFormatException,
    );
    expect(app.accountById('a')['balance'], 74.95);
    app.undoLastOperation();
    expect(app.accountById('a')['balance'], 100);
    expect(app.debtById('lent'), isNull);
    expect(app.maps('movements'), isEmpty);
    app.saveDebt({...data, 'originType': 'credit_sale'});
    expect(app.accountById('a')['balance'], 100);
    expect(
      () => app.saveDebt({
        ...data,
        'originType': 'credit_sale',
      }, withdrawAccountId: 'a'),
      throwsFormatException,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('Floating menu, all debt presets and compact rows fit $width', (
      tester,
    ) async {
      final dynamic app = await fixtures.fixture(tester);
      tester.view.physicalSize = Size(width, 844);
      app.showQuickActions(tester.element(find.byType(HomePage)));
      await capture(tester, 'actions-$width');
      final menu = find.byKey(const ValueKey('quick-action-popover'));
      expect(tester.getSize(menu).width, lessThan(width));
      expect(tester.getSize(menu).height, lessThan(400));
      await tester.tap(find.text('Cobrar/Pagar'));
      await capture(tester, 'debt-actions-$width');
      expect(tester.getSize(menu).height, lessThan(400));
      final presets = {
        'Presté dinero': 'lent',
        'Fiado': 'credit_sale',
        'Me prestaron dinero': 'borrowed',
        'Financiamiento': 'financing',
      };
      for (final entry in presets.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        final page = tester.widget<DebtEditorPage>(find.byType(DebtEditorPage));
        expect(page.initialFlow, entry.value);
        expect(
          page.initialKind,
          ['lent', 'credit_sale'].contains(entry.value)
              ? 'receivable'
              : 'payable',
        );
        expect(page.initialInstallments, entry.value == 'financing');
        if (entry.value == 'lent')
          expect(
            find.text('Descontar el préstamo de una cuenta'),
            findsOneWidget,
          );
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        showQuickActionMenu(
          tester.element(find.byType(HomePage)),
          app: app,
          debtsOnly: true,
        );
        await tester.pumpAndSettle();
      }
      app.rootNavigatorKey.currentState.pop();
      await tester.pumpAndSettle();
      showModernActionSheet(
        tester.element(find.byType(HomePage)),
        title: 'Cuentas',
        actions: [
          for (var i = 0; i < 15; i++)
            ModernSheetAction(
              title: 'Cuenta $i',
              subtitle: 'Bolívares',
              logoProvider: '0172',
              icon: CupertinoIcons.creditcard,
              onPressed: () {},
            ),
        ],
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ModernSheetTile).first).height,
        lessThanOrEqualTo(60),
      );
      final list = tester.widget<ListView>(
        find.descendant(
          of: find.byType(ModernSheet),
          matching: find.byType(ListView),
        ),
      );
      expect(list.padding, EdgeInsets.zero);
      await capture(tester, 'compact-accounts-$width');
      await tester.enterText(budgets.field('Buscar'), 'Cuenta 14');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ModernSheetTile),
          matching: find.text('Cuenta 14'),
        ),
        findsOneWidget,
      );
      expect(find.text('Cuenta 0'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets(
    'Debt chart masks percentages and compact cards remain legible at large text',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(320, 844);
      app.pushPage(
        tester.element(find.byType(HomePage)),
        (BuildContext context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: DebtDetailPage(app: app, debtId: 'd'),
        ),
      );
      await capture(tester, 'debt-large-text');
      expect(find.text('90%'), findsOneWidget);
      app.mutate(() => app.state['hideAmounts'] = true);
      await tester.pumpAndSettle();
      expect(find.text('90%'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('debt-percentage'))).data,
        '•••',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final dark in [true, false]) {
      testWidgets('New screens fit $width dark=$dark', (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() {
          app.state['darkMode'] = dark;
          app.state['themeColor'] = 'cyan';
          app.accountById('a').addAll({
            'provider': 'BINANCE',
            'kind': 'wallet',
            'label': 'Binance',
          });
          app.accountById('b').addAll({
            'provider': '0172',
            'kind': 'national',
            'label': 'Bancamiga',
          });
          app.debtById('d').addAll({
            'title': 'Reloj Cubitt',
            'creditor': 'Cashea',
            'partyType': 'Cashea',
            'amount': 110.50,
            'paidAmount': 27.63,
            'hasInstallments': true,
            'installments': 6,
            'initialPaid': true,
            'initialAmount': 27.63,
            'installmentMode': 'auto',
            'hasDueDate': true,
            'dueDate': formatDate(DateTime.now()),
            'paymentFrequency': 'Quincenal',
          });
        });
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => DebtsPage(app: app),
        );
        await capture(tester, 'debts-$width-$dark');
        final bar = tester.widget<material.LinearProgressIndicator>(
          find.byKey(const ValueKey('debt-progress-d')),
        );
        expect(bar.value, closeTo(27.63 / 110.50, .00001));
        await tester.tap(find.byKey(const ValueKey('debt-calendar-toggle')));
        await capture(tester, 'calendar-$width-$dark');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        app.openDebtDetail(
          tester.element(find.byType(HomePage)),
          app.debtById('d'),
        );
        await capture(tester, 'detail-$width-$dark');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => AccountsPage(app: app),
        );
        await capture(tester, 'accounts-$width-$dark');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        showModernActionSheet(
          tester.element(find.byType(HomePage)),
          title: 'Selecciona banco',
          actions: [
            for (final code in [
              '0102',
              '0134',
              '0172',
              'BINANCE',
              'OKX',
              'CASHEA',
              'ZINLI',
              'CESTATICKET',
            ])
              ModernSheetAction(
                title: shortProviderName(code),
                icon: CupertinoIcons.creditcard,
                logoProvider: code,
                selected: code == '0172',
                onPressed: () {},
              ),
          ],
        );
        await capture(tester, 'bank-picker-$width-$dark');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        app.mutate(() => app.state['seenFeatureTour'] = 'older');
        await capture(tester, 'tour-profile-$width-$dark');
        for (var step = 0; step < 4; step++) {
          await tester.tap(find.text('Siguiente'));
          await capture(tester, 'tour-${step + 2}-$width-$dark');
        }
        expect(tester.binding.transientCallbackCount, 0);
        await tester.tap(find.text('Empezar'));
        await tester.pumpAndSettle();
        expect(find.byType(ReleaseTour), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('Upcoming cards share compact styling and theme checks', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() {
      app.state['themeColor'] = 'cyan';
      app.state['homeSections'] = ['upcoming', 'recent'];
      app.state['debts'] = [
        for (final item in [
          ('Adaptador Wifi Sebas', 29.19, 13.62),
          ('Lentes mamá', 310.81, 202.72),
          ('Reloj Cubitt', 110.50, 44.21),
        ])
          {
            'id': item.$1,
            'title': item.$1,
            'amount': item.$2,
            'paidAmount': item.$3,
            'kind': 'payable',
            'currency': 'USD',
            'creditor': 'Cashea',
            'partyType': 'Cashea',
            'dueDate': formatDate(DateTime.now().add(const Duration(days: 3))),
            'hasDueDate': true,
            'hasInstallments': true,
            'installments': 3,
            'paymentFrequency': 'Quincenal',
          },
      ];
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(UpcomingPaymentsSection));
    await capture(tester, 'upcoming-compact');
    for (final card in find.byType(DebtProgressCard).evaluate()) {
      expect(
        tester.getSize(find.byWidget(card.widget)).height,
        lessThanOrEqualTo(160),
      );
    }
    app.openDebtDetail(
      tester.element(find.byType(HomePage)),
      app.maps('debts').first,
    );
    await tester.pumpAndSettle();
    for (final icon in tester.widgetList<Icon>(
      find.descendant(
        of: find.byType(DebtDetailPage),
        matching: find.byIcon(CupertinoIcons.check_mark_circled_solid),
      ),
    )) {
      expect(icon.color, app.theme.accent);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Release notes render headings and lists without fetching images',
    (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: SafeArea(
              child: ReleaseNotesBody(
                theme: RTheme(true, 'cyan'),
                notes: '## Deudas\n\n- **Progreso** del pago\n- Calendario\n\n![external](https://example.com/image.png)',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('## Deudas'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
