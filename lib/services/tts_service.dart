import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  Future<void> initialize() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setErrorHandler((_) => _speaking = false);
  }

  Future<void> speak(String text) async {
    if (_speaking) await stop();
    _speaking = true;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
  }

  Future<void> toggle(String text) async {
    _speaking ? await stop() : await speak(text);
  }
}
