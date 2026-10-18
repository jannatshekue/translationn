import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/services/offline_language_service.dart';
import '../../../../core/services/offline_speech_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/stt_service.dart';
import '../../../../core/services/translation_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/utils/app_permissions.dart';
import '../../../../core/utils/priority_languages.dart';
import '../../../../routes/app_routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/section_card.dart';

/// Two-person conversation mode: each participant picks their own language.
/// Whoever taps their mic has their speech recognized in their language,
/// translated into the other participant's language, and the translation is
/// shown as text and spoken aloud on the other participant's side.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

enum _ActiveSpeaker { none, personA, personB }

class _ConversationScreenState extends State<ConversationScreen> {
  List<LocaleName> _locales = [];
  String _personALocale = 'en-US';
  String _personBLocale = 'en-US';

  String _personAText = '';
  String _personBText = '';
  _ActiveSpeaker _activeSpeaker = _ActiveSpeaker.none;
  String _status = 'Pick each person\'s language, then tap their mic to speak';

  @override
  void initState() {
    super.initState();
    _loadLocales();
  }

  String _norm(String id) => id.replaceAll('_', '-').toLowerCase();

  Future<void> _loadLocales() async {
    final pluginLocales = await SttService.instance.getAvailableLocalesIfPermitted();
    if (!mounted) return;

    // The speech engine's own list can omit languages whose offline pack is
    // installed (and lists ones that only work online). Add every installed
    // offline language so the picker always offers what works with no internet.
    final installed = pluginLocales.isEmpty ? <({String tag, String name})>[] : await OfflineSpeechService.instance.installedLanguages();
    final known = pluginLocales.map((l) => _norm(l.localeId)).toSet();
    final merged = [
      ...pluginLocales,
      for (final lang in installed)
        if (!known.contains(_norm(lang.tag))) LocaleName(lang.tag.replaceAll('-', '_'), lang.name),
    ];
    final locales = sortByPriorityWith(merged, (l) => l.localeId);

    // Both people default to an installed offline English (US first).
    String? defaultLocale;
    final installedEnglish = installed
        .where((l) => _norm(l.tag).startsWith('en-'))
        .map((l) => l.tag.replaceAll('-', '_'))
        .toList()
      ..sort((a, b) => (_norm(a) == 'en-us' ? 0 : 1).compareTo(_norm(b) == 'en-us' ? 0 : 1));
    if (installedEnglish.isNotEmpty) {
      defaultLocale = installedEnglish.first;
    } else if (locales.isNotEmpty) {
      final english = locales.where((l) => _norm(l.localeId).startsWith('en-')).map((l) => l.localeId).toList()
        ..sort((a, b) => (_norm(a) == 'en-us' ? 0 : 1).compareTo(_norm(b) == 'en-us' ? 0 : 1));
      defaultLocale = english.isNotEmpty ? english.first : locales.first.localeId;
    }

    if (!mounted) return;
    setState(() {
      _locales = locales;
      if (defaultLocale != null) {
        _personALocale = defaultLocale;
        _personBLocale = defaultLocale;
      }
    });
    _refreshOffline();
  }

  /// Offline readiness of the two chosen languages (see
  /// [OfflineLanguageService]); drives the single strip under the header.
  final Map<String, OfflineLanguageStatus> _offline = {};
  bool _offlineWorking = false;

  List<String> get _chosenLocales =>
      _personALocale == _personBLocale ? [_personALocale] : [_personALocale, _personBLocale];

  Future<void> _refreshOffline() async {
    for (final id in _chosenLocales) {
      final status = await OfflineLanguageService.instance.status(id);
      if (!mounted) return;
      setState(() => _offline[id] = status);
    }
  }

  /// One-time download of whatever the chosen languages are missing.
  Future<void> _downloadOffline() async {
    setState(() => _offlineWorking = true);
    for (final id in _chosenLocales) {
      if (_offline[id]?.needsDownload != true) continue;
      final result = await OfflineLanguageService.instance.download(id);
      if (!mounted) return;
      if (result == OfflineDownloadResult.noInternet) {
        setState(() => _status = 'No internet — connect once, then tap Download again.');
        break;
      }
    }
    await _refreshOffline();
    if (mounted) setState(() => _offlineWorking = false);
  }

  String _languageName(String localeId) {
    final match = _locales.where((l) => l.localeId == localeId);
    return (match.isEmpty ? localeId : match.first.name).split(' (').first;
  }

  /// Quiet by default: a single muted line when everything works offline,
  /// and a banner with a Download button only when something is missing.
  Widget _offlineStrip() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statuses = [for (final id in _chosenLocales) ?_offline[id]];
    if (statuses.isEmpty) return const SizedBox.shrink();

    final needs = statuses.where((s) => s.needsDownload).toList();
    final onlineOnly = statuses.where((s) => s.speechNeedsInternet).toList();
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    String names(List<OfflineLanguageStatus> list) => list.map((s) => _languageName(s.localeId)).toSet().join(' and ');

    Widget note(IconData icon, String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: muted)),
          ]),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (needs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(Icons.download_for_offline_outlined, size: 20, color: scheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Download ${names(needs)} to use without internet',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                ),
                const SizedBox(width: 8),
                _offlineWorking
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : FilledButton.tonal(onPressed: _downloadOffline, child: const Text('Download')),
              ]),
            ),
          ),
        if (onlineOnly.isNotEmpty)
          note(Icons.cloud_outlined, 'Speaking ${names(onlineOnly)} needs internet on this phone')
        else if (needs.isEmpty)
          note(Icons.offline_pin_outlined, 'Works without internet'),
      ],
    );
  }

  Future<void> _startTurn(_ActiveSpeaker speaker) async {
    if (_activeSpeaker != _ActiveSpeaker.none) return;
    SettingsService.instance.hapticTap();

    if (!mounted) return;
    final micGranted = await AppPermissions.ensure(context, Permission.microphone, announceDenial: false);
    if (!micGranted) {
      if (mounted) setState(() => _status = AppPermissions.neededMessage(Permission.microphone));
      return;
    }
    await Permission.speech.request();

    final available = await SttService.instance.initialize();
    if (!available) {
      setState(() => _status = 'Speech recognition unavailable on this device.');
      return;
    }
    // The language lists stay empty until the microphone is allowed.
    if (_locales.isEmpty) await _loadLocales();

    setState(() {
      _activeSpeaker = speaker;
      _status = 'Listening…';
      if (speaker == _ActiveSpeaker.personA) {
        _personAText = '';
      } else {
        _personBText = '';
      }
    });

    final speakerLocale = speaker == _ActiveSpeaker.personA ? _personALocale : _personBLocale;

    await SttService.instance.startListening(
      (text, isFinal) {
        setState(() {
          if (speaker == _ActiveSpeaker.personA) {
            _personAText = text;
          } else {
            _personBText = text;
          }
        });
        if (isFinal) _finishTurn(speaker);
      },
      localeId: speakerLocale,
      onError: (error) {
        if (!mounted || _activeSpeaker == _ActiveSpeaker.none) return;
        // The recognizer ends with "no match"/"timeout" at a long pause even
        // when it already heard words: translate those instead of dropping them.
        final heard = speaker == _ActiveSpeaker.personA ? _personAText : _personBText;
        if ((error == 'error_no_match' || error == 'error_speech_timeout') && heard.trim().isNotEmpty) {
          _finishTurn(speaker);
          return;
        }
        SttService.instance.stopListening();
        setState(() {
          _activeSpeaker = _ActiveSpeaker.none;
          _status = error == 'error_network' || error == 'error_network_timeout' || SttService.instance.lastErrorIsMissingOfflinePack
              ? 'No offline speech pack for this language and no internet. Connect once and tap Download above.'
              : error == 'error_no_match' || error == 'error_speech_timeout'
                  ? 'Didn\'t catch that — try again'
                  : 'Speech recognition error: $error';
        });
      },
    );
  }

  Future<void> _finishTurn(_ActiveSpeaker speaker) async {
    await SttService.instance.stopListening();
    final spokenText = speaker == _ActiveSpeaker.personA ? _personAText : _personBText;
    setState(() => _activeSpeaker = _ActiveSpeaker.none);

    if (spokenText.trim().isEmpty) {
      setState(() => _status = SttService.instance.lastErrorIsMissingOfflinePack
          ? 'This language isn\'t installed for offline speech. Open Android Settings > Google > Speech > Offline speech recognition and download it.'
          : 'Didn\'t catch that — try again');
      return;
    }

    final speakerLocale = speaker == _ActiveSpeaker.personA ? _personALocale : _personBLocale;
    final listenerLocale = speaker == _ActiveSpeaker.personA ? _personBLocale : _personALocale;
    final fromLang = TranslationService.languageFor(speakerLocale);
    final toLang = TranslationService.languageFor(listenerLocale);

    if (fromLang == null || toLang == null) {
      setState(() => _status = 'Translation isn\'t supported for one of these languages');
      return;
    }

    setState(() => _status = 'Translating…');
    try {
      final translated = await TranslationService.instance.translate(
        spokenText,
        from: fromLang,
        to: toLang,
      );
      setState(() {
        if (speaker == _ActiveSpeaker.personA) {
          _personBText = translated;
        } else {
          _personAText = translated;
        }
        _status = 'Pick each person\'s language, then tap their mic to speak';
      });
      SettingsService.instance.hapticImpact();
      await TtsService.instance.speak(translated, language: listenerLocale);
    } on LanguagePackMissing catch (e) {
      setState(() => _status = e.toString());
    } catch (e) {
      setState(() => _status = 'Translation failed: $e');
    }
  }

  Future<void> _cancelTurn() async {
    if (_activeSpeaker == _ActiveSpeaker.none) return;
    await SttService.instance.stopListening();
    setState(() {
      _activeSpeaker = _ActiveSpeaker.none;
      _status = 'Pick each person\'s language, then tap their mic to speak';
    });
  }

  @override
  void dispose() {
    SttService.instance.stopListening();
    super.dispose();
  }

  Widget _buildSide({
    required String title,
    required Color color,
    required String localeId,
    required ValueChanged<String> onLocaleChanged,
    required String text,
    required bool isListening,
    required bool isDisabled,
    required VoidCallback onMicTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Expanded(
      child: SectionCard(
        padding: const EdgeInsets.all(14),
        borderColor: isListening ? color : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            if (_locales.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: localeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: [
                  for (final locale in _locales)
                    DropdownMenuItem(
                      value: locale.localeId,
                      child: Text(locale.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onLocaleChanged(value);
                },
              ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SingleChildScrollView(
                  child: text.isEmpty
                      ? Text(
                          isListening ? 'Listening…' : 'Tap the mic to speak',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        )
                      : Text(text, style: theme.textTheme.titleMedium?.copyWith(height: 1.35)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: PressableScale(
                borderRadius: BorderRadius.circular(32),
                onTap: isDisabled ? null : onMicTap,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDisabled
                        ? scheme.surfaceContainerHigh
                        : (isListening ? AppTheme.emergency : color),
                  ),
                  child: Icon(
                    isListening ? Icons.stop_rounded : Icons.mic,
                    size: 28,
                    color: isDisabled ? scheme.onSurfaceVariant : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Conversation mode')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 0, AppTheme.screenPadding, 16),
          child: Column(
            children: [
              SectionCard(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_status, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _offlineStrip(),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.deviceSync),
                  icon: const Icon(Icons.bluetooth_connected, size: 18),
                  label: const Text('Each have your own phone? Connect devices'),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSide(
                      title: 'Person A',
                      color: scheme.primary,
                      localeId: _personALocale,
                      onLocaleChanged: (value) {
                        setState(() => _personALocale = value);
                        _refreshOffline();
                      },
                      text: _personAText,
                      isListening: _activeSpeaker == _ActiveSpeaker.personA,
                      isDisabled: _activeSpeaker == _ActiveSpeaker.personB,
                      onMicTap: () => _activeSpeaker == _ActiveSpeaker.personA
                          ? _cancelTurn()
                          : _startTurn(_ActiveSpeaker.personA),
                    ),
                    const SizedBox(width: 12),
                    _buildSide(
                      title: 'Person B',
                      color: scheme.secondary,
                      localeId: _personBLocale,
                      onLocaleChanged: (value) {
                        setState(() => _personBLocale = value);
                        _refreshOffline();
                      },
                      text: _personBText,
                      isListening: _activeSpeaker == _ActiveSpeaker.personB,
                      isDisabled: _activeSpeaker == _ActiveSpeaker.personA,
                      onMicTap: () => _activeSpeaker == _ActiveSpeaker.personB
                          ? _cancelTurn()
                          : _startTurn(_ActiveSpeaker.personB),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
