class AppConfig {
  AppConfig._();

  static const String openAiApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static const String hackClubApiKey = String.fromEnvironment(
    'HACKCLUB_API_KEY',
    defaultValue: '',
  );

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
    return 'http://10.0.2.2:3000';
  }

  static bool get hasOpenAiApiKey => openAiApiKey.trim().isNotEmpty;
  static bool get hasHackClubApiKey => hackClubApiKey.trim().isNotEmpty;
  static bool get hasAnyAiApiKey => hasOpenAiApiKey || hasHackClubApiKey;
  static bool get hasApiUrl => apiUrl.trim().isNotEmpty;
}
