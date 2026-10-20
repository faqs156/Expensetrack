import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web-only: swap the global factory before any [openDatabase] call.
///
/// Per https://pub.dev/packages/sqflite_common_ffi_web — uses sqlite3 WASM with
/// IndexedDB persistence. Requires `web/sqlite3.wasm` and `web/sqflite_sw.js`
/// from `dart run sqflite_common_ffi_web:setup`.
Future<void> initializeDatabaseFactory() async {
  databaseFactory = databaseFactoryFfiWeb;
}
