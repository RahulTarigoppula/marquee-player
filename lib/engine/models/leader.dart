import 'media.dart';
import 'quota.dart';
import 'subtitles.dart';

enum LeaderPhase { idle, hashing, searching, downloading, flash, done }

enum ThreadingFailure {
  fileTooSmall, // < 128 KiB — NOT an error: skip the hash, go straight to filename search
  offline,
  timeout,
  noResults,
  unauthorized, // 401
  quotaExhausted, // 406
  rateLimited, // 429
  linkExpired, // 410
  writeFailed,
  decodeFailed,
  cancelled,
  noApiKey, // this build has no OpenSubtitles consumer key and the user has not added one
}

enum FallbackAction { signIn, retry, filenameSearch, subdl, manualSearch, skip }

/// Thrown by every port the threading machine calls. `lib/api` maps HTTP statuses to one of
/// these BEFORE anything reaches state — no raw exception crosses a provider boundary.
class ThreadingException implements Exception {
  final ThreadingFailure failure;
  final int? retryAfterSeconds;
  const ThreadingException(this.failure, {this.retryAfterSeconds});
  @override
  String toString() => 'ThreadingException($failure)';
}

sealed class LeaderEvent {
  const LeaderEvent();
}

class Stalled extends LeaderEvent {
  final LeaderPhase at;
  final ThreadingFailure failure;
  final List<FallbackAction> next;
  final String sentence;
  final DateTime stalledAt;
  const Stalled({
    required this.at,
    required this.failure,
    required this.next,
    required this.sentence,
    required this.stalledAt,
  });
}

/// A transient notice that does not stop the leader (e.g. "That print expired — fetching a
/// fresh link" while the single 410 retry runs).
class Notice extends LeaderEvent {
  final String sentence;
  const Notice(this.sentence);
}

class ThreadingState {
  final LeaderPhase phase;
  final DateTime? phaseStartedAt;
  final MovieHash? hash;
  final int? sizeBytes;
  final ParsedName? parsed;
  final List<ScoredCandidate> candidates;
  final ScoredCandidate? picked;
  final SubtitleTrackRef attached;
  final Quota quota;
  final LeaderEvent? event; // Stalled ⇒ the sweep is FROZEN at stalledAt

  const ThreadingState({
    this.phase = LeaderPhase.idle,
    this.phaseStartedAt,
    this.hash,
    this.sizeBytes,
    this.parsed,
    this.candidates = const [],
    this.picked,
    this.attached = const NoSubtitle(),
    this.quota = Quota.anonymous,
    this.event,
  });

  bool get stalled => event is Stalled;

  /// The numeral on the leader: 3 while hashing, 2 while searching, 1 while downloading.
  int? get numeral => switch (phase) {
    LeaderPhase.hashing => 3,
    LeaderPhase.searching => 2,
    LeaderPhase.downloading => 1,
    _ => null,
  };

  ThreadingState copyWith({
    LeaderPhase? phase,
    DateTime? phaseStartedAt,
    MovieHash? hash,
    int? sizeBytes,
    ParsedName? parsed,
    List<ScoredCandidate>? candidates,
    ScoredCandidate? picked,
    SubtitleTrackRef? attached,
    Quota? quota,
    LeaderEvent? event,
    bool clearEvent = false,
    bool clearPicked = false,
  }) => ThreadingState(
    phase: phase ?? this.phase,
    phaseStartedAt: phaseStartedAt ?? this.phaseStartedAt,
    hash: hash ?? this.hash,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    parsed: parsed ?? this.parsed,
    candidates: candidates ?? this.candidates,
    picked: clearPicked ? null : (picked ?? this.picked),
    attached: attached ?? this.attached,
    quota: quota ?? this.quota,
    event: clearEvent ? null : (event ?? this.event),
  );
}
