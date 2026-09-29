#version 460 core
// HOUSE LIGHTS — the projector beam. A soft tungsten cone from above-behind the viewer,
// 3-octave value noise for haze, and a field of drifting dust motes.
// Uniform order is load-bearing: lib/ui/components/beam.dart sets them by index.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // 0,1  canvas size in logical px
uniform float uTime;     // 2    seconds
uniform float uWidth;    // 3    half-width of the cone at the floor, 0..1 of the canvas
uniform float uAngle;    // 4    sway in radians
uniform float uHouse;    // 5    1 = house up, 0 = dark
uniform vec4 uTint;      // 6..9 beam colour (bias-light stop 0 or --accent), premultiplied later
uniform float uDust;     // 10   1 = draw dust, 0 = none (reduced motion)

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 3; i++) {
    v += amp * noise(p);
    p *= 2.03;
    amp *= 0.5;
  }
  return v;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  // Source sits just above the top edge, centred; rotate around it by the sway angle.
  vec2 src = vec2(0.5, -0.14);
  vec2 d = uv - src;
  float s = sin(uAngle);
  float c = cos(uAngle);
  d = vec2(c * d.x - s * d.y, s * d.x + c * d.y);

  float depth = max(d.y, 0.0);
  float halfW = mix(0.04, uWidth, clamp(depth / 1.14, 0.0, 1.0));
  float edge = 1.0 - smoothstep(halfW * 0.55, halfW, abs(d.x));
  float falloff = 1.0 - smoothstep(0.0, 1.25, depth);
  float haze = 0.75 + 0.25 * fbm(uv * vec2(3.0, 5.0) + vec2(0.0, uTime * 0.03));

  // 8–14 % alpha, brightest when the house is dark and the beam is doing its job.
  float alpha = edge * falloff * haze * mix(0.14, 0.08, uHouse);

  if (uDust > 0.5) {
    vec2 grid = uv * vec2(uSize.x / uSize.y, 1.0) * 26.0 + vec2(uTime * 0.12, uTime * 0.05);
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    float h = hash(cell);
    vec2 offset = vec2(hash(cell + 7.1), hash(cell + 3.3)) - 0.5;
    float r = length(local - offset * 0.6);
    float mote = step(0.82, h) * (1.0 - smoothstep(0.02, 0.06, r));
    alpha += mote * edge * 0.35;
  }

  vec3 col = uTint.rgb;
  fragColor = vec4(col * alpha, alpha);
}
