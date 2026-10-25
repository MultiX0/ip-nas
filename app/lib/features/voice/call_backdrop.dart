// Call backdrop: plain black (dark) or white (light) with a very faint pool of light around the orb that
// breathes with the voice. Drawn by shaders/nur_atmosphere.frag (dithered) or a gradient fallback, and repainted
// from CallVisuals without rebuilding.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'call_visuals.dart';
import 'voice_fx.dart';

class CallAtmosphere extends StatefulWidget {
  const CallAtmosphere({super.key, required this.visuals, this.light = false});
  final CallVisuals visuals;
  final bool light;

  static const darkBg = Color(0xFF000000);
  static const lightBg = Color(0xFFFFFFFF);

  @override
  State<CallAtmosphere> createState() => _CallAtmosphereState();
}

class _CallAtmosphereState extends State<CallAtmosphere> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (VoiceShaders.atmosphere != null) {
      _shader = VoiceShaders.atmosphere!.fragmentShader();
    } else {
      VoiceShaders.load().then((_) {
        if (mounted && VoiceShaders.atmosphere != null) setState(() => _shader = VoiceShaders.atmosphere!.fragmentShader());
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _AtmospherePainter(widget.visuals, _shader, widget.light), child: const SizedBox.expand()),
  );
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter(this.v, this.shader, this.light) : super(repaint: v);
  final CallVisuals v;
  final ui.FragmentShader? shader;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = v.orbRadius > 0 ? v.orbCenter : Offset(size.width / 2, size.height * 0.42);
    final orbR = v.orbRadius > 0 ? v.orbRadius : size.shortestSide * 0.25;
    final tint = Color.lerp(const Color(0xFF3F86FF), v.tint, 0.3)!;
    final sh = shader;
    if (sh != null) {
      sh
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, v.time)
        ..setFloat(3, v.level)
        ..setFloat(4, v.speak)
        ..setFloat(5, v.mutedW)
        ..setFloat(6, center.dx)
        ..setFloat(7, center.dy)
        ..setFloat(8, orbR)
        ..setFloat(9, tint.r)
        ..setFloat(10, tint.g)
        ..setFloat(11, tint.b)
        ..setFloat(12, light ? 1 : 0)
        ..setFloat(13, v.appear);
      canvas.drawRect(rect, Paint()..shader = sh);
      return;
    }
    canvas.drawRect(rect, Paint()..color = light ? CallAtmosphere.lightBg : CallAtmosphere.darkBg);
    final strength = ((0.075 + v.level * 0.06) * (1 - v.mutedW * 0.6) * v.appear).clamp(0.0, 0.3);
    final radius = (orbR * 2.6).clamp(size.shortestSide * 0.35, double.infinity) * 1.6;
    final c = light ? Color.lerp(Colors.white, tint, 0.45)! : tint;
    canvas.drawRect(
      rect,
      Paint()..shader = ui.Gradient.radial(center, radius, [c.withValues(alpha: strength * (light ? 0.5 : 1)), c.withValues(alpha: 0)]),
    );
  }

  @override
  bool shouldRepaint(_AtmospherePainter old) => old.v != v || old.shader != shader || old.light != light;
}
