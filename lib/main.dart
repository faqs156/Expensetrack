import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/database/database_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must run before AppDatabase / AppController open SQLite.
  await initializeDatabaseFactory();
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }
  runApp(const ExpenseTrackApp());
}
