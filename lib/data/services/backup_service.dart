import 'dart:convert';

import '../database/app_database.dart';

class BackupService {
  BackupService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;
  final AppDatabase _db;

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

    final categories = _asMaps(decoded['categories']);
    final transactions = _asMaps(decoded['transactions']);
    final budgets = _asMaps(decoded['budgets']);
    final settings = _asMaps(decoded['settings']);

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
      final m = Map<String, Object?>.from(e as Map);
      return m;
    }).toList();
  }
}
