import 'dart:typed_data';

import 'package:marquee/engine/bias_light.dart';
import 'package:test/test.dart';

const tungsten = 0xFFFFC56E;
const crimson = 0xFFA3252F;
const green = 0xFF5FD48A;

/// 64 × 36: 60 % tungsten, 30 % crimson, 10 % green — the frame-bias fixture.
Uint8List frame(List<(int, double)> mix, {int w = 64, int h = 36}) {
  final out = Uint8List(w * h * 4);
  final n = w * h;
  var p = 0;
  for (final (argb, share) in mix) {
    final count = (n * share).round();
    for (var i = 0; i < count && p < n; i++, p++) {
      out[p * 4] = (argb >> 16) & 0xFF;
      out[p * 4 + 1] = (argb >> 8) & 0xFF;
      out[p * 4 + 2] = argb & 0xFF;
      out[p * 4 + 3] = 0xFF;
    }
  }
  return out;
}

void main() {
  group('bias light', () {
    test('orders the three real stops by population', () async {
      final s = await extractStops(
        frame([(tungsten, 0.6), (crimson, 0.3), (green, 0.1)]),
        64,
        36,
        at: DateTime.utc(2026),
      );
      expect(s, isNotNull);
      expect(s!.argb.sublist(0, 3), [tungsten, crimson, green]);
      expect(s.argb, hasLength(5));
    });

    test('darkens the two outer stops below stop 2', () async {
      final s = (await extractStops(
        frame([(tungsten, 0.6), (crimson, 0.3), (green, 0.1)]),
        64,
        36,
      ))!;
      expect(toneOf(s.argb[3]), lessThan(toneOf(s.argb[2])));
      expect(toneOf(s.argb[4]), lessThan(toneOf(s.argb[2])));
      expect(toneOf(s.argb[3]), closeTo(29, 1.5));
      expect(toneOf(s.argb[4]), closeTo(8.5, 1.5));
    });

    test('returns null for an all-black letterbox frame', () async {
      expect(await extractStops(frame([(0xFF000000, 1.0)]), 64, 36), isNull);
    });

    test('finds the single lamp in a dark scene', () async {
      final s = await extractStops(frame([(0xFF000000, 0.95), (tungsten, 0.05)]), 64, 36);
      expect(s, isNotNull);
      expect(s!.argb.first, tungsten);
    });

    test('lerps between stop sets', () {
      expect(lerpStops([0xFF000000], [0xFFFFFFFF], 0.5), [0xFF808080]);
      expect(lerpStops([0xFF000000], [0xFFFFFFFF], 1), [0xFFFFFFFF]);
    });
  });
}
