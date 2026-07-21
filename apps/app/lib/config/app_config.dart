class AppConfig {
  AppConfig._();

  static const String appUrl = String.fromEnvironment(
    'APP_URL',
    defaultValue: '',
  );

  static const String _configuredApiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: '',
  );

  static String get apiUrl {
    if (_configuredApiUrl.trim().isNotEmpty) {
      return _configuredApiUrl;
    }
    if (appUrl.trim().isNotEmpty) {
      return appUrl;
    }
    return 'http://10.0.2.2:4000';
  }

  static bool get hasApiUrl => apiUrl.trim().isNotEmpty;

  /// Contact address shown wherever we need a human fallback (e.g. password
  /// reset, which the backend does not support yet — no SMTP configured).
  static const String supportEmail = 'support@rightanswer.app';
}
