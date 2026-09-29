// Bias light (§6.10): the walls glow with the colour of whatever is playing.
// material_color_utilities (Apache-2.0): QuantizerCelebi + Hct. The top-80 % crop happens in
// player/screenshot.dart — NOT here.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'models/settings.dart';

const int _kLetterboxTone = 8; // L* below this is letterbox/black-crush, not the film's colour
// Fewer kept pixels than this ⇒ an all-black frame. 4 %, not 5 %: a 64×36 frame cannot hold
// exactly 5 %, and the "single lamp in a dark scene" golden (a 5 % highlight) must survive.
const double _kMinKeptFraction = 0.04;
const int _kMaxSamples = 2304; // 64 × 36
const int _kClusters = 16;

/// Five stops from an RGBA buffer of [w]×[h] pixels, or null for an all-black frame.
Future<BiasStops?> extractStops(Uint8List rgba, int w, int h, {DateTime? at}) async {
  final stride = math.max(1, (w * h) ~/ _kMaxSamples);
  final kept = <int>[];
  var sampled = 0;
  for (var p = 0; p < w * h; p += stride) {
    final i = p * 4;
    if (i + 2 >= rgba.length) break;
    sampled++;
    final argb = 0xFF000000 | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    if (Hct.fromInt(argb).tone >= _kLetterboxTone) kept.add(argb); // drop the black bars
  }
  if (sampled == 0 || kept.length < sampled * _kMinKeptFraction) return null;

  // Order by POPULATION — what is on screen, not what makes a pretty Material palette.
  final q = await QuantizerCelebi().quantize(kept, _kClusters);
  final byCount = q.colorToCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final top = byCount.take(3).map((e) => e.key).toList();
  if (top.isEmpty) return null;
  while (top.length < 3) {
    top.add(top.last); // monochrome frames
  }

  // Three real stops, then two darkened duplicates carrying the gradient out to the wall's
  // edge. Both are guaranteed darker than stop 2.
  final s3 = _atTone(top[0], math.min(_tone(top[0]) * 0.35, _tone(top[2]) - 10));
  final s4 = _atTone(top[1], math.min(_tone(top[1]) * 0.25, _tone(top[2]) - 14));
  return BiasStops(argb: [top[0], top[1], top[2], s3, s4], sampledAt: at ?? clock.now());
}

double _tone(int argb) => Hct.fromInt(argb).tone;

int _atTone(int argb, double tone) {
  final c = Hct.fromInt(argb);
  return Hct.from(c.hue, c.chroma, tone.clamp(2.0, 100.0)).toInt();
}

/// HCT tone of a stop, exposed for the goldens.
double toneOf(int argb) => _tone(argb);

/// Alphas for the five wall stops: 14 % → 8 % → 4 % → 2 % → 0 %.
const List<double> kWallAlphas = [0.14, 0.08, 0.04, 0.02, 0.0];

/// Linear interpolation between two stop sets (the 600 ms `bias-lerp`).
List<int> lerpStops(List<int> from, List<int> to, double t) {
  int ch(int a, int b, int shift) {
    final x = (a >> shift) & 0xFF;
    final y = (b >> shift) & 0xFF;
    return (x + (y - x) * t).round().clamp(0, 255);
  }

  return [
    for (var i = 0; i < to.length; i++)
      0xFF000000 |
          (ch(from.length > i ? from[i] : to[i], to[i], 16) << 16) |
          (ch(from.length > i ? from[i] : to[i], to[i], 8) << 8) |
          ch(from.length > i ? from[i] : to[i], to[i], 0),
  ];
}
