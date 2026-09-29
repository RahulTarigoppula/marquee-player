import 'package:marquee/engine/timecode.dart';
import 'package:test/test.dart';

void main() {
  group('folio timecodes', () {
    test('floors the position and ceils the remaining', () {
      expect(folio(4364.4, 9663), '01:12:44 · −01:28:19');
      expect(folio(59.999, 61), '00:00:59 · −00:00:02');
      expect(folio(3599.2, 3600), '00:59:59 · −00:00:01');
    });

    test('shows the full duration at the start and zero at the end', () {
      expect(folio(0, 9663), '00:00:00 · −02:41:03');
      expect(folio(9663, 9663), '02:41:03 · −00:00:00');
    });

    test('never wraps at 24 hours', () {
      expect(folio(45000, 45000), '12:30:00 · −00:00:00');
      expect(fmtTimecode(90000), '25:00:00');
    });

    test('prints a dash for an unknown duration', () {
      expect(folio(45, null), '00:00:45 · —');
    });

    test('uses the true minus sign, not a hyphen', () {
      expect(folio(1, 2).contains('−'), isTrue);
      expect(folio(1, 2).contains('-'), isFalse);
    });

    test('appends suffixes after the timecode', () {
      expect(
        auditoriumFolio(
          title: 'The Third Man',
          position: 4364.4,
          duration: 9663,
          suffixes: [subSuffix(350)],
        ),
        'REEL 01 · THE THIRD MAN · 01:12:44 · −01:28:19 · SUB +0.35',
      );
      expect(subSuffix(0), '');
      expect(subSuffix(-300), 'SUB −0.30');
    });

    test('condenses a long title to 40 characters', () {
      final t = folioTitle('a' * 60);
      expect(t.length, 40);
      expect(t.endsWith('…'), isTrue);
    });

    test('clamps a negative position to zero', () {
      expect(folio(-3, 10), '00:00:00 · −00:00:10');
      expect(fmtTimecode(-5), '00:00:00');
    });
  });
}
