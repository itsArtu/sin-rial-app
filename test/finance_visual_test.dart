import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart' as charts;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'account_colors_test.dart' as account_fixtures;
import 'income_transfer_fee_test.dart' as fee_fixtures;
import 'shared_savings_test.dart' as savings_fixtures;
import 'budget_plans_test.dart' as budget_fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const fontPath = String.fromEnvironment('FINANCE_TEST_FONT');
    if (fontPath.isEmpty) return;
    final bytes = ByteData.sublistView(await File(fontPath).readAsBytes());
    for (final family in [
      '.SF Pro Text',
      '.SF Pro Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Ahem',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
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
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('Budget wizard and monthly breakdown fit $width dark=$dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() => app.state['darkMode'] = dark);
        Future<void> capture(String name) async {
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile(
                '../build/finance-qa/$name-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
              ),
            );
          }
        }

        app.setTab(1);
        await capture('budget-empty');
        await tester.tap(find.text('S\u00ed, crear plan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Quincenal'));
        await capture('budget-period');
        await tester.ensureVisible(find.text('Variables'));
        await tester.tap(find.text('Variables'));
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        await tester.enterText(
          budget_fixtures.field('Ahorro previsto en USD'),
          '100',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await capture('budget-income-keyboard');
        expect(find.text('Continuar').hitTestable(), findsOneWidget);
        tester.view.resetViewInsets();
        tester.testTextInput.hide();
        await tester.tap(find.text('Continuar'));
        await capture('budget-categories');
        app.rootNavigatorKey.currentState.pop();
        await tester.pumpAndSettle();
        expect(app.maps('budgetPlans'), isEmpty);
        budget_fixtures.plan(
          app,
          currentMonthKey(),
          items: [
            {'category': 'Comida', 'limit': 300.0},
            {'category': 'Transporte', 'limit': 100.0},
            {'category': 'Comisiones bancarias', 'limit': 20.0},
          ],
        );
        app.mutate(
          () => app.state['movements'] = [
            budget_fixtures.expense(
              formatDateTime(DateTime.now()),
              amount: 200,
            ),
            budget_fixtures.expense(
              formatDateTime(DateTime.now()),
              category: 'Transporte',
              amount: 80,
            ),
            budget_fixtures.expense(
              formatDateTime(DateTime.now()),
              category: 'Salud',
              amount: 50,
            ),
            budget_fixtures.expense(
              formatDateTime(DateTime.now()),
              category: 'Comisiones bancarias',
              amount: 3,
            ),
          ],
        );
        await tester.pump(const Duration(seconds: 9));
        await capture('budget-summary');
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('budget-spending-bar')),
        );
        await capture('budget-breakdown');
        final bar = tester.widget<RatioBar>(
          find.byKey(const ValueKey('budget-spending-bar')),
        );
        expect(bar.parts.map((p) => p.color).toSet().length, 4);
        expect(find.text('Salud'), findsNothing);
        await tester.pumpAndSettle();
        await tester.drag(
          find
              .descendant(
                of: find.byType(BudgetPage),
                matching: find.byType(Scrollable),
              )
              .first,
          const Offset(0, -400),
        );
        await capture('budget-limits');
        app.saveMovement(fixtures.movement('expense'));
        await capture('undo-notice');
        expect(find.byType(UndoNotice), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });

      testWidgets('Shared savings surfaces fit $width dark=$dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() {
          app.state['darkMode'] = dark;
          coupleSavings(app)['target'] = 500.0;
        });
        savings_fixtures.couple(app, 'deposit', 75);
        savings_fixtures.couple(app, 'deposit', 125, member: 'partner');
        saveSavingsCircle(app, savings_fixtures.sampleCircle());
        savings_fixtures.circlePayment(app, 0, 'a', 'contribution');
        await tester.pump(const Duration(seconds: 9));
        await tester.pumpAndSettle();
        final homeContext = tester.element(find.byType(HomePage));
        Future<void> capture(String name) async {
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile(
                '../build/finance-qa/$name-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
              ),
            );
          }
        }

        Future<void> closePage() async {
          Navigator.of(homeContext).pop();
          await tester.pumpAndSettle();
        }

        app.pushPage(homeContext, (_) => SavingsPage(app: app));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Bolso / San'));
        await capture('savings-sections');
        await closePage();
        app.pushPage(homeContext, (_) => CoupleSavingsPage(app: app));
        await capture('couple-savings');
        app.mutate(() {
          savingsMembers(coupleSavings(app)).first['name'] =
              'Un nombre de participante bastante largo';
        });
        savings_fixtures.couple(app, 'deposit', 999999999999);
        await tester.pump(const Duration(seconds: 9));
        await capture('couple-large');
        await closePage();
        app.pushPage(
          homeContext,
          (_) => SharedSavingEntryPage(
            app: app,
            collection: 'sharedSavings',
            recordId: 'couple',
            type: 'deposit',
          ),
        );
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.enterText(
          savings_fixtures.field('Monto en D\u00f3lares'),
          '2000',
        );
        await capture('couple-entry-keyboard');
        expect(find.text('Guardar registro').hitTestable(), findsOneWidget);
        tester.view.resetViewInsets();
        tester.testTextInput.hide();
        await closePage();
        app.pushPage(
          homeContext,
          (_) => SavingsCircleDetailsPage(app: app, circleId: 'san'),
        );
        await capture('circle-pending');
        savings_fixtures.circlePayment(
          app,
          0,
          'me',
          'contribution',
          account: 'a',
        );
        savings_fixtures.circlePayment(app, 0, 'b', 'contribution');
        await tester.pump(const Duration(seconds: 9));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Registrar cobro del turno'));
        await capture('circle-funded');
        await closePage();
        app.pushPage(homeContext, (_) => SavingsCircleEditorPage(app: app));
        await capture('circle-editor');
        await tester.enterText(
          savings_fixtures.field('Nombre del bolso'),
          'Ahorro familiar',
        );
        await tester.enterText(
          savings_fixtures.field('Cuota por persona'),
          '25',
        );
        await tester.ensureVisible(find.text('Agregar participante'));
        await tester.tap(find.text('Agregar participante'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(savings_fixtures.field('Turno 3'));
        await tester.enterText(savings_fixtures.field('Turno 3'), 'Ana');
        await capture('circle-participants');
        expect(find.text('Guardar bolso').hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });

      testWidgets('Manual time input fits $width dark=$dark with keyboard', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() => app.state['darkMode'] = dark);
        final selected = pickModernTime(
          context: tester.element(find.byType(HomePage)),
          theme: app.theme,
          initial: DateTime(2026, 9, 22, 19, 30),
        );
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('time-input-hour')),
          '8',
        );
        await tester.enterText(
          find.byKey(const ValueKey('time-input-minute')),
          '45',
        );
        await tester.ensureVisible(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/finance-qa/time-input-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
            ),
          );
        }
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(await selected, isNull);
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });

      testWidgets('Next-rate calculator and copy fit $width dark=$dark', (
        tester,
      ) async {
        final dynamic app = await fixtures.fixture(tester);
        tester.view.physicalSize = Size(width, 844);
        final nextDate = isoDate(
          caracasTime(DateTime.now()).add(const Duration(days: 1)),
        );
        app.mutate(() {
          app.state['darkMode'] = dark;
          app.state['rate'] = 849.564;
          app.state['eurRate'] = 974.09309112;
          app.state['bcvRateSnapshots'] = [
            {'USD': 850.1234, 'EUR': 980.5678, 'effective_date': nextDate},
          ];
        });
        Navigator.of(tester.element(find.byType(HomePage))).push(
          CupertinoPageRoute<void>(builder: (_) => CalculatorPage(app: app)),
        );
        await tester.pumpAndSettle();
        final amount = find.byWidgetPredicate(
          (widget) =>
              widget is CupertinoTextField && widget.placeholder == '0,00',
        );
        await tester.enterText(amount, '2000');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('calculator-next-rate')),
        );
        await tester.tap(find.text('Usar tasa del día siguiente'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('calculator-copy')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('calculator-copy')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/finance-qa/calculator-next-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
            ),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });

      testWidgets('Income and transfer fee forms fit $width dark=$dark', (
        tester,
      ) async {
        final dynamic app = await fee_fixtures.fixture(
          tester,
          width: width,
          dark: dark,
        );
        final homeContext = tester.element(find.byType(HomePage));
        await tester.runAsync(() async {
          for (final provider in ['0102', '0172']) {
            final asset = logoAsset(provider);
            if (asset != null) {
              await precacheImage(AssetImage(asset), homeContext);
            }
          }
        });
        for (final kind in ['income', 'other-bank', 'same-bank']) {
          app.openMovementEditor(
            homeContext,
            movement: fee_fixtures.movement(
              kind == 'income' ? 'income' : 'transfer',
              targetId: kind == 'same-bank' ? 'same' : 'other',
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Guardar cambios').hitTestable(), findsOneWidget);
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile(
                '../build/finance-qa/fee-$kind-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
              ),
            );
          }
          Navigator.of(tester.element(find.byType(MovementEditor))).pop();
          await tester.pumpAndSettle();
        }
        await fee_fixtures.closeFixture(tester);
      });

      testWidgets('Finance surfaces fit $width dark=$dark', (tester) async {
        final dynamic app = await fixtures.fixture(tester, count: 5);
        tester.view.physicalSize = Size(width, 844);
        app.mutate(() {
          app.state['darkMode'] = dark;
          app.state['themeColor'] = 'indigo';
          app.state['homeShortcutButtons'] = [
            'calculator',
            'movement',
            'debts',
            'settings',
          ];
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final suffix = '${width.toInt()}-${dark ? 'dark' : 'light'}';
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/home-$suffix.png'),
          );
        }
        app.pushPage(
          tester.element(find.byType(HomePage)),
          (_) => HomeCustomizePage(app: app),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/customize-$suffix.png'),
          );
        }
        Navigator.of(tester.element(find.byType(HomeCustomizePage))).pop();
        await tester.pumpAndSettle();
        final chart = find.byType(charts.LineChart);
        final beforeTouch = tester.getRect(chart);
        await tester.tap(chart);
        await tester.pumpAndSettle();
        expect(tester.getRect(chart), beforeTouch);
        expect(
          tester.widget<charts.LineChart>(chart).data.showingTooltipIndicators,
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/home-touch-$suffix.png'),
          );
        }
        await tester.ensureVisible(find.text('Movimientos').first);
        await tester.tap(find.text('Movimientos').first);
        await tester.pumpAndSettle();
        expect(find.byType(MovementHistoryPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/history-$suffix.png'),
          );
        }
        app.mutate(() {
          app.accountById('a').addAll({
            'provider': '0102',
            'kind': 'national',
            'currency': 'VES',
          });
        });
        app.openMovementEditor(
          tester.element(find.byType(MovementHistoryPage)),
          defaultAccountId: 'a',
          defaultAmount: 1000.0,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/editor-$suffix.png'),
          );
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('movement-editor-fields')),
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();
        expect(find.text('Guardar movimiento').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile(
              '../build/finance-qa/editor-keyboard-$suffix.png',
            ),
          );
        }
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final description = find.byWidgetPredicate(
          (w) => w is CupertinoTextField && w.placeholder == 'Descripción',
        );
        await tester.scrollUntilVisible(
          description,
          -150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('movement-editor-fields')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        for (final entry in {
          'motorcycle': 'La mamalona',
          'bank-commission': 'Comisiones bancarias',
        }.entries) {
          await tester.enterText(description, entry.value);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile('../build/finance-qa/${entry.key}-$suffix.png'),
            );
          }
        }
        final accounts = account_fixtures.collisionAccounts();
        assignAccountColors(accounts);
        app.mutate(() {
          app.state['accounts'] = accounts;
          app.state['rate'] = 847.44;
        });
        app.pushPage(
          tester.element(find.byType(MovementEditor)),
          (_) => CurrencyAccountsPage(app: app, currency: 'VES'),
        );
        await tester.pumpAndSettle();
        final accountContext = tester.element(
          find.byType(CurrencyAccountsPage),
        );
        await tester.runAsync(() async {
          for (final account in accounts) {
            final asset = logoAsset(account['provider'] as String);
            if (asset != null)
              await precacheImage(AssetImage(asset), accountContext);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byType(RialApp),
            matchesGoldenFile('../build/finance-qa/accounts-$suffix.png'),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
