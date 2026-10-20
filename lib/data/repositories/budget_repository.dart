import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/budget.dart';

class BudgetRepository {
  BudgetRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;
  final AppDatabase _db;

  Future<MonthlyBudget> getForMonth(String monthKey) async {
    final db = await _db.database;
    final rows = await db.query(
      'budgets',
      where: 'month_key = ?',
      whereArgs: [monthKey],
    );
    var overall = 0;
    final cats = <String, int>{};
    for (final r in rows) {
      final catId = r['category_id'] as String;
      final amount = r['amount_paise'] as int;
      if (catId.isEmpty) {
        overall = amount;
      } else {
        cats[catId] = amount;
      }
    }
    return MonthlyBudget(
      monthKey: monthKey,
      overallPaise: overall,
      categoryPaise: cats,
    );
  }

  Future<void> setOverall(String monthKey, int amountPaise) async {
    final db = await _db.database;
    await db.insert('budgets', {
      'month_key': monthKey,
      'category_id': '',
      'amount_paise': amountPaise,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setCategory(
    String monthKey,
    String categoryId,
    int amountPaise,
  ) async {
    final db = await _db.database;
    if (amountPaise <= 0) {
      await db.delete(
        'budgets',
        where: 'month_key = ? AND category_id = ?',
        whereArgs: [monthKey, categoryId],
      );
      return;
    }
    await db.insert('budgets', {
      'month_key': monthKey,
      'category_id': categoryId,
      'amount_paise': amountPaise,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> exportRows() async {
    final db = await _db.database;
    return db.query('budgets');
  }

  Future<void> restore(List<Map<String, Object?>> rows) async {
    final db = await _db.database;
    final batch = db.batch();
    batch.delete('budgets');
    for (final r in rows) {
      batch.insert('budgets', r);
    }
    await batch.commit(noResult: true);
  }
}
