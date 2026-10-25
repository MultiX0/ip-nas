// Nur voice orb (ChatGPT Advanced Voice style): a soft, luminous sphere of sky. Two parallax layers of
// slowly drifting, self-shaded clouds over a blue sky gradient, mapped onto a sphere (compressed towards
// the rim), with a gentle rim light, a subtle limb shadow and, on dark backgrounds, a faint glow.
// The sphere is a clean circle; its size follows a spring driven from Dart (uScale). Cloud drift and swirl
// are integrated on the CPU (uFlow, uSwirl) so speed changes never make the texture jump.
// Output is premultiplied alpha.
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // canvas size in px
uniform float uTime;    // seconds
uniform float uScale;   // sphere scale (spring, 1 = rest)
uniform float uLevel;   // smoothed audio level 0..1 (mic while listening, Nur while speaking)
uniform float uListen;  // eased state weights 0..1
uniform float uThink;
uniform float uSpeak;
uniform float uConnect;
uniform float uMuted;
uniform float uFlow;    // integrated cloud drift
uniform float uSwirl;   // integrated swirl angle (radians)
uniform float uSeed;    // per-orb variation
uniform vec3 uTint;     // per-voice accent 0..1
uniform float uLight;   // 0 = dark background, 1 = light background
uniform float uGlow;    // outer glow strength (1 = call orb, lower for avatars)
uniform float uAppear;  // entrance 0..1
uniform float uRest;    // sphere radius at rest, in units of half the canvas short side

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(233.34, 851.73));
  p += dot(p, p + 23.45);
  return fract(p.x * p.y);
}

// Value noise with quintic interpolation (smooth, no grid creases).
float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

const mat2 OCT = mat2(1.62, 1.18, -1.18, 1.62);

float fbm3(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    v += a * vnoise(p);
    p = OCT * p;
    a *= 0.5;
  }
  return v / 0.875;
}

// Soft fbm: the high octaves are kept faint so clouds stay smooth and airy.
float fbm5(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  float sum = 0.0;
  for (int i = 0; i < 5; i++) {
    v += a * vnoise(p);
    sum += a;
    p = OCT * p;
    a *= 0.42;
  }
  return v / sum;
}

mat2 rot(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}

// asin approximation (Abramowitz & Stegun 4.4.45), x in 0..1.
float asin01(float x) {
  return 1.5707963 - sqrt(max(1.0 - x, 0.0)) * (1.5707288 + x * (-0.2121144 + x * (0.0742610 - 0.0187293 * x)));
}

vec3 saturateHue(vec3 c) {
  float hi = max(c.r, max(c.g, c.b));
  float lo = min(c.r, min(c.g, c.b));
  return (c - vec3(lo)) / max(hi - lo, 0.001);
}

// Scales saturation around the luminance (keeps tinted skies vivid instead of greyish).
vec3 resat(vec3 c, float k) {
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  return clamp(vec3(l) + (c - vec3(l)) * k, 0.0, 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float s = min(uSize.x, uSize.y);
  vec2 uv = (frag - 0.5 * uSize) / (0.5 * s); // -1..1 across the short side, y points down
  float r = length(uv);
  float t = uTime;

  float appear = clamp(uAppear, 0.0, 1.0);
  float R = uRest * uScale;
  float aa = 1.6 / (0.5 * s);
  float body = 1.0 - smoothstep(R - aa, R + aa, r);
  float lvl = uLevel * (1.0 - uMuted * 0.8);

  // Palette: ChatGPT-like sky blue, nudged towards the voice tint.
  vec3 hue = saturateHue(uTint);
  float tintAmt = 0.24;
  vec3 deep = resat(mix(vec3(0.04, 0.34, 0.98), hue, tintAmt), 1.25);
  vec3 mid = resat(mix(vec3(0.26, 0.60, 1.00), mix(hue, vec3(1.0), 0.30), tintAmt * 0.8), 1.2);
  vec3 high = mix(vec3(0.80, 0.91, 1.00), mix(hue, vec3(1.0), 0.80), tintAmt * 0.6);
  vec3 sunlit = mix(vec3(1.0), mix(uTint, vec3(1.0), 0.35), 0.16);
  if (uLight > 0.5) {
    // A touch deeper on white so the silhouette reads.
    deep *= 0.92;
    mid = mix(mid, deep, 0.18);
    high = mix(high, mid, 0.30);
  }

  vec3 col = vec3(0.0);
  if (r < R + aa) {
    vec2 n2 = uv / R;                       // -1..1 on the sphere
    float rn = clamp(length(n2), 0.0, 1.0);
    float z = sqrt(max(1.0 - rn * rn, 0.0));
    vec2 dir = rn > 0.0001 ? n2 / rn : vec2(0.0, 1.0);

    // Sphere mapping: texture compresses towards the rim like a globe.
    float ang = mix(rn, asin01(rn) * 0.6366198, 0.65); // 0..1, gently compressed at the rim
    vec2 q = dir * ang;

    // Differential swirl: the core turns faster than the rim (thinking makes it visible).
    q = rot(uSwirl * (1.0 - 0.55 * rn) + uSeed * 2.0) * q;

    // Sky gradient: light at the top, deep blue at the bottom.
    float gy = clamp(n2.y * 0.5 + 0.5, 0.0, 1.0);
    float gyw = gy + (fbm3(q * 1.2 + vec2(uFlow * 0.4, t * 0.02)) - 0.5) * 0.35; // wavy horizon
    vec3 sky = mix(high, mid, smoothstep(-0.05, 0.42, gyw));
    sky = mix(sky, deep, smoothstep(0.50, 1.0, gyw));

    // Back layer: large, soft cloud banks, a little stretched sideways (slower, less curved = farther).
    vec2 drift = vec2(uFlow, uFlow * 0.18);
    vec2 pb = q * vec2(1.25, 1.5) + vec2(uSeed * 3.7, uSeed * 1.9) + drift * 0.55;
    vec2 w = vec2(fbm3(pb * 0.7 + vec2(0.0, t * 0.015)), fbm3(pb * 0.7 + vec2(5.2, 1.3 - t * 0.012)));
    float fb = fbm5(pb + (w - 0.5) * 2.2);
    float db = smoothstep(0.42, 0.78, fb);

    // Front layer: puffier clouds, more parallax, self-shaded (light from the top-left).
    vec2 pf = q * vec2(1.7, 2.0) + vec2(uSeed * 1.3 + 7.0, -uSeed) + drift + (w - 0.5) * 1.4;
    float ff = fbm5(pf);
    float ff2 = fbm5(pf - vec2(0.07, 0.10)); // towards the light
    float df = smoothstep(0.47, 0.77, ff);
    float lit = clamp(0.78 + (ff - ff2) * 3.5, 0.0, 1.15);

    // Fine wisps that follow the flow (the "swirl" you see while it talks).
    float wisp = fbm3(q * vec2(3.0, 6.0) + (w - 0.5) * 3.0 + drift * 1.6);
    float dw = smoothstep(0.55, 0.85, wisp) * 0.25;

    // Clouds thin out towards the very bottom, where the sky is deepest.
    float upper = 1.0 - smoothstep(0.62, 1.0, gy) * 0.5;
    db *= upper;
    df *= mix(0.6, 1.0, upper);

    col = sky;
    vec3 backCol = mix(mid, vec3(1.0), 0.80);
    col = mix(col, backCol, db * 0.85);
    col = mix(col, mix(high, vec3(1.0), 0.6), dw * (1.0 - df));
    vec3 shadeCol = mix(mid, high, 0.72);
    vec3 frontCol = mix(shadeCol, sunlit, clamp(lit, 0.0, 1.0)) + max(lit - 1.0, 0.0) * 0.4;
    col = mix(col, frontCol, df * 0.95);

    // Depth: soft limb shadow at the bottom, rim light at the top, a whisper of light everywhere.
    float limb = pow(1.0 - z, 2.2);
    col = mix(col, deep * 0.85, limb * 0.32 * smoothstep(-0.3, 1.0, n2.y));
    col += limb * 0.14 * smoothstep(0.35, -1.0, n2.y) * mix(vec3(1.0), high, 0.4);
    col += pow(1.0 - z, 6.0) * 0.06 * (1.0 - uLight);

    // Thinking: a slow shimmer band crossing the sphere.
    float sweep = sin(t * 1.15) * 1.25;
    float band = exp(-pow((dot(n2, normalize(vec2(1.0, -0.6))) - sweep) * 2.4, 2.0));
    col += band * uThink * 0.16 * mix(vec3(1.0), high, 0.5);

    // Speaking: the core brightens with Nur's voice; listening: a softer lift with the mic.
    float core = 1.0 - rn * rn;
    col += sunlit * core * lvl * (uSpeak * 0.11 + uListen * 0.05);
    col *= 1.0 + lvl * (uSpeak * 0.06 + uListen * 0.03);

    // Connecting / muted: calmer, greyer.
    float g = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(g), uConnect * 0.15 + uMuted * 0.42);
    col *= 1.0 - uMuted * 0.10 - uConnect * 0.06;
    col = clamp(col, 0.0, 1.0);
  }

  // Outside the sphere: faint glow on dark, a barely-there contact shadow on light.
  float d = max(r - R, 0.0);
  float fadeEdge = 1.0 - smoothstep(0.86, 1.0, r);
  float glowA = exp(-d * (9.0 - lvl * 3.0)) * (0.10 + lvl * 0.22 + uSpeak * 0.04) * uGlow * (1.0 - uLight) * (1.0 - uMuted * 0.6);
  float shadowA = exp(-d * 16.0) * 0.07 * uGlow * uLight;
  float outside = (1.0 - body) * fadeEdge;
  vec3 glowCol = mix(mid, vec3(1.0), 0.15);
  vec3 shadowCol = deep * 0.35;

  // On white, a hairline of deeper blue at the very edge keeps the silhouette crisp.
  float edge = (1.0 - smoothstep(0.0, aa * 2.5, abs(r - R + aa))) * uLight * 0.18;
  col = mix(col, deep * 0.8, edge);

  vec3 premul = col * body + (glowCol * glowA + shadowCol * shadowA) * outside;
  float a = clamp(body + (glowA + shadowA) * outside, 0.0, 1.0);

  // Dither against banding in the soft gradients.
  premul += (hash21(frag + fract(t) * 13.0) - 0.5) / 255.0 * a;

  premul *= appear;
  a *= appear;
  fragColor = vec4(clamp(premul, vec3(0.0), vec3(a)), a);
}
