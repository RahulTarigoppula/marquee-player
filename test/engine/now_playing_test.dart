import 'package:marquee/engine/now_playing.dart';
import 'package:test/test.dart';

const _film = NowPlayingInfo(
  title: 'Heat',
  duration: Duration(hours: 2),
  position: Duration(minutes: 10),
  playing: true,
);

NowPlayingInfo _at(NowPlayingInfo of, Duration position, {bool? playing, bool? buffering}) =>
    NowPlayingInfo(
      title: of.title,
      subtitle: of.subtitle,
      duration: of.duration,
      position: position,
      speed: of.speed,
      playing: playing ?? of.playing,
      buffering: buffering ?? of.buffering,
      hasPrevious: of.hasPrevious,
      hasNext: of.hasNext,
      stepSeconds: of.stepSeconds,
    );

void main() {
  group('expectedPosition', () {
    test('advances a playing film by the time that passed', () {
      expect(
        expectedPosition(_film, const Duration(seconds: 30)),
        const Duration(minutes: 10, seconds: 30),
      );
    });

    test('advances faster at a higher speed', () {
      const fast = NowPlayingInfo(
        title: 'Heat',
        duration: Duration(hours: 2),
        position: Duration(minutes: 10),
        speed: 2,
        playing: true,
      );
      expect(expectedPosition(fast, const Duration(seconds: 30)), const Duration(minutes: 11));
    });

    test('stands still while paused', () {
      final paused = _at(_film, _film.position, playing: false);
      expect(expectedPosition(paused, const Duration(minutes: 5)), _film.position);
    });

    test('stands still while buffering', () {
      final stalled = _at(_film, _film.position, buffering: true);
      expect(expectedPosition(stalled, const Duration(minutes: 5)), _film.position);
    });

    test('never runs past the end of the film', () {
      expect(expectedPosition(_film, const Duration(hours: 5)), _film.duration);
    });

    test('runs on when the length is unknown', () {
      const live = NowPlayingInfo(title: 'Stream', playing: true);
      expect(expectedPosition(live, const Duration(hours: 3)), const Duration(hours: 3));
    });
  });

  group('nowPlayingChanged', () {
    test('the first description is always sent', () {
      expect(nowPlayingChanged(null, Duration.zero, _film), isTrue);
    });

    test('a film playing on as expected is not sent again', () {
      final later = _at(_film, const Duration(minutes: 10, seconds: 30));
      expect(nowPlayingChanged(_film, const Duration(seconds: 30), later), isFalse);
    });

    test('two clocks a little apart are left alone', () {
      final later = _at(_film, const Duration(minutes: 10, seconds: 31));
      expect(nowPlayingChanged(_film, const Duration(seconds: 30), later), isFalse);
    });

    test('a seek forward is sent', () {
      final later = _at(_film, const Duration(minutes: 40));
      expect(nowPlayingChanged(_film, const Duration(seconds: 1), later), isTrue);
    });

    test('a seek backward is sent', () {
      final later = _at(_film, const Duration(minutes: 2));
      expect(nowPlayingChanged(_film, const Duration(seconds: 1), later), isTrue);
    });

    test('a pause is sent', () {
      final paused = _at(_film, _film.position, playing: false);
      expect(nowPlayingChanged(_film, Duration.zero, paused), isTrue);
    });

    test('a paused film that has not moved is not sent again', () {
      final paused = _at(_film, _film.position, playing: false);
      expect(nowPlayingChanged(paused, const Duration(minutes: 20), paused), isFalse);
    });

    test('a seek while paused is sent', () {
      final paused = _at(_film, _film.position, playing: false);
      final moved = _at(paused, const Duration(minutes: 50));
      expect(nowPlayingChanged(paused, const Duration(seconds: 5), moved), isTrue);
    });

    test('a stall is sent', () {
      final stalled = _at(_film, _film.position, buffering: true);
      expect(nowPlayingChanged(_film, Duration.zero, stalled), isTrue);
    });

    test('another title, speed, length, neighbour or jump size is sent', () {
      const base = NowPlayingInfo(title: 'Heat', duration: Duration(hours: 2));
      const changes = [
        NowPlayingInfo(title: 'Ronin', duration: Duration(hours: 2)),
        NowPlayingInfo(title: 'Heat', subtitle: 'heat.mkv', duration: Duration(hours: 2)),
        NowPlayingInfo(title: 'Heat', duration: Duration(hours: 3)),
        NowPlayingInfo(title: 'Heat', duration: Duration(hours: 2), speed: 1.5),
        NowPlayingInfo(title: 'Heat', duration: Duration(hours: 2), hasNext: true),
        NowPlayingInfo(title: 'Heat', duration: Duration(hours: 2), hasPrevious: true),
        NowPlayingInfo(title: 'Heat', duration: Duration(hours: 2), stepSeconds: 30),
      ];
      for (final c in changes) {
        expect(nowPlayingChanged(base, Duration.zero, c), isTrue, reason: '${c.toMap()}');
      }
    });
  });

  group('NowPlayingInfo', () {
    test('is described to the system in milliseconds', () {
      const info = NowPlayingInfo(
        title: 'Heat',
        subtitle: 'heat.1995.mkv',
        duration: Duration(seconds: 90),
        position: Duration(milliseconds: 1500),
        speed: 1.25,
        playing: true,
        hasNext: true,
        stepSeconds: 15,
      );
      expect(info.toMap(), {
        'title': 'Heat',
        'subtitle': 'heat.1995.mkv',
        'durationMs': 90000,
        'positionMs': 1500,
        'speed': 1.25,
        'playing': true,
        'buffering': false,
        'hasPrevious': false,
        'hasNext': true,
        'stepSeconds': 15,
      });
    });

    test('the clock runs only while playing and not stalled', () {
      expect(_film.advancing, isTrue);
      expect(_at(_film, _film.position, playing: false).advancing, isFalse);
      expect(_at(_film, _film.position, buffering: true).advancing, isFalse);
    });
  });

  group('nowPlayingSubtitle', () {
    test('adds the file name under a cleaned-up title', () {
      expect(
        nowPlayingSubtitle(title: 'Heat', fileName: 'Heat.1995.1080p.mkv'),
        'Heat.1995.1080p.mkv',
      );
    });

    test('says nothing twice when the title is the file name', () {
      expect(nowPlayingSubtitle(title: 'holiday.mp4', fileName: 'holiday.mp4'), isNull);
      expect(nowPlayingSubtitle(title: 'holiday', fileName: 'holiday.mp4'), isNull);
    });

    test('copes with a name that has no extension, or nothing but one', () {
      expect(nowPlayingSubtitle(title: 'Clip', fileName: 'clip-raw'), 'clip-raw');
      expect(nowPlayingSubtitle(title: 'Clip', fileName: ''), isNull);
      expect(nowPlayingSubtitle(title: '.hidden', fileName: '.hidden'), isNull);
    });
  });
}
