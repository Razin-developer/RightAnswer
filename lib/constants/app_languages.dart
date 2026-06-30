class AppLanguageOption {
  final String code;
  final String label;
  final String speechLocale;

  const AppLanguageOption({
    required this.code,
    required this.label,
    required this.speechLocale,
  });
}

const String autoResponseLanguageLabel = 'Auto';
const String defaultSpeechLocale = 'en-US';

const List<AppLanguageOption> appLanguageOptions = [
  AppLanguageOption(code: 'sq', label: 'Albanian', speechLocale: 'sq-AL'),
  AppLanguageOption(code: 'am', label: 'Amharic', speechLocale: 'am-ET'),
  AppLanguageOption(code: 'ar', label: 'Arabic', speechLocale: 'ar-SA'),
  AppLanguageOption(code: 'hy', label: 'Armenian', speechLocale: 'hy-AM'),
  AppLanguageOption(code: 'bn', label: 'Bengali', speechLocale: 'bn-IN'),
  AppLanguageOption(code: 'bs', label: 'Bosnian', speechLocale: 'bs-BA'),
  AppLanguageOption(code: 'bg', label: 'Bulgarian', speechLocale: 'bg-BG'),
  AppLanguageOption(code: 'my', label: 'Burmese', speechLocale: 'my-MM'),
  AppLanguageOption(code: 'ca', label: 'Catalan', speechLocale: 'ca-ES'),
  AppLanguageOption(code: 'zh', label: 'Chinese', speechLocale: 'zh-CN'),
  AppLanguageOption(code: 'hr', label: 'Croatian', speechLocale: 'hr-HR'),
  AppLanguageOption(code: 'cs', label: 'Czech', speechLocale: 'cs-CZ'),
  AppLanguageOption(code: 'da', label: 'Danish', speechLocale: 'da-DK'),
  AppLanguageOption(code: 'nl', label: 'Dutch', speechLocale: 'nl-NL'),
  AppLanguageOption(code: 'en', label: 'English', speechLocale: 'en-US'),
  AppLanguageOption(code: 'et', label: 'Estonian', speechLocale: 'et-EE'),
  AppLanguageOption(code: 'fi', label: 'Finnish', speechLocale: 'fi-FI'),
  AppLanguageOption(code: 'fr', label: 'French', speechLocale: 'fr-FR'),
  AppLanguageOption(code: 'ka', label: 'Georgian', speechLocale: 'ka-GE'),
  AppLanguageOption(code: 'de', label: 'German', speechLocale: 'de-DE'),
  AppLanguageOption(code: 'el', label: 'Greek', speechLocale: 'el-GR'),
  AppLanguageOption(code: 'gu', label: 'Gujarati', speechLocale: 'gu-IN'),
  AppLanguageOption(code: 'hi', label: 'Hindi', speechLocale: 'hi-IN'),
  AppLanguageOption(code: 'hu', label: 'Hungarian', speechLocale: 'hu-HU'),
  AppLanguageOption(code: 'is', label: 'Icelandic', speechLocale: 'is-IS'),
  AppLanguageOption(code: 'id', label: 'Indonesian', speechLocale: 'id-ID'),
  AppLanguageOption(code: 'it', label: 'Italian', speechLocale: 'it-IT'),
  AppLanguageOption(code: 'ja', label: 'Japanese', speechLocale: 'ja-JP'),
  AppLanguageOption(code: 'kn', label: 'Kannada', speechLocale: 'kn-IN'),
  AppLanguageOption(code: 'kk', label: 'Kazakh', speechLocale: 'kk-KZ'),
  AppLanguageOption(code: 'ko', label: 'Korean', speechLocale: 'ko-KR'),
  AppLanguageOption(code: 'lv', label: 'Latvian', speechLocale: 'lv-LV'),
  AppLanguageOption(code: 'lt', label: 'Lithuanian', speechLocale: 'lt-LT'),
  AppLanguageOption(code: 'mk', label: 'Macedonian', speechLocale: 'mk-MK'),
  AppLanguageOption(code: 'ms', label: 'Malay', speechLocale: 'ms-MY'),
  AppLanguageOption(code: 'ml', label: 'Malayalam', speechLocale: 'ml-IN'),
  AppLanguageOption(code: 'mr', label: 'Marathi', speechLocale: 'mr-IN'),
  AppLanguageOption(code: 'mn', label: 'Mongolian', speechLocale: 'mn-MN'),
  AppLanguageOption(code: 'no', label: 'Norwegian', speechLocale: 'no-NO'),
  AppLanguageOption(code: 'fa', label: 'Persian', speechLocale: 'fa-IR'),
  AppLanguageOption(code: 'pl', label: 'Polish', speechLocale: 'pl-PL'),
  AppLanguageOption(code: 'pt', label: 'Portuguese', speechLocale: 'pt-PT'),
  AppLanguageOption(code: 'pa', label: 'Punjabi', speechLocale: 'pa-IN'),
  AppLanguageOption(code: 'ro', label: 'Romanian', speechLocale: 'ro-RO'),
  AppLanguageOption(code: 'ru', label: 'Russian', speechLocale: 'ru-RU'),
  AppLanguageOption(code: 'sr', label: 'Serbian', speechLocale: 'sr-RS'),
  AppLanguageOption(code: 'sk', label: 'Slovak', speechLocale: 'sk-SK'),
  AppLanguageOption(code: 'sl', label: 'Slovenian', speechLocale: 'sl-SI'),
  AppLanguageOption(code: 'so', label: 'Somali', speechLocale: 'so-SO'),
  AppLanguageOption(code: 'es', label: 'Spanish', speechLocale: 'es-ES'),
  AppLanguageOption(code: 'sw', label: 'Swahili', speechLocale: 'sw-KE'),
  AppLanguageOption(code: 'sv', label: 'Swedish', speechLocale: 'sv-SE'),
  AppLanguageOption(code: 'tl', label: 'Tagalog', speechLocale: 'tl-PH'),
  AppLanguageOption(code: 'ta', label: 'Tamil', speechLocale: 'ta-IN'),
  AppLanguageOption(code: 'te', label: 'Telugu', speechLocale: 'te-IN'),
  AppLanguageOption(code: 'th', label: 'Thai', speechLocale: 'th-TH'),
  AppLanguageOption(code: 'tr', label: 'Turkish', speechLocale: 'tr-TR'),
  AppLanguageOption(code: 'uk', label: 'Ukrainian', speechLocale: 'uk-UA'),
  AppLanguageOption(code: 'ur', label: 'Urdu', speechLocale: 'ur-PK'),
  AppLanguageOption(code: 'vi', label: 'Vietnamese', speechLocale: 'vi-VN'),
];

List<String> get appLanguageLabels =>
    appLanguageOptions.map((option) => option.label).toList();

List<String> get appResponseLanguageLabels => [
  autoResponseLanguageLabel,
  ...appLanguageLabels,
];

bool isAutoResponseLanguage(String? value) {
  final normalized = value?.trim();
  return normalized == null ||
      normalized.isEmpty ||
      normalized == autoResponseLanguageLabel;
}

String? effectiveResponseLanguage(String? value) =>
    isAutoResponseLanguage(value) ? null : value!.trim();

String? speechLocaleForLanguage(String? language) {
  final target = effectiveResponseLanguage(language);
  if (target == null) return null;
  for (final option in appLanguageOptions) {
    if (option.label.toLowerCase() == target.toLowerCase()) {
      return option.speechLocale;
    }
  }
  return null;
}
