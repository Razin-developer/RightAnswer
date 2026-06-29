class AppConfig {
  AppConfig._();

  static const String openAiApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static bool get hasOpenAiApiKey => openAiApiKey.trim().isNotEmpty;
}
