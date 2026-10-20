import 'package:expense_track/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App theme builds light and dark', (tester) async {
    expect(AppTheme.light().useMaterial3, true);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });
}
