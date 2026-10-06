import 'package:flutter_test/flutter_test.dart';

import 'package:rial_flutter/main.dart';

void main() {
  testWidgets('Sin rial V2 loads', (tester) async {
    await tester.pumpWidget(RialApp(initialState: defaultState()));

    expect(find.byType(SinRialLogo), findsOneWidget);
    expect(find.text('¿Cómo te llamas?'), findsOneWidget);
  });
}
