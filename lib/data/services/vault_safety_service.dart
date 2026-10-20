import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// Keeps recent full-vault JSON snapshots on-device so a bad Drive pull / sign-out
/// cycle cannot permanently erase transactions that still existed locally.
class VaultSafetyService {
  VaultSafetyService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;
  final AppDatabase _db;

  static const latestId = 'latest';
  static const preSignOutId = 'pre_signout';
  static const preRestoreId = 'pre_restore';

  Future<void> save(String id, String json) async {
    final count = _txCount(json);
    if (count <= 0 && id != preRestoreId) return;
    final db = await _db.database;
    final row = {
      'id': id,
      'json': json,
      'saved_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      'tx_count': count,
    };
    await db.insert(
      'vault_snapshots',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Mirror into "latest" when this snapshot is at least as rich.
    if (id != latestId) {
      final latest = await read(latestId);
      if (latest == null || count >= _txCount(latest)) {
        await db.insert(
          'vault_snapshots',
          {
            ...row,
            'id': latestId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  Future<String?> read(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'vault_snapshots',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final json = rows.first['json'] as String?;
    if (json == null || json.trim().isEmpty) return null;
    return json;
  }

  /// Best on-device snapshot (most transactions, then newest).
  Future<String?> readBest() async {
    final db = await _db.database;
    final rows = await db.query(
      'vault_snapshots',
      orderBy: 'tx_count DESC, saved_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final json = rows.first['json'] as String?;
    if (json == null || json.trim().isEmpty) return null;
    return json;
  }

  /// Drop all snapshots (required after an intentional account wipe).
  Future<void> clearAll() async {
    final db = await _db.database;
    await db.delete('vault_snapshots');
  }

  static int _txCount(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return 0;
      final txs = decoded['transactions'];
      return txs is List ? txs.length : 0;
    } catch (_) {
      return 0;
    }
  }
}
