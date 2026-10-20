import 'dart:convert';

import 'package:expense_track/data/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeVaultJson keeps transactions from both devices', () {
    final local = jsonEncode({
      'version': 1,
      'categories': [
        {'id': 'c1', 'name': 'Food', 'kind': 'expense'},
      ],
      'transactions': [
        {
          'id': 'mac-1',
          'amount_paise': 100,
          'type': 'expense',
          'category_id': 'c1',
          'updated_at': 1000,
          'created_at': 1000,
        },
      ],
      'budgets': [],
      'settings': [
        {'key': 'theme', 'value': 'light'},
      ],
    });
    final remote = jsonEncode({
      'version': 1,
      'categories': [
        {'id': 'c1', 'name': 'Food', 'kind': 'expense'},
        {'id': 'c2', 'name': 'Travel', 'kind': 'expense'},
      ],
      'transactions': [
        {
          'id': 'phone-1',
          'amount_paise': 250,
          'type': 'expense',
          'category_id': 'c2',
          'updated_at': 2000,
          'created_at': 2000,
        },
      ],
      'budgets': [],
      'settings': [
        {'key': 'theme', 'value': 'dark'},
      ],
    });

    final merged = jsonDecode(BackupService.mergeVaultJson(local, remote))
        as Map<String, dynamic>;
    final txs = (merged['transactions'] as List)
        .map((e) => (e as Map)['id'])
        .toSet();
    expect(txs, containsAll(['mac-1', 'phone-1']));
    expect((merged['categories'] as List).length, 2);
    // Local settings preferred by default.
    final theme = (merged['settings'] as List)
        .cast<Map>()
        .firstWhere((e) => e['key'] == 'theme')['value'];
    expect(theme, 'light');
  });

  test('mergeVaultJsonAll recovers txs from safety + prev Drive', () {
    final local = jsonEncode({
      'version': 1,
      'categories': [],
      'transactions': [
        {'id': 'a', 'amount_paise': 1, 'updated_at': 1, 'created_at': 1},
      ],
      'budgets': [],
      'settings': [],
    });
    final olderDrive = jsonEncode({
      'version': 1,
      'categories': [],
      'transactions': [
        {'id': 'b', 'amount_paise': 2, 'updated_at': 2, 'created_at': 2},
      ],
      'budgets': [],
      'settings': [],
    });
    final safety = jsonEncode({
      'version': 1,
      'categories': [],
      'transactions': [
        {'id': 'c', 'amount_paise': 3, 'updated_at': 3, 'created_at': 3},
      ],
      'budgets': [],
      'settings': [],
    });

    final merged = jsonDecode(
      BackupService.mergeVaultJsonAll([local, olderDrive, safety]),
    ) as Map<String, dynamic>;
    final ids =
        (merged['transactions'] as List).map((e) => (e as Map)['id']).toSet();
    expect(ids, containsAll(['a', 'b', 'c']));
  });

  test('mergeVaultJson honors cleared_at wipe so Clear all stays cleared', () {
    final wiped = jsonEncode({
      'version': 1,
      'cleared_at': '2026-10-20T12:00:00.000Z',
      'categories': [],
      'transactions': [],
      'budgets': [],
      'settings': [
        {'key': 'vault_cleared_at', 'value': '2026-10-20T12:00:00.000Z'},
      ],
    });
    final oldPeer = jsonEncode({
      'version': 1,
      'categories': [],
      'transactions': [
        {
          'id': 'old-1',
          'amount_paise': 500,
          'updated_at': DateTime.utc(2026, 10, 19).millisecondsSinceEpoch,
          'created_at': DateTime.utc(2026, 10, 19).millisecondsSinceEpoch,
        },
      ],
      'budgets': [
        {'month_key': '2026-10', 'category_id': '', 'amount_paise': 1000},
      ],
      'settings': [],
    });

    final merged =
        jsonDecode(BackupService.mergeVaultJson(wiped, oldPeer))
            as Map<String, dynamic>;
    expect(merged['transactions'], isEmpty);
    expect(merged['budgets'], isEmpty);
    expect(merged['cleared_at'], '2026-10-20T12:00:00.000Z');
  });

  test('mergeVaultJson prefers newer transaction on same id', () {
    final local = jsonEncode({
      'version': 1,
      'categories': [],
      'transactions': [
        {
          'id': 't1',
          'amount_paise': 100,
          'updated_at': 1000,
          'created_at': 1000,
        },
      ],
      'budgets': [],
      'settings': [],
    });
    final remote = jsonEncode({
      'version': 1,
      'categories': [],
      'transactions': [
        {
          'id': 't1',
          'amount_paise': 999,
          'updated_at': 5000,
          'created_at': 1000,
        },
      ],
      'budgets': [],
      'settings': [],
    });

    final merged = jsonDecode(BackupService.mergeVaultJson(local, remote))
        as Map<String, dynamic>;
    final tx = (merged['transactions'] as List).first as Map;
    expect(tx['amount_paise'], 999);
  });
}
