import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  testWidgets('Transition ticks reuse the page and release their controller', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 260),
    );
    var builds = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: RialMotionTransition(
          animation: controller,
          child: Builder(
            builder: (_) {
              builds++;
              return const Text('Contenido');
            },
          ),
        ),
      ),
    );
    final initialBuilds = builds;
    controller.forward();
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    controller.reverse();
    await tester.pumpAndSettle();
    expect(builds, initialBuilds);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transitions fade smoothly in both directions without scaling', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: RialMotionTransition(
          animation: controller,
          child: const SizedBox.expand(child: Text('Destino')),
        ),
      ),
    );
    final motion = find.byType(RialMotionTransition);
    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(of: motion, matching: find.byType(FadeTransition)),
        )
        .opacity
        .value;
    expect(opacity(), 0);
    expect(
      find.descendant(of: motion, matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(opacity(), greaterThan(.9));
    await tester.pump(const Duration(milliseconds: 130));
    expect(opacity(), inExclusiveRange(.1, .9));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion shows the destination without opacity or slide', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: RialMotionTransition(
            animation: AlwaysStoppedAnimation(0),
            child: Text('Visible'),
          ),
        ),
      ),
    );
    final motion = find.byType(RialMotionTransition);
    expect(find.text('Visible'), findsOneWidget);
    expect(
      find.descendant(of: motion, matching: find.byType(FadeTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: motion, matching: find.byType(SlideTransition)),
      findsNothing,
    );
    expect(tester.binding.transientCallbackCount, 0);
  });
}
