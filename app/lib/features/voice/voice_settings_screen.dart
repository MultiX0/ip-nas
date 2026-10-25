// Voice settings: Fish Audio key, voice gallery, speed, latency, speech recognition language, Drama 3 direction.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/provider_logo.dart';
import 'fish_audio.dart';
import 'voice_fx.dart';
import 'voice_gallery.dart';
import 'voice_orb.dart';
import 'voice_prefs.dart';

class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});
  @override
  ConsumerState<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  final _key = TextEditingController();
  bool _obscure = true;
  bool _checking = false;
  String? _keyStatus;
  bool _keyOk = false;
  bool _loadedKey = false;
  double? _speedDraft;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveAndValidate() async {
    final key = _key.text.trim();
    setState(() => (_checking = true, _keyStatus = null));
    try {
      if (key.isEmpty) {
        await ref.read(voicePrefsProvider.notifier).setApiKey(null);
        if (mounted) setState(() => (_keyStatus = 'Key removed.', _keyOk = false));
        return;
      }
      final probe = FishAudio(key);
      try {
        await probe.validateKey();
      } finally {
        probe.close();
      }
      await ref.read(voicePrefsProvider.notifier).setApiKey(key);
      if (mounted) setState(() => (_keyStatus = 'Key works. Voice is ready.', _keyOk = true));
    } catch (e) {
      if (mounted) setState(() => (_keyStatus = '$e', _keyOk = false));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(voicePrefsProvider);
    final prefs = prefsAsync.value ?? const VoicePrefs();
    if (!_loadedKey && prefsAsync.hasValue) {
      _loadedKey = true;
      _key.text = prefs.apiKey ?? '';
    }
    final notifier = ref.read(voicePrefsProvider.notifier);
    final muted = TextStyle(color: context.nur.muted, fontSize: 13);

    Widget header(String t, [String? sub]) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (sub != null) ...[const SizedBox(height: 4), Text(sub, style: muted)],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Voice')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                VoiceOrbAvatar(tint: OrbTints.forVoice(prefs.voiceId), seed: OrbTints.seedFor(prefs.voiceId), size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          FishAudioLogo(size: 17, wordmark: true),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Drama 3',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Voice calls, voice messages and read-aloud use Fish Audio Drama 3. You need your own Fish Audio API key.', style: muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
          header('Fish Audio API key'),
          TextField(
            controller: _key,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'Paste your API key',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show key' : 'Hide key',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? NurIcons.visibility : NurIcons.visibilityOff),
              ),
            ),
            onSubmitted: (_) => _saveAndValidate(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: _checking ? null : _saveAndValidate,
                child: _checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save & check'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://fish.audio/app/api-keys'), mode: LaunchMode.externalApplication),
                icon: const Icon(NurIcons.externalLink, size: 16),
                label: const Text('Get a key'),
              ),
            ],
          ),
          if (_keyStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_keyStatus!, style: TextStyle(color: _keyOk ? NurColors.ok : NurColors.danger, fontSize: 13)),
            ),
          header('Voice', 'Selected: ${prefs.voiceName}'),
          const VoiceGallery(),
          header('Speaking speed', '${(_speedDraft ?? prefs.speed).toStringAsFixed(2)}x'),
          Slider(
            value: (_speedDraft ?? prefs.speed).clamp(0.5, 2.0),
            min: 0.5,
            max: 2.0,
            divisions: 30,
            onChanged: (v) => setState(() => _speedDraft = v),
            onChangeEnd: (v) async {
              await notifier.setSetting('voice_speed', v.toStringAsFixed(2));
              if (mounted) setState(() => _speedDraft = null);
            },
          ),
          header('Response speed', 'Lower latency starts speaking sooner; normal sounds best.'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'low', label: Text('Fastest')),
              ButtonSegment(value: 'balanced', label: Text('Balanced')),
              ButtonSegment(value: 'normal', label: Text('Best quality')),
            ],
            selected: {prefs.latency},
            onSelectionChanged: (v) => notifier.setSetting('voice_latency', v.first),
          ),
          header('Speech recognition language', 'Auto works for mixed Arabic and English. Pick one if words get misheard.'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Auto')),
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {prefs.sttLanguage},
            onSelectionChanged: (v) => notifier.setSetting('stt_language', v.first),
          ),
          header('Performance'),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('Drama 3 performance direction'),
            subtitle: Text(
              'Let the assistant add acting cues like [warmly] or <whisper> to spoken replies. Cues are hidden from captions.',
              style: muted,
            ),
            value: prefs.direction,
            onChanged: (v) => notifier.setSetting('voice_direction', v ? 'true' : 'false'),
          ),
        ],
      ),
    );
  }
}
