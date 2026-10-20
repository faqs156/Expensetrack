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
  String? lastKnownEmail;

  /// True after [initialize] finished (including silent auth attempt).
  bool get ready => _initialized;

  Timer? _pushDebounce;
  bool get isSignedIn => account != null;
  String? get email => account?.email ?? lastKnownEmail;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    promptDismissed = prefs.getBool('drive_sync_prompt_dismissed') ?? false;
    lastKnownEmail = prefs.getString('drive_sync_last_email');
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
          unawaited(_acceptOrRejectUser(event.user));
        case GoogleSignInAuthenticationEventSignOut():
          account = null;
          status = DriveSyncStatus.signedOut;
          notifyListeners();
      }
    }, onError: (Object e) {
      lastError = e.toString();
      status = DriveSyncStatus.error;
      notifyListeners();
    });

    try {
      final restored = await _signIn.attemptLightweightAuthentication();
      if (restored != null) {
        await _acceptOrRejectUser(restored);
      }
    } catch (_) {
      // User not signed in yet — fine.
    }

    _initialized = true;
    if (account == null) {
      status = DriveSyncStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> _acceptOrRejectUser(GoogleSignInAccount user) async {
    if (!GoogleAuthConfig.isEmailAllowed(user.email)) {
      lastError =
          'This Google account is not allowed (${user.email}). '
          'Ask the owner to add it to GOOGLE_ALLOWED_EMAILS.';
      status = DriveSyncStatus.error;
      account = null;
      notifyListeners();
      try {
        await _signIn.signOut();
      } catch (_) {}
      return;
    }
    account = user;
    status = DriveSyncStatus.idle;
    lastError = null;
    await _rememberSignedIn(user.email);
    await dismissPrompt();
    notifyListeners();
  }

  Future<void> _rememberSignedIn(String email) async {
    lastKnownEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drive_sync_last_email', email);
    await prefs.setBool('drive_sync_prompt_dismissed', true);
    promptDismissed = true;
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
        'GOOGLE_CLIENT_ID and GOOGLE_ALLOWED_EMAILS must be configured. '
        'See README → Google Drive sync.',
      );
    }
    lastError = null;
    if (_signIn.supportsAuthenticate()) {
      final user =
          await _signIn.authenticate(scopeHint: GoogleAuthConfig.driveScopes);
      await _acceptOrRejectUser(user);
      if (account == null) {
        throw StateError(lastError ?? 'Google account not allowed');
      }
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

  /// Mark local data dirty and schedule a silent upload when signed in.
  void schedulePush(Future<String> Function() buildBackupJson) {
    unawaited(markLocalChanged());
    if (!isSignedIn) return;
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 3), () async {
      try {
        await pushBackup(await buildBackupJson(), interactive: false);
      } catch (e) {
        // Silent background failure — user can tap Sync now (re-auth if needed).
        lastError =
            'Auto-sync paused. Tap Sync now to reconnect Google Drive.';
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
  /// [interactive] only when the user tapped Sync now / just signed in.
  Future<String?> reconcile({
    required Future<String> Function() buildBackupJson,
    required int localTransactionCount,
    bool interactive = false,
  }) async {
    if (!isSignedIn) return null;
    status = DriveSyncStatus.syncing;
    lastError = null;
    notifyListeners();

    try {
      await _ensureDriveAuthorized(interactive: interactive);
      final remote = await _downloadSyncFile(interactive: interactive);
      final localJson = await buildBackupJson();
      final localUpdated =
          localUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (remote == null) {
        if (localTransactionCount > 0 || localJson.trim().isNotEmpty) {
          await pushBackup(localJson, interactive: interactive);
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
        await pushBackup(localJson, interactive: interactive);
      } else {
        await _markSynced();
      }

      status = DriveSyncStatus.idle;
      notifyListeners();
      return null;
    } catch (e) {
      lastError = interactive
          ? e.toString()
          : 'Auto-sync paused. Tap Sync now to reconnect Google Drive.';
      status = DriveSyncStatus.error;
      notifyListeners();
      if (interactive) rethrow;
      return null;
    }
  }

  Future<void> pushBackup(
    String backupJson, {
    bool interactive = false,
  }) async {
    if (!isSignedIn) return;
    status = DriveSyncStatus.syncing;
    lastError = null;
    notifyListeners();

    try {
      final updated = localUpdatedAt ?? DateTime.now().toUtc();
      final envelope = _wrapBackup(backupJson, updated);
      final bytes = utf8.encode(envelope);
      final api = await _driveApi(interactive: interactive);
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
      lastError = interactive
          ? e.toString()
          : 'Auto-sync paused. Tap Sync now to reconnect Google Drive.';
      status = DriveSyncStatus.error;
      notifyListeners();
      if (interactive) rethrow;
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
      interactive: true,
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

  Future<_RemoteSync?> _downloadSyncFile({required bool interactive}) async {
    final api = await _driveApi(interactive: interactive);
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

  Future<drive.DriveApi> _driveApi({required bool interactive}) async {
    final auth = await _ensureDriveAuthorized(interactive: interactive);
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
      throw StateError(
        interactive
            ? 'Google Drive permission was not granted'
            : 'Drive authorization expired',
      );
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
