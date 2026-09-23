import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  testWidgets(
    'Loading arcs animate without changing their size in either theme',
    (tester) async {
      final capture = GlobalKey();
      for (final dark in [true, false]) {
        final theme = RTheme(dark, 'teal');
        await tester.pumpWidget(
          CupertinoApp(
            home: Center(
              child: RepaintBoundary(
                key: capture,
                child: Container(
                  width: 300,
                  height: 120,
                  color: theme.bg,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final size in [18.0, 32.0, 50.0])
                        RialLoadingIndicator(
                          key: ValueKey(size),
                          color: theme.accent,
                          size: size,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        final before = [
          for (final size in [18.0, 32.0, 50.0])
            tester.getRect(find.byKey(ValueKey(size))),
        ];
        Future<Uint8List?> pixels() => tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
          }
        });
        final first = await pixels();
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byKey(capture),
            matchesGoldenFile('../build/loading-qa/arc-$dark-first.png'),
          );
        }
        await tester.pump(const Duration(milliseconds: 450));
        final second = await pixels();
        expect(first, isNotNull);
        expect(second, isNot(orderedEquals(first!)));
        if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
          await expectLater(
            find.byKey(capture),
            matchesGoldenFile('../build/loading-qa/arc-$dark-second.png'),
          );
        }
        for (var i = 0; i < 3; i++) {
          final size = [18.0, 32.0, 50.0][i];
          expect(before[i].size, Size.square(size));
          expect(tester.getRect(find.byKey(ValueKey(size))), before[i]);
        }
        for (final indicator
            in tester.widgetList<material.CircularProgressIndicator>(
              find.byType(material.CircularProgressIndicator),
            )) {
          expect(indicator.color, theme.accent);
          expect(indicator.strokeCap, StrokeCap.round);
          expect(indicator.value, isNull);
        }
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'Reduced motion stops the arc without announcing an invented percentage',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          CupertinoApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: const Center(
                child: RialLoadingIndicator(
                  color: Color(0xff55bdbd),
                  semanticsLabel: 'Creando presupuesto',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<material.CircularProgressIndicator>(
                find.byType(material.CircularProgressIndicator),
              )
              .value,
          .7,
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel('Creando presupuesto'),
        );
        expect(node.value, isEmpty);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Protected bootstrap uses the shared loader while storage is pending',
    (tester) async {
      const channel = MethodChannel('rial/native_state');
      final reply = Completer<String?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async =>
                call.method == 'readState' ? await reply.future : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(const RialBootstrap());
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(RialLoadingIndicator), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(
        tester
            .widget<CupertinoPageScaffold>(find.byType(CupertinoPageScaffold))
            .backgroundColor,
        const Color(0xff000000),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      reply.completeError(PlatformException(code: 'TEST_STORAGE_UNAVAILABLE'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
