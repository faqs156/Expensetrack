/// Google OAuth login + allowlist.
///
/// ```
/// flutter build web \
///   --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_ALLOWED_EMAILS=you@gmail.com;other@gmail.com
/// ```
///
/// Prefer `;` between emails (commas can break some CI shells). Commas still work
/// when the whole define is quoted.
class GoogleAuthConfig {
  static const clientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  /// Separated by `;` or `,` (case-insensitive).
  static const allowedEmailsRaw = String.fromEnvironment(
    'GOOGLE_ALLOWED_EMAILS',
    defaultValue: '',
  );

  static bool get isConfigured =>
      clientId.trim().isNotEmpty && allowedEmails.isNotEmpty;

  /// Normalized allowlist (lowercase).
  static Set<String> get allowedEmails {
    return allowedEmailsRaw
        .split(RegExp(r'[,;\n]+'))
        .map((e) => e.trim().toLowerCase())
        .map((e) {
          // Strip accidental quotes from GitHub secrets / shell.
          if (e.length >= 2 &&
              ((e.startsWith('"') && e.endsWith('"')) ||
                  (e.startsWith("'") && e.endsWith("'")))) {
            return e.substring(1, e.length - 1).trim();
          }
          return e;
        })
        .where((e) => e.isNotEmpty && e.contains('@'))
        .toSet();
  }

  static bool isEmailAllowed(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    return allowedEmails.contains(email.trim().toLowerCase());
  }

  /// Only Drive — used for authorizeScopes / API calls (avoid extra popups).
  static const driveScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  /// Hint during authenticate() only.
  static const signInScopeHint = <String>[
    'email',
    'openid',
    ...driveScopes,
  ];

  static const syncFileName = 'expense_track_sync.json';

  /// Previous Drive copy — used to recover if a device overwrote with older data.
  static const syncPrevFileName = 'expense_track_sync.prev.json';

  /// How often to pull/push Drive while the app is open and Google is connected.
  static const periodicSyncInterval = Duration(minutes: 2);

  /// Faster retry while account upload is still in flight.
  static const pendingPushRetryInterval = Duration(seconds: 45);
}
