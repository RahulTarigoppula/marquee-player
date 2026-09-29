import 'package:marquee/engine/sync_rule.dart';
import 'package:marquee/engine/timecode.dart';
import 'package:test/test.dart';

void main() {
  group('sync rule', () {
    test('snaps a drag to the nearest 50 ms detent', () {
      expect(snapSeconds(0.37), 350);
      expect(subSuffix(snapSeconds(0.37)), 'SUB +0.35');
    });

    test('rounds to the nearest detent instead of flooring', () {
      expect(snapSeconds(0.376), 400);
      expect(subSuffix(snapSeconds(0.376)), 'SUB +0.40');
    });

    test('clamps a drag past the range to plus or minus two seconds', () {
      expect(snapSeconds(2.40), 2000);
      expect(snapSeconds(-9), -2000);
    });

    test('rounds half away from zero on both sides', () {
      expect(snapSeconds(0.025), 50);
      expect(snapSeconds(-0.025), -50);
      expect(snapSeconds(-0.01), 0);
    });

    test('steps later by 50 ms on K', () {
      expect(stepMs(350, later: true), 400);
    });

    test('steps earlier by 50 ms on J', () {
      expect(stepMs(350, later: false), 300);
    });

    test('steps 500 ms with Shift', () {
      expect(stepMs(350, later: true, shift: true), 850);
      expect(stepMs(1900, later: true, shift: true), 2000);
      expect(stepMs(-1800, later: false, shift: true), -2000);
    });

    test('resets to zero and drops the folio suffix', () {
      expect(resetMs, 0);
      expect(formatDelay(resetMs), '+0.00');
      expect(subSuffix(resetMs), '');
    });

    test('announces the value as plus or minus seconds', () {
      expect(spokenDelay(350), 'plus 0.35 seconds');
      expect(spokenDelay(-1000), 'minus 1.00 seconds');
      expect(spokenDelay(-50), 'minus 0.05 seconds');
      expect(spokenDelay(0), 'plus 0.00 seconds');
      expect(formatDelay(350), '+0.35');
      expect(formatDelay(-500), '−0.50');
    });

    test('formats the mpv sub-delay value', () {
      expect(mpvSubDelay(350), '0.35');
      expect(mpvSubDelay(-50), '-0.05');
    });
  });
}
