// Nur logo: an open ring with a dot in the gap ("light" in Arabic: نور). Drawn in code so it follows the theme.
import 'dart:math' as math;

import 'package:flutter/material.dart';

class NurLogo extends StatelessWidget {
  const NurLogo({super.key, this.size = 32, this.withWordmark = false, this.color});
  final double size;
  final bool withWordmark;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    final mark = CustomPaint(size: Size.square(size), painter: _NurMarkPainter(c));
    if (!withWordmark) return mark;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      mark,
      SizedBox(width: size * 0.3),
      Text('nur', style: TextStyle(fontSize: size * 0.72, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c, height: 1)),
    ]);
  }
}

class _NurMarkPainter extends CustomPainter {
  _NurMarkPainter(this.color);
  final Color color;
  static const _gapCenter = -math.pi / 4; // top-right
  static const _gap = 110 * math.pi / 180;
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width * 0.13;
    final r = s.width / 2 - w;
    final c = Offset(s.width / 2, s.height / 2);
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), _gapCenter + _gap / 2, 2 * math.pi - _gap, false, ring);
    canvas.drawCircle(c + Offset(math.cos(_gapCenter), math.sin(_gapCenter)) * r, w * 0.85, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NurMarkPainter old) => old.color != color;
}
