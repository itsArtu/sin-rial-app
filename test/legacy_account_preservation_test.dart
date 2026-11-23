import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rial_flutter/main.dart';
import 'package:rial_flutter/portable_backup.dart';

Map<String, dynamic> legacyState() => {
  'accounts': [
    {
      'id': 'legacy',
      'provider': 'KONTIGO',
      'kind': 'wallet',
      'currency': 'USD',
      'balance': 80.0,
    },
    {
      'id': 'bank',
      'provider': '0102',
      'kind': 'national',
      'currency': 'USD',
      'balance': 20.0,
    },
  ],
  'movements': [
    {
      'id': 'income',
      'type': 'income',
      'accountId': 'legacy',
      'currency': 'USD',
      'amount': 100.0,
      'date': '2026-11-01',
    },
    {
      'id': 'transfer',
      'type': 'transfer',
      'accountId': 'legacy',
      'targetAccountId': 'bank',
      'currency': 'USD',
      'amount': 20.0,
      'targetAmount': 20.0,
      'date': '2026-11-02',
    },
  ],
  'balanceAdjustments': [
    {'id': 'adjustment', 'accountId': 'legacy', 'amount': 0.0},
  ],
  'recurringMovements': [
    {
      'id': 'recurring',
      'accountId': 'legacy',
      'type': 'expense',
      'currency': 'USD',
      'amount': 5.0,
      'frequency': 'monthly',
      'startDate': '2026-11-01',
    },
  ],
};

void expectHistoryPreserved(
  Map<String, dynamic> actual,
  Map<String, dynamic> original,
) {
  final accounts = (actual['accounts'] as List).cast<Map>();
  expect(accounts.map((a) => a['id']), ['legacy', 'bank']);
  expect(accounts.map((a) => a['balance']), [80.0, 20.0]);
  expect(accounts.first['provider'], 'KONTIGO');
  for (final key in ['movements', 'balanceAdjustments', 'recurringMovements']) {
    expect(actual[key], original[key], reason: key);
  }
}

void main() {
  test('Loading legacy data preserves retired accounts and both sides of transfers', () {
    final original = legacyState();
    final loaded = withDefaults(
      jsonDecode(jsonEncode(original)) as Map<String, dynamic>,
    );
    expectHistoryPreserved(loaded, original);
    expect(wallets.any((wallet) => wallet.first == 'KONTIGO'), isFalse);
  });

  test(
    'Encrypted backup round trip preserves retired account history',
    () async {
      final original = legacyState();
      final bytes = await encryptPortableBackup({
        'state': original,
        'password': 'Legacy-test-backup-111',
        'appVersion': '3.6.1+111',
      });
      final restored = await decryptPortableBackup({
        'bytes': bytes,
        'password': 'Legacy-test-backup-111',
      });
      expectHistoryPreserved(
        withDefaults(restored['state'] as Map<String, dynamic>),
        original,
      );
      expectHistoryPreserved(original, legacyState());
    },
  );
}
