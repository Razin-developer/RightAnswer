import 'package:flutter_tts/flutter_tts.dart';

import '../constants/app_languages.dart';

class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  Future<void> initialize() async {
    try {
      await _tts.setLanguage(defaultSpeechLocale);
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _speaking = false);
    } catch (_) {
      _speaking = false;
    }
  }

  Future<void> speak(String text, {String? language}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_speaking) await stop();
    try {
      final locale = speechLocaleForLanguage(language) ?? defaultSpeechLocale;
      await _tts.setLanguage(locale);
      _speaking = true;
      await _tts.speak(trimmed);
    } catch (_) {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore plugin teardown issues and keep the UI responsive.
    }
  }

  Future<void> toggle(String text, {String? language}) async {
    _speaking ? await stop() : await speak(text, language: language);
  }
}
