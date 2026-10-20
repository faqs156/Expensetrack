import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Helps recover data after uninstall/reinstall on Android via:
/// 1) Google Auto Backup scheduling
/// 2) A JSON copy under Documents/ExpenseTrack that survives uninstall
class DataSurvivalService {
  static const _channel =
      MethodChannel('com.expensetrack.expense_track/data_survival');

  Timer? _debounce;

  bool get isSupported => Platform.isAndroid;

  Future<void> scheduleCloudBackup() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('scheduleCloudBackup');
    } catch (_) {
      // Best-effort; ignore on unsupported environments.
    }
  }

  Future<bool> writeSurvivingBackup(String json) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'writeSurvivingBackup',
        {'json': json},
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> readSurvivingBackup() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('readSurvivingBackup');
    } catch (_) {
      return null;
    }
  }

  /// Debounced write + cloud backup mark after local data changes.
  void scheduleAfterChange(Future<String> Function() buildBackupJson) {
    if (!isSupported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      try {
        final json = await buildBackupJson();
        await writeSurvivingBackup(json);
        await scheduleCloudBackup();
      } catch (_) {}
    });
  }

  void dispose() {
    _debounce?.cancel();
  }
}
