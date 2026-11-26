// The open film as one immutable value: the file, its player, where threading stands and
// everything the Auditorium shows about it. SessionNotifier (session.dart) is the only writer.
import 'package:path/path.dart' as p;

import '../engine/models/models.dart';
import '../engine/playback.dart';
import '../platform/files.dart';
import '../player/engine.dart';

class FilmSession {
  final OpenedFile file;
  final PlayerEngine engine;
  final ThreadingState threading;
  final ParsedName? parsed;
  final int? mediaId;
  final int delayMs;
  final int audioDelayMs;
  final List<Chapter> chapters;
  final String? title;
  final String? error; // "This print can't be projected.", never a code

  /// The folder's neighbours (desktop paths only), for N / P and "Up next".
  final String? previousPath, nextPath;

  /// A-B loop points; both set means looping.
  final Duration? loopA, loopB;
  final SleepTimer sleep;
  final PictureFit fit;

  /// The film has been told to play (threading finished or was skipped).
  final bool started;

  const FilmSession({
    required this.file,
    required this.engine,
    this.threading = const ThreadingState(),
    this.parsed,
    this.mediaId,
    this.delayMs = 0,
    this.audioDelayMs = 0,
    this.chapters = const [],
    this.title,
    this.error,
    this.previousPath,
    this.nextPath,
    this.loopA,
    this.loopB,
    this.sleep = SleepTimer.off,
    this.fit = PictureFit.fit,
    this.started = false,
  });

  bool get threadingVisible =>
      threading.phase != LeaderPhase.done && threading.phase != LeaderPhase.idle;

  String get displayTitle => title ?? parsed?.title ?? file.displayName;

  String? get nextName => nextPath == null ? null : p.basename(nextPath!);
  String? get previousName => previousPath == null ? null : p.basename(previousPath!);

  bool get looping => loopA != null && loopB != null;

  FilmSession copyWith({
    ThreadingState? threading,
    int? mediaId,
    int? delayMs,
    int? audioDelayMs,
    List<Chapter>? chapters,
    String? title,
    String? error,
    String? previousPath,
    String? nextPath,
    Duration? loopA,
    Duration? loopB,
    bool clearLoop = false,
    SleepTimer? sleep,
    PictureFit? fit,
    bool? started,
  }) => FilmSession(
    file: file,
    engine: engine,
    threading: threading ?? this.threading,
    parsed: parsed,
    mediaId: mediaId ?? this.mediaId,
    delayMs: delayMs ?? this.delayMs,
    audioDelayMs: audioDelayMs ?? this.audioDelayMs,
    chapters: chapters ?? this.chapters,
    title: title ?? this.title,
    error: error ?? this.error,
    previousPath: previousPath ?? this.previousPath,
    nextPath: nextPath ?? this.nextPath,
    loopA: clearLoop ? null : (loopA ?? this.loopA),
    loopB: clearLoop ? null : (loopB ?? this.loopB),
    sleep: sleep ?? this.sleep,
    fit: fit ?? this.fit,
    started: started ?? this.started,
  );
}
