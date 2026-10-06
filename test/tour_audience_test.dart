import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;
import 'security_test.dart' as security;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  for (final skip in [true, false]) {
    testWidgets(
      'New user introduction ${skip ? 'skip' : 'completion'} persists without showing release news',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        app.completeOnboarding('Nueva persona', addAccount: false);
        await tester.pumpAndSettle();
        expect(find.text('Conoce Sin Rial'), findsOneWidget);
        expect(find.text('Novedades de 3.2'), findsNothing);
        expect(
          tester.widget<ReleaseTour>(find.byType(ReleaseTour)).introduction,
          true,
        );
        if (!skip) {
          for (var i = 0; i < 4; i++) {
            await tester.tap(find.text('Siguiente'));
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.text(skip ? 'Omitir' : 'Empezar'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
        expect(app.state['pendingAppTour'], false);
        expect(app.state['seenFeatureTour'], '3.2');
        final saved = withDefaults(Map<String, dynamic>.from(app.state));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(RialApp(initialState: saved));
        await tester.pumpAndSettle();
        expect(find.byType(ReleaseTour), findsNothing);
        expect(find.byType(HomePage), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Older version gets only release news, once', (tester) async {
    final state = defaultState()
      ..['onboardingComplete'] = true
      ..['securitySetupComplete'] = true;
    state.remove('seenFeatureTour');
    state.remove('pendingAppTour');
    await tester.pumpWidget(RialApp(initialState: withDefaults(state)));
    await tester.pumpAndSettle();
    expect(find.text('Novedades de 3.2'), findsOneWidget);
    expect(find.text('Conoce Sin Rial'), findsNothing);
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();
    final dynamic app = tester.state(find.byType(RialApp));
    final saved = withDefaults(Map<String, dynamic>.from(app.state));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(RialApp(initialState: saved));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseTour), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Completing release news returns home without a general tour', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.mutate(() => app.state['seenFeatureTour'] = '');
    await tester.pumpAndSettle();
    for (var step = 0; step < 4; step++) {
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(ReleaseTour), findsNothing);
    expect(app.state['pendingAppTour'], false);
    expect(app.state['seenFeatureTour'], '3.2');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Unfinished introduction survives restart', (tester) async {
    final dynamic app = await fixtures.fixture(tester);
    app.completeOnboarding('Prueba', addAccount: false);
    await tester.pumpAndSettle();
    final saved = withDefaults(Map<String, dynamic>.from(app.state));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(RialApp(initialState: saved));
    await tester.pumpAndSettle();
    expect(find.text('Conoce Sin Rial'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Both tours remain behind the PIN lock', (tester) async {
    for (final introduction in [true, false]) {
      final state = security.protectedState()
        ..['pendingAppTour'] = introduction
        ..['seenFeatureTour'] = '';
      await tester.pumpWidget(RialApp(initialState: state));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(ReleaseTour), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('First account opens after the introduction, not over it', (
    tester,
  ) async {
    final dynamic app = await fixtures.fixture(tester);
    app.completeOnboarding('Prueba', addAccount: true);
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseTour), findsOneWidget);
    expect(find.byType(AccountEditor), findsNothing);
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseTour), findsNothing);
    expect(find.byType(AccountEditor), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
