import 'package:marquee/engine/sync_rule.dart' show formatDelay;
import 'package:marquee/engine/timecode.dart';
import 'package:test/test.dart';

void main() {
  group('folio timecodes', () {
    test('floors the position and ceils the remaining time', () {
      expect(folio(4364.4, 9663), '01:12:44 · −01:28:19');
    });

    test('prints the full duration as remaining at the start', () {
      expect(folio(0, 9663), '00:00:00 · −02:41:03');
    });

    test('prints zero remaining at the end', () {
      expect(folio(9663, 9663), '02:41:03 · −00:00:00');
    });

    test('never shows an off-by-one just before a whole second', () {
      expect(folio(59.999, 61), '00:00:59 · −00:00:02');
      expect(folio(3599.2, 3600), '00:59:59 · −00:00:01');
    });

    test('never wraps at 24 hours', () {
      expect(folio(45000, 45000), '12:30:00 · −00:00:00');
      expect(fmtTimecode(90000), '25:00:00');
      expect(fmtTimecode(108000), '30:00:00');
    });

    test('prints an em dash for an unknown duration', () {
      expect(folio(45, null), '00:00:45 · —');
      expect(folio(45, double.infinity), '00:00:45 · —');
      expect(folio(45, double.nan), '00:00:45 · —');
      expect(folio(45, 0), '00:00:45 · —');
      expect(folio(double.infinity, 10), '00:00:00 · −00:00:10');
    });

    test('uses the minus sign U+2212, not a hyphen', () {
      expect(folio(0, 10), contains('−'));
      expect(folio(0, 10), isNot(contains('-')));
    });

    test('clamps a position past the end to zero remaining', () {
      expect(folio(100, 90), '00:01:40 · −00:00:00');
      expect(fmtTimecode(-3), '00:00:00');
    });

    test('clamps a negative position to zero', () {
      expect(folio(-3, 10), '00:00:00 · −00:00:10');
      expect(fmtTimecode(-5), '00:00:00');
    });

    test('appends suffixes without replacing the timecode', () {
      final base = folio(4364.4, 9663);
      expect(
        auditoriumFolio(position: 4364.4, duration: 9663, suffixes: [subSuffix(350)]),
        'REEL 01 · $base · SUB +0.35',
      );
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
      expect(subSuffix(-350), 'SUB −0.35');
      expect(
        auditoriumFolio(position: 4364.4, duration: 9663, suffixes: [subSuffix(0)]),
        'REEL 01 · $base',
      );
    });

    test('prints the threading folio', () {
      expect(kThreadingFolio, 'REEL 01 · THREADING');
    });

    test('signs values with plus or the minus sign', () {
      // The Dart signed formatter lives beside the sync rule (whole milliseconds in).
      expect(formatDelay(0), '+0.00');
      expect(formatDelay(350), '+0.35');
      expect(formatDelay(-2000), '−2.00');
    });

    test('uppercases the title and condenses it to 40 characters', () {
      expect(
        auditoriumFolio(title: 'The Third Man', position: 4364.4, duration: 9663),
        'REEL 01 · THE THIRD MAN · 01:12:44 · −01:28:19',
      );
      final t = folioTitle('a' * 60);
      expect(t.length, 40);
      expect(t.endsWith('…'), isTrue);
      expect(auditoriumFolio(position: 0), 'REEL 01 · 00:00:00 · —');
    });
  });
}
