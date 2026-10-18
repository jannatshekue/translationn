import 'package:flutter/material.dart';

import '../../../../core/services/offline_language_service.dart';
import '../../../../core/services/offline_speech_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/translation_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/section_card.dart';

class _Lang {
  final String name;
  final String speechTag;
  const _Lang(this.name, this.speechTag);
}

/// Languages offered for offline use. Translation packs come from ML Kit
/// (which only covers Swahili and Afrikaans in Africa); speech packs come
/// from the phone's own speech engine and may be missing for some.
const _languages = [
  _Lang('English', 'en-US'),
  _Lang('Swahili', 'sw-KE'),
  _Lang('Afrikaans', 'af-ZA'),
  _Lang('Arabic', 'ar-EG'),
  _Lang('French', 'fr-FR'),
  _Lang('Spanish', 'es-ES'),
];

/// One-time "get ready for offline" step. Speech recognition and
/// translation need a language pack on the phone; downloading them needs
/// internet once, after which conversation mode works with no connection.
/// Shown after first launch, and reachable again from Settings.
class OfflineSetupScreen extends StatefulWidget {
  final bool firstRun;

  const OfflineSetupScreen({super.key, this.firstRun = false});

  @override
  State<OfflineSetupScreen> createState() => _OfflineSetupScreenState();
}

class _OfflineSetupScreenState extends State<OfflineSetupScreen> {
  final Set<String> _selected = {'en-US', 'sw-KE'};
  final Map<String, bool?> _translation = {};
  final Map<String, OfflineSpeechState> _speech = {};
  final Map<String, String> _busy = {};
  bool _working = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refresh(_Lang lang) async {
    final t = TranslationService.languageFor(lang.speechTag);
    final translation = t == null ? null : await TranslationService.instance.isModelDownloaded(t);
    final speech = await OfflineSpeechService.instance.status(lang.speechTag);
    if (!mounted) return;
    setState(() {
      _translation[lang.speechTag] = translation;
      _speech[lang.speechTag] = speech;
    });
  }

  Future<void> _refreshAll() async {
    for (final lang in _languages) {
      await _refresh(lang);
    }
  }

  bool _ready(_Lang lang) {
    // Not "ready" until its status has actually been checked.
    if (!_translation.containsKey(lang.speechTag)) return false;
    final translation = _translation[lang.speechTag];
    final speech = _speech[lang.speechTag];
    final translationOk = translation != false;
    final speechOk = speech != OfflineSpeechState.downloadable;
    return translationOk && speechOk;
  }

  bool get _allSelectedReady =>
      _selected.isNotEmpty && _languages.where((l) => _selected.contains(l.speechTag)).every(_ready);

  Future<void> _download() async {
    setState(() {
      _working = true;
      _message = null;
    });
    final chosen = _languages.where((l) => _selected.contains(l.speechTag)).toList();

    for (final lang in chosen) {
      if (!mounted) return;
      setState(() => _busy[lang.speechTag] = 'Downloading… confirm any Android prompt');
      final result = await OfflineLanguageService.instance.download(lang.speechTag);
      _busy.remove(lang.speechTag);
      await _refresh(lang);
      if (result == OfflineDownloadResult.noInternet) {
        if (!mounted) return;
        setState(() {
          _working = false;
          _message = 'Couldn\'t download — connect to the internet, then tap Download again.';
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _working = false);
    if (_allSelectedReady) setState(() => _message = 'All set — these languages now work offline.');
  }

  Future<void> _finish() async {
    await SettingsService.instance.setOfflineSetupDone(true);
    if (!mounted) return;
    if (widget.firstRun) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    } else {
      Navigator.of(context).pop();
    }
  }

  String _statusText(_Lang lang) {
    final busy = _busy[lang.speechTag];
    if (busy != null) return busy;
    final translation = _translation[lang.speechTag];
    final speech = _speech[lang.speechTag];
    final parts = <String>[
      switch (translation) {
        true => 'Translation ready',
        false => 'Translation not downloaded',
        null => 'No translation available',
      },
      switch (speech) {
        OfflineSpeechState.installed => 'speech ready',
        OfflineSpeechState.downloadable => 'speech not downloaded',
        OfflineSpeechState.unsupported => 'speech unavailable on this phone',
        OfflineSpeechState.unknown || null => 'speech status unknown',
      },
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _allSelectedReady;

    return Scaffold(
      appBar: AppBar(title: const Text('Get ready for offline')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 4, AppTheme.screenPadding, 12),
                children: [
                  Text(
                    'Conversation mode needs a small language pack on your phone for each '
                    'language. Download them once now, while you have internet, and they '
                    'work with no connection afterwards.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  for (final lang in _languages) ...[
                    SectionCard(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: CheckboxListTile(
                        value: _selected.contains(lang.speechTag),
                        onChanged: _working
                            ? null
                            : (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(lang.speechTag);
                                  } else {
                                    _selected.remove(lang.speechTag);
                                  }
                                }),
                        title: Text(lang.name, style: theme.textTheme.titleMedium),
                        subtitle: Text(_statusText(lang)),
                        secondary: _busy.containsKey(lang.speechTag)
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(
                                _ready(lang) ? Icons.offline_pin : Icons.download_for_offline_outlined,
                                color: _ready(lang) ? scheme.primary : scheme.onSurfaceVariant,
                              ),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_message!, style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 4, AppTheme.screenPadding, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _working ? null : (done ? _finish : (_selected.isEmpty ? null : _download)),
                    child: Text(_working ? 'Downloading…' : (done ? 'Continue' : 'Download selected')),
                  ),
                  if (!done)
                    TextButton(
                      onPressed: _working ? null : _finish,
                      child: Text(widget.firstRun ? 'Skip for now' : 'Close'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
