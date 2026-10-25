// Voice gallery: Drama 3 voices, Arabic voices, the user's own clones and search. Each card has its own
// animated mini orb (distinct tint) that reacts to the "Play sample" preview, a short line with direction tags
// spoken by Drama 3. Previews are cached on disk, so each voice and line is synthesised once.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/utils/text_dir.dart';
import '../../core/widgets/provider_logo.dart';
import 'audio_engine.dart';
import 'fish_audio.dart';
import 'voice_fx.dart';
import 'voice_orb.dart';
import 'voice_prefs.dart';

/// Short Drama 3 preview line for a voice (direction tags are performed, not read).
String sampleLineFor(FishVoice v) {
  switch (v.id) {
    case deliaVoiceId:
      return "[warmly] Hi, I'm Delia. [small laugh] Ready when you are.";
    case adrianVoiceId:
      return "[calmly] Hey, I'm Adrian. Your NAS is humming along nicely. [short pause] What should we do next?";
    case sheilaVoiceId:
      return "[excited] Hi! I'm Sheila, and honestly? I <emphasis>love</emphasis> what you've built here.";
  }
  final name = v.title.trim().isEmpty ? 'Nur' : v.title.trim();
  final arabic = v.languages.contains('ar') || isArabic(name);
  if (arabic) return '[warmly] أهلاً وسهلاً! [short pause] معك $name، كيف أقدر أساعدك اليوم؟';
  return "[warmly] Hi, I'm $name. [small laugh] Ready when you are.";
}

/// Plays one preview at a time (voice samples).
class SamplePlayer {
  SamplePlayer._();
  static final instance = SamplePlayer._();

  /// Voice id currently playing (audio is coming out).
  final playing = ValueNotifier<String?>(null);

  /// Voice id whose preview is being synthesised.
  final loading = ValueNotifier<String?>(null);
  PcmStreamPlayer? _pcm;
  CancelToken? _cancel;
  int _gen = 0;

  /// Output level of the preview, 0..1 (polled by the mini orbs).
  double get level => _pcm?.level ?? 0;

  Future<void> stop() async {
    _gen++;
    _cancel?.cancel();
    _cancel = null;
    await _pcm?.stop();
    _pcm = null;
    playing.value = null;
    loading.value = null;
  }

  static Future<File> _cacheFile(String voiceId, String line) async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'voice_samples'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final h = crypto.md5.convert(utf8.encode('drama-3|$voiceId|$line')).toString().substring(0, 16);
    return File(p.join(dir.path, '${voiceId}_$h.pcm'));
  }

  /// Speaks [voice]'s preview line with Drama 3 (cached on disk after the first time).
  Future<void> play(FishVoice voice, FishAudio? fish) async {
    await stop();
    final gen = _gen;
    final line = sampleLineFor(voice);
    loading.value = voice.id;
    final player = PcmStreamPlayer(
      onStarted: () {
        if (gen == _gen) {
          loading.value = null;
          playing.value = voice.id;
        }
      },
    );
    _pcm = player;
    try {
      await AudioEngine.ensure();
      await player.start();
      File? cache;
      try {
        cache = await _cacheFile(voice.id, line);
      } catch (_) {}
      if (cache != null && await cache.exists()) {
        final bytes = await cache.readAsBytes();
        if (gen != _gen) return;
        const chunk = 32 * 1024;
        for (var i = 0; i < bytes.length; i += chunk) {
          player.add(Uint8List.sublistView(bytes, i, i + chunk > bytes.length ? bytes.length : i + chunk));
        }
      } else {
        if (fish == null) throw FishException(missingKeyMessage);
        final all = BytesBuilder(copy: false);
        _cancel = CancelToken();
        await for (final c in fish.tts(line, voiceId: voice.id, cancel: _cancel)) {
          if (gen != _gen) return;
          all.add(c);
          player.add(c);
        }
        if (gen == _gen && cache != null && all.length > 0) {
          unawaited(cache.writeAsBytes(all.takeBytes(), flush: true).then((_) {}, onError: (_) {}));
        }
      }
      player.end();
      await player.finished;
    } catch (_) {
      if (gen != _gen) return; // stopped on purpose
      rethrow;
    } finally {
      if (gen == _gen) {
        _pcm = null;
        playing.value = null;
        loading.value = null;
      }
    }
  }
}

/// Curated voice lists, fetched once per app run.
final drama3VoicesProvider = FutureProvider<List<FishVoice>>((ref) async {
  final fish = ref.watch(fishAudioProvider);
  if (fish == null) return drama3Voices;
  final out = <FishVoice>[];
  for (final v in drama3Voices) {
    try {
      final full = await fish.getVoice(v.id);
      out.add(
        full == null
            ? v
            : FishVoice(
                id: v.id,
                title: v.title,
                languages: full.languages.isEmpty ? v.languages : full.languages,
                cover: full.cover,
                sampleUrl: full.sampleUrl,
                description: v.description,
              ),
      );
    } catch (_) {
      out.add(v);
    }
  }
  return out;
});

final arabicVoicesProvider = FutureProvider<List<FishVoice>>((ref) async {
  final fish = ref.watch(fishAudioProvider);
  if (fish == null) return const [];
  final lists = await Future.wait([
    fish.listVoices(language: 'ar', sortBy: 'task_count', pageSize: 12),
    fish.listVoices(query: 'arabic', sortBy: 'task_count', pageSize: 8).catchError((_) => <FishVoice>[]),
  ]);
  final seen = <String>{};
  return [
    for (final v in [...lists[0], ...lists[1]])
      if (seen.add(v.id)) v,
  ];
});

final myVoicesProvider = FutureProvider<List<FishVoice>>((ref) async {
  final fish = ref.watch(fishAudioProvider);
  if (fish == null) return const [];
  return fish.listVoices(self: true, pageSize: 50, sortBy: 'created_at');
});

class VoiceGallery extends ConsumerStatefulWidget {
  const VoiceGallery({super.key, this.dark = false});

  /// Force dark styling (used on the call screen).
  final bool dark;
  @override
  ConsumerState<VoiceGallery> createState() => _VoiceGalleryState();
}

class _VoiceGalleryState extends ConsumerState<VoiceGallery> {
  final _q = TextEditingController();
  String _lang = 'all';
  List<FishVoice>? _results;
  bool _searching = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    SamplePlayer.instance.stop();
    super.dispose();
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _search);
  }

  Future<void> _search() async {
    final fish = ref.read(fishAudioProvider);
    final q = _q.text.trim();
    if (fish == null || (q.isEmpty && _lang == 'all')) {
      setState(() => _results = null);
      return;
    }
    setState(() => (_searching = true, _error = null));
    try {
      final r = await fish.listVoices(query: q, language: _lang == 'all' ? null : _lang, pageSize: 24, sortBy: 'task_count');
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Color _fg(BuildContext context) => widget.dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
  Color _muted(BuildContext context) => widget.dark ? NurColors.g400 : context.nur.muted;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(voicePrefsProvider).value ?? const VoicePrefs();
    final hasKey = prefs.hasKey;
    final sections = <Widget>[];

    Widget header(String title, {String? trailing, String? sub}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.1, color: _fg(context)),
                ),
                if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: TextStyle(fontSize: 12.5, color: _muted(context)))],
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _muted(context)),
            ),
        ],
      ),
    );

    Widget section(String title, AsyncValue<List<FishVoice>> v, {String? empty, String? trailing, String? sub}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(title, trailing: trailing, sub: sub),
        switch (v) {
          AsyncData(:final value) when value.isEmpty => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Text(empty ?? 'Nothing here yet.', style: TextStyle(color: _muted(context), fontSize: 13)),
          ),
          AsyncData(:final value) => _grid(value, prefs.voiceId),
          AsyncError(:final error) => Padding(
            padding: const EdgeInsets.all(2),
            child: Text('$error', style: const TextStyle(color: NurColors.danger, fontSize: 13)),
          ),
          _ => _skeleton(),
        },
      ],
    );

    sections.add(
      TextField(
        controller: _q,
        onChanged: _onQuery,
        enabled: hasKey,
        style: TextStyle(color: _fg(context)),
        decoration: InputDecoration(
          hintText: hasKey ? 'Search Fish Audio voices' : 'Add your Fish Audio key to browse more voices',
          fillColor: widget.dark ? Colors.white.withValues(alpha: 0.05) : null,
          prefixIcon: Icon(NurIcons.search, color: _muted(context)),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
        ),
      ),
    );
    sections.add(
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in const [('all', 'All'), ('ar', 'العربية'), ('en', 'English')])
              _FilterChip(
                label: l.$2,
                selected: _lang == l.$1,
                dark: widget.dark,
                onTap: hasKey
                    ? () {
                        setState(() => _lang = l.$1);
                        _search();
                      }
                    : null,
              ),
          ],
        ),
      ),
    );
    if (_error != null) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: NurColors.danger)),
        ),
      );
    }
    if (_results != null) {
      sections.add(section('Results', AsyncData(_results!), empty: 'No voices found.'));
    } else {
      sections.add(section('Drama 3 voices', ref.watch(drama3VoicesProvider), sub: 'Expressive, emotional voices made for conversation'));
      if (hasKey) {
        sections.add(section('Arabic voices', ref.watch(arabicVoicesProvider), trailing: 'أصوات عربية', empty: 'No Arabic voices found.'));
        sections.add(section('My voices', ref.watch(myVoicesProvider), empty: 'Voices you clone on fish.audio appear here.'));
      }
    }
    sections.add(
      Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 4),
        child: PoweredByFish(dark: widget.dark),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections);
  }

  Widget _skeleton() => LayoutBuilder(
    builder: (c, box) {
      final cols = _cols(box.maxWidth);
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < cols; i++)
            Container(
              width: w,
              height: 148,
              decoration: BoxDecoration(
                color: widget.dark ? Colors.white.withValues(alpha: 0.04) : Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
        ],
      );
    },
  );

  static int _cols(double w) => w > 720 ? 4 : (w > 460 ? 3 : 2);

  Widget _grid(List<FishVoice> voices, String selectedId) => LayoutBuilder(
    builder: (c, box) {
      final cols = _cols(box.maxWidth);
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final v in voices)
            SizedBox(
              width: w,
              child: VoiceCard(voice: v, selected: v.id == selectedId, dark: widget.dark),
            ),
        ],
      );
    },
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.dark, this.onTap});
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final bg = selected ? fg : Colors.transparent;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: selected ? fg : fg.withValues(alpha: 0.18))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? (dark ? Colors.black : Theme.of(context).colorScheme.surface) : fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _langNames = {
  'en': 'English',
  'ar': 'العربية',
  'zh': '中文',
  'ja': '日本語',
  'ko': '한국어',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'pt': 'Português',
  'ru': 'Русский',
  'it': 'Italiano',
  'tr': 'Türkçe',
  'hi': 'हिन्दी',
};

/// One voice: mini orb in the voice's tint, name, language chips, play sample, selected state.
class VoiceCard extends ConsumerWidget {
  const VoiceCard({super.key, required this.voice, required this.selected, this.dark = false});
  final FishVoice voice;
  final bool selected;
  final bool dark;

  Future<void> _toggleSample(BuildContext context, WidgetRef ref) async {
    final sp = SamplePlayer.instance;
    haptic(Haptic.tap);
    if (sp.playing.value == voice.id || sp.loading.value == voice.id) {
      await sp.stop();
      return;
    }
    try {
      await sp.play(voice, ref.read(fishAudioProvider));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fg = dark ? Colors.white : scheme.onSurface;
    final muted = dark ? NurColors.g400 : context.nur.muted;
    final tint = OrbTints.forVoice(voice.id);
    final sp = SamplePlayer.instance;
    final bg = dark ? const Color(0xFF131316) : scheme.surfaceContainer;
    final langs = voice.languages.take(3).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: selected && dark ? [BoxShadow(color: tint.withValues(alpha: 0.18), blurRadius: 24, spreadRadius: -4)] : null,
      ),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? fg.withValues(alpha: 0.9) : (dark ? Colors.white.withValues(alpha: 0.07) : scheme.outlineVariant),
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            haptic(Haptic.toggle);
            ref.read(voicePrefsProvider.notifier).setVoice(voice);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<String?>(
                      valueListenable: sp.playing,
                      builder: (c, playing, _) =>
                          VoiceOrbAvatar(tint: tint, seed: OrbTints.seedFor(voice.id), size: 52, active: playing == voice.id, level: () => sp.level),
                    ),
                    const Spacer(),
                    _PlayButton(voiceId: voice.id, fg: fg, dark: dark, onTap: () => _toggleSample(context, ref)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        voice.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirOf(voice.title),
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg, letterSpacing: -0.1),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: selected
                          ? Padding(
                              key: const ValueKey('sel'),
                              padding: const EdgeInsetsDirectional.only(start: 5),
                              child: Icon(NurIcons.success, size: 16, color: fg),
                            )
                          : const SizedBox.shrink(key: ValueKey('nosel')),
                    ),
                  ],
                ),
                if (langs.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [for (final l in langs) _LangChip(label: _langNames[l.toLowerCase()] ?? l.toUpperCase(), fg: fg)],
                  ),
                ],
                const SizedBox(height: 7),
                SizedBox(
                  height: 32,
                  child: Text(
                    voice.description.isEmpty ? (voice.author == null || voice.author!.isEmpty ? ' ' : 'by ${voice.author}') : voice.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirOf(voice.description),
                    style: TextStyle(fontSize: 11.5, height: 1.35, color: muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.label, required this.fg});
  final String label;
  final Color fg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: fg.withValues(alpha: 0.16)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.75)),
    ),
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.voiceId, required this.fg, required this.dark, required this.onTap});
  final String voiceId;
  final Color fg;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sp = SamplePlayer.instance;
    return ValueListenableBuilder<String?>(
      valueListenable: sp.loading,
      builder: (c, loading, _) => ValueListenableBuilder<String?>(
        valueListenable: sp.playing,
        builder: (c, playing, _) {
          final isLoading = loading == voiceId;
          final isPlaying = playing == voiceId;
          return Tooltip(
            message: isPlaying || isLoading ? 'Stop' : 'Play sample',
            child: Material(
              color: isPlaying ? fg : fg.withValues(alpha: 0.08),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: isLoading
                        ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: fg))
                        : Icon(
                            isPlaying ? NurIcons.stop : NurIcons.play,
                            size: 20,
                            color: isPlaying ? (dark ? Colors.black : Theme.of(context).colorScheme.surface) : fg,
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Powered by Fish Audio Drama 3" footer.
class PoweredByFish extends StatelessWidget {
  const PoweredByFish({super.key, this.dark = false});
  final bool dark;
  @override
  Widget build(BuildContext context) {
    final c = dark ? NurColors.g500 : context.nur.muted;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Powered by', style: TextStyle(fontSize: 12, color: c)),
        const SizedBox(width: 7),
        FishAudioLogo(size: 15, wordmark: true, onDark: dark ? true : null),
        const SizedBox(width: 6),
        Text(
          'Drama 3',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dark ? NurColors.g300 : Theme.of(context).colorScheme.onSurface),
        ),
      ],
    );
  }
}
