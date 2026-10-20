/// Native / VM / test stub — keeps the platform sqflite factory unchanged.
///
/// On Android and iOS the default [databaseFactory] from the `sqflite` plugin
/// remains in effect. Tests that need FFI should set `databaseFactory` themselves
/// (see `test/database_test.dart`).
Future<void> initializeDatabaseFactory() async {
  // No-op.
}
