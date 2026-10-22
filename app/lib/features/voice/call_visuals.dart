// Per-frame visual state of a call: eased state weights, smoothed levels, a spring for the orb size and
// integrated cloud drift / swirl. One Ticker drives it; the orb and backdrop painters repaint from it (no
// widget rebuilds per frame).
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'call_view_model.dart';
import 'voice_fx.dart';

/// What an orb painter reads every frame.
abstract class OrbInputs implements Listenable {
  double get time;

  /// Smoothed audio level 0..1 (mic while listening, Nur's voice while speaking).
  double get level;
  double get listen;
  double get think;
  double get speak;
  double get connect;
  double get mutedW;

  /// Sphere scale (spring), 1 = rest.
  double get scale;

  /// Integrated cloud drift and swirl angle (never jump when speeds change).
  double get flow;
  double get swirl;

  /// Entrance 0..1.
  double get appear;
  Color get tint;
  double get seed;
}

/// A damped spring (semi-implicit Euler with fixed sub-steps, stable at any frame rate).
class OrbSpring {
  OrbSpring(this.value, {this.stiffness = 170, this.damping = 0.62});
  double value;
  double velocity = 0;
  double stiffness;

  /// Damping ratio (1 = critical, lower = a little bounce).
  double damping;

  void step(double dt, double target) {
    final c = 2 * damping * math.sqrt(stiffness);
    var left = dt;
    while (left > 1e-6) {
      final h = math.min(left, 1 / 240);
      velocity += (stiffness * (target - value) - c * velocity) * h;
      value += velocity * h;
      left -= h;
    }
  }
}

class CallVisuals extends ChangeNotifier implements OrbInputs {
  CallVisuals({Color voiceTint = OrbTints.nur, this.seed = 0.37}) : _voiceTint = voiceTint, tint = voiceTint;

  @override
  double time = 0;
  @override
  double level = 0;
  double micLevel = 0; // smoothed mic only
  double outLevel = 0; // smoothed output only
  @override
  double listen = 0;
  @override
  double think = 0;
  @override
  double speak = 0;
  @override
  double connect = 1;
  @override
  double mutedW = 0;
  @override
  double flow = 0;
  @override
  double swirl = 0;
  @override
  Color tint;
  @override
  double seed;

  final _scale = OrbSpring(0.82);
  final _appear = OrbSpring(0, stiffness: 60, damping: 0.9);

  @override
  double get scale => _scale.value;
  @override
  double get appear => _appear.value.clamp(0.0, 1.0);

  /// 1 while the screen is shown, 0 while it is closing (the orb shrinks and fades).
  double appearTarget = 1;

  Color _voiceTint;
  set voiceTint(Color c) => _voiceTint = c;

  /// Orb centre / radius in the call body (px), for the backdrop light pool.
  Offset orbCenter = Offset.zero;
  double orbRadius = 0;

  static double _ease(double cur, double target, double dt, double rate) => cur + (target - cur) * (1 - math.exp(-dt * rate));

  void step(double dt, {required CallPhase phase, required double mic, required double out, required bool muted}) {
    time += dt;
    final m = muted ? 0.0 : mic.clamp(0.0, 1.0);
    final o = out.clamp(0.0, 1.0);
    // Fast attack, slower release: the orb jumps with a syllable and settles softly.
    micLevel = _ease(micLevel, m, dt, m > micLevel ? 18 : 6);
    outLevel = _ease(outLevel, o, dt, o > outLevel ? 18 : 6);

    const rate = 3.4; // ~300 ms state crossfades, never jumps
    listen = _ease(listen, phase == CallPhase.listening ? 1 : 0, dt, rate);
    think = _ease(think, phase == CallPhase.thinking ? 1 : 0, dt, rate * 0.8);
    speak = _ease(speak, phase == CallPhase.speaking ? 1 : 0, dt, rate);
    connect = _ease(connect, phase == CallPhase.connecting || phase == CallPhase.ended ? 1 : 0, dt, rate);
    mutedW = _ease(mutedW, muted ? 1 : 0, dt, 5);

    final target = listen * micLevel + speak * outLevel;
    level = _ease(level, target, dt, target > level ? 16 : 6);

    // Size: breathing while idle/listening, a slow pulse while connecting, slightly drawn-in while
    // thinking, expansion with the voice (Nur's stronger than the user's).
    final breathe = math.sin(time * 1.35) * 0.012 * (listen + connect * 1.6) + math.sin(time * 0.9) * 0.018 * think;
    final base = 1.0 * (listen + speak) + 0.95 * think + 0.90 * connect;
    final norm = listen + speak + think + connect + 1e-6;
    final voice = listen * math.pow(micLevel, 0.8) * 0.10 * (1 - mutedW) + speak * math.pow(outLevel, 0.75) * 0.17;
    _appear.step(dt, appearTarget);
    final appearScale = 0.72 + 0.28 * appear;
    _scale.step(dt, (base / norm + breathe + voice) * appearScale);

    // Clouds drift slowly, faster with speech; thinking swirls them.
    flow += dt * (0.045 + speak * outLevel * 0.30 + listen * micLevel * 0.14 + think * 0.03);
    swirl += dt * (0.015 + think * 0.42 + speak * outLevel * 0.05);

    tint = Color.lerp(tint, _voiceTint, 1 - math.exp(-dt * 4))!;
    notifyListeners();
  }
}
