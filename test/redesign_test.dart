import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'budget_plans_test.dart' as budgets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const font = String.fromEnvironment('FINANCE_TEST_FONT');
    if (font.isEmpty) return;
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    for (final name in [
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Ahem',
    ]) {
      await (FontLoader(name)..addFont(Future.value(bytes))).load();
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final item in manifest.cast<Map>()) {
      final loader = FontLoader(item['family'] as String);
      for (final f in (item['fonts'] as List).cast<Map>())
        loader.addFont(rootBundle.load(f['asset'] as String));
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

  test(
    'Selected category budget excludes unrelated spending and missing rates',
    () {
      final records = [
        budgets.expense('22/09/2026 10:00 AM', amount: 10, fee: 1),
        budgets.expense(
          '22/09/2026 10:00 AM',
          amount: 9999,
          category: 'Salud',
          currency: 'EUR',
        ),
        budgets.expense('22/09/2026 10:00 AM', amount: 500, category: 'Otro'),
      ];
      final result = summarizeBudgetSpending(
        records,
        '2026-09',
        'monthly',
        usdRate: 0,
        eurRate: 0,
        selectedCategories: {'Comida', 'Transporte'},
      );
      expect(result.categories, {'Comida': 11});
      expect(result.total, 11);
      expect(result.missingRates, 0);
      expect(
        summarizeBudgetSpending(
          records,
          '2026-09',
          'monthly',
          usdRate: 10,
          eurRate: 12,
          selectedCategories: {},
        ).total,
        0,
      );
    },
  );
  test('Profile initials and shortcut maximum', () {
    expect(profileInitials(' Arturo ', 'P\u00e9rez'), 'AP');
    expect(profileInitials('Arturo', ''), 'A');
    expect(profileInitials('', ''), 'SR');
    expect(
      sanitizeHomeShortcutButtons([
        'settings',
        'calculator',
        'movement',
        'debts',
      ]),
      ['settings', 'calculator', 'movement'],
    );
  });
  test(
    'Rate charts use observed quotes, retain 60 days and never invent points',
    () {
      final state = defaultState();
      expect(rateObservations(state, 'USDT'), isEmpty);
      for (var i = 0; i < 65; i++)
        rememberUsdtQuote(
          state,
          100 + i.toDouble(),
          DateTime.utc(2026, 7, i + 1, 12),
        );
      expect((state['usdtRateHistory'] as List).length, 60);
      rememberUsdtQuote(state, 222, DateTime.utc(2026, 7, 65, 18));
      expect((state['usdtRateHistory'] as List).length, 60);
      expect(rateObservations(state, 'USDT').last.value, 222);
      state['rateEffectiveDate'] = '2026-09-22';
      state['eurRateEffectiveDate'] = '2026-09-22';
      state['bcvRateSnapshots'] = [
        {'effective_date': '2026-09-21', 'USD': 100, 'EUR': 110},
        {'effective_date': '2026-09-22', 'USD': 101, 'EUR': 112},
        {'effective_date': '2026-09-23', 'USD': 102, 'EUR': 114},
      ];
      expect(rateObservations(state, 'USD').map((p) => p.value), [100, 101]);
      expect(rateObservations(state, 'EUR').map((p) => p.value), [110, 112]);
      state['eurRateEffectiveDate'] = '';
      expect(rateObservations(state, 'EUR').map((p) => p.value), [110, 112]);
    },
  );
  testWidgets(
    'Variable and fixed income plans persist independent data and undo',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      saveBudgetPlan(
        app,
        period: currentMonthKey(),
        type: 'monthly',
        salary: 0,
        savings: 50,
        incomeMode: 'variable',
        items: [
          {'category': 'Comida', 'limit': 20},
        ],
      );
      final id = budgetPlanId(currentMonthKey(), 'monthly');
      expect(findBudgetPlan(app, id)!['incomeMode'], 'variable');
      expect(findBudgetPlan(app, id)!['salary'], 0);
      saveBudgetPlan(
        app,
        period: currentMonthKey(),
        type: 'monthly',
        salary: 999,
        savings: 50,
        incomeMode: 'fixed',
        incomes: [
          {'name': 'Salario', 'amount': 200},
          {'name': 'Freelance', 'amount': 100},
        ],
        items: [
          {'category': 'Comida', 'limit': 20},
        ],
        editingId: id,
      );
      expect(findBudgetPlan(app, id)!['salary'], 300);
      expect((findBudgetPlan(app, id)!['incomes'] as List).length, 2);
      app.undoLastOperation();
      expect(findBudgetPlan(app, id)!['incomeMode'], 'variable');
      final cache = BudgetSpendingCache();
      app.mutate(
        () => app.state['movements'] = [
          budgets.expense(formatDateTime(DateTime.now()), amount: 20),
        ],
      );
      expect(
        cache
            .read(
              app,
              currentMonthKey(),
              'monthly',
              selectedCategories: {'Comida'},
            )
            .total,
        20,
      );
      expect(
        cache
            .read(
              app,
              currentMonthKey(),
              'monthly',
              selectedCategories: {'Salud'},
            )
            .total,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('Profile saves all fields and version credits open', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => ProfilePage(app: app),
    );
    await tester.pumpAndSettle();
    await tester.enterText(budgets.field('Nombre'), 'Arturo');
    await tester.enterText(budgets.field('Apellido'), 'P\u00e9rez');
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();
    expect(app.state['userName'], 'Arturo');
    expect(app.state['userLastName'], 'P\u00e9rez');
    expect(find.text('AP'), findsOneWidget);
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => SettingsPage(app: app),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-version')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Gracias a los testers Rams\u00e9s, Gabriel, Kender, Daniel',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Hecha por Arturo el siuuuu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('Redesigned screens fit $width dark=$dark', (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.resetPadding);
        app.mutate(() {
          app.state['darkMode'] = dark;
          app.state['userName'] = 'Arturo';
          app.state['userLastName'] = 'P\u00e9rez';
          app.state['homeShortcutButtons'] = [
            'calculator',
            'movement',
            'accounts',
          ];
          app.state['rate'] = 852.42;
          app.state['eurRate'] = 978.17;
          app.state['usdtRate'] = 958.15;
          app.state['accounts'] = [
            {
              'id': 'cash',
              'provider': 'CASH',
              'currency': 'VES',
              'balance': 1350.0,
            },
            {
              'id': 'bank',
              'provider': '0172',
              'currency': 'VES',
              'balance': 2761.26,
            },
            {
              'id': 'bdv',
              'provider': '0102',
              'currency': 'VES',
              'balance': 70.44,
            },
            {
              'id': 'binance',
              'provider': 'BINANCE',
              'currency': 'USD',
              'balance': 124.28,
            },
          ];
          final today = caracasTime(DateTime.now());
          app.state['rateEffectiveDate'] = isoDate(today);
          app.state['eurRateEffectiveDate'] = isoDate(today);
          app.state['bcvRateSnapshots'] = [
            for (var i = 0; i < 7; i++)
              {
                'effective_date': isoDate(
                  today.subtract(Duration(days: 6 - i)),
                ),
                'USD': 846 + i,
                'EUR': 970 + i,
              },
            {
              'effective_date': isoDate(today.add(const Duration(days: 1))),
              'USD': 855.0,
              'EUR': 980.0,
            },
          ];
          for (var i = 0; i < 7; i++)
            rememberUsdtQuote(
              app.state,
              950 + i.toDouble(),
              DateTime.now().subtract(Duration(days: 6 - i)),
            );
        });
        Future<void> capture(String name) async {
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile('../build/redesign-qa/$name-$width-$dark.png'),
            );
          }
        }

        await capture('home');
        expect(find.text('Bienvenido Arturo'), findsOneWidget);
        expect(find.text('a Sin Rial'), findsOneWidget);
        final trendBounds = tester.getRect(find.byType(BalanceTrend));
        expect(trendBounds.left, closeTo(0, .01));
        expect(trendBounds.right, closeTo(width, .01));
        final homeScroll = tester.widget<AppScroll>(
          find.descendant(
            of: find.byType(HomePage),
            matching: find.byType(AppScroll),
          ),
        );
        expect(homeScroll.topOverlayColor, homeHeaderColor(app.theme));
        expect(find.byType(HomeShortcutButton), findsNWidgets(4));
        final context = tester.element(find.byType(HomePage));
        Future<void> screen(String name, Widget page) async {
          app.pushPage(context, (_) => page);
          await capture(name);
          app.rootNavigatorKey.currentState.pop();
          await tester.pumpAndSettle();
        }

        await screen(
          'accounts',
          CurrencyAccountsPage(app: app, currency: 'VES'),
        );
        await screen('calculator', CalculatorPage(app: app));
        await screen('rates', ExchangeRatesPage(app: app));
        await screen('profile', ProfilePage(app: app));
        await screen('settings', SettingsPage(app: app));
        await screen('widgets', PhoneWidgetsPage(app: app));
        app.setTab(2);
        await capture('menu');
        await tester.scrollUntilVisible(
          find.text('Colores'),
          150,
          scrollable: find
              .descendant(
                of: find.byType(ModernMenu),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('Colores')),
          alignment: .35,
        );
        await tester.pumpAndSettle();
        await capture('menu-personalization');
        await tester.tap(find.text('Colores'));
        await capture('colors');
        expect(find.byType(ThemeColorSelector), findsOneWidget);
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        app.setTab(0);
        await tester.pumpAndSettle();
        budgets.plan(
          app,
          currentMonthKey(),
          items: [
            {'category': 'Comida', 'limit': 100},
            {'category': 'Transporte', 'limit': 30},
          ],
        );
        app.mutate(
          () => app.state['movements'] = [
            budgets.expense(formatDateTime(DateTime.now()), amount: 110),
            budgets.expense(
              formatDateTime(DateTime.now()),
              category: 'Transporte',
              amount: 15,
            ),
            budgets.expense(
              formatDateTime(DateTime.now()),
              category: 'Salud',
              amount: 9000,
            ),
          ],
        );
        await tester.pump(const Duration(seconds: 3));
        app.setTab(1);
        await capture('budget');
        expect(find.text('Salud'), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('budget-remaining')))
              .data,
          r'$5,00',
        );
        final plan = findBudgetPlan(
          app,
          budgetPlanId(currentMonthKey(), 'monthly'),
        )!;
        app.pushPage(
          tester.element(find.byType(BudgetPage)),
          (_) => BudgetPlanEditorPage(
            app: app,
            plan: plan,
            initialPeriod: currentMonthKey(),
            initialType: 'monthly',
            initialStep: 2,
          ),
        );
        await capture('wizard-categories');
        await tester.tap(find.text('Continuar'));
        await capture('wizard-summary');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets(
    'Phone widget chooser sends the selected provider and handles unsupported launchers',
    (tester) async {
      final requests = <String>[];
      var supported = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
            call,
          ) async {
            if (call.method == 'pinHomeWidget') {
              requests.add((call.arguments as Map)['type'] as String);
              return supported;
            }
            return call.method == 'scheduleRateUpdate' ? true : null;
          });
      final dynamic app = await fixtures.fixture(tester);
      app.pushPage<void>(
        app.rootNavigatorKey.currentContext!,
        (_) => PhoneWidgetsPage(app: app),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PhoneWidgetsPage), findsOneWidget);
      for (final type in ['movement', 'USD', 'EUR']) {
        await tester.tap(find.byKey(ValueKey('pin-widget-$type')));
        await tester.pumpAndSettle();
      }
      expect(requests, ['movement', 'USD', 'EUR']);
      supported = false;
      await tester.tap(find.byKey(const ValueKey('pin-widget-USD')));
      await tester.pumpAndSettle();
      expect(find.textContaining('selector de widgets'), findsOneWidget);
      expect(tester.takeException(), isNull);
      app.rootNavigatorKey.currentState.pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Budget creating indicator stays centered through success at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget screen(bool saving) => CupertinoApp(
          theme: const CupertinoThemeData(
            textTheme: CupertinoTextThemeData(
              textStyle: TextStyle(fontFamily: 'Manrope'),
            ),
          ),
          home: BudgetCreationStatus(
            theme: RTheme(true, 'cyan'),
            saving: saving,
            periodLabel: 'septiembre de 2026',
            onDone: () {},
          ),
        );
        await tester.pumpWidget(screen(true));
        await tester.pump(const Duration(milliseconds: 200));
        final before = tester.getRect(
          find.byKey(const ValueKey('budget-status-symbol')),
        );
        expect(before.center.dx, closeTo(width / 2, .01));
        expect(find.text('Creando presupuesto...'), findsOneWidget);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(BudgetCreationStatus),
            matchesGoldenFile('../build/redesign-qa/creating-$width.png'),
          );
        }
        await tester.pumpWidget(screen(false));
        await tester.pump(const Duration(milliseconds: 125));
        expect(
          tester.getRect(find.byKey(const ValueKey('budget-status-symbol'))),
          before,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('budget-status-symbol'))),
          before,
        );
        expect(find.text('Ir a presupuestos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(BudgetCreationStatus),
            matchesGoldenFile('../build/redesign-qa/created-$width.png'),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
