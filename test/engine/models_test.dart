import 'package:marquee/engine/hash.dart';
import 'package:marquee/engine/models/models.dart';
import 'package:marquee/engine/sentences.dart';
import 'package:marquee/engine/threading.dart' show fallbacksFor;
import 'package:test/test.dart';

void main() {
  group('models and sentences', () {
    test('gives every failure exactly one plain sentence', () {
      for (final f in ThreadingFailure.values) {
        final s = sentenceFor(f, retryAfterSeconds: 3);
        if (f == ThreadingFailure.fileTooSmall) {
          expect(s, isEmpty); // not an error at all
        } else {
          expect(s, isNotEmpty);
          expect(s, isNot(matches(RegExp(r'\b(4\d\d|5\d\d)\b')))); // never a status code
        }
      }
      expect(sentenceFor(ThreadingFailure.rateLimited), 'OpenSubtitles asked us to wait 2 s.');
    });

    test('announces each phase once in words', () {
      expect(announceFor(LeaderPhase.idle), '');
      expect(announceFor(LeaderPhase.hashing), 'Reading file');
      expect(announceFor(LeaderPhase.searching), 'Searching subtitles');
      expect(announceFor(LeaderPhase.downloading), 'Downloading English subtitles');
      expect(announceFor(LeaderPhase.done, synced: true), 'Subtitles attached, in sync');
      expect(announceFor(LeaderPhase.flash), 'Subtitles attached');
      expect(languageName('hi'), 'Hindi');
      expect(languageName('xx'), 'XX');
    });

    test('names the hash exceptions', () {
      expect(const FileTooSmall(3).toString(), 'FileTooSmall(3)');
      expect(const HashUnavailable('x').toString(), 'HashUnavailable(x)');
      expect(const ThreadingException(ThreadingFailure.offline).toString(), contains('offline'));
    });

    test('round-trips settings and ignores unknown fields', () {
      const s = Settings(
        languages: ['en', 'hi', 'ta'],
        preferHearingImpaired: true,
        saveBesideFile: false,
        subdlEnabled: true,
        tmdbEnabled: true,
        roomTone: true,
        biasLight: false,
        beam: false,
        sounds: false,
        haptics: false,
        lobbyTheme: LobbyTheme.matinee,
        hwdec: 'no',
        scanMode: LibraryScanMode.folders,
      );
      final back = Settings.fromJson({...s.toJson(), 'mystery': 1});
      expect(back.toJson(), s.toJson());
      expect(
        Settings.fromJson({
          'languages': ['a', 'b', 'c', 'd'],
        }).languages,
        hasLength(3),
      );
      expect(Settings.fromJson(const {}).languages, ['en']);
      expect(const Settings().copyWith(hwdec: 'no').hwdec, 'no');
    });

    test('computes resume fractions and the finished state', () {
      final at = DateTime.utc(2026);
      const h = MovieHash('8e245d9679d31e12');
      expect(ResumePoint(hash: h, positionMs: 50, durationMs: 100, at: at).fraction, 0.5);
      expect(ResumePoint(hash: h, positionMs: 98, durationMs: 100, at: at).finished, isTrue);
      expect(ResumePoint(hash: h, positionMs: 0, durationMs: 0, at: at).fraction, 0);
      expect(const MovieHash('xyz').isValid, isFalse);
      expect(const SyncOffset(hash: h, delayMs: 350).delayMs, 350);
    });

    test('maps quota to ticket states', () {
      expect(Quota.anonymous.state, TicketState.anonymous);
      expect(const Quota(signedIn: true, vip: true).state, TicketState.vip);
      expect(const Quota(signedIn: true).state, TicketState.unknown);
      expect(const Quota(signedIn: true, remaining: 0).state, TicketState.exhausted);
      expect(const Quota(signedIn: true, remaining: 2).state, TicketState.twoLeft);
      expect(const Quota(signedIn: true, remaining: 3).state, TicketState.nLeft);
    });

    test('carries leader state through copies', () {
      const s = ThreadingState();
      expect(s.numeral, isNull);
      expect(s.copyWith(phase: LeaderPhase.hashing).numeral, 3);
      expect(s.copyWith(phase: LeaderPhase.searching).numeral, 2);
      expect(s.copyWith(phase: LeaderPhase.downloading).numeral, 1);
      final withEvent = s.copyWith(event: const Notice('n'));
      expect(withEvent.copyWith(clearEvent: true).event, isNull);
      expect(withEvent.stalled, isFalse);
    });

    test('skips subtitle entries that carry no file', () {
      expect(
        SubtitleCandidate.fromOpenSubtitles(const {
          'attributes': {'files': []},
        }),
        isNull,
      );
      expect(SubtitleCandidate.fromOpenSubtitles(const {'attributes': 1}), isNull);
      expect(
        SubtitleCandidate.fromOpenSubtitles(const {
          'attributes': {
            'files': [
              {'file_name': 'x'},
            ],
          },
        }),
        isNull,
      );
    });

    test('sends a build without an API key to the ticket office first', () {
      final next = fallbacksFor(
        ThreadingFailure.noApiKey,
        subdlEnabled: false,
        filenameSearchDone: true,
        at: LeaderPhase.searching,
      );
      expect(next.first, FallbackAction.signIn);
      expect(sentenceFor(ThreadingFailure.noApiKey), contains('API key'));
    });
  });
}
