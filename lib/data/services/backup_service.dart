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

  /// Restores a vault. By default **merges** with the current local DB so
  /// Drive / Sync never deletes transactions that exist only on this device.
  Future<void> restoreBackupJson(
    String json, {
    bool mergeWithLocal = true,
  }) async {
    var incoming = json;
    if (mergeWithLocal) {
      final current = await createBackupJson();
      if (_staticTxCount(current) > 0) {
        incoming = mergeVaultJson(current, json);
      }
    }

    final decoded = jsonDecode(incoming);
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

  static int _staticTxCount(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return 0;
      final txs = decoded['transactions'];
      return txs is List ? txs.length : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Merge many vault snapshots (order does not matter for transactions).
  static String mergeVaultJsonAll(Iterable<String> jsons) {
    String? acc;
    for (final j in jsons) {
      if (j.trim().isEmpty) continue;
      acc = acc == null ? j : mergeVaultJson(acc, j);
    }
    if (acc == null) {
      throw const FormatException('No vault JSON to merge');
    }
    return acc;
  }

  /// Merge two vault JSON snapshots so edits from different devices are kept.
  ///
  /// Transactions/categories conflict by id → keep newer [updated_at].
  /// Budgets conflict by month+category → keep higher amount.
  /// Settings conflict by key → keep [preferSide] ('local' or 'remote').
  static String mergeVaultJson(
    String localJson,
    String remoteJson, {
    String preferSettings = 'local',
  }) {
    final local = jsonDecode(localJson);
    final remote = jsonDecode(remoteJson);
    if (local is! Map || remote is! Map) {
      throw const FormatException('Invalid backup JSON for merge');
    }

    final localMap = Map<String, dynamic>.from(local);
    final remoteMap = Map<String, dynamic>.from(remote);

    final categories = _mergeById(
      _staticAsMaps(localMap['categories']),
      _staticAsMaps(remoteMap['categories']),
      idOf: (r) => '${r['id'] ?? ''}',
      isNewer: (a, b) => _rowUpdatedMs(a) >= _rowUpdatedMs(b),
    );
    final transactions = _mergeById(
      _staticAsMaps(localMap['transactions']),
      _staticAsMaps(remoteMap['transactions']),
      idOf: (r) => '${r['id'] ?? ''}',
      isNewer: (a, b) => _rowUpdatedMs(a) >= _rowUpdatedMs(b),
    );
    final budgets = _mergeById(
      _staticAsMaps(localMap['budgets']),
      _staticAsMaps(remoteMap['budgets']),
      idOf: (r) => '${r['month_key'] ?? ''}\u0000${r['category_id'] ?? ''}',
      isNewer: (a, b) {
        final aa = _asIntStatic(a['amount_paise'], 0);
        final bb = _asIntStatic(b['amount_paise'], 0);
        return aa >= bb;
      },
    );
    final settings = _mergeById(
      _staticAsMaps(localMap['settings']),
      _staticAsMaps(remoteMap['settings']),
      idOf: (r) => '${r['key'] ?? ''}',
      // When processing remote rows: replace local only if we prefer remote.
      isNewer: (incoming, existing) => preferSettings == 'remote',
    );

    final now = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'version': 1,
      'created_at': localMap['created_at'] ?? remoteMap['created_at'] ?? now,
      'updated_at': now,
      'categories': categories,
      'transactions': transactions,
      'budgets': budgets,
      'settings': settings,
      'sync_target': 'google_drive_appdata',
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static List<Map<String, Object?>> _staticAsMaps(dynamic value) {
    if (value is! List) return [];
    return value.map((e) => Map<String, Object?>.from(e as Map)).toList();
  }

  static int _asIntStatic(Object? value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  static int _rowUpdatedMs(Map<String, Object?> row) {
    return _asIntStatic(row['updated_at'], _asIntStatic(row['created_at'], 0));
  }

  static List<Map<String, Object?>> _mergeById(
    List<Map<String, Object?>> a,
    List<Map<String, Object?>> b, {
    required String Function(Map<String, Object?>) idOf,
    required bool Function(Map<String, Object?>, Map<String, Object?>) isNewer,
  }) {
    final out = <String, Map<String, Object?>>{};
    for (final row in a) {
      final id = idOf(row);
      if (id.isEmpty) continue;
      out[id] = row;
    }
    for (final row in b) {
      final id = idOf(row);
      if (id.isEmpty) continue;
      final existing = out[id];
      if (existing == null || isNewer(row, existing)) {
        out[id] = row;
      }
    }
    return out.values.toList();
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
