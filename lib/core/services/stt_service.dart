import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wraps the on-device (offline) speech recognizer. This is the default path
/// per the offline-first requirement; the online Google Speech-to-Text API
/// path is a separate, later addition for when connectivity is available and
/// higher accuracy is wanted — it must never be required for this to work.
class SttService {
  SttService._internal();

  static final SttService instance = SttService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  List<LocaleName>? _cachedLocales;

  /// Last recognizer error (e.g. `error_language_unavailable`), cleared at
  /// the start of every listen. Screens read this to explain a failed turn.
  String? lastError;

  void Function(String error)? _errorHandler;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _speech.initialize(
      onError: (error) {
        lastError = error.errorMsg;
        _errorHandler?.call(error.errorMsg);
      },
    );
    return _isInitialized;
  }

  /// True when [lastError] means the offline language pack for the chosen
  /// language isn't installed on the phone.
  bool get lastErrorIsMissingOfflinePack =>
      lastError == 'error_language_unavailable' || lastError == 'error_language_not_supported';

  /// Locales this device's speech recognizer actually supports. Cached
  /// after the first call — this list doesn't change during a session.
  Future<List<LocaleName>> getAvailableLocales() async {
    final cached = _cachedLocales;
    if (cached != null) return cached;
    final available = await initialize();
    if (!available) return const [];
    final locales = await _speech.locales();
    _cachedLocales = locales;
    return locales;
  }

  /// Like [getAvailableLocales], but never triggers Android's microphone
  /// prompt: starting the recognizer is what asks for the microphone, so
  /// calling it when a screen merely opens would pop the system prompt
  /// before the app has explained why. Returns an empty list until the
  /// microphone has been allowed; screens reload after they obtain it.
  Future<List<LocaleName>> getAvailableLocalesIfPermitted() async {
    if (!await Permission.microphone.isGranted) return const [];
    return getAvailableLocales();
  }

  /// Starts listening. Pass [localeId] (from [getAvailableLocales]) to
  /// recognize a specific language; omit it to use the system default.
  /// [onResult] receives the recognized text so far and whether the
  /// recognizer has determined the utterance is complete (useful for
  /// turn-based flows that should act once the speaker finishes).
  Future<void> startListening(
    void Function(String recognizedText, bool isFinal) onResult, {
    String? localeId,
    void Function(String error)? onError,
  }) async {
    final available = await initialize();
    if (!available) return;
    lastError = null;
    // Offline first: onDevice forces the local recognizer (Android's default
    // one sends audio to Google). If this language has no offline pack, fall
    // back once to the online recognizer, which works whenever there is a
    // connection; only if that fails too is the error reported.
    var onDevice = true;
    Future<void> listen() => _speech.listen(
          onResult: (result) => onResult(result.recognizedWords, result.finalResult),
          listenOptions: SpeechListenOptions(localeId: localeId, onDevice: onDevice),
        );
    _errorHandler = (error) {
      if (onDevice && lastErrorIsMissingOfflinePack) {
        onDevice = false;
        lastError = null;
        listen();
        return;
      }
      onError?.call(error);
    };
    await listen();
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}
