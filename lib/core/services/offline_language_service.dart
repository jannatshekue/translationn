import 'offline_speech_service.dart';
import 'translation_service.dart';

/// Whether one language can be used with no internet: its on-device speech
/// pack (to hear it) and its on-device translation pack (to translate it).
class OfflineLanguageStatus {
  final String localeId;

  /// Null when ML Kit has no translation for this language at all.
  final bool? translation;
  final OfflineSpeechState speech;

  const OfflineLanguageStatus(this.localeId, this.translation, this.speech);

  /// Something is missing but a one-time download would fix it.
  bool get needsDownload => translation == false || speech == OfflineSpeechState.downloadable;

  /// This phone's speech engine has no offline version of the language.
  bool get speechNeedsInternet => speech == OfflineSpeechState.unsupported;
}

enum OfflineDownloadResult { done, noInternet }

class OfflineLanguageService {
  OfflineLanguageService._internal();

  static final OfflineLanguageService instance = OfflineLanguageService._internal();

  Future<OfflineLanguageStatus> status(String localeId) async {
    final lang = TranslationService.languageFor(localeId);
    final translation = lang == null ? null : await TranslationService.instance.isModelDownloaded(lang);
    final speech = await OfflineSpeechService.instance.status(localeId);
    return OfflineLanguageStatus(localeId, translation, speech);
  }

  /// Downloads whatever [localeId] is missing: the translation pack first
  /// (fails fast when there's no internet), then the speech pack, which
  /// Android asks the user to confirm and installs in the background.
  Future<OfflineDownloadResult> download(String localeId) async {
    final lang = TranslationService.languageFor(localeId);
    if (lang != null && !await TranslationService.instance.isModelDownloaded(lang)) {
      if (!await TranslationService.instance.prepareLanguage(lang)) {
        return OfflineDownloadResult.noInternet;
      }
    }
    if (await OfflineSpeechService.instance.status(localeId) == OfflineSpeechState.downloadable) {
      await OfflineSpeechService.instance.download(localeId);
      for (var i = 0; i < 40; i++) {
        await Future.delayed(const Duration(seconds: 3));
        if (await OfflineSpeechService.instance.status(localeId) == OfflineSpeechState.installed) break;
      }
    }
    return OfflineDownloadResult.done;
  }
}
