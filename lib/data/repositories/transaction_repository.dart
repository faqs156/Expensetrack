import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:uuid/uuid.dart';

import '../../core/date_keys.dart';
import '../database/app_database.dart';
import '../models/transaction.dart';

class TransactionFilter {
  final DateTime? from;
  final DateTime? to;
  final String? categoryId;
  final TxType? type;
  final String? search;
  final TxSort sort;
  final bool ascending;

  const TransactionFilter({
    this.from,
    this.to,
    this.categoryId,
    this.type,
    this.search,
    this.sort = TxSort.date,
    this.ascending = false,
  });

  TransactionFilter copyWith({
    DateTime? from,
    DateTime? to,
    String? categoryId,
    TxType? type,
    String? search,
    TxSort? sort,
    bool? ascending,
    bool clearCategory = false,
    bool clearType = false,
    bool clearSearch = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return TransactionFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      type: clearType ? null : (type ?? this.type),
      search: clearSearch ? null : (search ?? this.search),
      sort: sort ?? this.sort,
      ascending: ascending ?? this.ascending,
    );
  }
}

enum TxSort { date, amount }

class MonthTotals {
  final int expensePaise;
  final int incomePaise;
  const MonthTotals({required this.expensePaise, required this.incomePaise});
  int get netPaise => incomePaise - expensePaise;
}

class CategorySpend {
  final String categoryId;
  final String name;
  final String iconKey;
  final int colorValue;
  final int amountPaise;
  const CategorySpend({
    required this.categoryId,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.amountPaise,
  });
}

class DailySpend {
  final DateTime day;
  final int amountPaise;
  const DailySpend({required this.day, required this.amountPaise});
}

class TransactionRepository {
  TransactionRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;
  final AppDatabase _db;
  final _uuid = const Uuid();

  static const _joinSelect = '''
    SELECT t.*, c.name AS category_name, c.icon_key AS category_icon_key,
           c.color_value AS category_color
    FROM transactions t
    INNER JOIN categories c ON c.id = t.category_id
  ''';

  Future<Transaction> insert({
    required int amountPaise,
    required TxType type,
    required String categoryId,
    required DateTime occurredAt,
    required PaymentMethod paymentMethod,
    String? description,
    String? importHash,
    String? id,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final tx = Transaction(
      id: id ?? _uuid.v4(),
      amountPaise: amountPaise,
      type: type,
      categoryId: categoryId,
      occurredAt: occurredAt,
      paymentMethod: paymentMethod,
      description: description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      createdAt: now,
      updatedAt: now,
      importHash: importHash,
    );
    await db.insert('transactions', tx.toMap());
    return (await getById(tx.id))!;
  }

  Future<void> update(Transaction tx) async {
    final db = await _db.database;
    final updated = tx.copyWith(updatedAt: DateTime.now());
    await db.update(
      'transactions',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [tx.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<Transaction?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.rawQuery('$_joinSelect WHERE t.id = ?', [id]);
    if (rows.isEmpty) return null;
    return Transaction.fromMap(rows.first);
  }

  Future<List<Transaction>> query(TransactionFilter filter) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (filter.from != null) {
      where.add('t.occurred_at >= ?');
      args.add(DateKeys.startOfDay(filter.from!).millisecondsSinceEpoch);
    }
    if (filter.to != null) {
      where.add('t.occurred_at <= ?');
      args.add(DateKeys.endOfDay(filter.to!).millisecondsSinceEpoch);
    }
    if (filter.categoryId != null) {
      where.add('t.category_id = ?');
      args.add(filter.categoryId);
    }
    if (filter.type != null) {
      where.add('t.type = ?');
      args.add(filter.type!.name);
    }
    if (filter.search != null && filter.search!.trim().isNotEmpty) {
      where.add("LOWER(IFNULL(t.description, '')) LIKE ?");
      args.add('%${filter.search!.trim().toLowerCase()}%');
    }

    final orderCol = filter.sort == TxSort.amount
        ? 't.amount_paise'
        : 't.occurred_at';
    final dir = filter.ascending ? 'ASC' : 'DESC';
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await db.rawQuery(
      '$_joinSelect $whereSql ORDER BY $orderCol $dir, t.created_at DESC',
      args,
    );
    return rows.map(Transaction.fromMap).toList();
  }

  Future<List<Transaction>> recent({int limit = 8, DateTime? month}) async {
    final filter = month == null
        ? const TransactionFilter()
        : TransactionFilter(
            from: DateKeys.startOfMonth(month),
            to: DateKeys.endOfMonth(month),
          );
    final list = await query(filter);
    return list.take(limit).toList();
  }

  Future<MonthTotals> monthTotals(DateTime month) async {
    final db = await _db.database;
    final from = DateKeys.startOfMonth(month).millisecondsSinceEpoch;
    final to = DateKeys.endOfMonth(month).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      '''
      SELECT type, SUM(amount_paise) AS total
      FROM transactions
      WHERE occurred_at >= ? AND occurred_at <= ?
      GROUP BY type
    ''',
      [from, to],
    );
    var expense = 0;
    var income = 0;
    for (final r in rows) {
      final t = r['type'] as String;
      final total = (r['total'] as int?) ?? 0;
      if (t == TxType.expense.name) expense = total;
      if (t == TxType.income.name) income = total;
    }
    return MonthTotals(expensePaise: expense, incomePaise: income);
  }

  Future<List<CategorySpend>> categoryBreakdown(
    DateTime month, {
    TxType type = TxType.expense,
  }) async {
    final db = await _db.database;
    final from = DateKeys.startOfMonth(month).millisecondsSinceEpoch;
    final to = DateKeys.endOfMonth(month).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      '''
      SELECT c.id, c.name, c.icon_key, c.color_value, SUM(t.amount_paise) AS total
      FROM transactions t
      INNER JOIN categories c ON c.id = t.category_id
      WHERE t.occurred_at >= ? AND t.occurred_at <= ? AND t.type = ?
      GROUP BY c.id
      ORDER BY total DESC
    ''',
      [from, to, type.name],
    );
    return rows
        .map(
          (r) => CategorySpend(
            categoryId: r['id'] as String,
            name: r['name'] as String,
            iconKey: r['icon_key'] as String,
            colorValue: r['color_value'] as int,
            amountPaise: r['total'] as int,
          ),
        )
        .toList();
  }

  Future<List<DailySpend>> dailyExpenses(DateTime month) async {
    final db = await _db.database;
    final from = DateKeys.startOfMonth(month).millisecondsSinceEpoch;
    final to = DateKeys.endOfMonth(month).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      '''
      SELECT occurred_at, amount_paise
      FROM transactions
      WHERE occurred_at >= ? AND occurred_at <= ? AND type = ?
    ''',
      [from, to, TxType.expense.name],
    );

    final map = <String, int>{};
    for (final r in rows) {
      final dt = DateTime.fromMillisecondsSinceEpoch(r['occurred_at'] as int);
      final key = DateKeys.dayKey(dt);
      map[key] = (map[key] ?? 0) + (r['amount_paise'] as int);
    }

    final start = DateKeys.startOfMonth(month);
    final end = DateKeys.endOfMonth(month);
    final days = <DailySpend>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      days.add(DailySpend(day: d, amountPaise: map[DateKeys.dayKey(d)] ?? 0));
    }
    return days;
  }

  Future<int> expenseInRange(
    DateTime from,
    DateTime to, {
    String? categoryId,
  }) async {
    final db = await _db.database;
    final where = <String>['type = ?', 'occurred_at >= ?', 'occurred_at <= ?'];
    final args = <Object?>[
      TxType.expense.name,
      DateKeys.startOfDay(from).millisecondsSinceEpoch,
      DateKeys.endOfDay(to).millisecondsSinceEpoch,
    ];
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    final result = await db.rawQuery(
      'SELECT SUM(amount_paise) AS total FROM transactions WHERE ${where.join(' AND ')}',
      args,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countAll() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM transactions');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<bool> importHashExists(String hash) async {
    final db = await _db.database;
    final rows = await db.query(
      'transactions',
      columns: ['id'],
      where: 'import_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> clearAll() async {
    final db = await _db.database;
    await db.delete('transactions');
  }
}
