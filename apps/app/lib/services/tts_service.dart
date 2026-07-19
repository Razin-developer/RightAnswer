import 'dart:convert';

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
    final trimmed = _speakerText(text).trim();
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

  String _speakerText(String raw) {
    final rich = _speechTextFromRichAnswer(raw);
    if (rich != null && rich.trim().isNotEmpty) {
      return rich;
    }

    var text = raw;
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    text = text.replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), ' formula ');
    text = text.replaceAll(RegExp(r'\$([^$]+)\$'), r' $1 ');
    text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), r'image $1');
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
    text = text.replaceAll(RegExp(r'[*_`~>#|]'), ' ');
    text = text.replaceAll(RegExp(r'^\s*[-+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+'), ' ');
    text = text.replaceAll(RegExp(r'[{}\\]'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  String? _speechTextFromRichAnswer(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    String candidate = trimmed;
    final fenced = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      multiLine: true,
    ).firstMatch(trimmed);
    if (fenced != null) {
      candidate = fenced.group(1) ?? trimmed;
    } else {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start >= 0 && end > start) {
        candidate = trimmed.substring(start, end + 1);
      }
    }

    try {
      final decoded = jsonDecode(candidate);
      if (decoded is! Map<String, dynamic>) return null;
      final speechText = decoded['speechText'];
      if (speechText is String && speechText.trim().isNotEmpty) {
        return speechText;
      }
      final markdown = decoded['renderMarkdown'];
      return markdown is String ? _speakerText(markdown) : null;
    } catch (_) {
      return null;
    }
  }
}
