/// Google OAuth + allowlist for Sign-In / Drive sync.
///
/// Build/run:
/// ```
/// flutter build web \
///   --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_ALLOWED_EMAILS=you@gmail.com,other@gmail.com
/// ```
class GoogleAuthConfig {
  static const clientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  /// Comma-separated Gmail addresses (case-insensitive).
  static const allowedEmailsRaw = String.fromEnvironment(
    'GOOGLE_ALLOWED_EMAILS',
    defaultValue: '',
  );

  static bool get isConfigured =>
      clientId.trim().isNotEmpty && allowedEmails.isNotEmpty;

  /// Normalized allowlist (lowercase, trimmed, non-empty).
  static Set<String> get allowedEmails {
    return allowedEmailsRaw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty && e.contains('@'))
        .toSet();
  }

  static bool isEmailAllowed(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    return allowedEmails.contains(email.trim().toLowerCase());
  }

  /// Drive scope: hidden app-data folder (not visible in the user's My Drive).
  static const driveScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
    'email',
    'openid',
  ];

  static const syncFileName = 'expense_track_sync.json';
}
