import 'package:marquee/engine/detents.dart';
import 'package:marquee/engine/models/media.dart';
import 'package:test/test.dart';

const chapters = [
  Chapter(index: 0, startSeconds: 0),
  Chapter(index: 1, startSeconds: 1800),
  Chapter(index: 2, startSeconds: 4200),
  Chapter(index: 3, startSeconds: 7200),
];

SnapResult at(double px) => snapTarget(
  releasePx: px,
  gateWidthPx: 800,
  durationSeconds: 9663,
  detents: detentsFor(chapters, 9663),
);

void main() {
  group('gate detents', () {
    test('snaps to a chapter within the 6 px capture radius', () {
      final r = at(152);
      expect(r.snapped, isTrue);
      expect(r.seconds, 1800);
    });

    test('seeks exactly when the nearest chapter is further than 6 px', () {
      final r = at(160);
      expect(r.snapped, isFalse);
      expect(r.seconds.toStringAsFixed(1), '1932.6');
    });

    test('lands on zero at the left edge', () {
      expect(at(0).seconds, 0);
    });

    test('reaches the end without snapping to a far chapter', () {
      final r = at(800);
      expect(r.snapped, isFalse);
      expect(r.seconds, 9663);
    });

    test('falls back to a detent every five minutes without chapters', () {
      expect(detentsFor(const [], 700), [0, 300, 600]);
      expect(detentsFor(const [], 0), [0]);
    });

    test('moves one eighth as far in FINE mode', () {
      final s = fineSeek(startSeconds: 1000, dragPx: 80, gateWidthPx: 800, durationSeconds: 9663);
      expect((s - 1000).toStringAsFixed(1), '120.8');
    });

    test('detects crossing a detent for the selection tick', () {
      final d = detentsFor(chapters, 9663);
      expect(crossesDetent(1700, 1900, d), isTrue);
      expect(crossesDetent(1900, 1700, d), isTrue);
      expect(crossesDetent(1900, 2000, d), isFalse);
    });
  });
}
