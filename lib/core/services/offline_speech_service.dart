import 'package:flutter/services.dart';

enum OfflineSpeechState { installed, downloadable, unsupported, unknown }

/// Asks Android (13+) whether a language's on-device speech pack is
/// installed, and can trigger its download. Without the pack, speech
/// recognition falls back to Google's servers and fails with no internet.
class OfflineSpeechService {
  OfflineSpeechService._internal();

  static final OfflineSpeechService instance = OfflineSpeechService._internal();

  static const _channel = MethodChannel('translation/offline_speech');

  Future<OfflineSpeechState> status(String localeId) async {
    try {
      final value = await _channel.invokeMethod<String>('status', {'locale': localeId});
      return switch (value) {
        'installed' => OfflineSpeechState.installed,
        'downloadable' => OfflineSpeechState.downloadable,
        'unsupported' => OfflineSpeechState.unsupported,
        _ => OfflineSpeechState.unknown,
      };
    } catch (_) {
      return OfflineSpeechState.unknown;
    }
  }

  /// Languages whose on-device speech pack is installed, as (tag, name).
  /// Empty when the phone can't report it (before Android 13).
  Future<List<({String tag, String name})>> installedLanguages() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('languages') ?? const [];
      return [
        for (final item in raw)
          if (item is Map) (tag: item['tag'] as String, name: item['name'] as String),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Asks the system to download the pack (needs internet once).
  Future<void> download(String localeId) async {
    try {
      await _channel.invokeMethod<bool>('download', {'locale': localeId});
    } catch (_) {}
  }
}
