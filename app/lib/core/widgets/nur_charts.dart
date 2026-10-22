// Tiny, dependency-free stat visuals for dashboards: ring gauge, sparkline, usage bar.
// Monochrome by default; warn/danger tint only when a value crosses a threshold.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nur_theme.dart';

/// Colour for a 0..1 usage value: text colour, then amber > 75 %, red > 90 %.
Color usageColor(BuildContext context, double v, {double warn = 0.75, double danger = 0.9}) {
  if (v >= danger) return NurColors.danger;
  if (v >= warn) return NurColors.warn;
  return Theme.of(context).colorScheme.onSurface;
}

/// Circular gauge with rounded caps; animates between values. [child] sits in the middle.
class RingGauge extends StatelessWidget {
  const RingGauge({super.key, required this.value, this.size = 56, this.stroke = 5, this.color, this.child});
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final v = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final c = color ?? usageColor(context, v);
    final track = Theme.of(context).colorScheme.outlineVariant;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: v),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(t, c, track, stroke),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v;
  final Color color;
  final Color track;
  final double stroke;
  @override
  void paint(Canvas canvas, Size s) {
    final r = (math.min(s.width, s.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: s.center(Offset.zero), radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, p..color = track);
    if (v > 0.001) canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track || o.stroke != stroke;
}

/// Smooth line with a soft fill under it. [values] are drawn left to right (oldest first), scaled to
/// [max] (or the largest value when null).
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 36, this.color, this.max, this.strokeWidth = 1.6});
  final List<double> values;
  final double height;
  final Color? color;
  final double? max;
  final double strokeWidth;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, c, max, strokeWidth, Directionality.of(context) == TextDirection.rtl)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.max, this.stroke, this.rtl);
  final List<double> values;
  final Color color;
  final double? max;
  final double stroke;
  final bool rtl;
  @override
  void paint(Canvas canvas, Size s) {
    if (values.length < 2) return;
    final top = max ?? values.reduce(math.max);
    final hi = top <= 0 ? 1.0 : top;
    final pad = stroke;
    final h = s.height - pad * 2;
    final dx = s.width / (values.length - 1);
    Offset pt(int i) {
      final x = dx * i;
      return Offset(rtl ? s.width - x : x, pad + h - (values[i].clamp(0, hi) / hi) * h);
    }

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = pt(i - 1), b = pt(i);
      final mx = (a.dx + b.dx) / 2;
      line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(line)
      ..lineTo(pt(values.length - 1).dx, s.height)
      ..lineTo(pt(0).dx, s.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)]).createShader(Offset.zero & s),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    final last = pt(values.length - 1);
    canvas.drawCircle(last, stroke * 1.7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.values != values || o.color != color || o.max != max || o.rtl != rtl;
}

/// Rounded usage bar that animates its fill.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.value, this.height = 6, this.color});
  final double value;
  final double height;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final v = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final c = color ?? usageColor(context, v);
    final track = Theme.of(context).colorScheme.outlineVariant;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: v),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Container(
        height: height,
        decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(height)),
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: t,
          child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(height))),
        ),
      ),
    );
  }
}
