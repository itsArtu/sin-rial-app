import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'credit_cards_test.dart' as cards;
import 'finance_workflow_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test('Credit names retain the bank and optional alias', () {
    expect(accountPrimaryName(cards.card()), 'Venezuela (Mi tarjeta)');
    expect(accountPrimaryName(cards.card()..['label'] = ''), 'Venezuela');
    expect(
      accountPrimaryName(cards.card()..['label'] = 'Venezuela'),
      'Venezuela',
    );
    final state = defaultState()
      ..['accounts'] = [cards.card()..['cardholderName'] = 'Arturo Perez'];
    final restored = withDefaults(
      jsonDecode(jsonEncode(state)) as Map<String, dynamic>,
    );
    expect(restored['accounts'][0]['cardholderName'], 'Arturo Perez');
    expect(
      () => validateCreditAccount(cards.card()..['lastFour'] = '12345'),
      throwsFormatException,
    );
  });

  testWidgets('Card editor limits pasted digits and saves a separate holder', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.saveAccount(cards.card());
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => CreditCardEditor(app: app, cardId: 'credit'),
    );
    await tester.pumpAndSettle();
    Finder field(String title) => find.descendant(
      of: find.byKey(ValueKey('credit-input-$title')),
      matching: find.byType(CupertinoTextField),
    );
    final scrollable = find
        .descendant(
          of: find.byType(CreditCardEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    final digits = field('Últimos 4 dígitos (opcional)');
    await tester.scrollUntilVisible(digits, 250, scrollable: scrollable);
    await tester.enterText(digits, '12x34567890123456');
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(digits).controller!.text, '1234');
    final holder = field('Titular de la tarjeta (opcional)');
    await tester.scrollUntilVisible(holder, -150, scrollable: scrollable);
    await tester.enterText(holder, 'Arturo Perez');
    await tester.pump();
    final alias = field('Nombre personalizado (opcional)');
    await tester.scrollUntilVisible(alias, -150, scrollable: scrollable);
    await tester.enterText(alias, 'Viajes');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    final save = find.text('Guardar tarjeta');
    await tester.scrollUntilVisible(save, 250, scrollable: scrollable);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final saved = app.accountById('credit') as Map<String, dynamic>;
    expect(saved['lastFour'], '1234');
    expect(saved['cardholderName'], 'Arturo Perez');
    expect(accountPrimaryName(saved), 'Venezuela (Viajes)');
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => CreditCardEditor(app: app, cardId: 'credit'),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(holder, 250, scrollable: scrollable);
    expect(
      tester.widget<CupertinoTextField>(holder).controller!.text,
      'Arturo Perez',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Bank shortcut uses verified package without an app selector', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    final account = <String, dynamic>{
      'id': 'bank',
      'provider': '0172',
      'kind': 'national',
      'currency': 'VES',
      'balance': 100,
      'bankAppPackage': 'com.untrusted.backup',
    };
    app.saveAccount(account);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rial/native_state'), (
          call,
        ) async {
          calls.add(call);
          return true;
        });
    app.pushPage(
      tester.element(find.byType(HomePage)),
      (_) => AccountDetailPage(app: app, account: account),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bancamiga Débito'), findsNothing);
    expect(find.text('Vincular app del banco'), findsNothing);
    final button = find.text('Abrir app de Bancamiga');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final open = calls.singleWhere((c) => c.method == 'openBankAppOrStore');
    expect(open.arguments['package'], 'com.bancamiga');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Hidden tabs retain state without rebuilding on unrelated updates',
    (tester) async {
      var index = 0;
      var revision = 0;
      final builds = [0, 0];
      late StateSetter update;
      await tester.pumpWidget(
        CupertinoApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return RetainedTabTransition(
                index: index,
                children: [
                  for (var i = 0; i < 2; i++)
                    Builder(
                      builder: (_) {
                        builds[i]++;
                        return Text('tab-$i-revision-$revision');
                      },
                    ),
                ],
              );
            },
          ),
        ),
      );
      update(() => index = 1);
      await tester.pumpAndSettle();
      final before = builds[0];
      update(() => revision++);
      await tester.pumpAndSettle();
      expect(builds[0], before);
      expect(find.text('tab-1-revision-1'), findsOneWidget);
      update(() => index = 0);
      await tester.pumpAndSettle();
      expect(find.text('tab-0-revision-1'), findsOneWidget);
      expect(builds[0], greaterThan(before));
    },
  );
}
