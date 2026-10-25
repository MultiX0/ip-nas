// Small shared pieces of the voice UI: shader loading, haptics, the shimmer text and per-voice orb tints.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'voice_prefs.dart' show adrianVoiceId, deliaVoiceId, sheilaVoiceId;

/// Fragment programs of the voice UI (shaders/*.frag). Null until loaded or when the platform cannot
/// compile them; every painter has a CustomPainter fallback.
class VoiceShaders {
  VoiceShaders._();
  static ui.FragmentProgram? orb;
  static ui.FragmentProgram? atmosphere;
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      orb = await ui.FragmentProgram.fromAsset('shaders/nur_orb.frag');
    } catch (e) {
      debugPrint('[voice] orb shader unavailable, using the painter fallback: $e');
    }
    try {
      atmosphere = await ui.FragmentProgram.fromAsset('shaders/nur_atmosphere.frag');
    } catch (e) {
      debugPrint('[voice] atmosphere shader unavailable, using the painter fallback: $e');
    }
  }
}

final bool _hapticsPlatform = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

enum Haptic { tap, toggle, heavy, warn }

/// Haptic feedback on phones; does nothing on desktop.
void haptic(Haptic h) {
  if (!_hapticsPlatform) return;
  switch (h) {
    case Haptic.tap:
      HapticFeedback.selectionClick();
    case Haptic.toggle:
      HapticFeedback.lightImpact();
    case Haptic.heavy:
      HapticFeedback.mediumImpact();
    case Haptic.warn:
      HapticFeedback.heavyImpact();
  }
}

/// Per-voice accents of the sky orbs. The orb stays a blue sky; the tint warms or cools its sunlit clouds and
/// deep tones a little, so voices are recognisable without losing the look.
class OrbTints {
  /// Nur's own tint (and the tint of an unknown voice while prefs load): a clear sky blue.
  static const nur = Color(0xFF8CC4FF);

  static const _named = <String, Color>{
    deliaVoiceId: Color(0xFFFFC08A), // warm amber
    adrianVoiceId: Color(0xFF9CC3FF), // steel blue
    sheilaVoiceId: Color(0xFFD8B0FF), // lilac
  };
  static const _palette = [
    Color(0xFF8FD8C8), // mint
    Color(0xFFFFB0A0), // coral
    Color(0xFFB4C4FF), // periwinkle
    Color(0xFFF0D49A), // sand
    Color(0xFFC8B4FF), // lavender
    Color(0xFF9ED8FF), // sky
    Color(0xFFFFC0DC), // blush
    Color(0xFFC2E3A0), // sage
  ];

  static Color forVoice(String id) {
    final named = _named[id];
    if (named != null) return named;
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  static double seedFor(String id) {
    var h = 7;
    for (final c in id.codeUnits) {
      h = (h * 17 + c) & 0xffff;
    }
    return (h % 997) / 97.0;
  }
}

/// Text with a light band sweeping through it ("Thinking", "Transcribing..."). Painted with a CustomPainter so
/// the animation repaints without rebuilding widgets.
class ShimmerText extends StatefulWidget {
  const ShimmerText(this.text, {super.key, this.style, this.baseColor, this.highlightColor, this.textDirection});
  final String text;
  final TextStyle? style;
  final Color? baseColor;
  final Color? highlightColor;
  final TextDirection? textDirection;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();

  TextPainter? _tp;

  @override
  void dispose() {
    _a.dispose();
    _tp?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final dir = widget.textDirection ?? Directionality.of(context);
    _tp?.dispose();
    final tp = _tp = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: style.copyWith(color: Colors.white),
      ),
      textDirection: dir,
      maxLines: 1,
      ellipsis: '…',
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final base = widget.baseColor ?? style.color?.withValues(alpha: 0.55) ?? Colors.white54;
    final hi = widget.highlightColor ?? Colors.white;
    return Semantics(
      label: widget.text,
      child: RepaintBoundary(
        child: CustomPaint(size: tp.size, painter: _ShimmerPainter(tp, _a, base, hi, dir == TextDirection.rtl)),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.tp, this.anim, this.base, this.hi, this.rtl) : super(repaint: anim);
  final TextPainter tp;
  final Animation<double> anim;
  final Color base;
  final Color hi;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect.inflate(2), Paint());
    tp.paint(canvas, Offset.zero);
    final v = Curves.easeInOut.transform(anim.value);
    final w = size.width;
    final band = 0.35 * w + 24;
    final x0 = -band + (w + 2 * band) * (rtl ? 1 - v : v);
    canvas.drawRect(
      rect.inflate(2),
      Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = ui.Gradient.linear(Offset(x0 - band / 2, 0), Offset(x0 + band / 2, 0), [base, hi, base], const [0.0, 0.5, 1.0]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.tp != tp || old.base != base || old.hi != hi || old.rtl != rtl;
}
