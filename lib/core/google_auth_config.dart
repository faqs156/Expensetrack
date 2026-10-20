/// Google OAuth Web client ID for Sign-In + Drive app-data sync.
///
/// Pass at build/run time:
///   flutter build web --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
///
/// Also add the same value as a meta tag in `web/index.html` (see README).
class GoogleAuthConfig {
  static const clientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static bool get isConfigured => clientId.trim().isNotEmpty;

  /// Drive scope: hidden app-data folder (not visible in the user's My Drive).
  static const driveScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
    'email',
    'openid',
  ];

  static const syncFileName = 'expense_track_sync.json';
}
