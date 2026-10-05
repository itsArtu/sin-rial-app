import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'finance_workflow_test.dart' as fixtures;

Finder field(String placeholder) => find.byWidgetPredicate(
  (widget) => widget is CupertinoTextField && widget.placeholder == placeholder,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  for (final kind in ['payable', 'receivable']) {
    testWidgets(
      'Fixed $kind supports a partial payment, edit, delete and undo',
      (tester) async {
        final dynamic app = await fixtures.fixture(tester);
        app.mutate(() {
          app.accountById('b')['currency'] = 'USD';
          app.debtById('d').addAll({
            'title': 'Prestamo',
            'kind': kind,
            'paidAmount': 0.0,
            'hasInstallments': false,
          });
        });
        app.openDebtDetail(
          tester.element(find.byType(HomePage)),
          app.debtById('d'),
        );
        await tester.pumpAndSettle();
        final abono = find.byKey(const ValueKey('debt-partial-payment'));
        await tester.ensureVisible(abono);
        await tester.tap(abono);
        await tester.pumpAndSettle();
        expect(
          tester.widget<CupertinoTextField>(field('Monto')).controller!.text,
          isEmpty,
        );
        expect(find.text('Saldo pendiente'), findsOneWidget);
        await tester.enterText(field('Monto'), '30');
        await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
        await tester.pumpAndSettle();
        expect(app.debtById('d')['paidAmount'], 30);
        expect(debtRemainingAmount(app.debtById('d')), 70);
        expect(debtHasInstallments(app.debtById('d')), isFalse);
        expect(app.accountById('a')['balance'], kind == 'payable' ? 70 : 130);
        expect(find.textContaining('Abonado parcialmente'), findsWidgets);
        final movement = Map<String, dynamic>.from(
          app.maps('movements').single,
        );
        expect(movement['debtAppliedAmount'], 30);
        app.saveMovement({
          ...movement,
          'amount': 40.0,
        }, editingId: movement['id']);
        expect(app.debtById('d')['paidAmount'], 40);
        app.deleteMovement(app.movementById(movement['id']));
        expect(app.debtById('d')['paidAmount'], 0);
        expect(app.accountById('a')['balance'], 100);
        expect(app.undoLastOperation(), isTrue);
        expect(app.debtById('d')['paidAmount'], 40);
        expect(app.undoLastOperation(), isTrue);
        expect(app.debtById('d')['paidAmount'], 30);
        expect(app.undoLastOperation(), isTrue);
        expect(app.debtById('d')['paidAmount'], 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'Partial payment keeps the entered amount in the selected account currency and rejects excess',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.mutate(() {
        app.debtById('d')['paidAmount'] = 0.0;
        app.accountById('b')['balance'] = 1000.0;
      });
      app.openDebtMovement(
        tester.element(find.byType(HomePage)),
        app.debtById('d'),
        partial: true,
      );
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(find.byType(MovementEditor));
      expect(editor.accountId, 'b');
      await tester.enterText(field('Monto'), '20');
      final account = find.byWidgetPredicate(
        (w) => w is OptionField && w.label == 'Cuenta',
      );
      await tester.ensureVisible(account);
      await tester.tap(account);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ModernSheet),
          matching: find.text(accountPrimaryName(app.accountById('a'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(editor.accountId, 'a');
      expect(parseAmount(editor.amount.text), 20);
      await tester.ensureVisible(field('Monto'));
      await tester.enterText(field('Monto'), '110');
      final before = jsonEncode(app.maps('accounts'));
      await tester.tap(find.byKey(const ValueKey('movement-editor-save')));
      await tester.pumpAndSettle();
      expect(find.text('Abono mayor al saldo pendiente'), findsOneWidget);
      expect(app.maps('movements'), isEmpty);
      expect(jsonEncode(app.maps('accounts')), before);
      expect(app.debtById('d')['paidAmount'], 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'A debt created with an earlier partial payment does not debit twice',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      app.openDebtEditor(tester.element(find.byType(HomePage)));
      await tester.pumpAndSettle();
      await tester.enterText(field('Qué se debe'), 'Prestamo personal');
      await tester.enterText(field('Monto total'), '100');
      await tester.ensureVisible(find.text('Abono previo'));
      await tester.tap(find.text('Abono previo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Monto ya pagado'));
      await tester.enterText(field('Monto ya pagado'), '25');
      final before = jsonEncode(app.maps('accounts'));
      await tester.ensureVisible(find.text('Guardar registro'));
      await tester.tap(find.text('Guardar registro'));
      await tester.pumpAndSettle();
      final debt = (app.maps('debts') as List<Map<String, dynamic>>).firstWhere(
        (d) => d['title'] == 'Prestamo personal',
      );
      expect(debtHasInstallments(debt), isFalse);
      expect(debt['paidAmount'], 25);
      expect(debtRemainingAmount(debt), 75);
      expect(jsonEncode(app.maps('accounts')), before);
      expect(app.maps('movements'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
