import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  static final SpeechService instance = SpeechService._();
  SpeechService._();

  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _available = false;

  bool get isListening => _stt.isListening;
  bool get isAvailable => _available;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _available = await _stt.initialize(
      onStatus: (_) {},
      onError: (_) {},
    );
    _initialized = true;
    return _available;
  }

  Future<bool> startListening({
    required void Function(String words, bool isFinal) onResult,
  }) async {
    if (!await initialize()) return false;
    if (_stt.isListening) await _stt.stop();
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
      ),
    );
    return _stt.isListening;
  }

  Future<void> stop() => _stt.stop();
  Future<void> cancel() => _stt.cancel();
}
