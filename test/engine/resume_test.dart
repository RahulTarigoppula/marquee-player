// The one resume rule the Lobby, the resume store and the session share, and Settings value
// equality (what lets an unchanged setting notify nobody).
import 'package:marquee/engine/models/models.dart';
import 'package:test/test.dart';

void main() {
  const film = 104 * 60000;

  group('resume rule', () {
    test('counts the last 30 seconds as watched', () {
      expect(isFinishedAt(film - 30000, film), isTrue);
      expect(isFinishedAt(film - 30001, film), isFalse);
      expect(isFinishedAt(film, film), isTrue);
    });

    test('never calls a film watched before it moved or without a length', () {
      expect(isFinishedAt(0, film), isFalse);
      expect(isFinishedAt(5000, 0), isFalse);
    });

    test('resumes two minutes before the end (the case that used to start over)', () {
      expect(isResumableAt(film - 120000, film), isTrue);
    });

    test('starts from the beginning in the first ten seconds and once watched', () {
      expect(isResumableAt(10000, film), isFalse);
      expect(isResumableAt(10001, film), isTrue);
      expect(isResumableAt(film - 1000, film), isFalse);
    });

    test('agrees between a Lobby card and the stored resume point', () {
      final at = DateTime.utc(2026);
      const h = MovieHash('8e245d9679d31e12');
      for (final pos in [0, 9000, 60000, film - 120000, film - 20000, film]) {
        final rp = ResumePoint(hash: h, positionMs: pos, durationMs: film, at: at);
        final card = LobbyCard(
          id: 1,
          locator: 'a.mkv',
          displayName: 'a.mkv',
          durationMs: film,
          resumePositionMs: pos,
          finished: rp.finished,
        );
        expect(card.inProgress, rp.resumable, reason: 'at $pos ms');
      }
    });

    test('derives the position from the fraction when only that is known', () {
      const c = LobbyCard(
        id: 1,
        locator: 'a.mkv',
        displayName: 'a.mkv',
        durationMs: 100000,
        resumeFraction: 0.5,
      );
      expect(c.positionMs, 50000);
      expect(c.inProgress, isTrue);
    });
  });

  group('settings equality', () {
    test('treats equal values as equal, lists included', () {
      expect(const Settings(languages: ['en', 'hi']), Settings(languages: ['en', 'hi'].toList()));
      expect(const Settings().hashCode, const Settings().copyWith().hashCode);
    });

    test('tells a changed field apart', () {
      expect(const Settings(), isNot(const Settings().copyWith(volume: 90)));
      expect(const Settings(), isNot(const Settings(audioLanguages: ['ja'])));
    });

    test('keeps the subtitle style apart from unrelated fields', () {
      const s = Settings();
      expect(s.copyWith(volume: 40).subtitleStyle, s.subtitleStyle);
      expect(s.copyWith(subtitleScale: 1.3).subtitleStyle, isNot(s.subtitleStyle));
    });
  });
}
