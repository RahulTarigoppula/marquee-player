// The open film: one PlayerEngine + one ThreadingMachine, wired to the cache, the sidecar
// writer and the API. The Auditorium appears the moment a film is chosen; libmpv opens the
// file (PAUSED, at the resume point) while the leader counts, and the film starts when
// threading is done, skipped, or falls back to "no subtitles".
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../engine/filename.dart';
import '../engine/hash.dart';
import '../engine/models/models.dart';
import '../engine/playback.dart';
import '../engine/threading.dart';
import '../platform/files.dart';
import '../platform/pip.dart';
import '../player/engine.dart';
import 'film_session.dart';
import 'notice.dart';
import 'providers.dart';
import 'subtitle_ports.dart';
import 'thumbnails.dart';

export 'film_session.dart';

const Duration kResumeSaveEvery = Duration(seconds: 5);
const Duration kUndecodableAfter = Duration(seconds: 5);

/// The volume is written to Settings this long after the last change (a wheel spin is one
/// write, not forty).
const Duration kVolumeSaveAfter = Duration(milliseconds: 800);

/// The Lobby frame is grabbed this far in (or at 10 % of a shorter film), and again on close.
const Duration kThumbnailAt = Duration(minutes: 2, seconds: 30);

class SessionNotifier extends Notifier<FilmSession?> {
  ThreadingMachine? _machine;
  Timer? _resumeTimer;
  Timer? _undecodable;
  Timer? _thumbTimer;
  Timer? _sleepTimer;
  Timer? _volumeSave;
  StreamSubscription<bool>? _completedSub;
  bool _attachedOnce = false;

  /// open() is serialised: each call waits for the previous one, and a call superseded while
  /// waiting does nothing (two quick drops play the second file, once).
  int _openSeq = 0;
  int _opening = 0;
  Future<void> _tail = Future.value();

  /// The resume key: the moviehash, or [urlResumeKey] for a stream.
  MovieHash? _resumeKey;
  Duration? _resumeAt;
  ({MovieHash key, int positionMs})? _lastSaved;
  bool _pausedForOffice = false;
  Completer<int>? _mediaIdReady;

  @override
  FilmSession? build() {
    // The machine holds its own quota; keep it current (sign-in, restore, sign-out) or a pick
    // after signing in is refused as "no tickets" without a request.
    ref.listen(quotaProvider, (_, q) => _machine?.setQuota(q));
    // Subtitle look and size apply to the open film the moment they change in Settings, and
    // ONLY then: a volume save or a theme change sends mpv nothing.
    ref.listen(settingsValueProvider.select((s) => s.subtitleStyle), (_, _) {
      final engine = state?.engine;
      if (engine != null) unawaited(engine.applySubtitleStyle(ref.read(settingsValueProvider)));
    });
    // The Ticket Office is a room of its own: the film waits for you there.
    ref.listen(roomProvider, (prev, room) {
      final engine = state?.engine;
      if (engine == null || engine.isDisposed) return;
      if (room == Room.ticketOffice && engine.player.state.playing) {
        _pausedForOffice = true;
        unawaited(engine.pause());
      } else if (room == Room.auditorium && _pausedForOffice) {
        _pausedForOffice = false;
        unawaited(engine.play());
      }
    });
    ref.read(pipProvider.notifier)
      ..onPlayPause = (() => unawaited(state?.engine.playOrPause()))
      ..onDismissed = pauseUnseen;
    ref.onDispose(() {
      _cancelTimers();
      _machine?.dispose();
    });
    return null;
  }

  ThreadingMachine? get machine => _machine;

  /// True while a film is being opened (the Auditorium may be empty for a moment then).
  bool get isOpening => _opening > 0;

  bool _isCurrent(PlayerEngine engine) => state?.engine == engine && !engine.isDisposed;

  void _cancelTimers() {
    _resumeTimer?.cancel();
    _undecodable?.cancel();
    _thumbTimer?.cancel();
    _sleepTimer?.cancel();
    unawaited(_completedSub?.cancel());
    _completedSub = null;
  }

  // ───────────────────────────── opening ─────────────────────────────

  /// THE entry point: a picked, dropped, forwarded or "Open URL…" film.
  Future<void> open(OpenedFile file) {
    final seq = ++_openSeq;
    _opening++;
    final run = _tail.then((_) async {
      if (seq != _openSeq) return;
      await _open(file, seq);
    });
    _tail = run.catchError((Object _) {});
    return run.whenComplete(() => _opening--);
  }

  /// A Lobby card, a command-line argument or an "Open with" URI. A film that has moved or
  /// been deleted (or whose Android grant was revoked) says so, with a way to drop the card.
  Future<void> openLocator(String locator) async {
    final f = await fileFromPath(locator);
    if (f == null) {
      await _missing(locator);
      return;
    }
    await open(f);
  }

  Future<void> _missing(String locator) async {
    final actions = ref.read(libraryActionsProvider);
    final known = await ref.read(databaseProvider).mediaIdFor(locator) != null;
    ref
        .read(noticeProvider.notifier)
        .show(
          'That file has moved or been deleted.',
          actionLabel: known ? 'Remove' : null,
          onAction: known ? () => unawaited(actions.removeLocator(locator)) : null,
          duration: const Duration(seconds: 8),
        );
  }

  /// A film replaced by one that could not open leaves no empty Auditorium behind.
  void _lobbyIfEmpty(int seq) {
    if (seq != _openSeq || state != null) return; // a newer open owns the room
    if (ref.read(roomProvider) == Room.auditorium) {
      ref.read(fullscreenProvider.notifier).set(false);
      ref.read(roomProvider.notifier).go(Room.lobby);
    }
  }

  Future<void> _open(OpenedFile file, int seq) async {
    if (state != null) await close(toLobby: false);
    PlayerEngine? engine;
    try {
      if (seq != _openSeq) return;
      final settings = await ref.read(settingsProvider.future);
      if (seq != _openSeq) return;
      if (!file.isRemote && !file.isContentUri && !await File(file.locator).exists()) {
        await _missing(file.locator);
        return;
      }
      final parsed = file.isRemote || file.isContentUri
          ? parseName(file.displayName)
          : parsePath(file.locator);
      // The hash (two 64 KiB reads) overlaps the player's start-up; the threading machine
      // reuses the same future, so the file is read once.
      final hashing = file.isRemote ? null : _hashOf(file);
      final e = engine = PlayerEngine(hwdec: settings.hwdec);
      _attachedOnce = false;
      _pausedForOffice = false;
      _resumeKey = null;
      _resumeAt = null;
      _mediaIdReady = Completer<int>();
      // The room changes NOW: the player configures behind the house lights.
      state = FilmSession(file: file, engine: e, parsed: parsed);
      ref.read(roomProvider.notifier).go(Room.auditorium);
      _watchCompletion(e);
      await e.configure(settings);
      if (!_isCurrent(e)) return;
      if (hashing == null) {
        await _openStream(file, e, settings, parsed);
      } else {
        await _openLocal(file, e, settings, parsed, hashing);
      }
    } on Object {
      final e = engine;
      if (e != null && _isCurrent(e)) {
        _fail(e);
      } else if (e != null) {
        unawaited(e.dispose());
      }
    } finally {
      _lobbyIfEmpty(seq);
    }
  }

  /// Starts reading the moviehash. Its failure is the threading machine's to report (a slow
  /// disk or a read error just means "search by name"), never an uncaught error.
  Future<MovieHash> _hashOf(OpenedFile file) {
    final hashing = chunkReaderFor(file).then((read) => movieHashOf(read, file.sizeBytes));
    unawaited(hashing.then((_) {}, onError: (Object _) {}));
    return hashing;
  }

  Future<void> _openLocal(
    OpenedFile file,
    PlayerEngine engine,
    Settings settings,
    ParsedName? parsed,
    Future<MovieHash> hashing,
  ) async {
    // Reading the hash first lets libmpv open AT the resume point (a seek after load is racy).
    MovieHash? hash;
    try {
      hash = await hashing.timeout(kHashDeadline);
    } on Object {
      hash = null;
    }
    if (!_isCurrent(engine)) return;
    if (hash != null) await _loadResume(hash);
    if (!_isCurrent(engine)) return;
    unawaited(_startPlayback(engine, file, start: _resumeAt));
    final machine = _machineFor(file, settings, engine, () => hashing);
    _machine = machine;
    await machine.open(displayName: file.displayName, sizeBytes: file.sizeBytes, parsed: parsed);
    unawaited(ref.read(databaseProvider).sweepArtwork());
  }

  /// A stream: no hash, no sidecar, no automatic search (manual search from the Booth still
  /// works). It resumes by URL and plays at once.
  Future<void> _openStream(
    OpenedFile file,
    PlayerEngine engine,
    Settings settings,
    ParsedName? parsed,
  ) async {
    final key = urlResumeKey(file.locator);
    final db = ref.read(databaseProvider);
    final id = await db.upsertMedia(
      locator: file.locator,
      displayName: file.displayName,
      sizeBytes: 0,
      hash: key,
      origin: 'remote',
      title: parsed?.confidence == NameConfidence.low ? null : parsed?.title,
      year: parsed?.year,
    );
    if (!_isCurrent(engine)) return;
    _mediaIdReady?.complete(id);
    final delay = await db.offsetFor(key);
    state = state?.copyWith(mediaId: id, delayMs: delay);
    await _loadResume(key);
    if (!_isCurrent(engine)) return;
    _machine = _machineFor(file, settings, engine, () => throw const HashUnavailable('a stream'));
    _attachedOnce = true; // nothing automatic to attach; a manual pick resets this
    await _startPlayback(engine, file, start: _resumeAt);
    if (delay != 0) await engine.setSubDelayMs(delay);
    await _begin(engine);
  }

  ThreadingMachine _machineFor(
    OpenedFile file,
    Settings settings,
    PlayerEngine engine,
    Future<MovieHash> Function() hash,
  ) => ThreadingMachine(
    ports: SubtitlePorts(
      ref: ref,
      file: file,
      settings: settings,
      engine: engine,
      onHashKnown: (h) => _recordMedia(file, engine, h),
      onFeatureTitle: (title, year) => _retitle(engine, title, year),
    ).build(hash),
    config: ThreadingConfig(
      languages: settings.languages,
      preferHearingImpaired: settings.preferHearingImpaired,
      subdlEnabled: settings.subdlEnabled,
    ),
    quota: ref.read(quotaProvider),
    onChange: (t) => _onThreading(engine, t),
  );

  /// The one resume rule ([ResumePoint.resumable]), the same one the Lobby shows.
  Future<void> _loadResume(MovieHash key) async {
    _resumeKey = key;
    final rp = await ref.read(databaseProvider).resumeFor(key);
    if (rp != null && rp.resumable) _resumeAt = Duration(milliseconds: rp.positionMs);
  }

  Future<void> _startPlayback(PlayerEngine engine, OpenedFile file, {Duration? start}) async {
    try {
      await engine.open(file.locator, start: start);
    } on Object {
      _fail(engine);
      return;
    }
    // Closed or replaced while libmpv was opening: the timers belong to the next film.
    if (!_isCurrent(engine)) return;
    if (state?.started ?? false) await engine.play(); // threading finished before the open did
    _undecodable?.cancel();
    _undecodable = Timer(kUndecodableAfter, () {
      if (!_isCurrent(engine)) return;
      // Nothing ever played: no length, no movement, and mpv said why. A live stream has no
      // length either, but it moves, so a recoverable network error never ends it.
      final s = engine.snapshot;
      final stuck = !s.playing && s.position == Duration.zero && s.duration == Duration.zero;
      if (stuck && s.error != null) _fail(engine);
    });
    _resumeTimer?.cancel();
    _resumeTimer = Timer.periodic(kResumeSaveEvery, (_) => unawaited(_saveResume()));
    unawaited(_afterLoad(engine, file));
  }

  /// container-fps, chapters, the probe for the Lobby card and the folder's neighbours only
  /// exist once the file has loaded.
  Future<void> _afterLoad(PlayerEngine engine, OpenedFile file) async {
    if (!await engine.whenLoaded() || !_isCurrent(engine)) return;
    final fps = await engine.containerFps();
    if (!_isCurrent(engine)) return;
    _machine?.setContainerFps(fps);
    final chapters = await engine.chapters();
    final near = PlayerEngine.isDesktop ? await siblingsOf(file) : (previous: null, next: null);
    if (!_isCurrent(engine)) return;
    state = state?.copyWith(chapters: chapters, previousPath: near.previous, nextPath: near.next);
    final dur = engine.player.state.duration;
    final thumbAt = dur < kThumbnailAt * 2 ? dur * 0.1 : kThumbnailAt;
    _thumbTimer?.cancel();
    if (!file.isRemote) {
      _thumbTimer = Timer(thumbAt, () {
        final cur = state;
        if (cur != null && cur.engine == engine) unawaited(_grabThumbnail(cur));
      });
    }
    try {
      final id = await _mediaIdReady!.future.timeout(const Duration(seconds: 20));
      final probe = await engine.probe();
      if (!_isCurrent(engine)) return;
      await ref
          .read(databaseProvider)
          .updateProbe(
            id,
            durationMs: dur.inMilliseconds,
            fps: fps,
            container: probe.container,
            width: probe.width,
            height: probe.height,
          );
    } on Object {
      // No media row (the hash and the name both failed): nothing to annotate.
    }
  }

  /// The Lobby frame. mpv encodes and writes it on its own thread (an async command).
  Future<void> _grabThumbnail(FilmSession s) async {
    final id = s.mediaId;
    if (id == null || s.engine.isDisposed || s.file.isRemote) return;
    if (s.engine.player.state.position < const Duration(seconds: 5)) return;
    final target = await thumbnailTarget(ref, id);
    if (await s.engine.screenshotTo(target)) await thumbnailWritten(ref, id);
  }

  void _watchCompletion(PlayerEngine engine) {
    unawaited(_completedSub?.cancel());
    _completedSub = engine.player.stream.completed.listen((done) {
      if (!done || !_isCurrent(engine)) return;
      unawaited(_saveResume());
      // "End of this film" stays set: it is what holds back "Up next" (the Auditorium reads it).
      if (state?.sleep == SleepTimer.endOfFilm) {
        ref.read(noticeProvider.notifier).show('Sleep timer: the film has ended. Good night.');
      }
    });
  }

  void _fail(PlayerEngine engine) {
    final cur = state;
    if (cur == null || cur.engine != engine) return;
    _machine?.skip();
    state = cur.copyWith(error: "This print can't be projected.");
  }

  Future<void> _recordMedia(OpenedFile file, PlayerEngine engine, MovieHash? hash) async {
    final db = ref.read(databaseProvider);
    final parsed = state?.parsed;
    final id = await db.upsertMedia(
      locator: file.locator,
      displayName: file.displayName,
      sizeBytes: file.sizeBytes,
      hash: hash,
      origin: file.isContentUri ? 'contentUri' : 'localPath',
      title: parsed?.confidence == NameConfidence.low ? null : parsed?.title,
      year: parsed?.year,
    );
    final delay = hash == null ? 0 : await db.offsetFor(hash);
    if (!_isCurrent(engine)) return;
    if (!(_mediaIdReady?.isCompleted ?? true)) _mediaIdReady!.complete(id);
    state = state!.copyWith(mediaId: id, delayMs: delay);
    if (delay != 0) await engine.setSubDelayMs(delay);
  }

  /// A download that lands after its film was closed must not retitle the next one.
  Future<void> _retitle(PlayerEngine engine, String title, int? year) async {
    final id = state?.mediaId;
    if (!_isCurrent(engine) || id == null) return;
    await ref.read(databaseProvider).setTitle(id, title, year);
    final now = state;
    if (now != null && now.engine == engine) state = now.copyWith(title: title);
  }

  void _onThreading(PlayerEngine engine, ThreadingState t) {
    final cur = state;
    if (cur == null || cur.engine != engine) return;
    state = cur.copyWith(threading: t);
    if (t.phase != LeaderPhase.done) return;
    if (!_attachedOnce) {
      _attachedOnce = true;
      unawaited(_attach(engine, t.attached));
    }
    if (!cur.started) unawaited(_begin(engine));
  }

  Future<void> _attach(PlayerEngine engine, SubtitleTrackRef a) async {
    try {
      switch (a) {
        case ExternalSubtitle():
          await engine.attachSubtitle(a.path, language: a.language);
        case EmbeddedSubtitle():
          if (await engine.whenLoaded()) await engine.selectSubtitle(a.mpvTrackId);
        case NoSubtitle():
          break;
      }
      final now = state;
      final delay = now != null && now.engine == engine ? now.delayMs : 0;
      if (delay != 0) await engine.setSubDelayMs(delay);
    } on Object {
      // The film was closed while the subtitle was being attached.
    }
  }

  /// House lights fully down: the film starts, at the resume point, which a notice offers
  /// to undo.
  Future<void> _begin(PlayerEngine engine) async {
    final cur = state;
    if (cur == null || cur.engine != engine || cur.started) return;
    state = cur.copyWith(started: true);
    await engine.play();
    final at = _resumeAt;
    if (at != null && _isCurrent(engine)) {
      ref
          .read(noticeProvider.notifier)
          .show(
            'Resumed at ${shortClock(at)}',
            actionLabel: 'Start over',
            onAction: () {
              if (_isCurrent(engine)) unawaited(engine.seekTo(Duration.zero));
            },
            duration: const Duration(seconds: 6),
          );
    }
  }

  // ───────────────────────────── controls ─────────────────────────────

  Future<void> setDelay(int ms) async {
    final cur = state;
    if (cur == null) return;
    state = cur.copyWith(delayMs: ms);
    await cur.engine.setSubDelayMs(ms);
    final h = cur.threading.hash ?? _resumeKey;
    if (h != null) await ref.read(databaseProvider).saveOffset(h, ms);
  }

  Future<void> setAudioDelay(int ms) async {
    final cur = state;
    if (cur == null) return;
    final v = ms.clamp(-5000, 5000);
    state = cur.copyWith(audioDelayMs: v);
    await cur.engine.setAudioDelayMs(v);
  }

  /// The volume slider, wheel, keys and swipes. Remembered for the next film, once the hand
  /// is still ([kVolumeSaveAfter]).
  Future<void> setVolume(double v) async {
    final engine = state?.engine;
    if (engine == null) return;
    final value = v.clamp(0, Settings.maxVolume).toDouble();
    await engine.setVolume(value);
    _volumeSave?.cancel();
    _volumeSave = Timer(kVolumeSaveAfter, () => unawaited(_persistVolume(value)));
  }

  Future<void> _persistVolume(double v) async {
    final s = ref.read(settingsProvider).value;
    if (s == null || s.volume == v) return;
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(volume: v));
  }

  /// The PiP window was closed, or the app went to the background without one: pause, so
  /// nothing plays unseen. Resume is the user's call.
  void pauseUnseen() {
    final engine = state?.engine;
    if (engine == null || engine.isDisposed || !engine.player.state.playing) return;
    unawaited(engine.pause());
    unawaited(_saveResume());
  }

  Future<void> pick(ScoredCandidate c) async {
    _attachedOnce = false;
    await _machine?.pick(c);
  }

  Future<void> findAnother(String query) async {
    _attachedOnce = false;
    final m = _machine;
    final cur = state;
    if (m == null || cur == null) return;
    if (query.trim().isNotEmpty) {
      await m.manualSearch(query);
    } else if (cur.file.isRemote) {
      await m.manualSearch(cur.parsed?.title ?? cur.file.displayName);
    } else {
      await m.filenameSearch();
    }
  }

  void skipSubtitles() => _machine?.skip();

  /// "Load subtitle file…" or a subtitle dropped on the picture.
  Future<void> loadSubtitleFile(String path) async {
    final engine = state?.engine;
    if (engine == null) return;
    await engine.attachSubtitle(path, title: p.basename(path));
    ref.read(noticeProvider.notifier).show('Subtitles loaded: ${p.basename(path)}');
  }

  /// "Load subtitle file…": the picker, then the file. On Android the picker is our own
  /// activity, so it must not count as going Home (which would shrink the film into PiP).
  Future<void> pickAndLoadSubtitle() async {
    final path = await ref.read(pipProvider.notifier).withoutAutoEnter(pickSubtitleFile);
    if (path != null) await loadSubtitleFile(path);
  }

  /// L: set A, then B (the loop starts), then clear.
  Future<void> toggleLoop() async {
    final cur = state;
    if (cur == null) return;
    final pos = cur.engine.player.state.position;
    final notice = ref.read(noticeProvider.notifier);
    if (cur.loopA == null) {
      state = cur.copyWith(loopA: pos);
      await cur.engine.setLoop(pos, null);
      notice.show('Loop start set at ${shortClock(pos)}. Press L again for the end.');
    } else if (cur.loopB == null) {
      final a = pos < cur.loopA! ? pos : cur.loopA!;
      final b = pos < cur.loopA! ? cur.loopA! : pos;
      if (b - a < const Duration(milliseconds: 500)) return;
      state = cur.copyWith(loopA: a, loopB: b);
      await cur.engine.setLoop(a, b);
      notice.show('Looping ${shortClock(a)} to ${shortClock(b)}');
    } else {
      state = cur.copyWith(clearLoop: true);
      await cur.engine.setLoop(null, null);
      notice.show('Loop off');
    }
  }

  void setFit(PictureFit fit) {
    final cur = state;
    if (cur != null) state = cur.copyWith(fit: fit);
  }

  void setSleep(SleepTimer t) {
    final cur = state;
    if (cur == null) return;
    _sleepTimer?.cancel();
    state = cur.copyWith(sleep: t);
    final after = t.after;
    if (after != null) {
      final engine = cur.engine;
      _sleepTimer = Timer(after, () {
        if (!_isCurrent(engine)) return;
        unawaited(engine.pause());
        state = state?.copyWith(sleep: SleepTimer.off);
        ref.read(noticeProvider.notifier).show('Sleep timer: paused. Good night.');
      });
    }
    ref
        .read(noticeProvider.notifier)
        .show(t == SleepTimer.off ? 'Sleep timer off' : 'Sleep timer: ${t.label.toLowerCase()}');
  }

  /// The frame as you see it (subtitles included), to Pictures\Marquee.
  Future<void> screenshot() async {
    final cur = state;
    if (cur == null) return;
    final pos = cur.engine.player.state.position;
    final stem = p
        .basenameWithoutExtension(cur.file.displayName)
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final stamp = shortClock(pos).replaceAll(':', '.');
    try {
      final dir = await screenshotDir();
      final path = p.join(dir.path, '$stem $stamp.jpg');
      final ok = await cur.engine.screenshotTo(path, subtitles: true);
      ref
          .read(noticeProvider.notifier)
          .show(ok ? 'Screenshot saved to ${dir.path}' : "Couldn't save the screenshot.");
    } on Object {
      ref.read(noticeProvider.notifier).show("Couldn't save the screenshot.");
    }
  }

  /// N / P and the Up-next card: the folder's next or previous film.
  Future<void> playNeighbour({required bool next}) async {
    final cur = state;
    final path = next ? cur?.nextPath : cur?.previousPath;
    if (path == null) {
      ref
          .read(noticeProvider.notifier)
          .show(
            next ? 'This is the last film in the folder.' : 'This is the first film in the folder.',
          );
      return;
    }
    await openLocator(path);
  }

  /// Saves where you are (every 5 s, on close, when the app goes to the background).
  Future<void> saveResumeNow() => _saveResume();

  Future<void> _saveResume([FilmSession? of]) async {
    final cur = of ?? state;
    final key = cur?.threading.hash ?? _resumeKey;
    if (cur == null || key == null || !cur.started || cur.engine.isDisposed) return;
    final s = cur.engine.snapshot;
    if (s.duration == Duration.zero) return;
    final pos = s.completed ? s.duration : s.position;
    if (pos == Duration.zero) return; // never overwrite a resume point before playback moved
    // Paused: the 5 s tick has nothing new to say (and every write re-runs the Lobby query).
    final last = _lastSaved;
    if (last != null && last.key == key && last.positionMs == pos.inMilliseconds) return;
    _lastSaved = (key: key, positionMs: pos.inMilliseconds);
    await ref.read(databaseProvider).saveResume(key, pos.inMilliseconds, s.duration.inMilliseconds);
  }

  /// House lights up: the room changes at once; the resume point, the Lobby frame and the
  /// player's disposal follow behind it.
  Future<void> close({bool toLobby = true}) async {
    final cur = state;
    _cancelTimers();
    _machine?.dispose();
    _machine = null;
    if (cur == null) return;
    // Read everything from the player BEFORE the room changes; write it after.
    final resume = _saveResume(cur);
    final volume = (_volumeSave?.isActive ?? false) ? cur.engine.player.state.volume : null;
    _volumeSave?.cancel();
    state = null;
    ref.read(boothOpenProvider.notifier).set(false);
    ref.read(cueSheetProvider.notifier).set(false);
    if (toLobby) {
      ref.read(fullscreenProvider.notifier).set(false);
      ref.read(roomProvider.notifier).go(Room.lobby);
    }
    try {
      await resume;
      if (cur.started && cur.error == null) await _grabThumbnail(cur);
      if (volume != null) await _persistVolume(volume);
    } on Object {
      // The film is closing either way.
    } finally {
      await cur.engine.dispose();
    }
  }

  String exportName() =>
      'marquee-library-${DateTime.now().toIso8601String().substring(0, 10)}.json';
}

final sessionProvider = NotifierProvider<SessionNotifier, FilmSession?>(SessionNotifier.new);

/// position/duration/tracks at 10 Hz, never 60. Watch it through `select` (see
/// `ControlsLayer`): only the controls need the clock, and only while they show.
final playbackProvider = StreamProvider<PlaybackState>((ref) {
  final engine = ref.watch(sessionProvider.select((s) => s?.engine));
  if (engine == null) return Stream.value(const PlaybackState());
  return engine.states;
});

String prettyJson(Object? o) => const JsonEncoder.withIndent('  ').convert(o);
