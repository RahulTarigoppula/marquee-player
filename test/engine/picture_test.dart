import 'package:marquee/engine/picture.dart';
import 'package:test/test.dart';

void main() {
  group('picture adjustments', () {
    test('starts neutral', () {
      expect(PictureAdjust.neutral.isNeutral, isTrue);
      expect(PictureAdjust(), PictureAdjust.neutral);
      expect(PictureAdjust().hasLevels, isFalse);
      expect(PictureAdjust(rotation: 90).isNeutral, isFalse);
      expect(PictureAdjust(deinterlace: true).isNeutral, isFalse);
    });

    test('keeps the levels inside mpv\'s range', () {
      final a = PictureAdjust(brightness: 140, contrast: -300, saturation: 12, gamma: -7);
      expect(a.brightness, 100);
      expect(a.contrast, -100);
      expect(a.saturation, 12);
      expect(a.gamma, -7);
      expect(a.hasLevels, isTrue);
      expect(a.copyWith(brightness: -101).brightness, -100);
    });

    test('rotates by quarter turns and wraps', () {
      var a = PictureAdjust.neutral;
      final seen = <int>[];
      for (var i = 0; i < 5; i++) {
        a = a.rotated;
        seen.add(a.rotation);
      }
      expect(seen, [90, 180, 270, 0, 90]);
      expect(PictureAdjust(rotation: -90).rotation, 270);
      expect(PictureAdjust(rotation: 450).rotation, 90);
      expect(PictureAdjust(rotation: 45).rotation, 0);
    });

    test('zooms in steps, inside the range, on a two-decimal grid', () {
      final a = PictureAdjust.neutral.zoomedBy(PictureAdjust.zoomStep);
      expect(a.zoom, 0.25);
      expect(a.zoomPercent, 119);
      expect(PictureAdjust(zoom: 9).zoom, PictureAdjust.maxZoom);
      expect(PictureAdjust(zoom: -9).zoom, PictureAdjust.minZoom);
      expect(PictureAdjust(zoom: 1).zoomPercent, 200);
      expect(PictureAdjust(zoom: -1).zoomPercent, 50);
      expect(PictureAdjust(zoom: 0.123456).zoom, 0.12);
      expect(PictureAdjust(zoom: double.nan).zoom, 0);
      expect(a.zoomedBy(-PictureAdjust.zoomStep), PictureAdjust.neutral);
    });

    test('resets the sliders without touching rotation or zoom', () {
      final a = PictureAdjust(
        brightness: 10,
        gamma: -4,
        rotation: 180,
        zoom: 0.5,
        deinterlace: true,
      );
      final r = a.levelsReset;
      expect(r.hasLevels, isFalse);
      expect(r.rotation, 180);
      expect(r.zoom, 0.5);
      expect(r.deinterlace, isTrue);
    });

    test('names the mpv properties', () {
      expect(PictureAdjust.neutral.mpvProperties, {
        'brightness': '0',
        'contrast': '0',
        'saturation': '0',
        'gamma': '0',
        'video-rotate': '0',
        'video-zoom': '0.00',
        'deinterlace': 'no',
      });
      final a = PictureAdjust(
        brightness: 5,
        contrast: -10,
        saturation: 20,
        gamma: 3,
        rotation: 270,
        zoom: 0.5,
        deinterlace: true,
      );
      expect(a.mpvProperties, {
        'brightness': '5',
        'contrast': '-10',
        'saturation': '20',
        'gamma': '3',
        'video-rotate': '270',
        'video-zoom': '0.50',
        'deinterlace': 'yes',
      });
    });

    test('round-trips through JSON', () {
      final a = PictureAdjust(brightness: 5, contrast: -10, rotation: 90, zoom: 0.75);
      expect(PictureAdjust.fromJson(a.toJson()), a);
      expect(PictureAdjust.fromJson(PictureAdjust.neutral.toJson()), PictureAdjust.neutral);
    });

    test('reads damaged JSON as far as it can', () {
      expect(PictureAdjust.fromJson(null), PictureAdjust.neutral);
      expect(PictureAdjust.fromJson('nonsense'), PictureAdjust.neutral);
      expect(PictureAdjust.fromJson(const <String, Object?>{}), PictureAdjust.neutral);
      final a = PictureAdjust.fromJson(const {
        'brightness': '12',
        'contrast': 4.6,
        'saturation': 900,
        'rotation': 91,
        'zoom': 'big',
        'deinterlace': 1,
        'unknown': true,
      });
      expect(a.brightness, 0);
      expect(a.contrast, 5);
      expect(a.saturation, 100);
      expect(a.rotation, 0);
      expect(a.zoom, 0);
      expect(a.deinterlace, isFalse);
    });

    test('compares by value', () {
      final a = PictureAdjust(brightness: 5, zoom: 0.25);
      final b = PictureAdjust(brightness: 5, zoom: 0.25);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == b.copyWith(gamma: 1), isFalse);
      expect(a == b.copyWith(deinterlace: true), isFalse);
    });
  });
}
