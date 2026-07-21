import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  static final SpeechService instance = SpeechService._();
  SpeechService._();

  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _available = false;
  void Function(String status)? _statusListener;
  void Function(String error)? _errorListener;

  bool get isListening => _stt.isListening;

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    _statusListener = onStatus;
    _errorListener = onError;
    if (_initialized) return _available;
    try {
      _available = await _stt.initialize(
        onStatus: (status) => _statusListener?.call(status),
        onError: (error) => _errorListener?.call(error.errorMsg),
      );
    } catch (_) {
      _available = false;
    }
    _initialized = true;
    return _available;
  }

  Future<bool> startListening({
    required void Function(String words, bool isFinal) onResult,
    String? localeId,
    void Function(String status)? onStatus,
    void Function(String error)? onError,
    void Function(double level)? onSoundLevelChange,
  }) async {
    if (!await initialize(onStatus: onStatus, onError: onError)) return false;
    if (_stt.isListening) await _stt.stop();
    try {
      await _stt.listen(
        onResult: (r) => onResult(r.recognizedWords, r.finalResult),
        onSoundLevelChange: onSoundLevelChange,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 90),
          pauseFor: const Duration(seconds: 5),
          partialResults: true,
          cancelOnError: true,
          localeId: localeId,
        ),
      );
      return _stt.isListening;
    } catch (_) {
      onError?.call('Could not start speech recognition.');
      return false;
    }
  }

  Future<void> stop() => _stt.stop();
  Future<void> cancel() => _stt.cancel();
}
