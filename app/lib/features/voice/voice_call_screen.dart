// Full-screen voice call: pure black (dark theme) or white (light theme) with the sky orb in the middle (it
// breathes while listening, swirls while thinking and pulses with Nur's voice; a tap interrupts), a quiet status
// line, optional two-line captions and a small control row (mute, captions, voice, end). Works as a phone screen
// and inside a desktop window.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/contracts/intelligence.dart';
import '../../core/layout/desktop.dart';
import '../../core/providers.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_logo.dart';
import '../../core/widgets/provider_logo.dart';
import '../chat/engine/live_store.dart';
import 'call_backdrop.dart';
import 'call_captions.dart';
import 'call_controls.dart';
import 'call_setup_card.dart';
import 'call_view_model.dart';
import 'call_visuals.dart';
import 'voice_call_controller.dart';
import 'voice_fx.dart';
import 'voice_gallery.dart';
import 'voice_orb.dart';
import 'voice_prefs.dart';

class VoiceCallScreen extends ConsumerStatefulWidget {
  const VoiceCallScreen({super.key, this.chatId});
  final String? chatId;
  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> with SingleTickerProviderStateMixin {
  VoiceCallController? _c;
  bool _captions = true;
  bool _needsKey = false;
  String? _setupError;
  late final ToolApprovalBroker _broker;

  final _visuals = CallVisuals();
  final _revealed = ValueNotifier<int>(0);
  final _clockText = ValueNotifier<String>('');
  final _stack = GlobalKey();
  final _orbKey = GlobalKey();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Stopwatch? _callClock;
  int _shownSecond = -1;

  /// Chrome (top bar, captions, controls) fades in after the first frame and out when the call ends.
  bool _shown = false;
  bool _closing = false;

  static final bool _touch = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    unawaited(VoiceShaders.load());
    // Risky tools asked for during a call are approved here (otherwise they would be denied while the chat screen is closed).
    _broker = ref.read(toolApprovalBrokerProvider);
    _broker.register(_approve);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
      _start();
    });
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    final v = _c;
    final phase = v == null || _needsKey ? CallPhase.connecting : v.phase;
    _visuals.step(dt, phase: phase, mic: v?.micLevel ?? 0, out: v?.outLevel ?? 0, muted: v?.muted ?? false);
    _revealed.value = v?.revealedWords ?? 0;
    if (_callClock == null && v != null && v.phase == CallPhase.listening) {
      _callClock = Stopwatch()..start();
    }
    final s = _callClock?.elapsed.inSeconds ?? -1;
    if (s != _shownSecond) {
      _shownSecond = s;
      _clockText.value = s < 0 ? '' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
  }

  void _measureOrb() {
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    final orb = _orbKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || orb == null || !orb.hasSize || !stack.hasSize || !orb.attached) return;
    _visuals
      ..orbCenter = orb.localToGlobal(orb.size.center(Offset.zero), ancestor: stack)
      ..orbRadius = orb.size.shortestSide / 2;
  }

  Future<bool> _approve(ApprovalRequest r) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(r.risk == ToolRisk.dangerous ? 'Allow a risky action?' : 'Allow this action?'),
        content: Text('Nur wants to run ${r.call.name}\n${r.call.argumentsJson}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Deny')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Allow')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _start() async {
    _c?.removeListener(_onController);
    _c?.dispose();
    _c = null;
    final prefs = await ref.read(voicePrefsProvider.future);
    if (!mounted) return;
    final fish = ref.read(fishAudioProvider);
    if (fish == null || !prefs.hasKey) {
      setState(() => _needsKey = true);
      return;
    }
    try {
      final engine = ref.read(chatEngineProvider);
      final c = VoiceCallController(engine: engine, fish: fish, prefs: () => ref.read(voicePrefsProvider).value ?? prefs, chatId: widget.chatId);
      c.addListener(_onController);
      setState(() => (_c = c, _needsKey = false, _setupError = null));
      await c.start(); // opens the warm TTS socket right away
    } catch (e) {
      if (mounted) setState(() => _setupError = 'Voice calls are not ready yet: $e');
    }
  }

  CallPhase? _lastPhase;
  void _onController() {
    final c = _c;
    if (c == null) return;
    // A small haptic tick when Nur starts speaking (phones).
    if (c.phase != _lastPhase) {
      if (c.phase == CallPhase.speaking) haptic(Haptic.tap);
      _lastPhase = c.phase;
    }
  }

  @override
  void dispose() {
    _broker.unregister(_approve);
    _ticker.dispose();
    _c?.removeListener(_onController);
    _c?.dispose();
    _visuals.dispose();
    _revealed.dispose();
    _clockText.dispose();
    super.dispose();
  }

  Future<void> _end() async {
    if (_closing) return;
    final c = _c;
    final chat = c?.chatId ?? widget.chatId;
    // Exit: the orb shrinks and fades with the chrome while the call shuts down.
    setState(() => (_closing = true, _shown = false));
    _visuals.appearTarget = 0;
    await Future.wait([c?.end() ?? Future<void>.value(), Future<void>.delayed(const Duration(milliseconds: 260))]);
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(chat == null ? '/' : '/chat/$chat');
    }
  }

  void _tapOrb() {
    final v = _c;
    if (v == null) return;
    if (v.phase == CallPhase.speaking || v.phase == CallPhase.thinking) {
      haptic(Haptic.heavy);
      v.interrupt();
    } else if (v.phase == CallPhase.listening && v.muted) {
      haptic(Haptic.toggle);
      v.setMuted(false);
    }
  }

  void _toggleMute() {
    final v = _c;
    if (v == null || _needsKey) return;
    v.setMuted(!v.muted);
  }

  void _pickVoice(bool light) {
    showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      maxWidth: 760,
      builder: (c) => Theme(
        data: light ? NurTheme.light() : NurTheme.dark(),
        child: _VoicePickerSheet(dark: !light),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(voicePrefsProvider).value ?? const VoicePrefs();
    final light = Theme.of(context).brightness == Brightness.light;
    final k = CallColors.of(light);
    _visuals
      ..voiceTint = OrbTints.forVoice(prefs.voiceId)
      ..seed = OrbTints.seedFor(prefs.voiceId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureOrb());
    final overlay = (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: k.bg,
    );
    final setup = _needsKey;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Theme(
        data: light ? NurTheme.light() : NurTheme.dark(),
        child: Scaffold(
          backgroundColor: k.bg,
          resizeToAvoidBottomInset: true,
          body: CallbackShortcuts(
            bindings: setup
                ? {const SingleActivator(LogicalKeyboardKey.escape): _end}
                : {
                    const SingleActivator(LogicalKeyboardKey.escape): _end,
                    const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
                    const SingleActivator(LogicalKeyboardKey.keyC): () => setState(() => _captions = !_captions),
                    const SingleActivator(LogicalKeyboardKey.space): _tapOrb,
                  },
            child: Focus(
              autofocus: true,
              child: Stack(
                key: _stack,
                children: [
                  Positioned.fill(
                    child: CallAtmosphere(visuals: _visuals, light: light),
                  ),
                  SafeArea(
                    child: Column(
                      children: [
                        _Reveal(shown: _shown, offset: -0.4, child: _topBar(k, prefs)),
                        Expanded(child: _body(k)),
                        _Reveal(
                          shown: _shown,
                          offset: 0.5,
                          delay: 80,
                          child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 22), child: _controls(k, prefs, light)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(CallColors k, VoicePrefs prefs) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: IconButton(tooltip: 'End call and go back', color: k.fg, onPressed: _end, icon: const Icon(NurIcons.chevronDown, size: 24)),
            ),
          ),
          Semantics(
            header: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NurLogo(size: 14, color: k.fg),
                    const SizedBox(width: 6),
                    Text(
                      'Nur',
                      style: TextStyle(color: k.fg, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                ValueListenableBuilder<String>(
                  valueListenable: _clockText,
                  builder: (c, t, _) => Text(
                    t.isEmpty ? prefs.voiceName : '${prefs.voiceName}  ·  $t',
                    maxLines: 1,
                    style: TextStyle(color: k.muted, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Tooltip(
                message: 'Voice by Fish Audio Drama 3',
                child: Semantics(
                  label: 'Voice by Fish Audio Drama 3',
                  child: SizedBox.square(
                    dimension: 40,
                    child: Center(
                      child: FishAudioLogo(size: 28, onDark: !k.light, opacity: FishAudioLogo.quiet, excludeFromSemantics: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(CallColors k) {
    final v = _c;
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        final w = box.maxWidth;

        if (_needsKey || (v != null && v.error != null && v.errorNeedsSettings)) {
          final orb = (h * 0.22).clamp(72.0, 150.0);
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VoiceOrb(key: _orbKey, visuals: _visuals, size: orb, light: k.light, semanticsLabel: 'Nur'),
                  SizedBox(height: orb * 0.36 + 8),
                  Theme(
                    data: NurTheme.dark(),
                    child: CallSetupCard(
                      key: ValueKey(v?.error),
                      message: _needsKey ? null : v?.error,
                      outOfCredits: (v?.error ?? '').contains('credits'),
                      onReady: _start,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (_setupError != null || v == null) {
          return Center(
            child: _setupError == null
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: k.fg))
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: _ErrorBlock(
                      colors: k,
                      message: _setupError!,
                      onRetry: () {
                        setState(() => _setupError = null);
                        _start();
                      },
                    ),
                  ),
          );
        }

        // Geometry: the orb sits a little above the centre; status and captions hang below it.
        const lines = 2;
        final captionH = CallCaptions.heightFor(lines);
        const statusH = 34.0;
        final orb = math.min(math.min(w * 0.62, (h - captionH - statusH - 48) * 0.72), 330.0).clamp(96.0, 330.0);
        final reach = orb * 0.62; // the sphere grows ~20 % with the voice, plus its glow
        final cy = math.max(h * 0.40, reach + 8);
        final statusTop = math.min(cy + reach + 6, h - captionH - statusH);

        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: cy - orb / 2,
              child: Center(
                child: ListenableBuilder(
                  listenable: v,
                  builder: (c, _) => VoiceOrb(
                    key: _orbKey,
                    visuals: _visuals,
                    size: orb,
                    light: k.light,
                    onTap: _tapOrb,
                    semanticsLabel: 'Nur, ${_phaseLabel(v)}',
                    semanticsHint: v.phase == CallPhase.speaking || v.phase == CallPhase.thinking
                        ? 'Interrupts Nur'
                        : (v.muted ? 'Turns the microphone on' : null),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: statusTop,
              child: _Reveal(
                shown: _shown,
                delay: 160,
                child: Column(
                  children: [
                    ListenableBuilder(
                      listenable: v,
                      builder: (c, _) => CallStatusLine(view: v, colors: k, touch: _touch),
                    ),
                    SizedBox(
                      height: captionH,
                      child: ListenableBuilder(
                        listenable: v,
                        builder: (c, _) {
                          if (v.error != null) {
                            return Align(
                              alignment: Alignment.topCenter,
                              child: _ErrorBlock(colors: k, message: v.error!, permission: v.errorNeedsPermission, onRetry: () => _c?.start()),
                            );
                          }
                          return AnimatedOpacity(
                            opacity: _captions ? 1 : 0,
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOut,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: CallCaptions(view: v, revealed: _revealed, colors: k, lines: lines),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Notices float at the top so nothing below the orb shifts.
            Positioned(
              left: 16,
              right: 16,
              top: 4,
              child: ListenableBuilder(
                listenable: v,
                builder: (c, _) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: v.status == null || v.error != null
                      ? const SizedBox.shrink()
                      : Center(
                          key: ValueKey(v.status),
                          child: CallNotice(text: v.status!, colors: k),
                        ),
                ),
              ),
            ),
            if (kDebugMode)
              Positioned(
                right: 16,
                bottom: 0,
                child: ListenableBuilder(
                  listenable: v,
                  builder: (c, _) => v.lastTtfaMs == null
                      ? const SizedBox.shrink()
                      : Text(
                          'first audio ${(v.lastTtfaMs! / 1000).toStringAsFixed(2)} s',
                          style: TextStyle(color: k.faint, fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _phaseLabel(CallViewModel v) => switch (v.phase) {
    CallPhase.connecting => 'connecting',
    CallPhase.listening => v.muted ? 'microphone off' : 'listening',
    CallPhase.thinking => v.tool ?? 'thinking',
    CallPhase.speaking => 'speaking',
    CallPhase.ended => 'call ended',
  };

  Widget _controls(CallColors k, VoicePrefs prefs, bool light) {
    final v = _c;
    Widget controls(bool muted) => CallControls(
      colors: k,
      muted: muted,
      captions: _captions,
      voiceName: prefs.voiceName,
      voiceTint: OrbTints.forVoice(prefs.voiceId),
      voiceSeed: OrbTints.seedFor(prefs.voiceId),
      onMute: v == null || _needsKey ? null : _toggleMute,
      onCaptions: () => setState(() => _captions = !_captions),
      onVoice: () => _pickVoice(light),
      onEnd: _end,
    );
    if (v == null) return controls(false);
    return ListenableBuilder(listenable: v, builder: (c, _) => controls(v.muted));
  }
}

/// Fades and slides its child in when [shown] turns true (entrance) and out when it turns false (exit).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.shown, required this.child, this.offset = 0.25, this.delay = 0});
  final bool shown;
  final Widget child;

  /// Slide distance as a fraction of the child's height (negative = from above).
  final double offset;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final d = Duration(milliseconds: shown ? 420 + delay : 200);
    final curve = shown ? Interval(delay / (420 + delay), 1, curve: Curves.easeOutCubic) : Curves.easeIn;
    return AnimatedSlide(
      offset: shown ? Offset.zero : Offset(0, offset),
      duration: d,
      curve: curve,
      child: AnimatedOpacity(opacity: shown ? 1 : 0, duration: d, curve: curve, child: child),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.colors, required this.message, required this.onRetry, this.permission = false});
  final CallColors colors;
  final String message;
  final VoidCallback onRetry;
  final bool permission;
  @override
  Widget build(BuildContext context) {
    final k = colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: k.fg, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (permission)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: k.fg, foregroundColor: k.bg),
                  onPressed: openAppSettings,
                  child: const Text('Open settings'),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: k.fg,
                  side: BorderSide(color: k.fg.withValues(alpha: 0.25)),
                ),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Voice gallery in a sheet (phones) or dialog (desktop), in the call screen's look.
class _VoicePickerSheet extends StatelessWidget {
  const _VoicePickerSheet({required this.dark});
  final bool dark;
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final k = CallColors.of(!dark);
    return SizedBox(
      height: (h * 0.82).clamp(320.0, 860.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose a voice',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: k.fg),
                      ),
                      const SizedBox(height: 3),
                      Text('Nur uses the new voice from the next answer.', style: TextStyle(color: k.muted, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(NurIcons.close, color: k.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: VoiceGallery(dark: dark),
            ),
          ),
        ],
      ),
    );
  }
}
