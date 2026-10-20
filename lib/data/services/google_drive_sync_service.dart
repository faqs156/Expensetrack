import 'dart:async';
import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
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
  Future<String> Function()? _pendingBackupBuilder;
  bool _hasPendingPush = false;

  bool get isSignedIn => account != null;
  String? get email => account?.email ?? lastKnownEmail;
  bool get hasPendingPush => _hasPendingPush;

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
      // Ignore transient popup/UI noise (common on Safari / Home Screen).
      final friendly = _friendlyGoogleError(e);
      if (friendly == null) return;
      lastError = friendly;
      status = DriveSyncStatus.error;
      notifyListeners();
    });

    // Always try to restore Google so Drive can sync on every open / login
    // (Chrome, Safari, Firefox — One Tap / FedCM timing differs by browser).
    await restoreGoogleSession(timeout: const Duration(seconds: 20));

    _initialized = true;
    if (account == null) {
      status = DriveSyncStatus.signedOut;
    }
    notifyListeners();
  }

  /// One Tap / silent restore. Returns true when a live Google session exists.
  Future<bool> restoreGoogleSession({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (account != null) return true;
    try {
      final restored = await _signIn.attemptLightweightAuthentication();
      if (restored != null) {
        await _acceptOrRejectUser(restored);
      }
    } catch (_) {
      // Continue waiting — web One Tap completes via authenticationEvents.
    }

    final deadline = DateTime.now().add(timeout);
    while (account == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return account != null;
  }

  /// Allowlisted email from this browser (survives refresh even if Google UI did not).
  bool get hasLocalSession =>
      lastKnownEmail != null && GoogleAuthConfig.isEmailAllowed(lastKnownEmail);

  /// Google identity is live (needed for Drive API). Local session alone is not enough.
  bool get needsGoogleReconnect => hasLocalSession && account == null;

  Future<void> _acceptOrRejectUser(GoogleSignInAccount user) async {
    if (!GoogleAuthConfig.isEmailAllowed(user.email)) {
      lastError = 'This Google account cannot access ExpenseTrack.';
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
    lastError = null; // clear prior popup / deny errors after a good login
    await _rememberSignedIn(user.email);
    await dismissPrompt();
    notifyListeners();
    // Flush edits made while Google was disconnected (after refresh).
    if (_hasPendingPush && _pendingBackupBuilder != null) {
      unawaited(flushPendingPush(interactive: false));
    }
  }

  void clearLastError() {
    lastError = null;
    if (status == DriveSyncStatus.error && isSignedIn) {
      status = DriveSyncStatus.idle;
    }
    notifyListeners();
  }

  /// Returns a user-facing message, or null to ignore the error entirely.
  static String? _friendlyGoogleError(Object e) {
    final text = e.toString();
    final lower = text.toLowerCase();
    if (e is GoogleSignInException) {
      if (e.code == GoogleSignInExceptionCode.uiUnavailable ||
          lower.contains('popup') ||
          lower.contains('uiunavailable')) {
        return 'Could not open Google sign-in. Allow popups and try again.';
      }
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
    }
    if (lower.contains('popup') || lower.contains('uiunavailable')) {
      return 'Could not open Google sign-in. Allow popups and try again.';
    }
    // Keep failures short — never surface env/secret names to users.
    if (lower.contains('google_allowed') ||
        lower.contains('google_client') ||
        lower.contains('dart-define') ||
        lower.contains('repository secret')) {
      return 'Something went wrong. Try again.';
    }
    return 'Something went wrong. Try again.';
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
      throw StateError('Sign-in is unavailable right now.');
    }
    lastError = null;
    await ensureGoogleConnected();
    try {
      await _ensureDriveAuthorized(interactive: true);
    } catch (e) {
      lastError = _friendlyGoogleError(e) ?? 'Could not connect. Try Sync now.';
      // Stay signed in — vault UI still works offline.
    }
    notifyListeners();
  }

  /// Restores a live Google session (needed for Drive). Safe to call from Sync now.
  ///
  /// Home can use [hasLocalSession] without this; Drive API cannot.
  Future<void> ensureGoogleConnected({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    if (account != null) return;
    if (!GoogleAuthConfig.isConfigured) {
      throw StateError('Sign-in is unavailable right now.');
    }
    lastError = null;

    if (_signIn.supportsAuthenticate()) {
      final user = await _signIn.authenticate(
        scopeHint: GoogleAuthConfig.signInScopeHint,
      );
      await _acceptOrRejectUser(user);
      if (account == null) {
        throw StateError(lastError ?? 'Google account not allowed');
      }
      return;
    }

    // Web: One Tap / FedCM (only when user taps Sync — not on every refresh).
    final done = Completer<void>();
    late final StreamSubscription<GoogleSignInAuthenticationEvent> sub;
    sub = _signIn.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          if (!done.isCompleted) done.complete();
        case GoogleSignInAuthenticationEventSignOut():
          break;
      }
    }, onError: (Object e, StackTrace st) {
      if (!done.isCompleted) {
        done.completeError(e, st);
      }
    });

    try {
      await _signIn.attemptLightweightAuthentication();
      await done.future.timeout(
        timeout,
        onTimeout: () {
          throw StateError('Sign-in timed out. Try again.');
        },
      );
    } finally {
      await sub.cancel();
    }

    if (account == null) {
      throw StateError(lastError ?? 'Google account not allowed');
    }
  }

  Future<void> signOut() async {
    _pushDebounce?.cancel();
    await _signIn.signOut();
    account = null;
    lastKnownEmail = null;
    status = DriveSyncStatus.signedOut;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drive_sync_last_email');
    notifyListeners();
  }

  /// Mark local vault dirty and upload full snapshot (txs, budgets, etc.) to Drive.
  void schedulePush(Future<String> Function() buildBackupJson) {
    _pendingBackupBuilder = buildBackupJson;
    _hasPendingPush = true;
    unawaited(markLocalChanged());
    if (!isSignedIn) {
      // Local session can keep editing; Sync now / reconnect will flush.
      notifyListeners();
      return;
    }
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(flushPendingPush(interactive: false));
    });
  }

  /// Upload the full local vault if there are pending edits (or [force]).
  Future<void> flushPendingPush({
    bool interactive = false,
    bool force = false,
  }) async {
    final builder = _pendingBackupBuilder;
    if (!isSignedIn) return;
    if (!force && !_hasPendingPush) return;
    if (builder == null) return;
    try {
      await pushBackup(await builder(), interactive: interactive);
      _hasPendingPush = false;
    } catch (e) {
      if (!interactive) {
        lastError = 'Sync paused. Tap Sync now to retry.';
        status = DriveSyncStatus.error;
        notifyListeners();
      } else {
        rethrow;
      }
    }
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
        // Never upload an empty vault as the first Drive file if we have nothing.
        if (localTransactionCount > 0 || _hasPendingPush) {
          await pushBackup(localJson, interactive: interactive);
          _hasPendingPush = false;
        }
        lastError = null;
        status = DriveSyncStatus.idle;
        notifyListeners();
        return null;
      }

      final remoteUpdated = remote.updatedAt;
      final remoteHasTx = _remoteHasTransactions(remote.json);

      // Empty local + Drive has data → always pull (fixes Safari / new browser).
      if (localTransactionCount == 0 && remoteHasTx) {
        await setLocalUpdatedFromRemote(remoteUpdated);
        await _markSynced();
        _hasPendingPush = false;
        lastError = null;
        status = DriveSyncStatus.idle;
        notifyListeners();
        return remote.json;
      }

      // Remote strictly newer → pull (unless we have unsynced local edits).
      if (remoteUpdated.isAfter(localUpdated) && !_hasPendingPush) {
        await setLocalUpdatedFromRemote(remoteUpdated);
        await _markSynced();
        lastError = null;
        status = DriveSyncStatus.idle;
        notifyListeners();
        return remote.json;
      }

      // Local newer, equal, or pending edits → upload full vault.
      // Do not upload a completely empty vault over a non-empty Drive copy.
      if (localTransactionCount == 0 && remoteHasTx) {
        await setLocalUpdatedFromRemote(remoteUpdated);
        await _markSynced();
        lastError = null;
        status = DriveSyncStatus.idle;
        notifyListeners();
        return remote.json;
      }

      if (_hasPendingPush ||
          !remoteUpdated.isAfter(localUpdated) ||
          localTransactionCount > 0) {
        await pushBackup(localJson, interactive: interactive);
        _hasPendingPush = false;
      } else {
        await _markSynced();
      }

      lastError = null;
      status = DriveSyncStatus.idle;
      notifyListeners();
      return null;
    } catch (e) {
      final friendly = _friendlyGoogleError(e);
      lastError = friendly ??
          (interactive ? 'Sync failed. Try again.' : 'Sync paused. Tap Sync now.');
      status = DriveSyncStatus.error;
      notifyListeners();
      if (interactive && friendly == null) rethrow;
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
      _hasPendingPush = false;
      lastError = null;
      status = DriveSyncStatus.idle;
      notifyListeners();
    } catch (e) {
      final friendly = _friendlyGoogleError(e);
      lastError = friendly ??
          (interactive ? 'Sync failed. Try again.' : 'Sync paused. Tap Sync now.');
      status = DriveSyncStatus.error;
      notifyListeners();
      if (interactive && friendly == null) rethrow;
    }
  }

  Future<void> syncNow({
    required Future<String> Function() buildBackupJson,
    required Future<void> Function(String json) restoreBackup,
    required int localTransactionCount,
  }) async {
    // Drive needs a live Google token; home page can stay open on local session alone.
    _pendingBackupBuilder = buildBackupJson;
    await ensureGoogleConnected();
    final remoteJson = await reconcile(
      buildBackupJson: buildBackupJson,
      localTransactionCount: localTransactionCount,
      interactive: true,
    );
    if (remoteJson != null) {
      await restoreBackup(remoteJson);
      _hasPendingPush = false;
    } else if (localTransactionCount > 0 || _hasPendingPush) {
      // Upload only when this device has something to save.
      await flushPendingPush(interactive: true, force: true);
    }
  }

  bool _remoteHasTransactions(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return false;
      final txs = decoded['transactions'];
      return txs is List && txs.isNotEmpty;
    } catch (_) {
      return false;
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
    try {
      GoogleSignInClientAuthorization? auth =
          await user.authorizationClient.authorizationForScopes(scopes);
      if (auth == null && interactive) {
        auth = await user.authorizationClient.authorizeScopes(scopes);
      }
      if (auth == null) {
        throw StateError(
          interactive ? 'Permission not granted. Try again.' : 'Session expired.',
        );
      }
      return auth;
    } on GoogleSignInException catch (e) {
      final msg = _friendlyGoogleError(e);
      throw StateError(msg ?? e.toString());
    }
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
