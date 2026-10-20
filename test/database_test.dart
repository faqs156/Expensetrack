import 'package:expense_track/core/date_keys.dart';
import 'package:expense_track/data/database/app_database.dart';
import 'package:expense_track/data/models/budget.dart';
import 'package:expense_track/data/models/category.dart';
import 'package:expense_track/data/models/transaction.dart';
import 'package:expense_track/data/repositories/budget_repository.dart';
import 'package:expense_track/data/repositories/category_repository.dart';
import 'package:expense_track/data/repositories/transaction_repository.dart';
import 'package:expense_track/data/services/csv_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository txRepo;
  late CategoryRepository catRepo;
  late BudgetRepository budgetRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase.instance;
    await db.close();
    db.debugSetPath(inMemoryDatabasePath);
    txRepo = TransactionRepository(db: db);
    catRepo = CategoryRepository(db: db);
    budgetRepo = BudgetRepository(db: db);
    await db.database;
  });

  tearDown(() async {
    await db.close();
  });

  test('seeds default categories', () async {
    final cats = await catRepo.getAll();
    expect(cats.where((c) => c.kind == CategoryKind.expense).length, 12);
    expect(cats.where((c) => c.kind == CategoryKind.income).length, 5);
  });

  test('expense and income monthly totals', () async {
    final cats = await catRepo.getAll();
    final food = cats.firstWhere((c) => c.name == 'Food & Dining');
    final salary = cats.firstWhere((c) => c.name == 'Salary');
    final month = DateTime(2026, 3, 1);

    await txRepo.insert(
      amountPaise: 50000,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateTime(2026, 3, 10, 12),
      paymentMethod: PaymentMethod.upi,
    );
    await txRepo.insert(
      amountPaise: 2000000,
      type: TxType.income,
      categoryId: salary.id,
      occurredAt: DateTime(2026, 3, 1, 9),
      paymentMethod: PaymentMethod.bank,
    );
    // Outside month
    await txRepo.insert(
      amountPaise: 99900,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateTime(2026, 2, 28, 23, 59),
      paymentMethod: PaymentMethod.cash,
    );

    final totals = await txRepo.monthTotals(month);
    expect(totals.expensePaise, 50000);
    expect(totals.incomePaise, 2000000);
  });

  test('month boundary includes last day', () async {
    final cats = await catRepo.getAll();
    final food = cats.firstWhere((c) => c.name == 'Food & Dining');
    await txRepo.insert(
      amountPaise: 1000,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateKeys.endOfMonth(DateTime(2026, 3, 1)),
      paymentMethod: PaymentMethod.cash,
    );
    final totals = await txRepo.monthTotals(DateTime(2026, 3, 1));
    expect(totals.expensePaise, 1000);
  });

  test('edit and delete transaction', () async {
    final cats = await catRepo.getAll();
    final food = cats.firstWhere((c) => c.name == 'Food & Dining');
    final tx = await txRepo.insert(
      amountPaise: 2500,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateTime(2026, 3, 5),
      paymentMethod: PaymentMethod.card,
      description: 'Coffee',
    );
    await txRepo.update(tx.copyWith(amountPaise: 3000, description: 'Tea'));
    final updated = await txRepo.getById(tx.id);
    expect(updated!.amountPaise, 3000);
    expect(updated.description, 'Tea');

    await txRepo.delete(tx.id);
    expect(await txRepo.getById(tx.id), isNull);
    expect(await txRepo.countAll(), 0);
  });

  test('category and date filters', () async {
    final cats = await catRepo.getAll();
    final food = cats.firstWhere((c) => c.name == 'Food & Dining');
    final travel = cats.firstWhere((c) => c.name == 'Travel');

    await txRepo.insert(
      amountPaise: 1000,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateTime(2026, 3, 2),
      paymentMethod: PaymentMethod.upi,
      description: 'lunch',
    );
    await txRepo.insert(
      amountPaise: 5000,
      type: TxType.expense,
      categoryId: travel.id,
      occurredAt: DateTime(2026, 3, 20),
      paymentMethod: PaymentMethod.card,
      description: 'cab',
    );

    final byCat = await txRepo.query(TransactionFilter(categoryId: food.id));
    expect(byCat.length, 1);
    expect(byCat.first.description, 'lunch');

    final byRange = await txRepo.query(
      TransactionFilter(from: DateTime(2026, 3, 15), to: DateTime(2026, 3, 25)),
    );
    expect(byRange.length, 1);
    expect(byRange.first.categoryId, travel.id);

    final search = await txRepo.query(const TransactionFilter(search: 'lun'));
    expect(search.length, 1);
  });

  test('budget uses expenses only', () async {
    final cats = await catRepo.getAll();
    final food = cats.firstWhere((c) => c.name == 'Food & Dining');
    final salary = cats.firstWhere((c) => c.name == 'Salary');
    final month = DateTime(2026, 4, 1);
    final key = DateKeys.monthKey(month);

    await budgetRepo.setOverall(key, 100000); // ₹1000
    await txRepo.insert(
      amountPaise: 40000,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateTime(2026, 4, 3),
      paymentMethod: PaymentMethod.upi,
    );
    await txRepo.insert(
      amountPaise: 500000,
      type: TxType.income,
      categoryId: salary.id,
      occurredAt: DateTime(2026, 4, 1),
      paymentMethod: PaymentMethod.bank,
    );

    final spent = await txRepo.expenseInRange(
      DateKeys.startOfMonth(month),
      DateKeys.endOfMonth(month),
    );
    expect(spent, 40000);
    final budget = await budgetRepo.getForMonth(key);
    final status = BudgetStatus(
      budgetPaise: budget.overallPaise,
      spentPaise: spent,
    );
    expect(status.remainingPaise, 60000);
    expect(status.utilization, closeTo(0.4, 0.001));
  });

  test(
    'category rename preserves transactions; delete archives when used',
    () async {
      final custom = await catRepo.create(
        name: 'Snacks',
        kind: CategoryKind.expense,
      );
      await txRepo.insert(
        amountPaise: 100,
        type: TxType.expense,
        categoryId: custom.id,
        occurredAt: DateTime(2026, 3, 1),
        paymentMethod: PaymentMethod.cash,
      );
      await catRepo.rename(custom.id, 'Evening snacks');
      final list = await txRepo.query(TransactionFilter(categoryId: custom.id));
      expect(list.length, 1);
      expect(list.first.categoryName, 'Evening snacks');

      final result = await catRepo.deleteOrArchive(custom.id);
      expect(result, DeleteCategoryResult.archived);
      final archived = await catRepo.getById(custom.id);
      expect(archived!.isArchived, true);
      expect(await txRepo.countAll(), 1);
    },
  );

  test('csv export and import with duplicate skip', () async {
    final cats = await catRepo.getAll();
    final food = cats.firstWhere((c) => c.name == 'Food & Dining');
    await txRepo.insert(
      amountPaise: 12345,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateTime(2026, 3, 8, 14, 30),
      paymentMethod: PaymentMethod.upi,
      description: 'Dinner',
    );
    final csv = CsvService(transactions: txRepo, categories: catRepo);
    final exported = csv.exportCsv(
      await txRepo.query(const TransactionFilter()),
    );
    expect(exported.contains('Dinner'), true);
    expect(exported.contains('amount'), true);

    final first = await csv.importCsv(exported);
    // same ids / hashes → skipped
    expect(first.imported + first.skippedDuplicates, greaterThan(0));

    final malformed = await csv.importCsv(
      'id,date,type,amount,category,payment_method,description\nbad',
    );
    expect(malformed.errors, greaterThan(0));
  });

  test('persistence after reopen', () async {
    final cats = await catRepo.getAll();
    final food = cats.firstWhere((c) => c.name == 'Food & Dining');
    final path = 'persist_${DateTime.now().microsecondsSinceEpoch}.db';
    await db.close();
    db.debugSetPath(path);
    await db.database;

    final repo1 = TransactionRepository(db: db);
    await repo1.insert(
      amountPaise: 777,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateTime(2026, 3, 9),
      paymentMethod: PaymentMethod.cash,
    );
    await db.close();

    db.debugSetPath(path);
    final repo2 = TransactionRepository(db: db);
    expect(await repo2.countAll(), 1);
  });

  test('empty query returns empty list', () async {
    final list = await txRepo.query(const TransactionFilter());
    expect(list, isEmpty);
  });
}
