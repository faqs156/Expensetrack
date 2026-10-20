import 'dart:convert';

/// Strong, device-agnostic sync rules for the shared Google Drive vault.
///
/// Invariants (never break these):
/// 1. Devices are peers — no phone/Mac primary.
/// 2. Never upload a vault that drops transaction ids already on Drive.
/// 3. Never restore Drive over local without merging (union by transaction id).
/// 4. Never blind-push local JSON; always merge with Drive (+ prev + safety) first.
/// 5. Background sync must not open Google account UI (no authorizeScopes / One Tap).
/// 6. Sign-out may best-effort upload, but must not block forever.
class SyncRules {
  SyncRules._();

  /// Debounce after an edit before merge+upload.
  static const editDebounce = Duration(milliseconds: 800);

  /// How often an open app pulls/merges from the shared vault.
  static const periodicPullInterval = Duration(minutes: 1);

  /// Faster retry while a merge-upload is still pending.
  static const pendingRetryInterval = Duration(seconds: 30);

  /// Max wait to upload on sign-out before continuing.
  static const signOutUploadTimeout = Duration(seconds: 6);

  /// Decide restore/upload after sources have been merged.
  static SyncDecision decide({
    required Set<String> localTxIds,
    required Set<String> remoteTxIds,
    required Set<String> mergedTxIds,
    required bool hasPendingLocalEdits,
  }) {
    if (mergedTxIds.isEmpty) {
      return const SyncDecision(
        restoreLocal: false,
        uploadRemote: false,
      );
    }

    final restoreLocal = !_sameIds(mergedTxIds, localTxIds);

    // Upload if Drive is missing anything from the merge, or local edits pending.
    final remoteMissingMerged = !_sameIds(mergedTxIds, remoteTxIds);
    final uploadRemote = remoteTxIds.isEmpty
        ? mergedTxIds.isNotEmpty
        : remoteMissingMerged || hasPendingLocalEdits;

    // Safety: refuse upload if merge somehow lost Drive ids.
    final dropsRemote = remoteTxIds.any((id) => !mergedTxIds.contains(id));
    if (uploadRemote && dropsRemote) {
      return SyncDecision(
        restoreLocal: restoreLocal,
        uploadRemote: false,
        refuseUpload: true,
      );
    }

    return SyncDecision(
      restoreLocal: restoreLocal,
      uploadRemote: uploadRemote,
    );
  }

  static Set<String> transactionIds(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return {};
      final txs = decoded['transactions'];
      if (txs is! List) return {};
      return txs
          .map((e) => e is Map ? '${e['id'] ?? ''}' : '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static int transactionCount(String json) => transactionIds(json).length;

  static bool _sameIds(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

class SyncDecision {
  const SyncDecision({
    required this.restoreLocal,
    required this.uploadRemote,
    this.refuseUpload = false,
  });

  /// Apply merged JSON to this device's local DB.
  final bool restoreLocal;

  /// Upload merged JSON to the shared Drive vault.
  final bool uploadRemote;

  /// Merge lost remote ids — do not upload.
  final bool refuseUpload;
}
