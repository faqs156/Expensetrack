import 'package:expense_track/data/database/app_database.dart';
import 'package:expense_track/data/database/database_init.dart';
import 'package:expense_track/data/models/category.dart';
import 'package:expense_track/data/models/transaction.dart';
import 'package:expense_track/data/repositories/category_repository.dart';
import 'package:expense_track/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// VM/native tests exercise the stub init path plus CRUD through AppDatabase.
/// Web factory (`databaseFactoryFfiWeb`) is selected only when compiled for
/// `dart.library.html` and is covered by package docs + manual web smoke.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Stub init must not throw and must not block tests from installing FFI.
    await initializeDatabaseFactory();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('initializeDatabaseFactory is safe to call more than once on VM', () async {
    await initializeDatabaseFactory();
    await initializeDatabaseFactory();
  });

  test('AppDatabase schema version 2 creates after factory init', () async {
    final db = AppDatabase.instance;
    await db.close();
    db.debugSetPath(
      'init_schema_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final database = await db.database;
    final version = await database.getVersion();
    expect(version, 2);

    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((r) => r['name'] as String).toSet();
    expect(names.contains('categories'), isTrue);
    expect(names.contains('transactions'), isTrue);
    expect(names.contains('budgets'), isTrue);
    expect(names.contains('settings'), isTrue);
  });

  test('basic CRUD after initializeDatabaseFactory', () async {
    final db = AppDatabase.instance;
    await db.close();
    db.debugSetPath(inMemoryDatabasePath);
    final catRepo = CategoryRepository(db: db);
    final txRepo = TransactionRepository(db: db);
    await db.database;

    final cats = await catRepo.getAll();
    final food = cats.firstWhere((c) => c.kind == CategoryKind.expense);

    final created = await txRepo.insert(
      amountPaise: 2500,
      type: TxType.expense,
      categoryId: food.id,
      occurredAt: DateTime(2026, 5, 1, 10),
      paymentMethod: PaymentMethod.upi,
      description: 'init-crud',
    );
    expect(created.id, isNotEmpty);

    final read = await txRepo.getById(created.id);
    expect(read?.amountPaise, 2500);
    expect(read?.description, 'init-crud');

    await txRepo.update(created.copyWith(amountPaise: 3000, description: 'upd'));
    final updated = await txRepo.getById(created.id);
    expect(updated?.amountPaise, 3000);
    expect(updated?.description, 'upd');

    await txRepo.delete(created.id);
    expect(await txRepo.getById(created.id), isNull);
  });

  test('foreign keys and unique import_hash index still apply', () async {
    final db = AppDatabase.instance;
    await db.close();
    db.debugSetPath(inMemoryDatabasePath);
    final database = await db.database;

    final fk = await database.rawQuery('PRAGMA foreign_keys');
    expect(fk.first.values.first, 1);

    final indexes = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    );
    final indexNames = indexes.map((r) => r['name'] as String).toSet();
    expect(indexNames.contains('idx_tx_import_hash'), isTrue);
    expect(indexNames.contains('idx_tx_occurred'), isTrue);
  });
}
