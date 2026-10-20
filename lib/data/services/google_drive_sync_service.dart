import 'dart:async';
import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/google_auth_config.dart';

enum DriveSyncStatus { idle, syncing, signedOut, error }

/// Signs in with Google and stores the full SQLite backup JSON in Drive
/// `appDataFolder` so the same account shares one vault across devices/browsers.
class GoogleDriveSyncService extends ChangeNotifier {
  GoogleDriveSyncService();

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;

  bool _initialized = false;
  GoogleSignInAccount? account;
  DriveSyncStatus status = DriveSyncStatus.signedOut;
  String? lastError;
  DateTime? lastSyncedAt;
  DateTime? localUpdatedAt;
  bool promptDismissed = false;

  Timer? _pushDebounce;
  bool get isSignedIn => account != null;
  String? get email => account?.email;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    promptDismissed = prefs.getBool('drive_sync_prompt_dismissed') ?? false;
    final localMs = prefs.getInt('drive_sync_local_updated_ms');
    if (localMs != null) {
      localUpdatedAt = DateTime.fromMillisecondsSinceEpoch(localMs, isUtc: true);
    }
    final syncedMs = prefs.getInt('drive_sync_last_synced_ms');
    if (syncedMs != null) {
      lastSyncedAt = DateTime.fromMillisecondsSinceEpoch(syncedMs, isUtc: true);
    }

    if (!GoogleAuthConfig.isConfigured) {
      status = DriveSyncStatus.signedOut;
      _initialized = true;
      notifyListeners();
      return;
    }

    await _signIn.initialize(clientId: GoogleAuthConfig.clientId);
    _authSub = _signIn.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          account = event.user;
          status = DriveSyncStatus.idle;
          lastError = null;
        case GoogleSignInAuthenticationEventSignOut():
          account = null;
          status = DriveSyncStatus.signedOut;
      }
      notifyListeners();
    }, onError: (Object e) {
      lastError = e.toString();
      status = DriveSyncStatus.error;
      notifyListeners();
    });

    try {
      await _signIn.attemptLightweightAuthentication();
    } catch (_) {
      // User not signed in yet — fine.
    }

    _initialized = true;
    if (account == null) {
      status = DriveSyncStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> dismissPrompt() async {
    promptDismissed = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drive_sync_prompt_dismissed', true);
    notifyListeners();
  }

  Future<void> signInInteractive() async {
    if (!GoogleAuthConfig.isConfigured) {
      throw StateError(
        'GOOGLE_CLIENT_ID is not configured. See README → Google Drive sync.',
      );
    }
    lastError = null;
    if (_signIn.supportsAuthenticate()) {
      await _signIn.authenticate(scopeHint: GoogleAuthConfig.driveScopes);
    } else {
      throw StateError(
        'Use the Google Sign-In button (web requires the official button).',
      );
    }
    await _ensureDriveAuthorized(interactive: true);
    notifyListeners();
  }

  Future<void> signOut() async {
    _pushDebounce?.cancel();
    await _signIn.signOut();
    account = null;
    status = DriveSyncStatus.signedOut;
    notifyListeners();
  }

  /// Mark local data dirty and schedule an upload when signed in.
  void schedulePush(Future<String> Function() buildBackupJson) {
    markLocalChanged();
    if (!isSignedIn) return;
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 3), () async {
      try {
        await pushBackup(await buildBackupJson());
      } catch (e) {
        lastError = e.toString();
        status = DriveSyncStatus.error;
        notifyListeners();
      }
    });
  }

  Future<void> markLocalChanged() async {
    localUpdatedAt = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'drive_sync_local_updated_ms',
      localUpdatedAt!.millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  Future<void> setLocalUpdatedFromRemote(DateTime remoteUpdatedAt) async {
    localUpdatedAt = remoteUpdatedAt.toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'drive_sync_local_updated_ms',
      localUpdatedAt!.millisecondsSinceEpoch,
    );
  }

  /// Pull/push so the newer of local vs Drive wins (last-write-wins).
  ///
  /// Returns remote JSON when a restore should be applied; otherwise null.
  Future<String?> reconcile({
    required Future<String> Function() buildBackupJson,
    required int localTransactionCount,
  }) async {
    if (!isSignedIn) return null;
    status = DriveSyncStatus.syncing;
    lastError = null;
    notifyListeners();

    try {
      await _ensureDriveAuthorized(interactive: false);
      final remote = await _downloadSyncFile();
      final localJson = await buildBackupJson();
      final localUpdated = localUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (remote == null) {
        if (localTransactionCount > 0 || localJson.trim().isNotEmpty) {
          await pushBackup(localJson);
        }
        status = DriveSyncStatus.idle;
        notifyListeners();
        return null;
      }

      final remoteUpdated = remote.updatedAt;
      if (remoteUpdated.isAfter(localUpdated.add(const Duration(seconds: 1)))) {
        await setLocalUpdatedFromRemote(remoteUpdated);
        await _markSynced();
        status = DriveSyncStatus.idle;
        notifyListeners();
        return remote.json;
      }

      if (localUpdated.isAfter(remoteUpdated.add(const Duration(seconds: 1))) ||
          localTransactionCount > 0 && remote.json.trim().isEmpty) {
        await pushBackup(localJson);
      } else {
        await _markSynced();
      }

      status = DriveSyncStatus.idle;
      notifyListeners();
      return null;
    } catch (e) {
      lastError = e.toString();
      status = DriveSyncStatus.error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> pushBackup(String backupJson) async {
    if (!isSignedIn) return;
    status = DriveSyncStatus.syncing;
    lastError = null;
    notifyListeners();

    try {
      await _ensureDriveAuthorized(interactive: true);
      final updated = localUpdatedAt ?? DateTime.now().toUtc();
      final envelope = _wrapBackup(backupJson, updated);
      final bytes = utf8.encode(envelope);
      final api = await _driveApi();
      final existingId = await _findSyncFileId(api);
      final media = drive.Media(Stream.value(bytes), bytes.length);

      if (existingId == null) {
        await api.files.create(
          drive.File()
            ..name = GoogleAuthConfig.syncFileName
            ..parents = ['appDataFolder'],
          uploadMedia: media,
        );
      } else {
        await api.files.update(
          drive.File(),
          existingId,
          uploadMedia: media,
        );
      }
      await _markSynced();
      status = DriveSyncStatus.idle;
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      status = DriveSyncStatus.error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> syncNow({
    required Future<String> Function() buildBackupJson,
    required Future<void> Function(String json) restoreBackup,
    required int localTransactionCount,
  }) async {
    final remoteJson = await reconcile(
      buildBackupJson: buildBackupJson,
      localTransactionCount: localTransactionCount,
    );
    if (remoteJson != null) {
      await restoreBackup(remoteJson);
    }
  }

  String _wrapBackup(String backupJson, DateTime updatedAt) {
    final decoded = jsonDecode(backupJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup JSON');
    }
    decoded['updated_at'] = updatedAt.toIso8601String();
    decoded['sync_target'] = 'google_drive_appdata';
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  Future<_RemoteSync?> _downloadSyncFile() async {
    final api = await _driveApi();
    final id = await _findSyncFileId(api);
    if (id == null) return null;

    final media = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await media.stream.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
    final text = utf8.decode(bytes);
    final map = jsonDecode(text);
    if (map is! Map<String, dynamic>) return null;
    final updatedRaw = map['updated_at'] as String?;
    final updated = updatedRaw != null
        ? DateTime.tryParse(updatedRaw)?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return _RemoteSync(json: text, updatedAt: updated);
  }

  Future<String?> _findSyncFileId(drive.DriveApi api) async {
    final listed = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '${GoogleAuthConfig.syncFileName}' and trashed = false",
      $fields: 'files(id, name, modifiedTime)',
      pageSize: 10,
    );
    final files = listed.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }

  Future<drive.DriveApi> _driveApi() async {
    final auth = await _ensureDriveAuthorized(interactive: true);
    final client = auth.authClient(scopes: GoogleAuthConfig.driveScopes);
    return drive.DriveApi(client);
  }

  Future<GoogleSignInClientAuthorization> _ensureDriveAuthorized({
    required bool interactive,
  }) async {
    final user = account;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final scopes = GoogleAuthConfig.driveScopes;
    GoogleSignInClientAuthorization? auth =
        await user.authorizationClient.authorizationForScopes(scopes);
    if (auth == null && interactive) {
      auth = await user.authorizationClient.authorizeScopes(scopes);
    }
    if (auth == null) {
      throw StateError('Google Drive permission was not granted');
    }
    return auth;
  }

  Future<void> _markSynced() async {
    lastSyncedAt = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'drive_sync_last_synced_ms',
      lastSyncedAt!.millisecondsSinceEpoch,
    );
  }

  @override
  void dispose() {
    _pushDebounce?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}

class _RemoteSync {
  const _RemoteSync({required this.json, required this.updatedAt});
  final String json;
  final DateTime updatedAt;
}
