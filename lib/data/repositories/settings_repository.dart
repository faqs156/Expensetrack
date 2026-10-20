import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;
  final AppDatabase _db;

  Future<AppSettings> load() async {
    final db = await _db.database;
    final rows = await db.query('settings');
    final map = {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
    return AppSettings(
      theme: ThemePreference.values.byName(map['theme'] ?? 'system'),
      currencyCode: map['currency_code'] ?? 'INR',
      currencySymbol: map['currency_symbol'] ?? '₹',
      defaultOverallBudgetPaise:
          int.tryParse(map['default_budget_paise'] ?? '0') ?? 0,
    );
  }

  Future<void> save(AppSettings settings) async {
    final db = await _db.database;
    Future<void> put(String key, String value) async {
      await db.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await put('theme', settings.theme.name);
    await put('currency_code', settings.currencyCode);
    await put('currency_symbol', settings.currencySymbol);
    await put(
      'default_budget_paise',
      settings.defaultOverallBudgetPaise.toString(),
    );
  }

  Future<Map<String, String>> exportMap() async {
    final db = await _db.database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<void> restore(Map<String, String> map) async {
    final db = await _db.database;
    final batch = db.batch();
    batch.delete('settings');
    for (final e in map.entries) {
      batch.insert('settings', {'key': e.key, 'value': e.value});
    }
    await batch.commit(noResult: true);
  }
}
