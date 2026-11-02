import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const backupMaxBytes = 32 * 1024 * 1024;
const _iterations = 600000;
const _format = 'sin-rial-portable';
const _aad = 'sin-rial-portable:1:pbkdf2-sha256:600000:aes-256-gcm';

bool isDeviceOnlyBackupKey(String key) =>
    key.startsWith('pin') ||
    key.startsWith('biometric') ||
    key.startsWith('dismissedUpdate') ||
    const {
      'nativeSecurityV1',
      'securitySetupComplete',
      'seenFeatureTour',
      'pendingAppTour',
      'lastUpdateCheckMillis',
    }.contains(key);

const _recordCollections = {
  'accounts',
  'movements',
  'debts',
  'budgets',
  'budgetPlans',
  'goals',
  'cards',
  'balanceAdjustments',
  'sharedSavings',
  'savingsCircles',
  'customCategories',
  'recurringMovements',
  'usdtRateHistory',
  'bcvRateSnapshots',
};

Map<String, dynamic> validatePortableState(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['accounts'] is! List ||
      value['movements'] is! List) {
    throw const FormatException('La copia no contiene datos de Sin Rial.');
  }
  void validateJson(Object? item, int depth) {
    if (depth > 32) throw const FormatException('Copia demasiado compleja.');
    if (item is Map) {
      for (final entry in item.entries) {
        if (entry.key is! String) {
          throw const FormatException('Clave no valida.');
        }
        validateJson(entry.value, depth + 1);
      }
    } else if (item is List) {
      for (final child in item) {
        validateJson(child, depth + 1);
      }
    } else if (item is num && !item.isFinite) {
      throw const FormatException('Importe no valido.');
    } else if (item != null &&
        item is! String &&
        item is! num &&
        item is! bool) {
      throw const FormatException('Dato no compatible.');
    }
  }

  validateJson(value, 0);
  for (final key in _recordCollections) {
    if (!value.containsKey(key)) continue;
    final records = value[key];
    if (records is! List || records.any((record) => record is! Map)) {
      throw FormatException('Coleccion no valida: $key');
    }
    final ids = <String>{};
    for (final record in records.cast<Map>()) {
      final id = record['id'];
      if (id != null && (id is! String || id.isEmpty || !ids.add(id))) {
        throw FormatException('Identificador no valido: $key');
      }
      if ((key == 'accounts' || key == 'movements') && id == null) {
        throw FormatException('Falta un identificador: $key');
      }
    }
  }
  if (value.containsKey('savingsFunds') && value['savingsFunds'] is! Map) {
    throw const FormatException('Fondos no validos.');
  }
  return Map<String, dynamic>.from(value)
    ..removeWhere((key, _) => isDeviceOnlyBackupKey(key));
}

Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: _iterations,
  bits: 256,
).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

void _validatePassword(String password) {
  if (password.length < 10 || password.length > 256) {
    throw const FormatException('Usa una contrasena de 10 a 256 caracteres.');
  }
}

// Called on a worker isolate: key derivation never blocks animation or input.
Future<Uint8List> encryptPortableBackup(Map<String, dynamic> request) async {
  final password = request['password'] as String;
  _validatePassword(password);
  final state = validatePortableState(request['state']);
  final payload = utf8.encode(
    jsonEncode({
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': request['appVersion'],
      'state': state,
    }),
  );
  if (payload.length > backupMaxBytes * 3 ~/ 4 - 2048) {
    throw const FormatException('La copia supera el limite de 32 MB.');
  }
  final cipher = AesGcm.with256bits();
  final saltBytes = await (await cipher.newSecretKey()).extractBytes();
  final key = await _key(password, saltBytes);
  final box = await cipher.encrypt(
    payload,
    secretKey: key,
    aad: utf8.encode(_aad),
  );
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': _format,
        'version': 1,
        'kdf': 'pbkdf2-sha256',
        'iterations': _iterations,
        'cipher': 'aes-256-gcm',
        'salt': base64Encode(saltBytes),
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'data': base64Encode(box.cipherText),
      }),
    ),
  );
}

Future<Map<String, dynamic>> decryptPortableBackup(
  Map<String, dynamic> request,
) async {
  final bytes = request['bytes'] as Uint8List;
  final password = request['password'] as String;
  _validatePassword(password);
  if (bytes.isEmpty || bytes.length > backupMaxBytes) {
    throw const FormatException('Archivo vacio o mayor de 32 MB.');
  }
  final envelope = jsonDecode(utf8.decode(bytes));
  if (envelope is! Map ||
      envelope['format'] != _format ||
      envelope['version'] != 1 ||
      envelope['kdf'] != 'pbkdf2-sha256' ||
      envelope['iterations'] != _iterations ||
      envelope['cipher'] != 'aes-256-gcm') {
    throw const FormatException('Formato de copia no compatible.');
  }
  List<int> field(String name, int? length) {
    final raw = envelope[name];
    if (raw is! String) throw const FormatException('Copia incompleta.');
    final result = base64Decode(raw);
    if (length != null && result.length != length) {
      throw const FormatException('Copia incompleta.');
    }
    return result;
  }

  final salt = field('salt', 32);
  final box = SecretBox(
    field('data', null),
    nonce: field('nonce', 12),
    mac: Mac(field('mac', 16)),
  );
  final key = await _key(password, salt);
  final clear = await AesGcm.with256bits().decrypt(
    box,
    secretKey: key,
    aad: utf8.encode(_aad),
  );
  final payload = jsonDecode(utf8.decode(clear));
  if (payload is! Map ||
      payload['createdAt'] is! String ||
      DateTime.tryParse(payload['createdAt'] as String) == null) {
    throw const FormatException('Contenido de copia no valido.');
  }
  return {
    'createdAt': payload['createdAt'],
    'state': validatePortableState(payload['state']),
  };
}
