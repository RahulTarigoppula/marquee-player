import 'package:marquee/engine/filename.dart';
import 'package:marquee/engine/playback.dart';
import 'package:test/test.dart';

void main() {
  group('seek clamping', () {
    const dur = Duration(minutes: 100);

    test('never seeks before the start', () {
      expect(clampSeek(const Duration(seconds: -12), dur), Duration.zero);
    });

    test('stops one second short of the end', () {
      expect(clampSeek(dur + const Duration(seconds: 30), dur), dur - const Duration(seconds: 1));
      expect(clampSeek(dur, dur), dur - const Duration(seconds: 1));
    });

    test('passes an in-range target through', () {
      expect(clampSeek(const Duration(minutes: 3), dur), const Duration(minutes: 3));
    });

    test('only clamps at zero while the duration is unknown', () {
      expect(clampSeek(const Duration(hours: 9), Duration.zero), const Duration(hours: 9));
    });

    test('holds a sub-second film at zero', () {
      const tiny = Duration(milliseconds: 400);
      expect(clampSeek(const Duration(milliseconds: 300), tiny), Duration.zero);
    });

    test('maps the digit keys to tenths of the film', () {
      expect(percentSeek(0, dur), Duration.zero);
      expect(percentSeek(5, dur), const Duration(minutes: 50));
      expect(percentSeek(9, dur), const Duration(minutes: 90));
      expect(percentSeek(12, dur), const Duration(minutes: 90));
    });

    test('prints a short clock', () {
      expect(shortClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(shortClock(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(shortClock(const Duration(seconds: -3)), '0:00');
    });
  });

  group('natural order', () {
    test('compares digit runs as numbers', () {
      final files = ['Ep 10.mkv', 'Ep 2.mkv', 'ep 1.mkv', 'Ep 2b.mkv'];
      files.sort(naturalCompare);
      expect(files, ['ep 1.mkv', 'Ep 2.mkv', 'Ep 2b.mkv', 'Ep 10.mkv']);
    });

    test('orders zero-padded twins deterministically', () {
      expect(naturalCompare('S01E02', 'S01E002'), lessThan(0));
      expect(naturalCompare('a', 'a'), 0);
      expect(naturalCompare('a1', 'a1x'), lessThan(0));
    });

    test('finds the neighbours of the playing file', () {
      final names = ['Show S01E03.mkv', 'Show S01E01.mkv', 'Show S01E02.mkv'];
      final n = neighboursOf(names, 'Show S01E02.mkv');
      expect(n.previous, 'Show S01E01.mkv');
      expect(n.next, 'Show S01E03.mkv');
      final first = neighboursOf(names, 'Show S01E01.mkv');
      expect(first.previous, isNull);
      final last = neighboursOf(names, 'Show S01E03.mkv');
      expect(last.next, isNull);
      expect(neighboursOf(names, 'other.mkv').next, isNull);
    });

    test('lists only video containers', () {
      expect(isVideoFile('a.MKV'), isTrue);
      expect(isVideoFile('a.srt'), isFalse);
      expect(isVideoFile('README'), isFalse);
    });
  });

  group('speed and picture', () {
    test('steps through the presets', () {
      expect(stepSpeed(1, faster: true), 1.25);
      expect(stepSpeed(1, faster: false), 0.75);
      expect(stepSpeed(2, faster: true), 2);
      expect(stepSpeed(0.25, faster: false), 0.25);
      expect(stepSpeed(1.1, faster: false), 1);
    });

    test('labels a rate without trailing zeros', () {
      expect(speedLabel(1), '1×');
      expect(speedLabel(1.25), '1.25×');
      expect(speedLabel(0.5), '0.5×');
    });

    test('cycles the picture fits', () {
      expect(PictureFit.fit.next, PictureFit.fill);
      expect(PictureFit.stretch.next, PictureFit.fit);
      expect(PictureFit.wide.forcedAspect, closeTo(1.778, 0.001));
      expect(PictureFit.classic.forcedAspect, closeTo(1.333, 0.001));
      expect(PictureFit.fill.forcedAspect, isNull);
      expect(PictureFit.fill.label, 'Fill (crop)');
    });

    test('knows how long each sleep timer runs', () {
      expect(SleepTimer.min30.after, const Duration(minutes: 30));
      expect(SleepTimer.min60.after, const Duration(minutes: 60));
      expect(SleepTimer.endOfFilm.after, isNull);
      expect(SleepTimer.off.label, 'Off');
    });
  });

  group('resume keys for streams', () {
    test('is stable and 16 hex characters', () {
      final a = urlResumeKey('https://example.com/film.m3u8');
      expect(a.isValid, isTrue);
      expect(urlResumeKey('https://example.com/film.m3u8'), a);
      expect(urlResumeKey('https://example.com/other.m3u8'), isNot(a));
    });

    test('matches the FNV-1a reference vector', () {
      expect(urlResumeKey('a').value, 'af63dc4c8601ec8c');
      expect(urlResumeKey('').value, 'cbf29ce484222325');
    });
  });

  group('languages', () {
    test('lists every container spelling for alang', () {
      expect(mpvLanguageList(['fr', 'xx']), ['fr', 'fra', 'fre', 'xx']);
    });

    test('matches 639-1, 639-2 and region tags', () {
      expect(languageMatches('eng', 'en'), isTrue);
      expect(languageMatches('en-US', 'en'), isTrue);
      expect(languageMatches('ger', 'de'), isTrue);
      expect(languageMatches('fra', 'de'), isFalse);
      expect(languageMatches(null, 'en'), isFalse);
      expect(languageMatches('', 'en'), isFalse);
    });

    test('knows which languages the bundled font cannot draw', () {
      expect(isNonLatinLanguage('ara'), isTrue);
      expect(isNonLatinLanguage('hi'), isTrue);
      expect(isNonLatinLanguage('ru'), isFalse);
      expect(isNonLatinLanguage('en'), isFalse);
      expect(isNonLatinLanguage(null), isFalse);
    });

    test('spots text outside Latin, Greek and Cyrillic', () {
      expect(needsSystemFonts('Héllo — “Ωμέγα” Привет …'), isFalse);
      expect(needsSystemFonts('﻿ok�'), isFalse);
      expect(needsSystemFonts('مرحبا'), isTrue);
      expect(needsSystemFonts('こんにちは'), isTrue);
      expect(needsSystemFonts('नमस्ते'), isTrue);
    });
  });
}
