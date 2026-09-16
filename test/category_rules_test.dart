import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

import 'payment_method_test.dart' as payments;
import 'finance_workflow_test.dart' as fixtures;

Finder descriptionField() => find.byWidgetPredicate(
  (widget) =>
      widget is CupertinoTextField && widget.placeholder == 'Descripción',
);

Future<void> describe(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    descriptionField(),
    -150,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('movement-editor-fields')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.enterText(descriptionField(), text);
  await tester.pumpAndSettle();
}

String selectedCategory(WidgetTester tester) =>
    tester.widget<OptionField>(payments.option('Categoría')).value;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('rial/native_state'),
          (call) async => call.method == 'scheduleRateUpdate' ? true : null,
        );
  });

  test('Every keyword classifies correctly, with accents and punctuation', () {
    for (final category in budgetCategories) {
      final expected = switch (category) {
        'Wifi' => 'Servicios',
        'Pasaje' => 'Transporte',
        _ => category,
      };
      expect(categoryFromDescription(category), expected, reason: category);
    }
    for (final entry in categoryKeywords.entries) {
      expect(budgetCategories, contains(entry.key));
      for (final keyword in entry.value) {
        expect(categoryFromDescription(keyword), entry.key, reason: keyword);
        expect(
          categoryFromDescription('  ${keyword.toUpperCase()}!  '),
          entry.key,
          reason: keyword,
        );
      }
    }
    const examples = {
      'Medicamento': 'Salud',
      'Medicamentos para la casa': 'Salud',
      'Farmatodo': 'Salud',
      'Compra en LOCATEL': 'Salud',
      'Farmacia SAAS': 'Salud',
      'Farmarket': 'Salud',
      'Farmahorro': 'Salud',
      'Farmacia San José': 'Salud',
      'Yummy': 'Delivery',
      'Yummy Rides': 'Transporte',
      'YummyRides para ir al trabajo': 'Transporte',
      'Pasaje': 'Transporte',
      'Pasajes de autobús': 'Transporte',
      'Wifi': 'Servicios',
      'Wi-Fi de la casa': 'Servicios',
      'Pago de internet': 'Servicios',
      'Comida': 'Comida',
      'Comida para la casa': 'Comida',
      'Mercado Libre': 'Compras',
      'Cuota de Cashea': 'Cuotas',
      'Curso de cocina': 'Educación',
      'Pago de la tarjeta de crédito': 'Pago TDC',
      'Abono TDC Banesco': 'Pago TDC',
      'Tarjeta de crédito': 'Pago TDC',
      'Cuota TDC': 'Pago TDC',
      'La mamalona': 'La mamalona',
      'Mantenimiento de la moto': 'La mamalona',
      'Gasolina para la moto': 'La mamalona',
      'Gasolina': 'Transporte',
      'Recarga saldo Movistar': 'Recarga saldo',
      'Comisión bancaria': 'Comisiones bancarias',
      'Mantenimiento de cuenta': 'Comisiones bancarias',
      'Corte de luz': 'Servicios',
    };
    for (final entry in examples.entries) {
      expect(
        categoryFromDescription(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('Unknown words do not accidentally match short keyword fragments', () {
    for (final text in [
      '',
      ' ',
      'buscando',
      'gustavo',
      'maximiliano',
      'interesante',
      'banco',
      'mantenimiento',
    ]) {
      expect(categoryFromDescription(text), isNull, reason: text);
    }
    expect(categoryIcon('La mamalona'), material.Icons.two_wheeler);
    expect(categoryIcon('Pago TDC'), CupertinoIcons.creditcard_fill);
  });

  test('Bank commissions cannot incur another fee for any payment method', () {
    for (final method in [
      'bank_transfer',
      'payment_mobile_p2p',
      'payment_mobile_c2p',
      'debit_card',
    ]) {
      expect(
        canConfigureBankFee(
          payments.bank,
          type: 'expense',
          method: method,
          category: 'Comisiones bancarias',
        ),
        isFalse,
      );
      expect(
        estimatedBankFee(
          method: method,
          amount: 10000,
          type: 'expense',
          category: 'Comisiones bancarias',
        ),
        0,
      );
    }
  });

  testWidgets(
    'Description updates category, resets unknown text and respects manual choice',
    (tester) async {
      await payments.openExpense(tester);
      for (final entry in {
        'Medicamento': 'Salud',
        'Yummy': 'Delivery',
        'Yummy Rides': 'Transporte',
        'Pasaje': 'Transporte',
        'Wifi': 'Servicios',
        'Pago TDC': 'Pago TDC',
        'La mamalona': 'La mamalona',
        'Texto sin coincidencias': 'Otro',
        '': 'Otro',
      }.entries) {
        await describe(tester, entry.key);
        expect(selectedCategory(tester), entry.value);
      }
      await payments.choose(tester, 'Categoría', 'Casa');
      await describe(tester, 'Farmatodo');
      expect(selectedCategory(tester), 'Casa');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Bank commission hides payment and fee controls and discards a previous manual fee',
    (tester) async {
      final dynamic app = await payments.openExpense(tester);
      await payments.choose(tester, 'Comisión', 'Manual');
      final manualFee = find.byWidgetPredicate(
        (w) => w is CupertinoTextField && w.placeholder == 'Comisión manual',
      );
      await tester.ensureVisible(manualFee);
      await tester.enterText(manualFee, '75');
      await describe(tester, 'Comisión bancaria');
      expect(selectedCategory(tester), 'Comisiones bancarias');
      expect(payments.option('Forma de pago'), findsNothing);
      expect(payments.option('Comisión'), findsNothing);
      expect(payments.option('Transferencia bancaria'), findsNothing);
      expect(manualFee, findsNothing);
      expect(find.text('Comisión estimada'), findsNothing);
      await tester.tap(find.text('Guardar movimiento'));
      await tester.pumpAndSettle();
      final saved = app.maps('movements').single;
      expect(saved['category'], 'Comisiones bancarias');
      expect(saved['feeAmount'], 0.0);
      expect(saved['feeMode'], 'none');
      expect(saved['paymentMethod'], '');
      expect(saved['bankTransferScope'], '');
      expect(app.accountById('bank')['balance'], 10000.0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Commissions are fee-free when saved or edited directly; undo stays exact',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      final input = fixtures.movement('expense')
        ..addAll({
          'category': 'Comisiones bancarias',
          'feeAmount': 5.0,
          'feeMode': 'manual',
          'paymentMethod': 'bank_transfer',
          'bankTransferScope': 'other_bank',
        });
      app.saveMovement(input);
      expect(input['feeAmount'], 5.0);
      expect(app.accountById('a')['balance'], 80.0);
      expect(app.maps('movements').single['feeAmount'], 0.0);
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById('a')['balance'], 100.0);
      app.saveMovement(fixtures.movement('expense'));
      app.saveMovement(input, editingId: 'm');
      expect(app.accountById('a')['balance'], 80.0);
      expect(app.undoLastOperation(), isTrue);
      expect(app.accountById('a')['balance'], 79.7);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('New categories are selectable and the motorcycle icon renders', (
    tester,
  ) async {
    await payments.openExpense(tester);
    for (final category in [
      'Pago TDC',
      'La mamalona',
      'Comisiones bancarias',
    ]) {
      await tester.ensureVisible(payments.option('Categoría'));
      await tester.tap(payments.option('Categoría'));
      await tester.pumpAndSettle();
      final sheet = find.byType(ModernSheet);
      final search = find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate(
          (w) => w is CupertinoTextField && w.placeholder == 'Buscar',
        ),
      );
      await tester.enterText(search, category);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ModernSheetTile),
          matching: find.text(category),
        ),
      );
      await tester.pumpAndSettle();
      expect(selectedCategory(tester), category);
      if (category == 'La mamalona') {
        expect(
          find.descendant(
            of: payments.option('Categoría'),
            matching: find.byIcon(material.Icons.two_wheeler),
          ),
          findsOneWidget,
        );
      }
    }
    expect(payments.option('Forma de pago'), findsNothing);
    expect(payments.option('Comisión'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Prefilled descriptions are inferred unless a category is explicitly given',
    (tester) async {
      final dynamic app = await fixtures.fixture(tester);
      for (final category in [null, 'Casa']) {
        app.openMovementEditor(
          tester.element(find.byType(HomePage)),
          defaultDescription: 'Medicamento Farmatodo',
          defaultCategory: category,
        );
        await tester.pumpAndSettle();
        expect(selectedCategory(tester), category ?? 'Salud');
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
