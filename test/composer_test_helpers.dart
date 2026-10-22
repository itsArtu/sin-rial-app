import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

Future<void> chooseType(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('movement-editor-type')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(ModernSheet), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Finder saveChanges() => find.byType(MovementEditor).evaluate().isNotEmpty
    ? find.byKey(const ValueKey('movement-editor-save'))
    : find.text('Guardar cambios');
