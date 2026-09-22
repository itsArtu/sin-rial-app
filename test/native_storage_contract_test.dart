import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rial/native_state');

  test(
    'SQLite bridge includes plans and shared savings in separate parts',
    () async {
      final original = defaultState()
        ..['userName'] = 'Storage test'
        ..['budgetPlans'] = [
          {'id': 'plan', 'periodType': 'monthly'},
        ]
        ..['sharedSavings'] = [
          {'id': 'couple', 'history': <dynamic>[]},
        ]
        ..['savingsCircles'] = [
          {'id': 'san', 'quota': 10.0},
        ];
      final writes = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'readState') return jsonEncode(original);
            if (call.method == 'writeSplitState') {
              writes.add(Map<dynamic, dynamic>.from(call.arguments as Map));
              return true;
            }
            throw PlatformException(code: 'UNEXPECTED_METHOD');
          });
      final state = await NativeStateStore.load();
      await NativeStateStore.save(state);
      await NativeStateStore.flush();
      final main = jsonDecode(writes.single['state'] as String) as Map;
      final parts = writes.single['parts'] as Map;
      for (final key in ['budgetPlans', 'sharedSavings', 'savingsCircles']) {
        expect(main.containsKey(key), isFalse);
        expect(jsonDecode(parts[key] as String), state[key]);
      }
      ((state['sharedSavings'] as List).first as Map)['history'] = [
        {'amountUsd': 15.25, 'type': 'deposit'},
      ];
      await NativeStateStore.save(state);
      await NativeStateStore.flush();
      expect(writes.last['parts'], hasLength(1));
      expect((writes.last['parts'] as Map).keys, ['sharedSavings']);
    },
  );
}
