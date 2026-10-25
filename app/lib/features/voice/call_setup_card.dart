// Shown in the call screen when there is no working Fish Audio key: paste a key, it is checked, and the call starts.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/provider_logo.dart';
import 'fish_audio.dart';
import 'voice_fx.dart';
import 'voice_prefs.dart';

class CallSetupCard extends ConsumerStatefulWidget {
  const CallSetupCard({super.key, required this.onReady, this.message, this.outOfCredits = false});

  /// Called after a valid key was saved.
  final VoidCallback onReady;

  /// Why setup is shown again (e.g. the saved key was rejected).
  final String? message;
  final bool outOfCredits;

  @override
  ConsumerState<CallSetupCard> createState() => _CallSetupCardState();
}

class _CallSetupCardState extends ConsumerState<CallSetupCard> {
  final _key = TextEditingController();
  bool _obscure = true;
  bool _checking = false;
  String? _error;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isNotEmpty) {
      _key.text = t;
      setState(() => _error = null);
    }
  }

  Future<void> _continue() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Paste your Fish Audio API key first.');
      return;
    }
    setState(() => (_checking = true, _error = null));
    final probe = FishAudio(key);
    try {
      await probe.validateKey();
      await ref.read(voicePrefsProvider.notifier).setApiKey(key);
      if (!mounted) return;
      haptic(Haptic.heavy);
      setState(() => _ok = true);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted) widget.onReady();
    } catch (e) {
      haptic(Haptic.warn);
      if (mounted) setState(() => _error = '$e');
    } finally {
      probe.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: NurColors.g400, fontSize: 14, height: 1.45);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF111114).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 16))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                  child: const FishAudioLogo(size: 28, onDark: true, excludeFromSemantics: true),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Give Nur a voice',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Fish Audio Drama 3',
                        style: TextStyle(color: NurColors.g500, fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.outOfCredits
                  ? 'Your Fish Audio account is out of credits. Top up, or paste a different key to keep talking.'
                  : 'Voice calls use Fish Audio Drama 3 for natural, expressive speech. Paste your API key to start. It stays on this device.',
              style: muted,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_checking && !_ok,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              onSubmitted: (_) => _continue(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: 'Fish Audio API key',
                hintStyle: const TextStyle(color: NurColors.g600),
                fillColor: Colors.white.withValues(alpha: 0.05),
                prefixIcon: const Icon(NurIcons.key, size: 18, color: NurColors.g500),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _obscure ? 'Show' : 'Hide',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? NurIcons.visibility : NurIcons.visibilityOff, size: 18, color: NurColors.g500),
                    ),
                    IconButton(
                      tooltip: 'Paste',
                      onPressed: _paste,
                      icon: const Icon(NurIcons.paste, size: 18, color: NurColors.g500),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(NurIcons.error, size: 16, color: NurColors.danger),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, height: 1.35)),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: NurColors.g300),
                    onPressed: () => launchUrl(
                      Uri.parse(widget.outOfCredits ? 'https://fish.audio/app/billing/' : 'https://fish.audio/app/api-keys'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(NurIcons.externalLink, size: 16),
                    label: Text(widget.outOfCredits ? 'Top up' : 'Get a key', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _ok ? NurColors.ok : Colors.white,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: _ok ? NurColors.ok : Colors.white.withValues(alpha: 0.6),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _checking || _ok ? null : _continue,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _ok
                        ? const Row(
                            key: ValueKey('ok'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(NurIcons.check, size: 18, color: Colors.white),
                              SizedBox(width: 6),
                              Text('Connected', style: TextStyle(color: Colors.white)),
                            ],
                          )
                        : _checking
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Row(
                            key: ValueKey('go'),
                            mainAxisSize: MainAxisSize.min,
                            children: [Text('Continue'), SizedBox(width: 6), Icon(NurIcons.forward, size: 18)],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
