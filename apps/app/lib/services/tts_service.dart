import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';

import '../constants/app_languages.dart';
import '../repositories/settings_repository.dart';

class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  final _settingsRepo = SettingsRepository();
  bool _speaking = false;
  double _speechRate = 0.5;

  // How much of the current streaming message's cleaned text has already
  // been queued for speech (see speakStreamingUpdate/finishStreaming).
  int _spokenLength = 0;

  bool get isSpeaking => _speaking;
  double get speechRate => _speechRate;

  Future<void> initialize() async {
    try {
      final saved = await _settingsRepo.get(SettingKeys.ttsSpeechRate);
      final rate = double.tryParse(saved ?? '');
      _speechRate = (rate != null && rate >= 0.25 && rate <= 1.0) ? rate : 0.5;

      await _tts.setLanguage(defaultSpeechLocale);
      await _tts.setSpeechRate(_speechRate);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _speaking = false);
    } catch (_) {
      _speaking = false;
    }
  }

  /// Persists and applies a new reading speed (0.25x-1.0x). Values outside
  /// that range are clamped rather than rejected, so a slider that somehow
  /// reports an out-of-range value (rounding, a future UI change) can never
  /// hand the plugin a rate it might reject.
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.25, 1.0);
    try {
      await _tts.setSpeechRate(_speechRate);
    } catch (_) {
      // Non-fatal — the rate still applies to the next speak() call's
      // setLanguage/setSpeechRate cycle even if this immediate call failed.
    }
    await _settingsRepo.set(SettingKeys.ttsSpeechRate, _speechRate.toString());
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

  /// Call with the FULL text received so far on every streamed update.
  /// Speaks only the newly-arrived, sentence-complete portion since the
  /// last call (queued after any in-flight utterance), so playback starts
  /// as soon as the first sentence lands instead of waiting for the whole
  /// response to finish generating. Pair with [resetStreamingState] before
  /// starting a new message and [finishStreaming] once generation ends.
  Future<void> speakStreamingUpdate(String fullTextSoFar, {String? language}) async {
    final cleaned = _speakerText(fullTextSoFar);
    if (cleaned.length <= _spokenLength) return;
    final pending = cleaned.substring(_spokenLength);
    final boundary = _lastSentenceBoundary(pending);
    if (boundary <= 0) return;
    final chunk = pending.substring(0, boundary).trim();
    _spokenLength += boundary;
    if (chunk.isEmpty) return;
    await _enqueue(chunk, language: language);
  }

  /// Flushes any trailing partial sentence once generation has finished.
  Future<void> finishStreaming(String fullText, {String? language}) async {
    final cleaned = _speakerText(fullText);
    if (cleaned.length <= _spokenLength) return;
    final chunk = cleaned.substring(_spokenLength).trim();
    _spokenLength = cleaned.length;
    if (chunk.isEmpty) return;
    await _enqueue(chunk, language: language);
  }

  /// Resets the streaming cursor — call before speaking a new message.
  void resetStreamingState() {
    _spokenLength = 0;
  }

  Future<void> _enqueue(String chunk, {String? language}) async {
    try {
      final locale = speechLocaleForLanguage(language) ?? defaultSpeechLocale;
      await _tts.setLanguage(locale);
      _speaking = true;
      await _tts.speak(chunk);
    } catch (_) {
      _speaking = false;
    }
  }

  int _lastSentenceBoundary(String text) {
    for (var i = text.length - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '.' || ch == '!' || ch == '?' || ch == '\n') return i + 1;
    }
    return 0;
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
