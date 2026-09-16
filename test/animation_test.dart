import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  testWidgets('Long screens only build items near the viewport', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: AppScroll(
            title: 'Prueba',
            theme: RTheme(true, 'indigo'),
            children: [
              for (var i = 0; i < 100; i++)
                Builder(
                  builder: (_) {
                    builds++;
                    return SizedBox(height: 80, child: Text('Item $i'));
                  },
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, lessThan(20));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(builds, lessThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion skips entrance animation', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: softEntrance(const Text('Contenido')),
        ),
      ),
    );
    expect(find.text('Contenido'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
