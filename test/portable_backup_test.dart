import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/portable_backup.dart';

void main() {
  const password = 'Prueba-copia-2026';
  final state = <String, dynamic>{
    'userName': 'Private name',
    'pinHash': 'secret',
    'pinSalt': 'salt',
    'pinEnabled': true,
    'nativeSecurityV1': true,
    'biometricEnabled': true,
    'securitySetupComplete': true,
    'themeColor': 'blue',
    'accounts': [
      {'id': 'a', 'balance': 123.45, 'currency': 'USD'},
    ],
    'movements': [
      {'id': 'm', 'accountId': 'a', 'amount': 12.34, 'rate': 889.579},
    ],
    'debts': [
      {'id': 'd', 'paidAmount': 5.25, 'amount': 20},
    ],
    'savingsFunds': {
      'Emergency': {
        'history': [
          {'amount': 3.25},
        ],
      },
    },
    'futurePreference': {'preserved': true},
  };
  late Uint8List encrypted;
  setUpAll(() async {
    encrypted = await encryptPortableBackup({
      'state': state,
      'password': password,
      'appVersion': '3.5.1+99',
    });
  });
  test(
    'portable encrypted roundtrip preserves data but never device security',
    () async {
      final raw = utf8.decode(encrypted);
      expect(raw, isNot(contains('Private name')));
      expect(raw, isNot(contains('123.45')));
      final result = await decryptPortableBackup({
        'bytes': encrypted,
        'password': password,
      });
      final restored = result['state'] as Map;
      expect(restored['accounts'], state['accounts']);
      expect(restored['movements'], state['movements']);
      expect(restored['savingsFunds'], state['savingsFunds']);
      expect(restored['futurePreference'], state['futurePreference']);
      for (final field in [
        'pinHash',
        'pinSalt',
        'pinEnabled',
        'nativeSecurityV1',
        'biometricEnabled',
        'securitySetupComplete',
      ]) {
        expect(restored.containsKey(field), isFalse, reason: field);
      }
      expect(state['pinHash'], 'secret');
    },
  );
  test(
    'incorrect password and changed authentication tag are rejected',
    () async {
      await expectLater(
        decryptPortableBackup({
          'bytes': encrypted,
          'password': 'incorrect-password',
        }),
        throwsA(anything),
      );
      final envelope = jsonDecode(utf8.decode(encrypted)) as Map;
      final mac = base64Decode(envelope['mac'] as String);
      mac[0] ^= 1;
      envelope['mac'] = base64Encode(mac);
      await expectLater(
        decryptPortableBackup({
          'bytes': Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          'password': password,
        }),
        throwsA(anything),
      );
    },
  );
  test(
    'unsupported format, expensive KDF, and malformed records are rejected',
    () async {
      final envelope = jsonDecode(utf8.decode(encrypted)) as Map;
      envelope['iterations'] = 999999999;
      await expectLater(
        decryptPortableBackup({
          'bytes': Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          'password': password,
        }),
        throwsFormatException,
      );
      expect(
        () => validatePortableState({'accounts': 'broken', 'movements': []}),
        throwsFormatException,
      );
      expect(
        () => validatePortableState({
          'accounts': [
            {'id': 'a'},
            {'id': 'a'},
          ],
          'movements': [],
        }),
        throwsFormatException,
      );
      expect(
        () => validatePortableState({
          'accounts': [],
          'movements': [
            {'id': 'm', 'amount': double.nan},
          ],
        }),
        throwsFormatException,
      );
    },
  );
}
