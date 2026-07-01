class AppConfig {
  AppConfig._();

  static const String openAiApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000', // Android emulator → localhost
  );

  static bool get hasOpenAiApiKey => openAiApiKey.trim().isNotEmpty;
  static bool get hasApiUrl => apiUrl.trim().isNotEmpty;
}
