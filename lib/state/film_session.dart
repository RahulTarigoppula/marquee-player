// The open film as one immutable value: the file, its player, where threading stands and
// everything the Auditorium shows about it. SessionNotifier (session.dart) is the only writer.
import 'package:path/path.dart' as p;

import '../engine/models/models.dart';
import '../engine/picture.dart';
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

  /// The folder's neighbours, for N / P and "Up next": files beside this one on desktop, the
  /// device library's order for a phone's content:// film.
  final String? previousPath, nextPath;

  /// The folder's first film, for "Repeat the folder" (null when this IS the first, or the
  /// only one).
  final String? firstPath;

  /// A-B loop points; both set means looping.
  final Duration? loopA, loopB;
  final SleepTimer sleep;
  final PictureFit fit;

  /// Levels, rotation, zoom and deinterlacing: remembered per film.
  final PictureAdjust picture;

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
    this.firstPath,
    this.loopA,
    this.loopB,
    this.sleep = SleepTimer.off,
    this.fit = PictureFit.fit,
    this.picture = PictureAdjust.neutral,
    this.started = false,
  });

  /// The leader covers the picture: only BEFORE the film starts. A search or a pick made
  /// from the Booth mid-film shows in the Booth, never over the playing picture.
  bool get threadingVisible =>
      !started && threading.phase != LeaderPhase.done && threading.phase != LeaderPhase.idle;

  /// A subtitle search or download is running right now (for the Booth's status line).
  bool get subtitlesBusy =>
      !threading.stalled &&
      (threading.phase == LeaderPhase.hashing ||
          threading.phase == LeaderPhase.searching ||
          threading.phase == LeaderPhase.downloading);

  String get displayTitle => title ?? parsed?.title ?? file.displayName;

  String? get nextName => nextPath == null ? null : p.basename(nextPath!);
  String? get previousName => previousPath == null ? null : p.basename(previousPath!);

  bool get looping => loopA != null && loopB != null;

  /// What the end of this film does under [s] (see [endAction]).
  EndAction endActionFor(Settings s) => endAction(
    repeat: s.repeat,
    autoplayNext: s.autoplayNext,
    hasNext: nextPath != null,
    hasFirst: firstPath != null,
    sleepAtEnd: sleep == SleepTimer.endOfFilm,
  );

  /// The film the "Up next" card counts down to, if the end of this one starts another.
  String? upNextFor(Settings s) => switch (endActionFor(s)) {
    EndAction.next => nextPath,
    EndAction.wrap => firstPath,
    _ => null,
  };

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
    String? firstPath,
    Duration? loopA,
    Duration? loopB,
    bool clearLoop = false,
    SleepTimer? sleep,
    PictureFit? fit,
    PictureAdjust? picture,
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
    firstPath: firstPath ?? this.firstPath,
    loopA: clearLoop ? null : (loopA ?? this.loopA),
    loopB: clearLoop ? null : (loopB ?? this.loopB),
    sleep: sleep ?? this.sleep,
    fit: fit ?? this.fit,
    picture: picture ?? this.picture,
    started: started ?? this.started,
  );
}
