// Nur call backdrop: plain black (dark theme) or white (light theme), like ChatGPT voice, with a very faint
// light pool around the orb that breathes with the voice, and dithering so the soft gradient never bands.
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uLevel;
uniform float uSpeak;
uniform float uMuted;
uniform vec2 uCenter;   // orb centre in px
uniform float uOrbR;    // orb radius in px
uniform vec3 uTint;     // pool colour 0..1
uniform float uLight;   // 0 = dark, 1 = light
uniform float uAppear;  // entrance 0..1

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec3 bg = mix(vec3(0.0), vec3(1.0), uLight);

  float scale = max(uOrbR * 2.6, min(uSize.x, uSize.y) * 0.35);
  vec2 pc = (frag - uCenter) / scale;
  float pool = exp(-dot(pc, pc) * 1.4);
  float strength = (0.075 + uLevel * 0.06 + uSpeak * 0.015) * (1.0 - uMuted * 0.6) * uAppear;

  vec3 col = uLight > 0.5
      ? bg - (vec3(1.0) - uTint) * pool * strength * 0.45
      : bg + uTint * pool * strength;

  col += (hash21(frag + fract(uTime) * 17.0) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
