import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/category.dart';

class CategoryRepository {
  CategoryRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;
  final AppDatabase _db;
  final _uuid = const Uuid();

  Future<List<ExpenseCategory>> getAll({bool includeArchived = false}) async {
    final db = await _db.database;
    final rows = await db.query(
      'categories',
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'kind ASC, sort_order ASC, name ASC',
    );
    return rows.map(ExpenseCategory.fromMap).toList();
  }

  Future<List<ExpenseCategory>> byKind(CategoryKind kind) async {
    final db = await _db.database;
    final rows = await db.query(
      'categories',
      where: 'kind = ? AND is_archived = 0',
      whereArgs: [kind.name],
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(ExpenseCategory.fromMap).toList();
  }

  Future<ExpenseCategory?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ExpenseCategory.fromMap(rows.first);
  }

  Future<ExpenseCategory> create({
    required String name,
    required CategoryKind kind,
    String iconKey = 'custom',
    int colorValue = 0xFF0D9488,
  }) async {
    final db = await _db.database;
    final cat = ExpenseCategory(
      id: _uuid.v4(),
      name: name.trim(),
      kind: kind,
      iconKey: iconKey,
      colorValue: colorValue,
      isDefault: false,
      sortOrder: 999,
    );
    await db.insert('categories', cat.toMap());
    return cat;
  }

  Future<void> rename(String id, String name) async {
    final db = await _db.database;
    await db.update(
      'categories',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> transactionCount(String categoryId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions WHERE category_id = ?',
      [categoryId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Archives if transactions exist; deletes only when unused.
  Future<DeleteCategoryResult> deleteOrArchive(String id) async {
    final db = await _db.database;
    final cat = await getById(id);
    if (cat == null) return DeleteCategoryResult.notFound;
    final count = await transactionCount(id);
    if (count > 0) {
      await db.update(
        'categories',
        {'is_archived': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return DeleteCategoryResult.archived;
    }
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    return DeleteCategoryResult.deleted;
  }
}

enum DeleteCategoryResult { deleted, archived, notFound }
