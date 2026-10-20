import 'dart:convert';

import '../database/app_database.dart';

class BackupService {
  BackupService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;
  final AppDatabase _db;

  /// Full vault snapshot: categories, transactions, budgets, settings.
  Future<String> createBackupJson() async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'version': 1,
      'created_at': now,
      'updated_at': now,
      'categories': await db.query('categories'),
      'transactions': await db.query('transactions'),
      'budgets': await db.query('budgets'),
      'settings': await db.query('settings'),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> restoreBackupJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup file');
    }
    if (decoded['version'] != 1) {
      throw FormatException(
        'Unsupported backup version: ${decoded['version']}',
      );
    }

    final categories = _asMaps(decoded['categories']).map(_normalizeCategory);
    final transactions =
        _asMaps(decoded['transactions']).map(_normalizeTransaction);
    final budgets = _asMaps(decoded['budgets']).map(_normalizeBudget);
    final settings = _asMaps(decoded['settings']).map(_normalizeSetting);

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('budgets');
      await txn.delete('categories');
      await txn.delete('settings');

      final batch = txn.batch();
      for (final r in categories) {
        batch.insert('categories', r);
      }
      for (final r in settings) {
        batch.insert('settings', r);
      }
      for (final r in budgets) {
        batch.insert('budgets', r);
      }
      for (final r in transactions) {
        batch.insert('transactions', r);
      }
      await batch.commit(noResult: true);
    });
  }

  List<Map<String, Object?>> _asMaps(dynamic value) {
    if (value is! List) return [];
    return value.map((e) {
      return Map<String, Object?>.from(e as Map);
    }).toList();
  }

  Map<String, Object?> _normalizeCategory(Map<String, Object?> r) {
    return {
      'id': '${r['id'] ?? ''}',
      'name': '${r['name'] ?? ''}',
      'kind': '${r['kind'] ?? 'expense'}',
      'icon_key': '${r['icon_key'] ?? 'category'}',
      'color_value': _asInt(r['color_value'], 0xFF607D8B),
      'is_default': _asInt(r['is_default'], 0),
      'is_archived': _asInt(r['is_archived'], 0),
      'sort_order': _asInt(r['sort_order'], 0),
    };
  }

  Map<String, Object?> _normalizeTransaction(Map<String, Object?> r) {
    return {
      'id': '${r['id'] ?? ''}',
      'amount_paise': _asInt(r['amount_paise'], 0),
      'type': '${r['type'] ?? 'expense'}',
      'category_id': '${r['category_id'] ?? ''}',
      'occurred_at': _asInt(r['occurred_at'], 0),
      'payment_method': '${r['payment_method'] ?? 'other'}',
      'description': r['description'] == null ? null : '${r['description']}',
      'created_at': _asInt(r['created_at'], 0),
      'updated_at': _asInt(r['updated_at'], 0),
      'import_hash': r['import_hash'] == null ? null : '${r['import_hash']}',
    };
  }

  Map<String, Object?> _normalizeBudget(Map<String, Object?> r) {
    // Overall budget uses empty category_id — never null (breaks PRIMARY KEY).
    final cat = r['category_id'];
    return {
      'month_key': '${r['month_key'] ?? ''}',
      'category_id': cat == null ? '' : '$cat',
      'amount_paise': _asInt(r['amount_paise'], 0),
    };
  }

  Map<String, Object?> _normalizeSetting(Map<String, Object?> r) {
    return {
      'key': '${r['key'] ?? ''}',
      'value': '${r['value'] ?? ''}',
    };
  }

  int _asInt(Object? value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}
