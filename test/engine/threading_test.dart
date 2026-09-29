import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:marquee/engine/filename.dart';
import 'package:marquee/engine/hash.dart';
import 'package:marquee/engine/models/models.dart';
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
        subdl: subdl ? (r) async => const [] : null,
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

void main() {
  group('leader state machine', () {
    test('runs 3, 2, 1, flash on a hash hit and auto-picks the matched row', () {
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
        expect(h.downloads, ['1234567']);
        expect(h.m.state.quota.remaining, 7);
        expect(h.m.state.attached, attachedSub);
      });
    });

    test('costs zero requests when a sidecar or cached subtitle exists', () {
      fakeAsync((a) {
        final h = Harness()..existing = (_) async => attachedSub;
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.searches, isEmpty);
        expect(h.downloads, isEmpty);
        expect(h.m.state.phase, LeaderPhase.done);
      });
    });

    test('treats a file under 128 KiB silently and searches by name', () {
      fakeAsync((a) {
        final h = Harness()..hash = () async => throw const FileTooSmall(100);
        h.open(a, display: 'Paddington.2014.720p.WEB-DL.H264-NTb.mkv', size: 100);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.states.every((s) => s.event is! Stalled), isTrue);
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

    test('freezes the sweep when the search rejects and lists the fallbacks', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (_) async => throw const ThreadingException(ThreadingFailure.offline);
        h.open(a);
        a.elapse(const Duration(milliseconds: 20));
        final s = h.m.state;
        final ev = s.event! as Stalled;
        expect(s.phase, LeaderPhase.searching);
        expect(ev.failure, ThreadingFailure.offline);
        expect(ev.next, [
          FallbackAction.retry,
          FallbackAction.filenameSearch,
          FallbackAction.manualSearch,
          FallbackAction.skip,
        ]);
        expect(ev.sentence, "You're offline — playing without new subtitles.");
        final frozen = leaderSweep(s.phaseStartedAt!, clock.now(), frozenAt: ev.stalledAt);
        a.elapse(const Duration(milliseconds: 400));
        expect(leaderSweep(s.phaseStartedAt!, clock.now(), frozenAt: ev.stalledAt), frozen);
        expect(h.downloads, isEmpty);
      });
    });

    test('lists name results but never spends a ticket when the hash misses', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (r) async => r.hash != null ? const [] : fixture('search-by-name.json');
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        final ev = h.m.state.event! as Stalled;
        expect(ev.failure, ThreadingFailure.noResults);
        expect(ev.next, isNot(contains(FallbackAction.filenameSearch)));
        expect(h.m.state.candidates, isNotEmpty);
        expect(h.downloads, isEmpty);
        expect(h.searches, hasLength(2));
      });
    });

    test('inserts sign-in first and makes no request when the quota is exhausted', () {
      fakeAsync((a) {
        final h = Harness(quota: const Quota(signedIn: true, remaining: 0, total: 10));
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        final ev = h.m.state.event! as Stalled;
        expect(ev.failure, ThreadingFailure.quotaExhausted);
        expect(ev.next.first, FallbackAction.signIn);
        expect(h.downloads, isEmpty);
      });
    });

    test('stalls the download on 406 with sign-in first and the strip at zero', () {
      fakeAsync((a) {
        final h = Harness()
          ..download = (p, x) async =>
              throw const ThreadingException(ThreadingFailure.quotaExhausted);
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        final ev = h.m.state.event! as Stalled;
        expect(ev.at, LeaderPhase.downloading);
        expect(ev.next.first, FallbackAction.signIn);
        expect(h.m.state.quota.remaining, 0);
      });
    });

    test('retries a 410 link exactly once', () {
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
        expect((h.m.state.event! as Stalled).failure, ThreadingFailure.linkExpired);
        expect(h.states.any((s) => s.event is Notice), isTrue);
      });
    });

    test('shows the retried remaining after a 410', () {
      fakeAsync((a) {
        var calls = 0;
        final h = Harness()
          ..download = (p, x) async {
            if (calls++ == 0) throw const ThreadingException(ThreadingFailure.linkExpired);
            return const DownloadOutcome(attached: attachedSub, remaining: 6);
          };
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.m.state.quota.remaining, 6);
      });
    });

    test('times out a slow search as a stall, not a crash', () {
      fakeAsync((a) {
        final h = Harness()..search = (_) => Completer<List<SubtitleCandidate>>().future;
        h.open(a);
        a.elapse(const Duration(seconds: 9));
        expect((h.m.state.event! as Stalled).failure, ThreadingFailure.timeout);
      });
    });

    test('shows fallback rows within 500 ms of the failure', () {
      fakeAsync((a) {
        final h = Harness()
          ..search = (_) async =>
              throw const ThreadingException(ThreadingFailure.rateLimited, retryAfterSeconds: 2);
        final t0 = clock.now();
        h.open(a);
        a.elapse(const Duration(milliseconds: 1));
        final ev = h.m.state.event! as Stalled;
        expect(ev.stalledAt.difference(t0).inMilliseconds, lessThan(500));
        expect(ev.sentence, 'OpenSubtitles asked us to wait 2 s.');
      });
    });

    test('overrides the auto-pick when a row is tapped and cancels the in-flight download', () {
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

    test('resolves to done with no subtitle when skipped, so playback still starts', () {
      fakeAsync((a) {
        final h = Harness()..search = (_) => Completer<List<SubtitleCandidate>>().future;
        h.open(a);
        a.elapse(const Duration(milliseconds: 10));
        h.m.skip();
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.m.state.attached, isA<NoSubtitle>());
      });
    });

    test('offers the Subdl slot only when it is enabled', () {
      fakeAsync((a) {
        final h = Harness(subdl: true)..search = (_) async => const [];
        h.open(a);
        a.elapse(const Duration(milliseconds: 100));
        expect((h.m.state.event! as Stalled).next, contains(FallbackAction.subdl));
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
        expect(h.m.state.phase, LeaderPhase.done);
        expect(h.downloads, hasLength(1));
      });
    });

    test('retries a stalled search on request', () {
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
        expect(h.m.state.phase, LeaderPhase.done);
      });
    });

    test('sweeps once per second while pending', () {
      final t0 = DateTime.utc(2026, 9, 6, 15, 44);
      expect(leaderSweep(t0, t0.add(const Duration(milliseconds: 250))), 0.25);
      expect(leaderSweep(t0, t0.add(const Duration(milliseconds: 1500))), 0.5);
      expect(leaderSweep(t0, t0), 0);
    });
  });
}
