import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../seed/default_categories.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  String? _overridePath;

  /// For tests — inject an in-memory or temp path before [database] is opened.
  void debugSetPath(String path) {
    _overridePath = path;
    _db = null;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path =
        _overridePath ?? p.join(await getDatabasesPath(), 'expense_track.db');
    return openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV1Tables(db);
        await _createVaultSnapshots(db);
        await _seedDefaults(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createVaultSnapshots(db);
        }
      },
    );
  }

  static Future<void> _createV1Tables(Database db) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        icon_key TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        amount_paise INTEGER NOT NULL CHECK(amount_paise > 0),
        type TEXT NOT NULL,
        category_id TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        import_hash TEXT,
        FOREIGN KEY(category_id) REFERENCES categories(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_tx_occurred ON transactions(occurred_at)',
    );
    await db.execute(
      'CREATE INDEX idx_tx_category ON transactions(category_id)',
    );
    await db.execute('CREATE INDEX idx_tx_type ON transactions(type)');
    await db.execute(
      'CREATE UNIQUE INDEX idx_tx_import_hash ON transactions(import_hash) WHERE import_hash IS NOT NULL',
    );
    await db.execute('''
      CREATE TABLE budgets (
        month_key TEXT NOT NULL,
        category_id TEXT NOT NULL DEFAULT '',
        amount_paise INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (month_key, category_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createVaultSnapshots(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_snapshots (
        id TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        saved_at INTEGER NOT NULL,
        tx_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _seedDefaults(Database db) async {
    final batch = db.batch();
    for (final c in defaultCategories()) {
      batch.insert('categories', c.toMap());
    }
    batch.insert('settings', {'key': 'theme', 'value': 'system'});
    batch.insert('settings', {'key': 'currency_code', 'value': 'INR'});
    batch.insert('settings', {'key': 'currency_symbol', 'value': '₹'});
    batch.insert('settings', {'key': 'default_budget_paise', 'value': '0'});
    await batch.commit(noResult: true);
  }
}
