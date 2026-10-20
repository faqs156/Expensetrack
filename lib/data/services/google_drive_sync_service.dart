import 'dart:async';
import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/google_auth_config.dart';
import '../../core/sync_rules.dart';
import 'backup_service.dart';

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
  bool _manualSyncLock = false;
  bool _authBusy = false;
  bool _lightweightAttempted = false;
  bool _syncCycleBusy = false;
  GoogleSignInClientAuthorization? _driveAuth;
  static const _pendingPushPrefsKey = 'drive_sync_pending_push';

  /// Called when a background merge produced JSON this device should apply.
  Future<void> Function(String mergedJson)? onVaultMerged;

  bool get isSignedIn => account != null;
  String? get email => account?.email ?? lastKnownEmail;
  bool get hasPendingPush => _hasPendingPush;
  bool get isManualSyncing => _manualSyncLock;

  /// Wire the vault JSON builder so pending uploads survive a page reload.
  void bindBackupBuilder(Future<String> Function() buildBackupJson) {
    _pendingBackupBuilder = buildBackupJson;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    promptDismissed = prefs.getBool('drive_sync_prompt_dismissed') ?? false;
    lastKnownEmail = prefs.getString('drive_sync_last_email');
    _hasPendingPush = prefs.getBool(_pendingPushPrefsKey) ?? false;
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
          _driveAuth = null;
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

    // Only silent-restore when this browser already has a session.
    // Fresh login uses the GIS button once — do not also open One Tap.
    if (hasLocalSession) {
      unawaited(
        restoreGoogleSession(
          timeout: const Duration(seconds: 8),
          allowPrompt: false,
        ),
      );
    }

    _initialized = true;
    if (account == null) {
      status = DriveSyncStatus.signedOut;
    }
    notifyListeners();
  }

  /// Restore a live Google session. [allowPrompt] false = poll only / no One Tap.
  Future<bool> restoreGoogleSession({
    Duration timeout = const Duration(seconds: 8),
    bool allowPrompt = false,
    bool forcePrompt = false,
  }) async {
    if (account != null) return true;
    if (_authBusy) {
      final deadline = DateTime.now().add(timeout);
      while (account == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return account != null;
    }

    _authBusy = true;
    try {
      final shouldPrompt =
          allowPrompt && (forcePrompt || !_lightweightAttempted);
      if (shouldPrompt) {
        _lightweightAttempted = true;
        try {
          final restored = await _signIn.attemptLightweightAuthentication();
          if (restored != null) {
            await _acceptOrRejectUser(restored);
          }
        } catch (_) {
          // Web One Tap may complete via authenticationEvents.
        }
      }

      final deadline = DateTime.now().add(timeout);
      while (account == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return account != null;
    } finally {
      _authBusy = false;
    }
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
    // Skip when Sync now owns the flow — it will pull/push itself.
    if (!_manualSyncLock &&
        _hasPendingPush &&
        _pendingBackupBuilder != null) {
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
    // StateError / clear user messages from our own throws.
    if (e is StateError) {
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
    }
    const prefix = 'Bad state: ';
    if (text.startsWith(prefix)) {
      final msg = text.substring(prefix.length).trim();
      if (msg.isNotEmpty && !msg.contains('Exception')) return msg;
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
    // Web: the official GIS button already signed the user in via
    // authenticationEvents. Native: authenticate() once.
    if (account == null && _signIn.supportsAuthenticate()) {
      await ensureGoogleConnected();
    } else if (account == null) {
      // Wait briefly for the GIS button event — do not open a second chooser.
      final ok = await restoreGoogleSession(
        timeout: const Duration(seconds: 20),
        allowPrompt: false,
      );
      if (!ok) {
        throw StateError('Choose your Google account with the Sign in button.');
      }
    }
    try {
      await _ensureDriveAuthorized(interactive: true);
    } catch (e) {
      lastError = _friendlyGoogleError(e) ?? 'Could not connect. Try Sync now.';
    }
    notifyListeners();
  }

  /// Restores a live Google session (needed for Drive). Safe to call from Sync now.
  Future<void> ensureGoogleConnected({
    Duration timeout = const Duration(seconds: 40),
    bool allowPrompt = false,
  }) async {
    if (account != null) return;
    if (!GoogleAuthConfig.isConfigured) {
      throw StateError('Sign-in is unavailable right now.');
    }
    lastError = null;

    if (_signIn.supportsAuthenticate()) {
      if (_authBusy) {
        final ok = await restoreGoogleSession(
          timeout: timeout,
          allowPrompt: false,
        );
        if (!ok || account == null) {
          throw StateError(lastError ?? 'Could not connect Google.');
        }
        return;
      }
      _authBusy = true;
      try {
        final user = await _signIn.authenticate(
          scopeHint: GoogleAuthConfig.signInScopeHint,
        );
        await _acceptOrRejectUser(user);
      } finally {
        _authBusy = false;
      }
      if (account == null) {
        throw StateError(lastError ?? 'This Google account cannot access ExpenseTrack.');
      }
      return;
    }

    // Web: only Sync now may prompt; login uses the GIS button alone.
    final ok = await restoreGoogleSession(
      timeout: timeout,
      allowPrompt: allowPrompt,
      forcePrompt: allowPrompt,
    );
    if (!ok || account == null) {
      throw StateError(
        allowPrompt
            ? 'Choose your Google account when prompted, then try again.'
            : 'Tap Sign in with Google, choose your account once, then try again.',
      );
    }
  }

  Future<void> signOut() async {
    _pushDebounce?.cancel();
    _driveAuth = null;
    _lightweightAttempted = false;
    await _signIn.signOut();
    account = null;
    lastKnownEmail = null;
    status = DriveSyncStatus.signedOut;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drive_sync_last_email');
    notifyListeners();
  }

  Future<void> _setPendingPush(bool value) async {
    _hasPendingPush = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingPushPrefsKey, value);
  }

  /// Mark vault dirty; after debounce run a full merge cycle (never blind push).
  void schedulePush(Future<String> Function() buildBackupJson) {
    _pendingBackupBuilder = buildBackupJson;
    unawaited(_setPendingPush(true));
    unawaited(markLocalChanged());
    _pushDebounce?.cancel();
    _pushDebounce = Timer(SyncRules.editDebounce, () {
      unawaited(autoFlushAfterEdit());
    });
  }

  int _autoFlushAttempts = 0;

  /// After an edit: merge with Drive, then upload — peer devices, no blind push.
  Future<void> autoFlushAfterEdit() async {
    final builder = _pendingBackupBuilder;
    if (builder == null) return;

    if (!isSignedIn) {
      await restoreGoogleSession(
        timeout: const Duration(seconds: 3),
        allowPrompt: false,
      );
    }
    if (!isSignedIn) {
      _scheduleAutoFlushRetry();
      return;
    }

    try {
      final count = SyncRules.transactionCount(await builder());
      final toRestore = await reconcile(
        buildBackupJson: builder,
        localTransactionCount: count,
        interactive: false,
      );
      if (toRestore != null && onVaultMerged != null) {
        await onVaultMerged!(toRestore);
      }
      _autoFlushAttempts = 0;
    } catch (_) {
      _scheduleAutoFlushRetry();
    }
  }

  void _scheduleAutoFlushRetry() {
    _autoFlushAttempts++;
    if (_autoFlushAttempts > 8) return;
    _pushDebounce?.cancel();
    _pushDebounce = Timer(SyncRules.pendingRetryInterval, () {
      unawaited(autoFlushAfterEdit());
    });
  }

  /// Upload the full local vault if there are pending edits (or [force]).
  Future<void> flushPendingPush({
    bool interactive = false,
    bool force = false,
  }) async {
    final builder = _pendingBackupBuilder;
    if (!force && !_hasPendingPush) return;
    if (builder == null) return;

    if (!isSignedIn) {
      if (interactive) {
        await ensureGoogleConnected();
      } else {
        await restoreGoogleSession(
          timeout: const Duration(seconds: 3),
          allowPrompt: false,
        );
      }
    }
    if (!isSignedIn) {
      if (interactive) {
        throw StateError('Could not connect. Try Sync now again.');
      }
      return;
    }

    try {
      final json = await builder();
      await pushBackup(json, interactive: interactive);
      if (interactive) {
        await verifyRemoteContains(json, interactive: true);
      }
      await _setPendingPush(false);
      _autoFlushAttempts = 0;
      lastError = null;
      status = DriveSyncStatus.idle;
      notifyListeners();
    } catch (e) {
      if (interactive) rethrow;
      // Background: retry via autoFlush / periodic tick — no scary banner.
    }
  }

  /// Re-download Drive and ensure every local transaction id is present.
  Future<void> verifyRemoteContains(
    String localJson, {
    required bool interactive,
  }) async {
    final localIds = _txIdSet(localJson);
    if (localIds.isEmpty) return;

    Object? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      try {
        final remote = await _downloadSyncFile(interactive: interactive);
        if (remote == null) {
          lastFailure = StateError('Could not confirm upload. Tap Sync now.');
          continue;
        }
        final remoteIds = _txIdSet(remote.json);
        final missing =
            localIds.where((id) => !remoteIds.contains(id)).toList();
        if (missing.isEmpty) return;
        lastFailure = StateError(
          'Upload incomplete (${missing.length} missing). Tap Sync now.',
        );
      } catch (e) {
        lastFailure = e;
      }
    }
    throw lastFailure ?? StateError('Could not confirm upload. Tap Sync now.');
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

  /// Pull / merge / push using [SyncRules]. Devices are peers.
  ///
  /// [safetyJson] — optional on-device snapshot (survives bad pulls / sign-out).
  Future<String?> reconcile({
    required Future<String> Function() buildBackupJson,
    required int localTransactionCount,
    String? safetyJson,
    bool interactive = false,
  }) async {
    if (!isSignedIn) return null;
    if (_syncCycleBusy) return null;
    _syncCycleBusy = true;
    status = DriveSyncStatus.syncing;
    if (interactive) {
      lastError = null;
      notifyListeners();
    }

    try {
      await _ensureDriveAuthorized(interactive: interactive);
      final remote = await _downloadSyncFile(interactive: interactive);
      final prev = await _downloadPrevSyncFile(interactive: interactive);
      final localJson = await buildBackupJson();

      final result = await _applySyncDecision(
        localJson: localJson,
        remote: remote,
        prevRemoteJson: prev,
        safetyJson: safetyJson,
        interactive: interactive,
      );

      lastError = null;
      status = DriveSyncStatus.idle;
      notifyListeners();
      return result;
    } catch (e) {
      final friendly = _friendlyGoogleError(e);
      if (interactive) {
        lastError = friendly ?? 'Sync failed. Try again.';
        status = DriveSyncStatus.error;
        notifyListeners();
        if (friendly == null) rethrow;
      } else {
        status = DriveSyncStatus.idle;
      }
      return null;
    } finally {
      _syncCycleBusy = false;
    }
  }

  /// Merge all sources, then apply [SyncRules.decide].
  Future<String?> _applySyncDecision({
    required String localJson,
    required _RemoteSync? remote,
    String? prevRemoteJson,
    String? safetyJson,
    required bool interactive,
  }) async {
    final sources = <String>[localJson];
    if (safetyJson != null && safetyJson.trim().isNotEmpty) {
      sources.add(safetyJson);
    }
    if (remote != null) sources.add(remote.json);
    if (prevRemoteJson != null && prevRemoteJson.trim().isNotEmpty) {
      sources.add(prevRemoteJson);
    }

    final merged = sources.length == 1
        ? localJson
        : BackupService.mergeVaultJsonAll(sources);

    final decision = SyncRules.decide(
      localTxIds: SyncRules.transactionIds(localJson),
      remoteTxIds:
          remote == null ? <String>{} : SyncRules.transactionIds(remote.json),
      mergedTxIds: SyncRules.transactionIds(merged),
      hasPendingLocalEdits: _hasPendingPush,
    );

    if (decision.refuseUpload) {
      if (interactive) {
        lastError = 'Sync refused an unsafe upload. Try Sync now again.';
        status = DriveSyncStatus.error;
        notifyListeners();
      }
      return decision.restoreLocal ? merged : null;
    }

    if (SyncRules.transactionCount(merged) == 0) {
      await _markSynced();
      await _setPendingPush(false);
      return null;
    }

    if (decision.uploadRemote) {
      await markLocalChanged();
      try {
        await pushBackup(merged, interactive: interactive);
        if (interactive) {
          await verifyRemoteContains(merged, interactive: true);
        }
        await _setPendingPush(false);
        _autoFlushAttempts = 0;
      } catch (e) {
        await _setPendingPush(true);
        if (interactive) rethrow;
      }
    } else {
      await _markSynced();
      await _setPendingPush(false);
    }

    return decision.restoreLocal ? merged : null;
  }

  Set<String> _txIdSet(String json) => SyncRules.transactionIds(json);

  Future<void> pushBackup(
    String backupJson, {
    bool interactive = false,
  }) async {
    if (!isSignedIn) {
      throw StateError('Could not sync. Try Sync now.');
    }
    status = DriveSyncStatus.syncing;
    if (interactive) {
      lastError = null;
      notifyListeners();
    }

    try {
      final updated = localUpdatedAt ?? DateTime.now().toUtc();
      final envelope = _wrapBackup(backupJson, updated);
      final bytes = utf8.encode(envelope);
      final api = await _driveApi(interactive: interactive);

      // Keep previous Drive copy so an accidental older upload can be recovered.
      await _rotateToPrev(api, interactive: interactive);

      final existingId = await _findFileId(api, GoogleAuthConfig.syncFileName);
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
      await _setPendingPush(false);
      lastError = null;
      status = DriveSyncStatus.idle;
      notifyListeners();
    } catch (e) {
      final friendly = _friendlyGoogleError(e);
      if (interactive) {
        lastError = friendly ?? 'Sync failed. Try again.';
        status = DriveSyncStatus.error;
        notifyListeners();
        throw StateError(lastError ?? e.toString());
      }
      status = DriveSyncStatus.idle;
      rethrow;
    }
  }

  Future<void> syncNow({
    required Future<String> Function() buildBackupJson,
    required Future<void> Function(String json) restoreBackup,
    required int localTransactionCount,
    String? safetyJson,
  }) async {
    if (_manualSyncLock) return;
    _manualSyncLock = true;
    _pendingBackupBuilder = buildBackupJson;
    status = DriveSyncStatus.syncing;
    lastError = null;
    notifyListeners();

    try {
      await ensureGoogleConnected(
        timeout: const Duration(seconds: 40),
        allowPrompt: true,
      );
      await _ensureDriveAuthorized(interactive: true);

      final remote = await _downloadSyncFile(interactive: true);
      final prev = await _downloadPrevSyncFile(interactive: true);
      final localJson = await buildBackupJson();
      final toRestore = await _applySyncDecision(
        localJson: localJson,
        remote: remote,
        prevRemoteJson: prev,
        safetyJson: safetyJson,
        interactive: true,
      );

      if (toRestore != null) {
        await restoreBackup(toRestore);
      }

      status = DriveSyncStatus.idle;
      notifyListeners();
    } catch (e) {
      lastError = _friendlyGoogleError(e) ?? 'Sync failed. Try again.';
      status = DriveSyncStatus.error;
      notifyListeners();
      rethrow;
    } finally {
      _manualSyncLock = false;
      if (status == DriveSyncStatus.syncing) {
        status = DriveSyncStatus.idle;
        notifyListeners();
      }
    }
  }

  bool _remoteHasTransactions(String json) =>
      SyncRules.transactionCount(json) > 0;

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
    final id = await _findFileId(api, GoogleAuthConfig.syncFileName);
    if (id == null) return null;
    return _readRemoteFile(api, id);
  }

  Future<String?> _downloadPrevSyncFile({required bool interactive}) async {
    try {
      final api = await _driveApi(interactive: interactive);
      final id = await _findFileId(api, GoogleAuthConfig.syncPrevFileName);
      if (id == null) return null;
      final remote = await _readRemoteFile(api, id);
      return remote?.json;
    } catch (_) {
      return null;
    }
  }

  Future<_RemoteSync?> _readRemoteFile(drive.DriveApi api, String id) async {
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

  /// Copy current sync file → `.prev` before overwriting.
  Future<void> _rotateToPrev(
    drive.DriveApi api, {
    required bool interactive,
  }) async {
    try {
      final currentId = await _findFileId(api, GoogleAuthConfig.syncFileName);
      if (currentId == null) return;
      final current = await _readRemoteFile(api, currentId);
      if (current == null || !_remoteHasTransactions(current.json)) return;
      final bytes = utf8.encode(current.json);
      final media = drive.Media(Stream.value(bytes), bytes.length);
      final prevId = await _findFileId(api, GoogleAuthConfig.syncPrevFileName);
      if (prevId == null) {
        await api.files.create(
          drive.File()
            ..name = GoogleAuthConfig.syncPrevFileName
            ..parents = ['appDataFolder'],
          uploadMedia: media,
        );
      } else {
        await api.files.update(
          drive.File(),
          prevId,
          uploadMedia: media,
        );
      }
    } catch (_) {
      // Best-effort; main upload still proceeds.
    }
  }

  Future<String?> _findFileId(drive.DriveApi api, String name) async {
    final listed = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$name' and trashed = false",
      $fields: 'files(id, name, modifiedTime)',
      pageSize: 20,
    );
    final files = listed.files;
    if (files == null || files.isEmpty) return null;
    files.sort((a, b) {
      final am = a.modifiedTime?.millisecondsSinceEpoch ?? 0;
      final bm = b.modifiedTime?.millisecondsSinceEpoch ?? 0;
      return bm.compareTo(am);
    });
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
    if (_driveAuth != null) return _driveAuth!;

    final scopes = GoogleAuthConfig.driveScopes;
    try {
      GoogleSignInClientAuthorization? auth =
          await user.authorizationClient.authorizationForScopes(scopes);
      // Background sync must NEVER call authorizeScopes — on mobile Chrome it
      // re-opens the account picker in a loop.
      if (auth == null && interactive) {
        auth = await user.authorizationClient.authorizeScopes(scopes);
      }
      if (auth == null) {
        throw StateError(
          interactive ? 'Permission not granted. Try Sync now.' : 'Sync reconnect needed',
        );
      }
      _driveAuth = auth;
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
