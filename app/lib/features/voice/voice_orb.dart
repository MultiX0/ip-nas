// The Nur voice orb: a soft sphere of blue sky with drifting clouds, drawn by a fragment shader
// (shaders/nur_orb.frag) with a CustomPainter fallback. It repaints from a Listenable every frame instead of
// rebuilding widgets.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'call_visuals.dart';
import 'voice_fx.dart';

/// Paints an orb from [OrbInputs] with the shader when available, else with gradients.
/// [rest] is the sphere radius at rest as a fraction of half the canvas' short side.
class OrbPainter extends CustomPainter {
  OrbPainter(this.m, {this.shader, this.glow = 1.0, this.light = false, this.rest = 0.7}) : super(repaint: m);
  final OrbInputs m;
  final ui.FragmentShader? shader;
  final double glow;
  final bool light;
  final double rest;

  @override
  void paint(Canvas canvas, Size size) {
    final sh = shader;
    if (sh != null) {
      final tint = m.tint;
      sh
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, m.time)
        ..setFloat(3, m.scale)
        ..setFloat(4, m.level)
        ..setFloat(5, m.listen)
        ..setFloat(6, m.think)
        ..setFloat(7, m.speak)
        ..setFloat(8, m.connect)
        ..setFloat(9, m.mutedW)
        ..setFloat(10, m.flow)
        ..setFloat(11, m.swirl)
        ..setFloat(12, m.seed)
        ..setFloat(13, tint.r)
        ..setFloat(14, tint.g)
        ..setFloat(15, tint.b)
        ..setFloat(16, light ? 1 : 0)
        ..setFloat(17, glow)
        ..setFloat(18, m.appear)
        ..setFloat(19, rest);
      canvas.drawRect(Offset.zero & size, Paint()..shader = sh);
      return;
    }
    _fallback(canvas, size);
  }

  // Sky colours of the fallback (match the shader's untinted palette).
  static const _deep = Color(0xFF1054F5);
  static const _mid = Color(0xFF5CA3FF);
  static const _high = Color(0xFFDCEFFF);

  void _fallback(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final a = m.appear;
    if (a <= 0.001) return;
    final r = size.shortestSide / 2 * rest * m.scale;
    final tint = m.tint;
    final deep = Color.lerp(_deep, tint, 0.25)!;
    final mid = Color.lerp(_mid, tint, 0.22)!;
    final high = Color.lerp(_high, tint, 0.12)!;
    final lvl = m.level * (1 - m.mutedW * 0.8);
    final grey = (m.mutedW * 0.55 + m.connect * 0.35).clamp(0.0, 1.0);
    Color g(Color x) =>
        Color.lerp(x, Color.from(alpha: 1, red: x.computeLuminance(), green: x.computeLuminance(), blue: x.computeLuminance()), grey)!;

    // Glow (dark) or contact shadow (light).
    final halo = light ? deep.withValues(alpha: 0.08 * glow * a) : mid.withValues(alpha: (0.14 + lvl * 0.25) * glow * a * (1 - m.mutedW * 0.6));
    canvas.drawCircle(c, r * 1.35, Paint()..shader = ui.Gradient.radial(c, r * 1.35, [halo, halo.withValues(alpha: 0)], const [0.7, 1.0]));

    final sphere = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    canvas.drawRect(
      sphere,
      Paint()
        ..shader = ui.Gradient.linear(sphere.topCenter, sphere.bottomCenter, [g(high), g(mid), g(deep)], const [0.0, 0.5, 1.0])
        ..color = Colors.white.withValues(alpha: a),
    );
    // Soft clouds: blurred ovals drifting on slow orbits.
    final cloud = Paint()
      ..color = Colors.white.withValues(alpha: 0.55 * a)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.16);
    for (var i = 0; i < 5; i++) {
      final ph = m.seed * 3 + i * 1.7;
      final x = math.sin(m.flow * 1.4 + ph + m.swirl) * r * 0.55;
      final y = (-0.45 + i * 0.2) * r + math.cos(m.flow * 0.9 + ph) * r * 0.08;
      canvas.drawOval(Rect.fromCenter(center: c + Offset(x, y), width: r * (0.9 - i * 0.08), height: r * 0.34), cloud);
    }
    // Speaking: the core brightens.
    if (lvl > 0.01) {
      canvas.drawCircle(
        c,
        r,
        Paint()..shader = ui.Gradient.radial(c, r, [Colors.white.withValues(alpha: lvl * 0.25 * a), Colors.white.withValues(alpha: 0)]),
      );
    }
    // Limb: light rim at the top, deeper at the bottom.
    canvas.drawRect(
      sphere,
      Paint()..shader = ui.Gradient.radial(c, r, [Colors.transparent, Colors.transparent, deep.withValues(alpha: 0.35 * a)], const [0.0, 0.72, 1.0]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(OrbPainter old) => old.m != m || old.shader != shader || old.glow != glow || old.light != light || old.rest != rest;
}

/// Creates the orb's FragmentShader once the program has loaded.
mixin _OrbShaderHolder<T extends StatefulWidget> on State<T> {
  ui.FragmentShader? shader;

  void initShader() {
    if (VoiceShaders.orb != null) {
      shader = VoiceShaders.orb!.fragmentShader();
    } else {
      VoiceShaders.load().then((_) {
        if (!mounted || VoiceShaders.orb == null) return;
        setState(() => shader = VoiceShaders.orb!.fragmentShader());
      });
    }
  }

  void disposeShader() {
    shader?.dispose();
    shader = null;
  }
}

/// The big call orb. [visuals] is ticked by the call screen. [size] is the diameter of the sphere at rest; the
/// painted canvas is larger so the orb can grow with the voice and keep its glow.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.visuals,
    this.size = 280,
    this.light = false,
    this.onTap,
    this.semanticsLabel,
    this.semanticsHint,
  });
  final CallVisuals visuals;
  final double size;
  final bool light;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final String? semanticsHint;

  /// Canvas size / sphere diameter.
  static const canvasFactor = 1.42;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with _OrbShaderHolder {
  @override
  void initState() {
    super.initState();
    initShader();
  }

  @override
  void dispose() {
    disposeShader();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvas = widget.size * VoiceOrb.canvasFactor;
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      onTap: widget.onTap,
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            OverflowBox(
              maxWidth: canvas,
              maxHeight: canvas,
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size.square(canvas),
                    painter: OrbPainter(widget.visuals, shader: shader, light: widget.light, rest: 1 / VoiceOrb.canvasFactor),
                  ),
                ),
              ),
            ),
            MouseRegion(
              cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: widget.onTap,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small animated sky orb: voice cards, the voice button of the call bar, settings.
/// [level] is polled every frame (e.g. the preview player's output level) while [active].
class VoiceOrbAvatar extends StatefulWidget {
  const VoiceOrbAvatar({super.key, required this.tint, this.seed = 0.5, this.size = 48, this.active = false, this.level, this.well = true});
  final Color tint;
  final double seed;
  final double size;
  final bool active;
  final double Function()? level;
  final bool well;
  @override
  State<VoiceOrbAvatar> createState() => _VoiceOrbAvatarState();
}

class _AvatarInputs extends ChangeNotifier implements OrbInputs {
  @override
  double time = 0;
  @override
  double level = 0;
  @override
  double listen = 1;
  @override
  double think = 0;
  @override
  double speak = 0;
  @override
  double connect = 0;
  @override
  double mutedW = 0;
  @override
  double flow = 0;
  @override
  double swirl = 0;
  @override
  double appear = 1;
  @override
  Color tint = Colors.white;
  @override
  double seed = 0;
  final spring = OrbSpring(1, stiffness: 160, damping: 0.6);
  @override
  double get scale => spring.value;
  void tick() => notifyListeners();
}

class _VoiceOrbAvatarState extends State<VoiceOrbAvatar> with SingleTickerProviderStateMixin, _OrbShaderHolder {
  late final Ticker _ticker;
  final _m = _AvatarInputs();
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _m
      ..tint = widget.tint
      ..seed = widget.seed
      ..time = widget.seed * 13
      ..flow = widget.seed;
    initShader();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(VoiceOrbAvatar old) {
    super.didUpdateWidget(old);
    _m
      ..tint = widget.tint
      ..seed = widget.seed;
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    final target = widget.active ? (widget.level?.call() ?? 0.35).clamp(0.0, 1.0) : 0.0;
    _m.level += (target - _m.level) * (1 - math.exp(-dt * (target > _m.level ? 18 : 6)));
    final sp = widget.active ? 1.0 : 0.0;
    _m.speak += (sp - _m.speak) * (1 - math.exp(-dt * 4));
    _m.listen = 1 - _m.speak;
    _m.time += dt;
    _m.flow += dt * (0.05 + _m.speak * _m.level * 0.3);
    _m.swirl += dt * 0.02;
    _m.spring.step(dt, 0.92 + math.sin(_m.time * 1.35) * 0.012 + _m.speak * math.pow(_m.level, 0.75) * 0.12);
    _m.tick();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _m.dispose();
    disposeShader();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final light = Theme.of(context).brightness == Brightness.light;
    final orb = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(s),
        painter: OrbPainter(_m, shader: shader, glow: 0.5, light: light && !widget.well, rest: widget.well ? 0.86 : 0.9),
      ),
    );
    if (!widget.well) return SizedBox.square(dimension: s, child: orb);
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: light ? const Color(0xFFF2F4F7) : const Color(0xFF0B0B0D),
        border: Border.all(color: light ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: orb,
    );
  }
}
