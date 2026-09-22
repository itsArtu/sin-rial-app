import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  testWidgets(
    'Home treats dollars as USDT 1:1 and converts only VES at the USDT rate',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() {
        app.state['usdtRate'] = 20.0;
        app.state['homeBalanceCurrency'] = 'USDT';
      });
      await tester.pumpAndSettle();
      final hero = tester.widget<BalanceHero>(find.byType(BalanceHero));
      expect(hero.total, 105); // 100 USD + 100 VES / 20.
      expect(hero.trend.last.amount, 105);
      expect(app.convertForHome(25.0, 'USD', 'USDT'), 25);
      expect(app.convertForHome(25.0, 'USDT', 'USD'), 25);
      expect(app.convertForHome(100.0, 'VES', 'USDT'), 5);
      expect(app.toUsd(25.0, 'USDT'), 25);
      app.mutate(() => app.state['homeBalanceCurrency'] = 'USD');
      await tester.pumpAndSettle();
      expect(tester.widget<BalanceHero>(find.byType(BalanceHero)).total, 110);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Dollar-only balance needs no USDT quote but VES balance does', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() {
      app.state['homeBalanceCurrency'] = 'USDT';
      app.accountById('b')['balance'] = 0.0;
    });
    await tester.pumpAndSettle();
    expect(find.text('₮100,00'), findsOneWidget);
    expect(find.text('Sin tasa'), findsNothing);
    app.mutate(() => app.accountById('b')['balance'] = 100.0);
    await tester.pumpAndSettle();
    expect(find.text('Sin tasa'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
