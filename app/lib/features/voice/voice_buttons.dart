// Voice buttons for the chat composer and the messages:
// - VoiceMessageButton: tap to record (pill with live waveform, timer, cancel, send) or press and hold
//   (release to send, slide away to cancel); transcribes with Fish Audio and shows errors inline.
// - VoiceCallButton: opens the voice call.
// - ReadAloudButton: reads a message with the selected Drama 3 voice; animated speaker while playing.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../core/theme/nur_theme.dart';
import '../../core/utils/app_dirs.dart';
import '../../core/widgets/nur_icons.dart';
import 'audio_engine.dart';
import 'fish_audio.dart';
import 'speech_text.dart';
import 'voice_fx.dart';
import 'voice_prefs.dart';

void _snack(BuildContext context, String text, {bool settings = false}) {
  final router = GoRouter.maybeOf(context);
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: settings && router != null ? SnackBarAction(label: 'Settings', onPressed: () => router.push('/settings/voice')) : null,
      ),
    );
}

enum _RecState { starting, recording, transcribing, error }

enum _ErrKind { plain, retry, permission, settings }

/// Recording + transcription of one voice message. The pill overlay listens to it.
class _Recorder extends ChangeNotifier {
  _Recorder({required this.hold, required this.fish, required this.prefs});
  final FishAudio fish;
  final VoicePrefs prefs;

  /// Press-and-hold mode (release sends, slide cancels) vs tap mode (buttons).
  bool hold;

  _RecState state = _RecState.starting;
  String? error;
  _ErrKind errKind = _ErrKind.plain;

  final elapsed = ValueNotifier<Duration>(Duration.zero);
  final drag = ValueNotifier<double>(0); // hold mode: horizontal slide, px towards "cancel"

  static const bars = 72;
  final levels = Float32List(bars); // newest first
  final sampleClock = Stopwatch();
  static const sampleMs = 60;

  AudioRecorder? _rec;
  StreamSubscription<Amplitude>? _amp;

  /// Linux: the raw microphone stream, written to the WAV file when the recording stops.
  BytesBuilder? _pcm;
  Future<void>? _pcmDone;
  Timer? _timer;
  final _sw = Stopwatch();
  String? path;
  CancelToken? _cancel;
  bool _disposed = false;

  /// Result: (text, path) on success.
  final done = Completer<(String, String)?>();

  void _set(_RecState s) {
    state = s;
    if (!_disposed) notifyListeners();
  }

  void _fail(String message, [_ErrKind kind = _ErrKind.plain]) {
    error = message;
    errKind = kind;
    _set(_RecState.error);
  }

  Future<void> start() async {
    try {
      final rec = _rec = AudioRecorder();
      if (Platform.isAndroid || Platform.isIOS) {
        final st = await Permission.microphone.request();
        if (!st.isGranted) {
          _fail('Nur needs the microphone to record voice messages.', _ErrKind.permission);
          return;
        }
      } else if (!await rec.hasPermission()) {
        _fail('Nur cannot use the microphone. Allow microphone access in your system settings.');
        return;
      }
      final dir = Directory(p.join((await appFilesDir()).path, 'voice_messages'));
      await dir.create(recursive: true);
      if (Platform.isLinux) {
        // record encodes files with ffmpeg on Linux; the raw stream only needs parecord, and the WAV is written here.
        path = p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.wav');
        if (_disposed) return;
        final pcm = _pcm = BytesBuilder(copy: false);
        final stream = await startPcmStream(
          rec,
          const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: MicStream.sampleRate, numChannels: 1, noiseSuppress: true, autoGain: true),
        );
        _pcmDone = stream.forEach(pcm.add);
      } else {
        final wav = await rec.isEncoderSupported(AudioEncoder.wav);
        path = p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.${wav ? 'wav' : 'm4a'}');
        if (_disposed) return;
        await rec.start(
          RecordConfig(encoder: wav ? AudioEncoder.wav : AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, noiseSuppress: true, autoGain: true),
          path: path!,
        );
      }
      _sw.start();
      sampleClock.start();
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        elapsed.value = _sw.elapsed;
        if (_sw.elapsed > const Duration(minutes: 10)) unawaited(send());
      });
      _amp = rec.onAmplitudeChanged(const Duration(milliseconds: sampleMs)).listen((a) {
        final v = ((a.current + 52) / 46).clamp(0.0, 1.0);
        for (var i = levels.length - 1; i > 0; i--) {
          levels[i] = levels[i - 1];
        }
        levels[0] = v.toDouble();
        sampleClock.reset();
      });
      haptic(Haptic.toggle);
      _set(_RecState.recording);
    } catch (e) {
      _fail(e is FishException ? e.message : 'Could not start recording: $e');
    }
  }

  Future<void> _stopRecorder() async {
    _timer?.cancel();
    _sw.stop();
    sampleClock.stop();
    await _amp?.cancel();
    _amp = null;
    final rec = _rec;
    if (rec == null) return;
    try {
      if (await rec.isRecording()) await rec.stop();
    } catch (_) {}
    // The stream ends when parecord exits; whatever came in until then is kept, even if it ended with an error.
    await _pcmDone?.timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((Object _) {});
    _pcmDone = null;
  }

  Duration get recorded => _sw.elapsed;

  Future<void> send() async {
    if (state == _RecState.transcribing) return;
    final wasRecording = state == _RecState.recording;
    if (wasRecording) await _stopRecorder();
    final file = path;
    if (file == null) return;
    if (wasRecording && _sw.elapsed < const Duration(milliseconds: 600)) {
      _fail(hold ? 'Hold the mic a little longer, then release to send.' : 'That was too short. Try again.');
      return;
    }
    haptic(Haptic.heavy);
    error = null;
    _set(_RecState.transcribing);
    try {
      final pcm = _pcm;
      if (pcm != null) {
        _pcm = null;
        await File(file).writeAsBytes(await encodeWav(pcm.takeBytes(), MicStream.sampleRate));
      }
      final bytes = await File(file).readAsBytes();
      _cancel = CancelToken();
      final r = await fish.transcribe(bytes, filename: p.basename(file), language: prefs.sttLanguage, model: prefs.sttModel, cancel: _cancel);
      final text = cleanTranscript(r.text);
      if (_disposed) return;
      if (text.isEmpty) {
        _fail('I did not catch any words. Try again a bit closer to the mic.');
        return;
      }
      if (!done.isCompleted) done.complete((text, file));
    } catch (e) {
      if (_disposed) return;
      if (e is FishException && e.message == 'Cancelled.') return;
      final settings = e is FishException && (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 402);
      _fail('$e', settings ? _ErrKind.settings : _ErrKind.retry);
    }
  }

  Future<void> cancel() async {
    _cancel?.cancel();
    await _stopRecorder();
    final file = path;
    if (file != null) {
      try {
        await File(file).delete();
      } catch (_) {}
    }
    if (!done.isCompleted) done.complete(null);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _amp?.cancel();
    final rec = _rec;
    if (rec != null) unawaited(rec.dispose().catchError((_) {}));
    elapsed.dispose();
    drag.dispose();
    super.dispose();
  }
}

/// Tap to record a voice message, or press and hold (release to send, slide to cancel).
/// Transcribes with Fish Audio and calls [onTranscript].
class VoiceMessageButton extends ConsumerStatefulWidget {
  const VoiceMessageButton({super.key, required this.onTranscript});
  final void Function(String text, String? audioPath) onTranscript;

  @override
  ConsumerState<VoiceMessageButton> createState() => _VoiceMessageButtonState();
}

class _VoiceMessageButtonState extends ConsumerState<VoiceMessageButton> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  _Recorder? _r;
  static const _cancelSlide = 110.0;

  bool get _open => _entry != null;

  Future<bool> _begin({required bool hold}) async {
    if (_open) return false;
    final prefs = await ref.read(voicePrefsProvider.future);
    final fish = ref.read(fishAudioProvider);
    if (!mounted) return false;
    if (!prefs.hasKey || fish == null) {
      _snack(context, missingKeyMessage, settings: true);
      return false;
    }
    final r = _r = _Recorder(hold: hold, fish: fish, prefs: prefs);
    _show(r);
    unawaited(r.start());
    unawaited(
      r.done.future.then((res) {
        if (!identical(_r, r)) return;
        _close();
        if (res != null && res.$1.trim().isNotEmpty) widget.onTranscript(res.$1, res.$2);
      }),
    );
    return true;
  }

  void _show(_Recorder r) {
    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final ob = overlay.context.findRenderObject() as RenderBox?;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    var width = 420.0;
    if (box != null && ob != null && box.hasSize) {
      final rect = box.localToGlobal(Offset.zero, ancestor: ob) & box.size;
      final room = rtl ? ob.size.width - rect.left - 12 : rect.right - 12;
      width = room.clamp(220.0, 460.0);
    }
    _entry = OverlayEntry(
      builder: (c) => Positioned(
        width: width,
        height: 48,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: rtl ? Alignment.centerLeft : Alignment.centerRight,
          followerAnchor: rtl ? Alignment.centerLeft : Alignment.centerRight,
          offset: Offset(rtl ? -2 : 2, 0),
          child: _RecorderPill(r: r, rtl: rtl, onCancel: _cancel, onSend: () => r.send()),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  Future<void> _cancel() async {
    final r = _r;
    if (r == null) return;
    haptic(Haptic.warn);
    await r.cancel();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    final r = _r;
    _r = null;
    // Dispose after the overlay is gone (its listeners unsubscribe on unmount).
    if (r != null) SchedulerBinding.instance.addPostFrameCallback((_) => r.dispose());
  }

  @override
  void dispose() {
    final r = _r;
    if (r != null && !r.done.isCompleted) unawaited(r.cancel());
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onLongPressStart: (_) => _begin(hold: true),
        onLongPressMoveUpdate: (d) {
          final r = _r;
          if (r == null || !r.hold || r.state != _RecState.recording) return;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final slide = rtl ? d.offsetFromOrigin.dx : -d.offsetFromOrigin.dx;
          r.drag.value = slide.clamp(0.0, _cancelSlide + 20);
          if (slide > _cancelSlide) _cancel();
        },
        onLongPressEnd: (_) {
          final r = _r;
          if (r == null || !r.hold) return;
          if (r.state == _RecState.recording) {
            r.send();
          } else if (r.state == _RecState.starting) {
            _cancel();
          }
        },
        child: IconButton(
          tooltip: 'Voice message (hold to talk)',
          icon: const Icon(NurIcons.mic),
          onPressed: () {
            haptic(Haptic.tap);
            _begin(hold: false);
          },
        ),
      ),
    );
  }
}

/// The recording pill that covers the composer row.
class _RecorderPill extends StatefulWidget {
  const _RecorderPill({required this.r, required this.rtl, required this.onCancel, required this.onSend});
  final _Recorder r;
  final bool rtl;
  final Future<void> Function() onCancel;
  final VoidCallback onSend;
  @override
  State<_RecorderPill> createState() => _RecorderPillState();
}

class _RecorderPillState extends State<_RecorderPill> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  late final AnimationController _frames = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.r.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.r.hold) _focus.requestFocus();
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (widget.r.state == _RecState.error || widget.r.state == _RecState.transcribing) {
      _frames.stop();
    }
  }

  @override
  void dispose() {
    widget.r.removeListener(_changed);
    _intro.dispose();
    _frames.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if ((e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) && widget.r.state == _RecState.recording) {
      widget.onSend();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nur = context.nur;
    final r = widget.r;
    final fg = scheme.onSurface;

    Widget circle({required IconData icon, required String tip, required VoidCallback? onTap, bool filled = false}) => Tooltip(
      message: tip,
      child: Material(
        color: filled ? scheme.primary : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 20, color: filled ? scheme.onPrimary : fg)),
        ),
      ),
    );

    final wave = Expanded(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PillWavePainter(r, _frames, fg, dim: r.state != _RecState.recording, rtl: widget.rtl),
          size: const Size(double.infinity, 32),
        ),
      ),
    );

    final timer = ValueListenableBuilder<Duration>(
      valueListenable: r.elapsed,
      builder: (c, d, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RecDot(active: r.state == _RecState.recording),
          const SizedBox(width: 6),
          Text(
            '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 13.5, color: fg, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );

    List<Widget> children;
    switch (r.state) {
      case _RecState.starting:
      case _RecState.recording:
        if (r.hold) {
          children = [
            const SizedBox(width: 12),
            timer,
            const SizedBox(width: 10),
            wave,
            const SizedBox(width: 8),
            ValueListenableBuilder<double>(
              valueListenable: r.drag,
              builder: (c, dx, _) => Opacity(
                opacity: (1 - dx / 140).clamp(0.3, 1.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.rtl ? NurIcons.chevronRight : NurIcons.chevronLeft, size: 18, color: nur.muted),
                    ShimmerText(
                      'Slide to cancel',
                      style: TextStyle(fontSize: 12.5, color: nur.muted),
                      baseColor: nur.muted,
                      highlightColor: fg,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
          ];
        } else {
          children = [
            const SizedBox(width: 4),
            circle(icon: NurIcons.close, tip: 'Cancel (Esc)', onTap: widget.onCancel),
            const SizedBox(width: 4),
            timer,
            const SizedBox(width: 10),
            wave,
            const SizedBox(width: 8),
            circle(icon: NurIcons.send, tip: 'Send (Enter)', filled: true, onTap: r.state == _RecState.recording ? widget.onSend : null),
            const SizedBox(width: 6),
          ];
        }
      case _RecState.transcribing:
        children = [
          const SizedBox(width: 4),
          circle(icon: NurIcons.close, tip: 'Cancel', onTap: widget.onCancel),
          const SizedBox(width: 6),
          ShimmerText(
            'Transcribing...',
            style: TextStyle(fontSize: 13.5, color: fg, fontWeight: FontWeight.w500),
            baseColor: nur.muted,
            highlightColor: fg,
          ),
          const SizedBox(width: 10),
          wave,
          const SizedBox(width: 12),
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
          const SizedBox(width: 16),
        ];
      case _RecState.error:
        children = [
          const SizedBox(width: 14),
          const Icon(NurIcons.error, size: 18, color: NurColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.error ?? 'Something went wrong.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.25, color: fg),
            ),
          ),
          if (r.errKind == _ErrKind.retry) circle(icon: NurIcons.refresh, tip: 'Try again', onTap: widget.onSend),
          if (r.errKind == _ErrKind.permission)
            TextButton(onPressed: openAppSettings, child: const Text('Settings'))
          else if (r.errKind == _ErrKind.settings)
            TextButton(
              onPressed: () {
                final router = GoRouter.maybeOf(context);
                widget.onCancel();
                router?.push('/settings/voice');
              },
              child: const Text('Settings'),
            ),
          circle(icon: NurIcons.close, tip: 'Close', onTap: widget.onCancel),
          const SizedBox(width: 6),
        ];
    }

    final a = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(a),
          alignment: widget.rtl ? Alignment.centerLeft : Alignment.centerRight,
          child: ValueListenableBuilder<double>(
            valueListenable: r.drag,
            builder: (c, dx, child) => Transform.translate(offset: Offset(widget.rtl ? dx * 0.5 : -dx * 0.5, 0), child: child),
            child: Material(
              color: nur.composer,
              elevation: 0,
              shape: StadiumBorder(
                side: BorderSide(color: r.state == _RecState.error ? NurColors.danger.withValues(alpha: 0.5) : nur.composerBorder),
              ),
              shadowColor: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: Row(children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecDot extends StatefulWidget {
  const _RecDot({required this.active});
  final bool active;
  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: widget.active ? Tween(begin: 0.35, end: 1.0).animate(_a) : const AlwaysStoppedAnimation(0.4),
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: NurColors.danger, shape: BoxShape.circle),
    ),
  );
}

/// Mirrored bars, newest at the trailing edge, scrolling smoothly between samples.
class _PillWavePainter extends CustomPainter {
  _PillWavePainter(this.r, Animation<double> frames, this.color, {required this.dim, required this.rtl}) : super(repaint: frames);
  final _Recorder r;
  final Color color;
  final bool dim;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 5.0;
    const barW = 3.0;
    final mid = size.height / 2;
    final sub = dim ? 0.0 : (r.sampleClock.elapsedMilliseconds / _Recorder.sampleMs).clamp(0.0, 1.0);
    final n = math.min(_Recorder.bars, (size.width / spacing).floor());
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final d = (i + sub) * spacing + barW / 2;
      final x = rtl ? d : size.width - d;
      if (x < 0 || x > size.width) continue;
      final v = r.levels[i];
      final fade = (1 - d / size.width).clamp(0.0, 1.0);
      final h = math.max(barW, v * size.height);
      paint.color = color.withValues(alpha: (dim ? 0.3 : 0.9) * (0.35 + 0.65 * fade));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, mid), width: barW, height: h), const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(_PillWavePainter old) => old.color != color || old.dim != dim || old.r != r || old.rtl != rtl;
}

/// Opens a voice call in [chatId] (null starts a new chat).
class VoiceCallButton extends StatelessWidget {
  const VoiceCallButton({super.key, this.chatId});
  final String? chatId;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Voice call',
      child: Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            haptic(Haptic.toggle);
            context.push(chatId == null ? '/call' : '/call?chat=${Uri.encodeQueryComponent(chatId!)}');
          },
          child: SizedBox(width: 36, height: 36, child: Icon(NurIcons.voice, size: 20, color: scheme.onPrimary)),
        ),
      ),
    );
  }
}

/// One read-aloud at a time across the app.
class _ReadAloud {
  _ReadAloud._();
  static final instance = _ReadAloud._();
  final current = ValueNotifier<int?>(null); // identity of the playing button
  final loading = ValueNotifier<bool>(false);
  PcmStreamPlayer? _player;
  CancelToken? _cancel;
  int _gen = 0;

  double get level => _player?.level ?? 0;

  Future<void> stop() async {
    _gen++;
    _cancel?.cancel();
    _cancel = null;
    await _player?.stop();
    _player = null;
    current.value = null;
    loading.value = false;
  }

  Future<void> play(int id, String text, FishAudio fish, VoicePrefs prefs) async {
    await stop();
    final gen = _gen;
    current.value = id;
    loading.value = true;
    final player = PcmStreamPlayer(
      onStarted: () {
        if (gen == _gen) loading.value = false;
      },
    );
    _player = player;
    try {
      await player.start();
      final pieces = _chunks(markdownToSpeech(text, keepDirections: false));
      for (final piece in pieces) {
        _cancel = CancelToken();
        await for (final chunk in fish.tts(
          piece,
          voiceId: prefs.voiceId,
          model: prefs.model,
          latency: prefs.latency,
          speed: prefs.speed,
          cancel: _cancel,
        )) {
          if (gen != _gen) return;
          player.add(chunk);
        }
      }
      player.end();
      await player.finished;
    } catch (e) {
      if (gen != _gen) return;
      rethrow;
    } finally {
      if (gen == _gen) {
        current.value = null;
        loading.value = false;
        _player = null;
      }
    }
  }

  static List<String> _chunks(String s) {
    const max = 1200;
    final out = <String>[];
    var rest = s;
    while (rest.length > max) {
      var cut = rest.lastIndexOf(RegExp(r'[.!?؟]\s'), max);
      if (cut < max ~/ 3) cut = rest.lastIndexOf(' ', max);
      if (cut <= 0) cut = max;
      out.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1);
    }
    if (rest.trim().isNotEmpty) out.add(rest.trim());
    return out;
  }
}

/// Plays a finished assistant message with the selected Fish Audio voice ("read aloud").
class ReadAloudButton extends ConsumerStatefulWidget {
  const ReadAloudButton({super.key, required this.text});
  final String text;
  @override
  ConsumerState<ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends ConsumerState<ReadAloudButton> {
  int get _id => identityHashCode(this);

  @override
  void dispose() {
    if (_ReadAloud.instance.current.value == _id) _ReadAloud.instance.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    final ra = _ReadAloud.instance;
    if (ra.current.value == _id) {
      await ra.stop();
      return;
    }
    final prefs = await ref.read(voicePrefsProvider.future);
    final fish = ref.read(fishAudioProvider);
    if (!mounted) return;
    if (fish == null || !prefs.hasKey) {
      _snack(context, missingKeyMessage, settings: true);
      return;
    }
    if (markdownToSpeech(widget.text).isEmpty) {
      _snack(context, 'Nothing to read aloud in this message.');
      return;
    }
    haptic(Haptic.tap);
    try {
      await ra.play(_id, widget.text, fish, prefs);
    } catch (e) {
      if (mounted) _snack(context, '$e', settings: e is FishException && (e.statusCode == 401 || e.statusCode == 402));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ra = _ReadAloud.instance;
    return ValueListenableBuilder<int?>(
      valueListenable: ra.current,
      builder: (c, cur, _) {
        final mine = cur == _id;
        return ValueListenableBuilder<bool>(
          valueListenable: ra.loading,
          builder: (c, loading, _) => IconButton(
            tooltip: mine ? 'Stop reading' : 'Read aloud',
            onPressed: _toggle,
            icon: _SpeakerIcon(playing: mine && !loading, loading: mine && loading, level: () => ra.level, size: 18),
          ),
        );
      },
    );
  }
}

/// Speaker glyph whose sound waves move with the voice while playing and pulse while loading.
class _SpeakerIcon extends StatefulWidget {
  const _SpeakerIcon({required this.playing, required this.loading, required this.level, this.size = 18});
  final bool playing;
  final bool loading;
  final double Function() level;
  final double size;
  @override
  State<_SpeakerIcon> createState() => _SpeakerIconState();
}

class _SpeakerIconState extends State<_SpeakerIcon> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _t = ValueNotifier<double>(0);
  double _lvl = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_SpeakerIcon old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final on = widget.playing || widget.loading;
    if (on && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!on && _ticker.isActive) {
      _ticker.stop();
      _lvl = 0;
      _t.value = 0;
    }
  }

  void _tick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = e;
    final target = widget.playing ? widget.level() : 0.0;
    _lvl += (target - _lvl) * (1 - math.exp(-dt * (target > _lvl ? 20 : 8)));
    _t.value += dt;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _SpeakerPainter(_t, () => _lvl, color, playing: widget.playing, loading: widget.loading),
      ),
    );
  }
}

class _SpeakerPainter extends CustomPainter {
  _SpeakerPainter(this.t, this.level, this.color, {required this.playing, required this.loading}) : super(repaint: t);
  final ValueNotifier<double> t;
  final double Function() level;
  final Color color;
  final bool playing;
  final bool loading;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s);
    // Speaker body (24x24 grid).
    final body = Path()
      ..moveTo(3, 9.5)
      ..lineTo(7, 9.5)
      ..lineTo(11.5, 5.5)
      ..lineTo(11.5, 18.5)
      ..lineTo(7, 14.5)
      ..lineTo(3, 14.5)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
    final time = t.value;
    final lvl = level();
    final wave = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round;
    const c = Offset(11.5, 12);
    for (var i = 0; i < 2; i++) {
      var alpha = 1.0;
      var r = i == 0 ? 4.2 : 8.0;
      if (loading) {
        alpha = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(time * 6 - i * 1.4));
      } else if (playing) {
        final k = i == 0 ? 1.0 : 0.7;
        alpha = (0.35 + 0.65 * math.min(1.0, lvl * 1.6 * k + 0.15 * (0.5 + 0.5 * math.sin(time * 7 + i)))).clamp(0.0, 1.0);
        r += lvl * 1.2 * (i + 1) * 0.6;
      }
      wave.color = color.withValues(alpha: color.a * alpha);
      final sweep = (i == 0 ? 70 : 84) * math.pi / 180;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -sweep / 2, sweep, false, wave);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpeakerPainter old) => old.color != color || old.playing != playing || old.loading != loading || old.t != t;
}
