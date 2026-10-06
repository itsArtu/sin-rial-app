import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

Map<String, dynamic> rule({String? start, String type = 'expense'}) => {
  'name': 'Internet',
  'amount': 20,
  'accountId': 'a',
  'type': type,
  'category': 'Servicios',
  'frequency': 'monthly',
  'startDate': start ?? recurringDateKey(DateTime.now()),
};
Map<String, dynamic> confirmation(
  Map<String, dynamic> r, {
  String id = 'payment',
}) => {
  'id': id,
  'accountId': r['accountId'],
  'amount': 20,
  'currency': r['currency'],
  'type': r['type'],
  'category': r['category'],
  'recurringId': r['id'],
  'recurringDate': r['startDate'],
  'date': formatDateTime(DateTime.now()),
};
Finder field(String name) => find.byWidgetPredicate(
  (w) => w is CupertinoTextField && w.placeholder == name,
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
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          null,
        ),
  );

  test('Monthly anchor survives February, leap years and year boundaries', () {
    for (final year in [2024, 2026]) {
      final r = {...rule(start: '$year-01-31'), 'id': 'r'};
      expect(recurringDateAt(r, 1), DateTime(year, 2, year == 2024 ? 29 : 28));
      expect(recurringDateAt(r, 2), DateTime(year, 3, 31));
      expect(recurringDateAt(r, 12), DateTime(year + 1, 1, 31));
      expect(
        nextRecurringDate(
          {
            ...r,
            'skippedDates': ['$year-01-31'],
          },
          [
            {
              'recurringId': 'r',
              'recurringDate': recurringDateKey(recurringDateAt(r, 1)),
            },
          ],
        ),
        DateTime(year, 3, 31),
      );
    }
    expect(recurringParseDate('2026-02-31'), isNull);
    expect(recurringParseDate('2026-01-01junk'), isNull);
    expect(
      recurringDateAt({...rule(start: '2026-12-28'), 'frequency': 'weekly'}, 1),
      DateTime(2027, 1, 4),
    );
    expect(
      recurringDateAt({
        ...rule(start: '2026-12-28'),
        'frequency': 'fortnightly',
      }, 1),
      DateTime(2027, 1, 12),
    );
  });

  for (final type in ['income', 'expense']) {
    testWidgets(
      '$type changes balance only on confirmation, remains linked on edit and can be undone',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        saveRecurringRule(app, rule(type: type));
        final r = app.maps('recurringMovements').single as Map<String, dynamic>;
        expect(app.maps('movements'), isEmpty);
        expect(app.accountById('a')['balance'], 100);
        expect(recurringPendingItems(app), hasLength(1));
        app.saveMovement(confirmation(r));
        expect(app.accountById('a')['balance'], type == 'income' ? 120 : 80);
        expect(recurringPendingItems(app), isEmpty);
        expect(
          () => app.saveMovement(confirmation(r, id: 'duplicate')),
          throwsFormatException,
        );
        expect(app.maps('movements'), hasLength(1));
        final edited =
            Map<String, dynamic>.from(app.movementById('payment') as Map)
              ..remove('recurringId')
              ..remove('recurringDate')
              ..['amount'] = 15;
        app.saveMovement(edited, editingId: 'payment');
        expect(app.movementById('payment')['recurringId'], r['id']);
        expect(app.accountById('a')['balance'], type == 'income' ? 115 : 85);
        app.undoLastOperation();
        expect(recurringPendingItems(app), isEmpty);
        app.undoLastOperation();
        expect(recurringPendingItems(app), hasLength(1));
        expect(app.accountById('a')['balance'], 100);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Skip, pause, delete, restore and existing-movement linking never duplicate money',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      saveRecurringRule(app, rule());
      var r = app.maps('recurringMovements').single as Map<String, dynamic>;
      skipRecurringDate(app, r['id'].toString(), r['startDate'].toString());
      expect(recurringPendingItems(app), isEmpty);
      expect(app.maps('movements'), isEmpty);
      app.undoLastOperation();
      expect(recurringPendingItems(app), hasLength(1));
      saveRecurringRule(app, {
        ...r,
        'paused': true,
      }, editingId: r['id'].toString());
      expect(recurringPendingItems(app), isEmpty);
      expect(() => app.saveMovement(confirmation(r)), throwsFormatException);
      app.undoLastOperation();
      app.saveMovement(
        confirmation(r)
          ..remove('recurringId')
          ..remove('recurringDate'),
      );
      final balance = app.accountById('a')['balance'];
      app.saveMovement(<String, dynamic>{
        ...Map<String, dynamic>.from(app.movementById('payment') as Map),
        'recurringId': r['id'],
        'recurringDate': r['startDate'],
      }, editingId: 'payment');
      expect(app.maps('movements'), hasLength(1));
      expect(app.accountById('a')['balance'], balance);
      expect(recurringPendingItems(app), isEmpty);
      app.deleteMovement(app.movementById('payment'));
      expect(recurringPendingItems(app), hasLength(1));
      expect(app.accountById('a')['balance'], 100);
      expect(() => saveRecurringRule(app, rule()), throwsFormatException);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Future, wrong currency/type, missing account and schedule changes are rejected',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final future = recurringDateKey(
        DateTime.now().add(const Duration(days: 7)),
      );
      saveRecurringRule(app, rule(start: future));
      var r = app.maps('recurringMovements').single as Map<String, dynamic>;
      expect(recurringPendingItems(app), isEmpty);
      expect(() => app.saveMovement(confirmation(r)), throwsFormatException);
      saveRecurringRule(app, rule(), editingId: r['id'].toString());
      r = app.maps('recurringMovements').single as Map<String, dynamic>;
      expect(
        () => app.saveMovement(confirmation(r)..['currency'] = 'VES'),
        throwsFormatException,
      );
      expect(
        () => app.saveMovement(confirmation(r)..['type'] = 'income'),
        throwsFormatException,
      );
      app.saveMovement(confirmation(r));
      expect(
        () => saveRecurringRule(app, {
          ...r,
          'frequency': 'weekly',
        }, editingId: r['id'].toString()),
        throwsFormatException,
      );
      expect(
        () => saveRecurringRule(app, {...rule(), 'accountId': 'missing'}),
        throwsFormatException,
      );
      expect(
        () => saveRecurringRule(app, {...rule(), 'amount': double.nan}),
        throwsFormatException,
      );
      final restored = decodeStoredState(jsonEncode(app.state));
      expect(restored['recurringMovements'], app.state['recurringMovements']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Create, review, edit amount and confirm at $width dark=$dark',
        (tester) async {
          final dynamic app = await fixtures.fixture(tester);
          tester.view.physicalSize = Size(width, 844);
          app.mutate(() => app.state['darkMode'] = dark);
          app.pushPage(
            tester.element(find.byType(HomePage)),
            (_) => RecurringEditor(app: app),
          );
          await tester.pumpAndSettle();
          await tester.enterText(field('Nombre'), 'Internet mensual');
          await tester.enterText(field('Monto en USD'), '20');
          await tester.pumpAndSettle();
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile(
                '../build/recurring-qa/editor-$width-$dark.png',
              ),
            );
          }
          await tester.scrollUntilVisible(
            find.text('Guardar recurrente'),
            180,
            scrollable: find
                .descendant(
                  of: find.byType(RecurringEditor),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.ancestor(
              of: find.text('Guardar recurrente'),
              matching: find.byType(PrimaryActionButton),
            ),
          );
          await tester.tap(find.text('Guardar recurrente'));
          await tester.pumpAndSettle();
          expect(app.maps('movements'), isEmpty);
          await tester.pump(const Duration(seconds: 9));
          app.pushPage(
            tester.element(find.byType(HomePage)),
            (_) => RecurringMovementsPage(app: app),
          );
          await tester.pumpAndSettle();
          if (const bool.fromEnvironment('FINANCE_GOLDENS')) {
            await expectLater(
              find.byType(RialApp),
              matchesGoldenFile(
                '../build/recurring-qa/pending-$width-$dark.png',
              ),
            );
          }
          final r =
              app.maps('recurringMovements').single as Map<String, dynamic>;
          openRecurringMovement(
            tester.element(find.byType(RecurringMovementsPage)),
            app,
            r,
            r['startDate'].toString(),
          );
          await tester.pumpAndSettle();
          expect(find.byType(MovementEditor), findsOneWidget);
          final input = find.byWidgetPredicate(
            (w) => w is CupertinoTextField && w.controller?.text == '20,00',
          );
          expect(input, findsOneWidget);
          await tester.enterText(input, '15');
          await tester.ensureVisible(find.text('Guardar movimiento'));
          await tester.tap(find.text('Guardar movimiento'));
          await tester.pumpAndSettle();
          expect(app.accountById('a')['balance'], 85);
          expect(recurringPendingItems(app), isEmpty);
          expect(find.byType(RecurringMovementsPage), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
