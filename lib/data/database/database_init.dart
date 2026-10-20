import 'database_init_stub.dart'
    if (dart.library.html) 'database_init_web.dart' as impl;

/// Initializes the sqflite [databaseFactory] for the current platform.
///
/// - **Web:** sets `databaseFactoryFfiWeb` (must run before first DB open).
/// - **Android / iOS / desktop / VM tests:** no-op; native plugin or test FFI
///   factory remains responsible.
Future<void> initializeDatabaseFactory() => impl.initializeDatabaseFactory();
