import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:marquee/engine/filename.dart';
import 'package:marquee/engine/hash.dart';
import 'package:marquee/engine/models/models.dart';
import 'package:marquee/engine/sentences.dart';
import 'package:marquee/engine/threading.dart';
import 'package:test/test.dart';

List<SubtitleCandidate> fixture(String name) {
  final j = jsonDecode(File('test/fixtures/os/$name').readAsStringSync()) as Map<String, Object?>;
  return (j['data']! as List)
      .cast<Map<String, Object?>>()
      .map(SubtitleCandidate.fromOpenSubtitles)
      .whereType<SubtitleCandidate>()
      .toList();
}

const name = 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv';
const attachedSub = ExternalSubtitle(
  path: 'x.en.srt',
  language: 'en',
  provider: SubtitleProvider.openSubtitles,
  syncedByHash: true,
);

class Harness {
  Future<MovieHash> Function() hash = () async => const MovieHash('8e245d9679d31e12');
  Future<ExternalSubtitle?> Function(MovieHash?) existing = (_) async => null;
  Future<List<SubtitleCandidate>> Function(SearchRequest) search = (r) async =>
      r.hash != null ? fixture('search-hash-hit.json') : fixture('search-by-name.json');
  Future<DownloadOutcome> Function(ScoredCandidate, MovieHash?) download = (p, h) async =>
      const DownloadOutcome(attached: attachedSub, remaining: 7);
  final searches = <SearchRequest>[];
  final subdlSearches = <SearchRequest>[];
  final downloads = <String>[];
  final states = <ThreadingState>[];
  late final ThreadingMachine m;

  Harness({
    Quota quota = const Quota(signedIn: true, remaining: 8, total: 10),
    bool subdl = false,
  }) {
    m = ThreadingMachine(
      ports: ThreadingPorts(
        hash: () => hash(),
        findExisting: (h) => existing(h),
        search: (r) {
          searches.add(r);
          return search(r);
        },
        subdl: subdl
            ? (r) async {
                subdlSearches.add(r);
                return const [];
              }
            : null,
        download: (p, h) {
          downloads.add(p.candidate.id);
          return download(p, h);
        },
      ),
      config: ThreadingConfig(subdlEnabled: subdl),
      quota: quota,
      onChange: states.add,
    );
  }

  void open(FakeAsync a, {String display = name, int size = 1524000000}) {
    m.open(displayName: display, sizeBytes: size, parsed: parseName(display), containerFps: 23.976);
    a.flushMicrotasks();
  }

  List<LeaderPhase> get phases {
    final out = <LeaderPhase>[];
    for (final s in states) {
      if (out.isEmpty || out.last != s.phase) out.add(s.phase);
    }
    return out;
  }
}

const hash = MovieHash('8e245d9679d31e12');

SubtitleCandidate machineOnly() => const SubtitleCandidate(
  provider: SubtitleProvider.openSubtitles,
  id: 'mt',
  language: 'en',
  release: 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE',
  downloadCount: 500,
  moviehashMatch: true,
  machineTranslated: true,
);

Stalled stalledOf(Harness h) => h.m.state.event! as Stalled;

void main() {
  group('leader state machine', () {
    test('starts hashing on open with the numeral 3', () {
      fakeAsync((a) {
        final h = Harness()..hash = () => Completer<MovieHash>().future;
        h.open(a);
        expect(h.m.state.phase, LeaderPhase.hashing);
        expect(h.m.state.numeral, 3);
        expect(h.searches, isEmpty);
      });
    });

    test('moves to searching by hash when the hash is ready', () {
      fakeAsync((a) {
        final h = Harness()..search = (_) => Completer<List<SubtitleCandidate>>().future;
        h.open(a);
        a.elapse(const Duration(milliseconds: 10));
        expect(h.m.state.phase, LeaderPhase.searching);
        expect(h.m.state.hash, hash);
        expect(h.m.state.numeral, 2);
        expect(h.searches.single.hash, hash);
      });
    });

    test('skips silently to a filename search when the file is too small', () {
      fakeAsync((a) {
        final h = Harness()..hash = () async => throw const FileTooSmall(100);
        h.open(a, display: 'Paddington.2014.720p.WEB-DL.H264-NTb.mkv', size: 100);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.states.every((s) => s.event is! Stalled), isTrue);
        expect(h.m.state.hash, isNull);
        expect(h.searches.single.hash, isNull);
        expect(h.searches.single.parsed!.title, 'Paddington');
        expect(h.m.state.phase, LeaderPhase.done);
      });
    });

    test('sends the raw filename when the name is low confidence', () {
      fakeAsync((a) {
        final h = Harness()..hash = () async => throw const FileTooSmall(1);
        h.open(a, display: 'movie.mkv', size: 1);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.searches.single.query, 'movie.mkv');
      });
    });

    test('skips to a name search when the file vanishes mid-hash without stalling', () {
      fakeAsync((a) {
        final h = Harness()..hash = () async => throw HashUnavailable(Exception('gone'));
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.searches.single.hash, isNull);
        expect(h.states.any((s) => s.event is Stalled), isFalse);
      });
    });

    test('advances the sweep only while the phase is pending', () {
      final t0 = DateTime.utc(2026, 9, 6, 15, 44);
      expect(leaderSweep(t0, t0), 0);
      expect(leaderSweep(t0, t0.add(const Duration(milliseconds: 250))), 0.25);
      expect(leaderSweep(t0, t0.add(const Duration(milliseconds: 400))), closeTo(0.4, 1e-9));
      // Once stalled the sweep stops where it stood, however much later it is drawn.
      final stalledAt = t0.add(const Duration(milliseconds: 400));
      final later = t0.add(const Duration(seconds: 3));
      expect(leaderSweep(t0, later, frozenAt: stalledAt), closeTo(0.4, 1e-9));
    });

    test('freezes the sweep when the search rejects', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (_) async => throw const ThreadingException(ThreadingFailure.offline);
        h.open(a);
        a.elapse(const Duration(milliseconds: 20));
        final s = h.m.state;
        final ev = stalledOf(h);
        expect(s.phase, LeaderPhase.searching);
        expect(ev.failure, ThreadingFailure.offline);
        expect(ev.sentence, "You're offline — playing without new subtitles.");
        final frozen = leaderSweep(s.phaseStartedAt!, clock.now(), frozenAt: ev.stalledAt);
        a.elapse(const Duration(milliseconds: 400));
        expect(leaderSweep(s.phaseStartedAt!, clock.now(), frozenAt: ev.stalledAt), frozen);
        expect(h.downloads, isEmpty);
      });
    });

    test('never jumps the sweep to full or resets it to zero on a stall', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (_) => Future<List<SubtitleCandidate>>.delayed(
            const Duration(milliseconds: 5040),
            () => throw const ThreadingException(ThreadingFailure.rateLimited),
          );
        h.open(a);
        a.elapse(const Duration(milliseconds: 5100));
        final s = h.m.state;
        final ev = stalledOf(h);
        final sweep = leaderSweep(s.phaseStartedAt!, clock.now(), frozenAt: ev.stalledAt);
        expect(sweep, greaterThan(0));
        expect(sweep, lessThan(1));
      });
    });

    test('times out each phase at its deadline', () {
      fakeAsync((a) {
        final h = Harness()..search = (_) => Completer<List<SubtitleCandidate>>().future;
        h.open(a);
        a.elapse(const Duration(milliseconds: 7990));
        expect(h.m.state.stalled, isFalse);
        a.elapse(const Duration(milliseconds: 20));
        expect(stalledOf(h).failure, ThreadingFailure.timeout);
        expect(stalledOf(h).at, LeaderPhase.searching);
      });
      fakeAsync((a) {
        final h = Harness()..download = (p, x) => Completer<DownloadOutcome>().future;
        h.open(a);
        a.elapse(const Duration(milliseconds: 14990));
        expect(h.m.state.stalled, isFalse);
        a.elapse(const Duration(milliseconds: 20));
        expect(stalledOf(h).failure, ThreadingFailure.timeout);
        expect(stalledOf(h).at, LeaderPhase.downloading);
      });
      expect(kHashDeadline, const Duration(seconds: 2));
      expect(kSearchDeadline, const Duration(seconds: 8));
      expect(kDownloadDeadline, const Duration(seconds: 15));
    });

    test('orders the fallback rows filename, subdl, manual, skip', () {
      expect(
        fallbacksFor(
          ThreadingFailure.noResults,
          subdlEnabled: true,
          filenameSearchDone: false,
          at: LeaderPhase.searching,
        ),
        [
          FallbackAction.filenameSearch,
          FallbackAction.subdl,
          FallbackAction.manualSearch,
          FallbackAction.skip,
        ],
      );
      fakeAsync((a) {
        // A machine-translated hash hit may not be auto-picked: no results, name search untried.
        final h = Harness(subdl: true)..search = (_) async => [machineOnly()];
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(stalledOf(h).next, [
          FallbackAction.filenameSearch,
          FallbackAction.subdl,
          FallbackAction.manualSearch,
          FallbackAction.skip,
        ]);
      });
    });

    test('omits subdl when it is not enabled and rungs already tried', () {
      fakeAsync((a) {
        final h = Harness()
          ..hash = (() async => throw const FileTooSmall(100))
          ..search = (_) async => const [];
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(stalledOf(h).failure, ThreadingFailure.noResults);
        expect(stalledOf(h).next, [FallbackAction.manualSearch, FallbackAction.skip]);
      });
    });

    test('lists name results but never spends a ticket when the hash misses', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (r) async => r.hash != null ? const [] : fixture('search-by-name.json');
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        final ev = stalledOf(h);
        expect(ev.failure, ThreadingFailure.noResults);
        expect(ev.next, isNot(contains(FallbackAction.filenameSearch)));
        expect(h.m.state.candidates, isNotEmpty);
        expect(h.downloads, isEmpty);
        expect(h.searches, hasLength(2));
      });
    });

    test('inserts sign-in first when the download is unauthorized', () {
      fakeAsync((a) {
        final h = Harness()
          ..download = (p, x) async =>
              throw const ThreadingException(ThreadingFailure.unauthorized);
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(stalledOf(h).at, LeaderPhase.downloading);
        expect(stalledOf(h).failure, ThreadingFailure.unauthorized);
        expect(stalledOf(h).next.first, FallbackAction.signIn);
      });
    });

    test('inserts sign-in first when the quota is exhausted', () {
      fakeAsync((a) {
        final h = Harness()
          ..download = (p, x) async =>
              throw const ThreadingException(ThreadingFailure.quotaExhausted);
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        final ev = stalledOf(h);
        expect(ev.at, LeaderPhase.downloading);
        expect(ev.failure, ThreadingFailure.quotaExhausted);
        expect(ev.next.first, FallbackAction.signIn);
        expect(h.m.state.quota.remaining, 0);
      });
    });

    test('offers a retry after a rate limit or going offline', () {
      for (final f in [ThreadingFailure.rateLimited, ThreadingFailure.offline]) {
        fakeAsync((a) {
          final h = Harness()..search = (_) async => throw ThreadingException(f);
          h.open(a);
          a.elapse(const Duration(milliseconds: 20));
          expect(stalledOf(h).next, [
            FallbackAction.retry,
            FallbackAction.filenameSearch,
            FallbackAction.manualSearch,
            FallbackAction.skip,
          ]);
        });
      }
    });

    test('publishes the fallback rows within 500 ms of the failure', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (_) async =>
              throw const ThreadingException(ThreadingFailure.rateLimited, retryAfterSeconds: 2);
        final t0 = clock.now();
        h.open(a);
        a.elapse(const Duration(milliseconds: 1));
        final ev = stalledOf(h);
        expect(ev.next, isNotEmpty);
        expect(ev.stalledAt.difference(t0).inMilliseconds, lessThan(500));
        expect(ev.sentence, 'OpenSubtitles asked us to wait 2 s.');
      });
    });

    test('auto-picks rank 1 and downloads when signed in with tickets', () {
      fakeAsync((a) {
        final h = Harness();
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.phases, [
          LeaderPhase.hashing,
          LeaderPhase.searching,
          LeaderPhase.downloading,
          LeaderPhase.flash,
          LeaderPhase.done,
        ]);
        expect(h.states.any((s) => s.phase == LeaderPhase.downloading && s.numeral == 1), isTrue);
        expect(h.downloads, ['1234567']);
        expect(h.m.state.picked!.candidate.id, '1234567');
        expect(h.m.state.quota.remaining, 7);
        expect(h.m.state.attached, attachedSub);
      });
    });

    test('makes no request when no tickets are left', () {
      fakeAsync((a) {
        final h = Harness(quota: const Quota(signedIn: true, remaining: 0, total: 10));
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        final ev = stalledOf(h);
        expect(ev.failure, ThreadingFailure.quotaExhausted);
        expect(ev.next.first, FallbackAction.signIn);
        expect(h.downloads, isEmpty);
      });
    });

    test('resumes the pending download after sign-in', () {
      fakeAsync((a) {
        var signedIn = false;
        final h = Harness()
          ..download = (p, x) async {
            if (!signedIn) throw const ThreadingException(ThreadingFailure.unauthorized);
            return const DownloadOutcome(attached: attachedSub, remaining: 19);
          };
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(stalledOf(h).next.first, FallbackAction.signIn);
        signedIn = true;
        h.m.setQuota(const Quota(signedIn: true, remaining: 20, total: 20));
        h.m.retry();
        a.elapse(const Duration(milliseconds: 100));
        expect(h.downloads, ['1234567', '1234567']);
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.m.state.quota.remaining, 19);
      });
    });

    test('retries the download exactly once on a 410', () {
      fakeAsync((a) {
        var calls = 0;
        final h = Harness()
          ..download = (p, x) async {
            if (calls++ == 0) throw const ThreadingException(ThreadingFailure.linkExpired);
            return const DownloadOutcome(attached: attachedSub, remaining: 6);
          };
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(calls, 2);
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.m.state.quota.remaining, 6);
      });
      fakeAsync((a) {
        var calls = 0;
        final h = Harness()
          ..download = (p, x) async {
            calls++;
            throw const ThreadingException(ThreadingFailure.linkExpired);
          };
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(calls, 2);
        expect(stalledOf(h).failure, ThreadingFailure.linkExpired);
        expect(h.states.any((s) => s.event is Notice), isTrue);
      });
    });

    test('stalls with no results when only machine translations were found', () {
      fakeAsync((a) {
        final h = Harness()..search = (_) async => [machineOnly()];
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(stalledOf(h).failure, ThreadingFailure.noResults);
        expect(h.m.state.candidates.map((c) => c.candidate.id), ['mt']);
        expect(h.downloads, isEmpty);
      });
    });

    test('lets a tap override the auto-pick and cancel the download in flight', () {
      fakeAsync((a) {
        final slow = Completer<DownloadOutcome>();
        final h = Harness();
        h.download = (p, x) => p.candidate.id == '1234567'
            ? slow.future
            : Future.value(const DownloadOutcome(attached: attachedSub, remaining: 5));
        h.open(a);
        a.elapse(const Duration(milliseconds: 10));
        expect(h.m.state.phase, LeaderPhase.downloading);
        final other = h.m.state.candidates.firstWhere((c) => c.candidate.id != '1234567');
        h.m.pick(other);
        a.elapse(const Duration(milliseconds: 100));
        slow.complete(const DownloadOutcome(attached: attachedSub, remaining: 1));
        a.flushMicrotasks();
        expect(h.m.state.picked!.candidate.id, other.candidate.id);
        expect(h.m.state.quota.remaining, 5);
      });
    });

    test('resolves a cancel to done and still starts playback', () {
      fakeAsync((a) {
        final h = Harness()..search = (_) => Completer<List<SubtitleCandidate>>().future;
        h.open(a);
        a.elapse(const Duration(milliseconds: 10));
        h.m.skip();
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.m.state.picked, isNull);
        expect(h.m.state.attached, isA<NoSubtitle>());
      });
    });

    test('resolves skip to done without subtitles', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (_) async => throw const ThreadingException(ThreadingFailure.offline);
        h.open(a);
        a.elapse(const Duration(milliseconds: 20));
        expect(h.m.state.stalled, isTrue);
        h.m.skip();
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.m.state.stalled, isFalse);
        expect(h.m.state.attached, isA<NoSubtitle>());
      });
    });

    test('flashes for 66 ms and then plays with subtitles', () {
      fakeAsync((a) {
        final h = Harness()
          ..download = (p, x) async => const DownloadOutcome(attached: attachedSub, remaining: 6);
        h.open(a);
        expect(h.m.state.phase, LeaderPhase.flash);
        expect(kFlash, const Duration(milliseconds: 66));
        a.elapse(const Duration(milliseconds: 65));
        expect(h.m.state.phase, LeaderPhase.flash);
        a.elapse(const Duration(milliseconds: 1));
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.m.state.attached, attachedSub);
        expect(h.m.state.quota.remaining, 6);
      });
    });

    test('reattaches from the cache without a search', () {
      fakeAsync((a) {
        final h = Harness()..existing = (_) async => attachedSub;
        h.open(a);
        expect(h.m.state.phase, LeaderPhase.flash);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.searches, isEmpty);
        expect(h.downloads, isEmpty);
        expect(h.m.state.phase, LeaderPhase.done);
      });
    });

    test('runs a manual search from the stall and downloads the pick', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (r) async =>
              r.query == 'third man' ? fixture('search-hash-hit.json') : const [];
        h.open(a);
        a.elapse(const Duration(milliseconds: 50));
        expect(h.m.state.stalled, isTrue);
        h.m.manualSearch('third man');
        a.elapse(const Duration(milliseconds: 100));
        expect(h.searches.last.query, 'third man');
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.downloads, hasLength(1));
      });
    });

    test('retries a stalled download or a stalled search on the same rung', () {
      fakeAsync((a) {
        var fail = true;
        final h = Harness()
          ..search = (r) async {
            if (fail) throw const ThreadingException(ThreadingFailure.offline);
            return fixture('search-hash-hit.json');
          };
        h.open(a);
        a.elapse(const Duration(milliseconds: 10));
        fail = false;
        h.m.retry();
        a.elapse(const Duration(milliseconds: 100));
        expect(h.searches.map((r) => r.hash), [hash, hash]);
        expect(h.m.state.phase, LeaderPhase.done);
      });
      fakeAsync((a) {
        var fail = true;
        final h = Harness()
          ..download = (p, x) async {
            if (fail) throw const ThreadingException(ThreadingFailure.offline);
            return const DownloadOutcome(attached: attachedSub, remaining: 6);
          };
        h.open(a);
        a.elapse(const Duration(milliseconds: 10));
        expect(stalledOf(h).at, LeaderPhase.downloading);
        fail = false;
        h.m.retry();
        a.elapse(const Duration(milliseconds: 100));
        expect(h.downloads, ['1234567', '1234567']);
        expect(h.searches, hasLength(1));
        expect(h.m.state.phase, LeaderPhase.done);
      });
    });

    test('runs the filename and Subdl rungs when chosen', () {
      fakeAsync((a) {
        final h = Harness(subdl: true)..search = (_) async => const [];
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(stalledOf(h).next, contains(FallbackAction.subdl));
        final before = h.searches.length;
        h.m.filenameSearch();
        a.elapse(const Duration(milliseconds: 100));
        expect(h.searches, hasLength(before + 1));
        expect(h.searches.last.hash, isNull);
        h.m.subdlSearch();
        a.elapse(const Duration(milliseconds: 100));
        expect(h.subdlSearches, hasLength(1));
      });
      fakeAsync((a) {
        final h = Harness()..search = (_) async => const [];
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(stalledOf(h).next, isNot(contains(FallbackAction.subdl)));
      });
    });

    test('stalls instead of hanging when a port throws a raw error', () {
      fakeAsync((a) {
        final h = Harness()..search = (_) async => throw const FormatException('bad json');
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.m.state.phase, LeaderPhase.searching);
        expect(stalledOf(h).failure, ThreadingFailure.timeout);
        expect(stalledOf(h).next, contains(FallbackAction.retry));
      });
      fakeAsync((a) {
        final h = Harness()..download = (_, _) async => throw StateError('bad zip');
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.m.state.phase, LeaderPhase.downloading);
        expect(stalledOf(h).failure, ThreadingFailure.timeout);
      });
      fakeAsync((a) {
        final h = Harness()..existing = (_) async => throw StateError('closed');
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.m.state.phase, LeaderPhase.done);
      });
    });

    test('lists a subtitle once when the hash and name searches both return it', () {
      fakeAsync((a) {
        final h = Harness()..search = (_) async => fixture('search-by-name.json');
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.searches, hasLength(2));
        final keys = [
          for (final c in h.m.state.candidates) '${c.candidate.provider.name}/${c.candidate.id}',
        ];
        expect(keys, isNotEmpty);
        expect(keys.toSet(), hasLength(keys.length));
      });
    });

    test('labels the numerals and phases in plain words', () {
      expect(const ThreadingState().numeral, isNull);
      expect(const ThreadingState(phase: LeaderPhase.hashing).numeral, 3);
      expect(const ThreadingState(phase: LeaderPhase.searching).numeral, 2);
      expect(const ThreadingState(phase: LeaderPhase.downloading).numeral, 1);
      expect(languageName('hi'), 'Hindi');
      expect(languageName('not a code!'), 'NOT A CODE!');
    });
  });
}
