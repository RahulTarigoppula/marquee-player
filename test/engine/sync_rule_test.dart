import 'package:marquee/engine/sync_rule.dart';
import 'package:test/test.dart';

void main() {
  group('sync rule', () {
    test('snaps a drag to the nearest 50 ms detent', () {
      expect(snapSeconds(0.37), 350);
    });

    test('rounds rather than floors', () {
      expect(snapSeconds(0.376), 400);
    });

    test('clamps at plus or minus two seconds', () {
      expect(snapSeconds(2.40), 2000);
      expect(snapSeconds(-9), -2000);
    });

    test('steps 50 ms with J and K', () {
      expect(stepMs(350, later: true), 400);
      expect(stepMs(350, later: false), 300);
    });

    test('steps 500 ms with Shift', () {
      expect(stepMs(350, later: true, shift: true), 850);
      expect(stepMs(1900, later: true, shift: true), 2000);
    });

    test('resets to zero', () {
      expect(resetMs, 0);
      expect(formatDelay(resetMs), '+0.00');
    });

    test('formats the readout, mpv value and spoken value', () {
      expect(formatDelay(350), '+0.35');
      expect(formatDelay(-300), '−0.30');
      expect(mpvSubDelay(350), '0.35');
      expect(mpvSubDelay(-50), '-0.05');
      expect(spokenDelay(350), 'plus 0.35 seconds');
      expect(spokenDelay(-50), 'minus 0.05 seconds');
    });
  });
}
