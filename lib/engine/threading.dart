// The leader state machine (§6.5). Each numeral is a promise: the sweep advances only while
// the current phase is pending, and a failure FREEZES it where it stands.
//
//   idle ─open─► hashing ─► searching ─► downloading ─► flash ─► done
//                   │ FileTooSmall is silent      │ stall ⇒ fallback rows, never a reset
import 'dart:async';

import 'package:clock/clock.dart';

import 'hash.dart';
import 'models/models.dart';
import 'scoring.dart';
import 'sentences.dart';

const Duration kHashDeadline = Duration(seconds: 2);
const Duration kSearchDeadline = Duration(seconds: 8);
const Duration kDownloadDeadline = Duration(seconds: 15);
const Duration kSweepPeriod = Duration(milliseconds: 1000);
const Duration kFlash = Duration(milliseconds: 66);

/// 0..1 position of the conic sweep. Loops once per second while a phase is pending; frozen
/// at [frozenAt] when the phase stalled. Never jumps to 1, never resets to 0 on a stall.
double leaderSweep(DateTime phaseStart, DateTime now, {DateTime? frozenAt}) {
  final end = frozenAt ?? now;
  final ms = end.difference(phaseStart).inMilliseconds;
  if (ms <= 0) return 0;
  return (ms % kSweepPeriod.inMilliseconds) / kSweepPeriod.inMilliseconds;
}

class SearchRequest {
  final MovieHash? hash;
  final ParsedName? parsed;
  final String? query; // raw filename (low confidence) or the manual search text
  final List<String> languages;
  const SearchRequest({this.hash, this.parsed, this.query, required this.languages});
}

class DownloadOutcome {
  final ExternalSubtitle attached;
  final int? remaining;
  final DateTime? resetUtc;
  const DownloadOutcome({required this.attached, this.remaining, this.resetUtc});
}

/// Everything the machine touches outside itself. Every port throws [ThreadingException]
/// (never a raw exception) so failures are typed before they reach state.
class ThreadingPorts {
  final Future<MovieHash> Function() hash;

  /// Rung 0: sidecar beside the file, then the hash_cache row, then (when preferred) an
  /// embedded track in a wanted language. Costs 0 requests.
  final Future<SubtitleTrackRef?> Function(MovieHash? hash) findExisting;
  final Future<List<SubtitleCandidate>> Function(SearchRequest request) search;
  final Future<List<SubtitleCandidate>> Function(SearchRequest request)? subdl;

  /// The ONLY call that spends a ticket.
  final Future<DownloadOutcome> Function(ScoredCandidate pick, MovieHash? hash) download;

  const ThreadingPorts({
    required this.hash,
    required this.findExisting,
    required this.search,
    required this.download,
    this.subdl,
  });
}

class ThreadingConfig {
  final List<String> languages;
  final bool preferHearingImpaired;
  final bool subdlEnabled;
  final Duration hashDeadline, searchDeadline, downloadDeadline;
  const ThreadingConfig({
    this.languages = const ['en'],
    this.preferHearingImpaired = false,
    this.subdlEnabled = false,
    this.hashDeadline = kHashDeadline,
    this.searchDeadline = kSearchDeadline,
    this.downloadDeadline = kDownloadDeadline,
  });
}

/// The fallback rows, in their fixed order; `signIn` is inserted first on 401/406.
List<FallbackAction> fallbacksFor(
  ThreadingFailure f, {
  required bool subdlEnabled,
  required bool filenameSearchDone,
  required LeaderPhase at,
}) {
  final next = <FallbackAction>[
    if (f == ThreadingFailure.unauthorized ||
        f == ThreadingFailure.quotaExhausted ||
        f == ThreadingFailure.noApiKey)
      FallbackAction.signIn,
    if (f == ThreadingFailure.timeout ||
        f == ThreadingFailure.rateLimited ||
        f == ThreadingFailure.offline ||
        (at == LeaderPhase.downloading && f == ThreadingFailure.linkExpired))
      FallbackAction.retry,
    if (!filenameSearchDone && at == LeaderPhase.searching) FallbackAction.filenameSearch,
    if (subdlEnabled) FallbackAction.subdl,
    FallbackAction.manualSearch,
    FallbackAction.skip,
  ];
  return next;
}

class ThreadingMachine {
  final ThreadingPorts ports;
  final ThreadingConfig config;
  final void Function(ThreadingState state) onChange;

  ThreadingState _state;
  int _generation = 0;
  bool _filenameSearchDone = false;
  String _displayName = '';
  double? _containerFps;
  Completer<void>? _done;

  ThreadingMachine({
    required this.ports,
    required this.onChange,
    this.config = const ThreadingConfig(),
    Quota quota = Quota.anonymous,
  }) : _state = ThreadingState(quota: quota);

  ThreadingState get state => _state;

  /// Completes when the machine reaches `done` (attached, skipped or cancelled).
  Future<void> get finished => (_done ??= Completer<void>()).future;

  void _emit(ThreadingState s) {
    _state = s;
    onChange(s);
    if (s.phase == LeaderPhase.done && !(_done?.isCompleted ?? false)) {
      (_done ??= Completer<void>()).complete();
    }
  }

  void _enter(LeaderPhase phase, {ThreadingState? from}) =>
      _emit((from ?? _state).copyWith(phase: phase, phaseStartedAt: clock.now(), clearEvent: true));

  void _stall(ThreadingFailure f, {int? retryAfterSeconds}) {
    if (_state.phase == LeaderPhase.done) return;
    _emit(
      _state.copyWith(
        event: Stalled(
          at: _state.phase,
          failure: f,
          next: fallbacksFor(
            f,
            subdlEnabled: config.subdlEnabled && ports.subdl != null,
            filenameSearchDone: _filenameSearchDone,
            at: _state.phase,
          ),
          sentence: sentenceFor(f, retryAfterSeconds: retryAfterSeconds),
          stalledAt: clock.now(),
        ),
      ),
    );
  }

  /// Feeds mpv's `container-fps` once the player knows it; re-ranks the list in place.
  void setContainerFps(double? fps) {
    _containerFps = fps;
    if (_state.candidates.isEmpty) return;
    _emit(_state.copyWith(candidates: _rank(_state.candidates.map((c) => c.candidate))));
  }

  void setQuota(Quota q) => _emit(_state.copyWith(quota: q));

  List<ScoredCandidate> _rank(Iterable<SubtitleCandidate> cs) => rankCandidates(
    cs,
    parsed: _state.parsed,
    containerFps: _containerFps,
    preferHI: config.preferHearingImpaired,
    languages: config.languages,
  );

  /// Every port error reaches state typed: a raw exception (a bad zip, malformed JSON, a disk
  /// error) is read as a timeout so the numeral stalls with a retry instead of hanging.
  Future<T> _guard<T>(Future<T> Function() f, Duration deadline) async {
    try {
      return await f().timeout(deadline);
    } on ThreadingException {
      rethrow;
    } on TimeoutException {
      throw const ThreadingException(ThreadingFailure.timeout);
    } on Object {
      throw const ThreadingException(ThreadingFailure.timeout);
    }
  }

  /// idle ─open(file)─► hashing. Libmpv opens the file concurrently with these phases.
  Future<void> open({
    required String displayName,
    required int sizeBytes,
    ParsedName? parsed,
    double? containerFps,
  }) async {
    final gen = ++_generation;
    _filenameSearchDone = false;
    _displayName = displayName;
    _containerFps = containerFps;
    _done = Completer<void>();
    _enter(
      LeaderPhase.hashing,
      from: ThreadingState(quota: _state.quota, sizeBytes: sizeBytes, parsed: parsed),
    );

    // ── "3": read the print ──
    MovieHash? hash;
    try {
      hash = await ports.hash().timeout(config.hashDeadline);
    } on FileTooSmall {
      hash = null; // SILENT: "3" completes normally, "2" starts with a filename query
    } on HashUnavailable {
      hash = null; // the file vanished mid-read: skip to filename search, no stall
    } on Object {
      hash = null; // a slow disk (or any read error) is not worth a stall — the name still works
    }
    if (gen != _generation) return;
    if (hash != null) _emit(_state.copyWith(hash: hash));

    // ── rung 0: sidecar, then hash_cache — 0 requests, 0 tickets ──
    try {
      final existing = await ports.findExisting(hash);
      if (gen != _generation) return;
      if (existing != null) {
        await _finish(gen, existing);
        return;
      }
    } on Object {
      // A broken cache row is not a stall — carry on to the network.
      if (gen != _generation) return;
    }

    await _searchAndPick(gen, hash == null ? _nameRequest() : _hashRequest(hash));
  }

  SearchRequest _hashRequest(MovieHash hash) =>
      SearchRequest(hash: hash, parsed: _state.parsed, languages: config.languages);

  SearchRequest _nameRequest() {
    final p = _state.parsed;
    final low = p == null || p.confidence == NameConfidence.low;
    return SearchRequest(
      parsed: low ? null : p,
      query: low ? (p?.raw ?? _displayName) : null,
      languages: config.languages,
    );
  }

  Future<void> _searchAndPick(int gen, SearchRequest req, {bool subdl = false}) async {
    final byName = req.hash == null;
    if (byName && !subdl) _filenameSearchDone = true;
    _enter(LeaderPhase.searching);
    List<SubtitleCandidate> found;
    try {
      final port = subdl ? ports.subdl : ports.search;
      if (port == null) throw const ThreadingException(ThreadingFailure.noResults);
      found = await _guard(() => port(req), config.searchDeadline);
    } on ThreadingException catch (e) {
      if (gen != _generation) return;
      _stall(e.failure, retryAfterSeconds: e.retryAfterSeconds);
      return;
    }
    if (gen != _generation) return;

    // Keep earlier rows (a Subdl or manual search appends to what was already listed).
    final merged = _mergeUnique(found, _state.candidates.map((s) => s.candidate));
    final ranked = _rank(merged);
    _emit(_state.copyWith(candidates: ranked));

    final hashHit = ranked.isNotEmpty && ranked.first.candidate.moviehashMatch;
    if (!byName && !hashHit) {
      // No exact print. Search by name now (free — search is unlimited) so the rows are
      // already there when the numeral stalls; never spend a ticket on a guess without a tap.
      _filenameSearchDone = true;
      try {
        final named = await _guard(() => ports.search(_nameRequest()), config.searchDeadline);
        if (gen != _generation) return;
        _emit(_state.copyWith(candidates: _rank(_mergeUnique(merged, named))));
      } on ThreadingException {
        if (gen != _generation) return;
      }
      _stall(ThreadingFailure.noResults);
      return;
    }

    final pick = autoPickOf(ranked);
    if (pick == null) {
      _stall(ThreadingFailure.noResults);
      return;
    }
    await _download(gen, pick);
  }

  /// [first] in order, then every row of [rest] not already listed (same provider and id).
  static List<SubtitleCandidate> _mergeUnique(
    Iterable<SubtitleCandidate> first,
    Iterable<SubtitleCandidate> rest,
  ) {
    final out = <SubtitleCandidate>[];
    final seen = <String>{};
    for (final c in [...first, ...rest]) {
      if (seen.add('${c.provider.name}|${c.id}')) out.add(c);
    }
    return out;
  }

  Future<void> _download(int gen, ScoredCandidate pick, {bool isRetry = false}) async {
    if (_state.quota.state == TicketState.exhausted) {
      // Refuse to spend a ticket we do not have: NO request is made.
      _emit(_state.copyWith(picked: pick));
      _stall(ThreadingFailure.quotaExhausted);
      return;
    }
    _enter(LeaderPhase.downloading, from: _state.copyWith(picked: pick));
    try {
      final out = await _guard(() => ports.download(pick, _state.hash), config.downloadDeadline);
      if (gen != _generation) return;
      var q = _state.quota;
      if (out.remaining != null) {
        q = q.copyWith(remaining: out.remaining, resetUtc: out.resetUtc);
      }
      _emit(_state.copyWith(quota: q));
      await _finish(gen, out.attached);
    } on ThreadingException catch (e) {
      if (gen != _generation) return;
      if (e.failure == ThreadingFailure.linkExpired && !isRetry) {
        // The ONE automatic retry in the whole machine: a fresh link for an expired one.
        _emit(_state.copyWith(event: Notice(sentenceFor(ThreadingFailure.linkExpired))));
        await _download(gen, pick, isRetry: true);
        return;
      }
      if (e.failure == ThreadingFailure.quotaExhausted) {
        _emit(_state.copyWith(quota: _state.quota.copyWith(remaining: 0)));
      }
      _stall(e.failure, retryAfterSeconds: e.retryAfterSeconds);
    }
  }

  Future<void> _finish(int gen, SubtitleTrackRef attached) async {
    _enter(LeaderPhase.flash, from: _state.copyWith(attached: attached));
    await Future<void>.delayed(kFlash);
    if (gen != _generation) return;
    _enter(LeaderPhase.done);
  }

  // ───────────────────────────── human actions ─────────────────────────────

  /// Tapping any row overrides the auto-pick and cancels an in-flight download.
  Future<void> pick(ScoredCandidate c) async {
    final gen = ++_generation;
    await _download(gen, c);
  }

  Future<void> filenameSearch() async {
    final gen = ++_generation;
    await _searchAndPick(gen, _nameRequest());
  }

  Future<void> manualSearch(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final gen = ++_generation;
    await _searchAndPick(gen, SearchRequest(query: q, languages: config.languages));
  }

  Future<void> subdlSearch() async {
    final gen = ++_generation;
    await _searchAndPick(gen, _nameRequest(), subdl: true);
  }

  /// Re-runs the stalled phase (after a 429 wait, a timeout, reconnecting, or signing in).
  Future<void> retry() async {
    final ev = _state.event;
    final gen = ++_generation;
    if (ev is Stalled && ev.at == LeaderPhase.downloading && _state.picked != null) {
      await _download(gen, _state.picked!);
      return;
    }
    final h = _state.hash;
    await _searchAndPick(gen, h == null ? _nameRequest() : _hashRequest(h));
  }

  /// "Skip subtitles" / predictive back / Esc: resolves to done — playback still starts.
  void skip() {
    ++_generation;
    _emit(
      _state.copyWith(
        phase: LeaderPhase.done,
        phaseStartedAt: clock.now(),
        attached: const NoSubtitle(),
        clearEvent: true,
      ),
    );
  }

  void dispose() => ++_generation;
}
