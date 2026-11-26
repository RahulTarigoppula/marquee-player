// The open film: one PlayerEngine + one ThreadingMachine, wired to the cache, the sidecar
// writer and the API. The Auditorium appears the moment a film is chosen; libmpv opens the
// file (PAUSED, at the resume point) while the leader counts, and the film starts when
// threading is done, skipped, or falls back to "no subtitles".
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../engine/filename.dart';
import '../engine/hash.dart';
import '../engine/models/models.dart';
import '../engine/picture.dart';
import '../engine/playback.dart';
import '../engine/threading.dart';
import '../platform/audio_focus.dart';
import '../platform/files.dart';
import '../platform/pip.dart';
import '../platform/window.dart';
import '../player/engine.dart';
import '../player/preview.dart';
import 'film_session.dart';
import 'library.dart';
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

/// A film's own choices (audio track, picture, subtitle) are written this long after the last
/// change: dragging a picture slider is one write.
const Duration kPrefsSaveAfter = Duration(milliseconds: 600);

/// The Lobby frame is grabbed this far in (or at 10 % of a shorter film), and again on close.
const Duration kThumbnailAt = Duration(minutes: 2, seconds: 30);

class SessionNotifier extends Notifier<FilmSession?> {
  ThreadingMachine? _machine;
  Timer? _resumeTimer;
  Timer? _undecodable;
  Timer? _thumbTimer;
  Timer? _sleepTimer;
  Timer? _volumeSave;
  Timer? _prefsSave;
  Timer? _stuckCheck;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _playingSub;

  /// Android: other apps' music stops while the film plays; a call or unplugged headphones
  /// pause it (see [AudioFocus]).
  late final AudioFocus _focus = AudioFocus(onPause: pauseUnseen);
  bool _attachedOnce = false;

  // Per-film memory. The subtitle choice is restored only once BOTH the stored choices have
  // been read and threading has attached its own pick, so the viewer's choice wins.
  FilmPrefs _prefs = const FilmPrefs();
  bool _prefsLoaded = false;
  bool _prefsTouched = false;
  bool _attachSettled = false;
  bool _subtitlesRestored = false;

  /// Subtitles were switched off for this film last time: the automatic search may attach
  /// what is already on disk, but asks nobody online (and so can never spend a ticket). Any
  /// search made by hand clears it.
  bool _searchDeclined = false;

  /// The seek bar's preview frames for the open film, made on the first hover (see
  /// [seekPreview]); it goes when the film does.
  SeekPreview? _preview;

  /// libmpv has the file (and its audio output): sound effects can be applied and checked.
  bool _loaded = false;

  /// Until the folder has been listed, a folder of one cannot be told from a folder of ten.
  bool _neighboursKnown = false;

  /// The sound profile this libmpv build last refused, so each is said once, not per film.
  static ({bool normalize, EqPreset preset})? _fxRefused;

  /// open() is serialised: each call waits for the previous one, and a call superseded while
  /// waiting does nothing (two quick drops play the second file, once).
  int _openSeq = 0;
  int _opening = 0;
  Future<void> _tail = Future.value();

  /// The resume key: the moviehash, or [urlResumeKey] for a stream and for a file whose hash
  /// could not be read (an Android provider that gives no size): those resume by locator.
  MovieHash? _resumeKey;

  /// Set when [_resumeKey] is the locator's key: the position is saved under it as well as
  /// under a hash that arrives late, so the next open finds it either way.
  MovieHash? _locatorKey;
  Duration? _resumeAt;

  /// "Start over" was tapped: nothing may put the film back at the resume point.
  bool _resumeDeclined = false;

  /// The "add your API key" sentence is said once a run, not at every film.
  static bool _noKeySaid = false;
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
    // The sound profile likewise, once the film has loaded (see [PlayerEngine.applyAudioFx]).
    ref.listen(settingsValueProvider.select((s) => s.audioFx), (_, _) {
      final engine = state?.engine;
      if (engine != null && _loaded) unawaited(_applyAudioFx(engine));
    });
    ref.listen(settingsValueProvider.select((s) => (s.repeat, s.autoplayNext)), (_, _) {
      final engine = state?.engine;
      if (engine != null) unawaited(_applyLoop(engine));
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
    // A key added or a sign-in completed while the search waits for exactly that: try again.
    void retryIfWaitingFor(Set<ThreadingFailure> failures) {
      final ev = state?.threading.event;
      if (ev is Stalled && failures.contains(ev.failure)) unawaited(retrySubtitles());
    }

    ref.listen(osKeyProvider, (_, has) {
      if (has) retryIfWaitingFor(const {ThreadingFailure.noApiKey});
    });
    ref.listen(accountProvider.select((a) => a.status), (_, status) {
      if (status == AccountStatus.signedIn) {
        retryIfWaitingFor(const {ThreadingFailure.unauthorized, ThreadingFailure.quotaExhausted});
      }
    });
    ref.read(pipProvider.notifier)
      ..onPlayPause = (() => unawaited(state?.engine.playOrPause()))
      ..onDismissed = pauseUnseen;
    ref.onDispose(() {
      _cancelTimers();
      _prefsSave?.cancel();
      _dropPreview();
      _machine?.dispose();
      unawaited(_focus.dispose());
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
    _stuckCheck?.cancel();
    unawaited(_completedSub?.cancel());
    _completedSub = null;
    unawaited(_errorSub?.cancel());
    _errorSub = null;
    unawaited(_playingSub?.cancel());
    _playingSub = null;
    unawaited(_focus.setPlaying(false));
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
      _locatorKey = null;
      _resumeAt = null;
      _resumeDeclined = false;
      _prefs = const FilmPrefs();
      _prefsLoaded = false;
      _prefsTouched = false;
      _attachSettled = false;
      _subtitlesRestored = false;
      _searchDeclined = false;
      _loaded = false;
      _neighboursKnown = false;
      _mediaIdReady = Completer<int>();
      // The room changes NOW: the player configures behind the house lights.
      state = FilmSession(file: file, engine: e, parsed: parsed);
      ref.read(roomProvider.notifier).go(Room.auditorium);
      _watchCompletion(e);
      await e.configure(settings);
      if (!_isCurrent(e)) return;
      await _applyLoop(e);
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
    // No hash (unknown size, a slow or unreadable source): the film still resumes, and keeps
    // its own choices, by where it lives.
    if (hash == null) _locatorKey = urlResumeKey(file.locator);
    await _loadResume(hash ?? _locatorKey!);
    if (!_isCurrent(engine)) return;
    unawaited(_startPlayback(engine, file, start: _resumeAt));
    // Known before the machine starts, so it is in place by the time the search would begin.
    _searchDeclined = await _subtitlesWereOff(hash ?? _locatorKey!);
    if (!_isCurrent(engine)) return;
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
    _attachSettled = true;
    await _startPlayback(engine, file, start: _resumeAt);
    if (delay != 0) await engine.setSubDelayMs(delay);
    await _begin(engine);
  }

  ThreadingMachine _machineFor(
    OpenedFile file,
    Settings settings,
    PlayerEngine engine,
    Future<MovieHash> Function() hash,
  ) {
    final ports = SubtitlePorts(
      ref: ref,
      file: file,
      settings: settings,
      engine: engine,
      onHashKnown: (h) => _recordMedia(file, engine, h),
      onFeatureTitle: (title, year) => _retitle(engine, title, year),
    ).build(hash);
    late final ThreadingMachine machine;
    return machine = ThreadingMachine(
      ports: ThreadingPorts(
        hash: ports.hash,
        findExisting: ports.findExisting,
        // The automatic search of a film whose subtitles were switched off stops HERE, before
        // any request: the leader ends as "no subtitles" (the sidecar and the cache had their
        // turn in findExisting). The Booth's searches clear the flag first, so they go through.
        search: (request) async {
          if (_searchDeclined && _isCurrent(engine)) {
            _searchDeclined = false;
            machine.skip();
            throw const ThreadingException(ThreadingFailure.noResults);
          }
          return ports.search(request);
        },
        subdl: ports.subdl,
        download: ports.download,
      ),
      config: ThreadingConfig(
        languages: settings.languages,
        preferHearingImpaired: settings.preferHearingImpaired,
        subdlEnabled: settings.subdlEnabled,
      ),
      quota: ref.read(quotaProvider),
      onChange: (t) => _onThreading(engine, t),
    );
  }

  /// True when the stored choices for the film under [key] say "subtitles off". Unreadable
  /// means no: the search runs as it always did.
  Future<bool> _subtitlesWereOff(MovieHash key) async {
    try {
      final stored = FilmPrefs.fromJson(await ref.read(databaseProvider).filePrefsFor(key));
      return stored.subtitle == FilmPrefs.off;
    } on Object {
      return false;
    }
  }

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
    _undecodable = Timer(kUndecodableAfter, () => unawaited(_failIfStuck(engine)));
    _resumeTimer?.cancel();
    _resumeTimer = Timer.periodic(kResumeSaveEvery, (_) => unawaited(_saveResume()));
    unawaited(_afterLoad(engine, file));
  }

  /// Nothing ever played: no length, no movement, mpv said why and has gone back to idle (it
  /// gave the file up). "Playing" proves nothing: media_kit says so the moment play is asked
  /// for. A live stream has no length either, but it moves, and a slow one is still loading
  /// (not idle), so a recoverable network error never ends it.
  Future<void> _failIfStuck(PlayerEngine engine) async {
    if (!_isCurrent(engine) || state?.error != null) return;
    final s = engine.snapshot;
    if (s.position != Duration.zero || s.duration != Duration.zero || s.error == null) return;
    final idle = await engine.property('idle-active');
    if (!_isCurrent(engine)) return;
    // A build that cannot say whether it is idle: the error and the stillness decide.
    if (idle == null || idle.isEmpty || idle == 'yes') _fail(engine);
  }

  /// container-fps, chapters, the probe for the Lobby card and the folder's neighbours only
  /// exist once the file has loaded; the sound profile and the film's remembered choices can
  /// only be applied (and checked) then.
  Future<void> _afterLoad(PlayerEngine engine, OpenedFile file) async {
    if (!await engine.whenLoaded() || !_isCurrent(engine)) return;
    _loaded = true;
    // Android: the video surface attaching can seek the film to "where it is" before mpv has
    // reported the start position, which throws the resume point away. Put it back, once.
    final at = _resumeAt;
    if (Platform.isAndroid &&
        at != null &&
        !_resumeDeclined &&
        engine.player.state.position < at - const Duration(seconds: 5)) {
      await engine.seekTo(at);
      if (!_isCurrent(engine)) return;
    }
    unawaited(_applyAudioFx(engine));
    unawaited(_restorePrefs(engine));
    final fps = await engine.containerFps();
    if (!_isCurrent(engine)) return;
    _machine?.setContainerFps(fps);
    final chapters = await engine.chapters();
    final near = await _neighbours(file);
    if (!_isCurrent(engine)) return;
    state = state?.copyWith(
      chapters: chapters,
      previousPath: near.previous,
      nextPath: near.next,
      firstPath: near.first,
    );
    _neighboursKnown = true;
    await _applyLoop(engine);
    if (!_isCurrent(engine)) return;
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

  /// The films either side of [file], and the first of them: the files beside it on desktop,
  /// the device library's order for a phone's content:// film (nothing when it is not in the
  /// library). A folder that cannot be listed just has no neighbours.
  Future<({String? previous, String? next, String? first})> _neighbours(OpenedFile file) async {
    const none = (previous: null, next: null, first: null);
    if (file.isRemote) return none;
    try {
      if (!PlayerEngine.isDesktop || file.isContentUri) {
        return ref.read(libraryNeighboursProvider)(file.locator);
      }
      final dir = Directory(p.dirname(file.locator));
      final names = <String>[
        await for (final e in dir.list(followLinks: false))
          if (e is File && isVideoFile(e.path)) p.basename(e.path),
      ];
      final n = folderOrder(names, p.basename(file.locator));
      String? full(String? name) => name == null ? null : p.join(dir.path, name);
      return (previous: full(n.previous), next: full(n.next), first: full(n.first));
    } on Object {
      return none;
    }
  }

  /// The sound profile from Settings. A libmpv build without the filters refuses it: the film
  /// keeps its plain sound and one sentence says why nothing changed.
  Future<void> _applyAudioFx(PlayerEngine engine) async {
    try {
      final fx = ref.read(settingsValueProvider).audioFx;
      final ok = await engine.applyAudioFx(fx);
      if (ok || !_isCurrent(engine) || _fxRefused == fx) return;
      _fxRefused = fx;
      ref.read(noticeProvider.notifier).show("This build can't apply sound effects.");
    } on Object {
      // The film was closed mid-change.
    }
  }

  /// "Repeat this video" (and a repeating folder of one) is mpv's own loop: the film never
  /// reports an end, so no "Up next" card and no second start. Every other ending goes through
  /// the card ([FilmSession.upNextFor]); the two read the same rule ([endAction]).
  Future<void> _applyLoop(PlayerEngine engine) async {
    final cur = state;
    if (cur == null || cur.engine != engine || engine.isDisposed) return;
    final s = ref.read(settingsValueProvider);
    final loop =
        cur.endActionFor(s) == EndAction.loop && (s.repeat == RepeatMode.one || _neighboursKnown);
    await engine.setLoopFile(loop);
  }

  // ───────────────────────────── per-film memory ─────────────────────────────

  /// What this film's choices are stored under: the moviehash, or the URL key of a stream.
  /// A film opened by its locator keeps that key even if the hash turns up later, so what is
  /// read at the next open is what was written at this one.
  MovieHash? get _filmKey => _locatorKey ?? state?.threading.hash ?? _resumeKey;

  /// Notes a choice the viewer just made for this film and saves it, once the hand is still.
  void _remember(FilmPrefs next) {
    _prefsTouched = true;
    if (next == _prefs) return;
    _prefs = next;
    final key = _filmKey;
    if (key == null) return; // no hash and no URL: nothing to remember it by
    _prefsSave?.cancel();
    _prefsSave = Timer(kPrefsSaveAfter, () => unawaited(_writePrefs(key, next)));
  }

  Future<void> _writePrefs(MovieHash key, FilmPrefs prefs) async {
    try {
      await ref.read(databaseProvider).saveFilePrefs(key, prefs.toJson());
    } on Object {
      // A choice that could not be saved still holds for this showing.
    }
  }

  /// The audio track and picture the viewer chose for this film last time. A track id is
  /// only applied if mpv still lists it; nothing here may stop the film.
  Future<void> _restorePrefs(PlayerEngine engine) async {
    final key = _filmKey;
    try {
      if (key != null) {
        final stored = FilmPrefs.fromJson(await ref.read(databaseProvider).filePrefsFor(key));
        if (!_isCurrent(engine)) return;
        // A choice made while the database was being read is newer than anything stored.
        if (!_prefsTouched) {
          _prefs = stored;
          if (!stored.picture.isNeutral) {
            state = state?.copyWith(picture: stored.picture);
            await engine.applyPicture(stored.picture);
          }
          final audio = stored.audioId;
          if (audio != null && (await engine.trackIds('audio')).contains(audio)) {
            await engine.selectAudio(audio);
          }
        }
      }
    } on Object {
      // The film plays without its memory rather than not at all.
    }
    if (!_isCurrent(engine)) return;
    _prefsLoaded = true;
    await _restoreSubtitles(engine);
  }

  /// The remembered subtitle choice (a track of the film, or off) and second subtitle, once:
  /// after the stored choices were read AND threading attached its own pick, so this wins.
  Future<void> _restoreSubtitles(PlayerEngine engine) async {
    if (!_prefsLoaded || !_attachSettled || _subtitlesRestored || !_isCurrent(engine)) return;
    _subtitlesRestored = true;
    final want = _prefs.subtitle;
    final second = _prefs.secondSubtitleId;
    if (want == null && second == null) return;
    try {
      final ids = await engine.trackIds('sub');
      if (!_isCurrent(engine)) return;
      if (want == FilmPrefs.off) {
        await engine.subtitlesOff();
      } else if (want != null && ids.contains(want)) {
        await engine.selectSubtitle(want);
      }
      if (second == null || !ids.contains(second) || !_isCurrent(engine)) return;
      if (await engine.property('sid') != second) await engine.setSecondarySubtitle(second);
    } on Object {
      // The automatic pick stands.
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
    // A dead link or an undecodable file may say so before or after the one timed check:
    // look again a moment after every error mpv reports.
    unawaited(_errorSub?.cancel());
    _errorSub = engine.player.stream.error.listen((_) {
      _stuckCheck?.cancel();
      _stuckCheck = Timer(const Duration(seconds: 2), () => unawaited(_failIfStuck(engine)));
    });
    unawaited(_playingSub?.cancel());
    _playingSub = engine.player.stream.playing.listen((playing) {
      if (_isCurrent(engine)) unawaited(_focus.setPlaying(playing));
    });
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
    if (cur == null || cur.engine != engine || cur.error != null) return;
    // The sentence first: ending the leader below must not "start" a film that cannot play.
    state = cur.copyWith(error: "This print can't be projected.");
    _machine?.skip();
    unawaited(engine.pause()); // never a black screen that claims to be playing
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
    if (t.phase == LeaderPhase.done) {
      if (!_attachedOnce) {
        _attachedOnce = true;
        unawaited(_attach(engine, t.attached, explicit: true));
      }
      if (!cur.started) unawaited(_begin(engine));
      return;
    }
    // Subtitles never hold the film back. When the automatic search stalls (offline, no key,
    // no exact match, a timeout) the film starts, one sentence says what happened, and the
    // machine stays where it stalled: the Booth shows the rows, the retry and the search
    // while the film plays.
    final ev = t.event;
    if (ev is Stalled && !cur.started) {
      // Nothing was found, but nothing was refused either: an embedded track mpv picked by
      // itself (a wanted language, or the file's own default) stays on.
      unawaited(_attach(engine, const NoSubtitle(), explicit: false));
      unawaited(_begin(engine, stall: ev));
    }
  }

  /// [explicit]: the leader ended in a decision ("Play without subtitles", or a print). Only
  /// then does "no subtitles" switch off the track mpv selected by itself.
  Future<void> _attach(PlayerEngine engine, SubtitleTrackRef a, {required bool explicit}) async {
    try {
      switch (a) {
        case ExternalSubtitle():
          await engine.attachSubtitle(a.path, language: a.language);
        case EmbeddedSubtitle():
          if (await engine.whenLoaded()) await engine.selectSubtitle(a.mpvTrackId);
        case NoSubtitle():
          if (explicit) await engine.subtitlesOff();
      }
      final now = state;
      final delay = now != null && now.engine == engine ? now.delayMs : 0;
      if (delay != 0) await engine.setSubDelayMs(delay);
    } on Object {
      // The film was closed while the subtitle was being attached.
    }
    if (!_isCurrent(engine)) return;
    _attachSettled = true;
    await _restoreSubtitles(engine);
  }

  /// House lights fully down: the film starts, at the resume point, which a notice offers
  /// to undo. Started because the subtitle search stalled ([stall]), the notice says that
  /// instead and opens the Booth, where the search carries on.
  Future<void> _begin(PlayerEngine engine, {Stalled? stall}) async {
    final cur = state;
    if (cur == null || cur.engine != engine || cur.started) return;
    state = cur.copyWith(started: true);
    if (cur.error != null) return; // nothing to play: the "can't be projected" card is up
    await engine.play();
    if (!_isCurrent(engine)) return;
    final at = _resumeAt;
    final notice = ref.read(noticeProvider.notifier);
    var why = stall?.sentence;
    if (stall?.failure == ThreadingFailure.noApiKey) {
      if (_noKeySaid) why = null;
      _noKeySaid = true;
    }
    if (why != null && why.isNotEmpty) {
      notice.show(
        at == null ? why : 'Resumed at ${shortClock(at)}. $why',
        actionLabel: 'Subtitles…',
        onAction: () {
          if (_isCurrent(engine)) ref.read(boothOpenProvider.notifier).set(true);
        },
        duration: const Duration(seconds: 8),
      );
    } else if (at != null) {
      notice.show(
        'Resumed at ${shortClock(at)}',
        actionLabel: 'Start over',
        onAction: () {
          _resumeDeclined = true;
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

  /// Levels, rotation, zoom and deinterlacing: applied now, remembered for this film.
  Future<void> setPicture(PictureAdjust picture) async {
    final cur = state;
    if (cur == null || cur.picture == picture) return;
    state = cur.copyWith(picture: picture);
    _remember(_prefs.copyWith(picture: picture));
    await cur.engine.applyPicture(picture);
  }

  /// The audio track the viewer picked (menu or A): this film opens with it next time.
  Future<void> selectAudio(String id) async {
    final engine = state?.engine;
    if (engine == null) return;
    _remember(_prefs.copyWith(audioId: id));
    await engine.selectAudio(id);
  }

  /// An explicit subtitle choice. Only a track of the film itself can be remembered: a loaded
  /// or downloaded file gets a new id every showing, so picking one goes back to automatic.
  Future<void> selectSubtitle(String id) async {
    final engine = state?.engine;
    if (engine == null) return;
    _remember(
      engine.isExternal(id) ? _prefs.copyWith(clearSubtitle: true) : _prefs.copyWith(subtitle: id),
    );
    // The same track twice (bottom and top) helps nobody.
    if (engine.snapshot.secondarySubtitleId == id) await setSecondSubtitle(null);
    await engine.selectSubtitle(id);
  }

  Future<void> subtitlesOff() async {
    final engine = state?.engine;
    if (engine == null) return;
    _remember(_prefs.copyWith(subtitle: FilmPrefs.off));
    await engine.subtitlesOff();
  }

  /// The subtitle Marquee found for this film: the automatic pick again, next time too.
  Future<void> useAttachedSubtitle() async {
    final cur = state;
    final a = cur?.threading.attached;
    if (cur == null || a is! ExternalSubtitle) return;
    _remember(_prefs.copyWith(clearSubtitle: true));
    await cur.engine.attachSubtitle(a.path, language: a.language);
  }

  /// A second text subtitle at the top of the picture, or null for none.
  Future<void> setSecondSubtitle(String? id) async {
    final engine = state?.engine;
    if (engine == null) return;
    _remember(
      id == null || engine.isExternal(id)
          ? _prefs.copyWith(clearSecondSubtitle: true)
          : _prefs.copyWith(secondSubtitleId: id),
    );
    await engine.setSecondarySubtitle(id);
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

  /// A print picked by hand is a new choice: a remembered "off" or embedded track gives way.
  Future<void> pick(ScoredCandidate c) async {
    _attachedOnce = false;
    _searchDeclined = false;
    _remember(_prefs.copyWith(clearSubtitle: true));
    await _machine?.pick(c);
  }

  Future<void> findAnother(String query) async {
    _attachedOnce = false;
    _searchDeclined = false;
    _remember(_prefs.copyWith(clearSubtitle: true));
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

  /// The Booth's fallback rows while the film plays. Each one may end in a new subtitle, so
  /// each one re-arms the attach (like [pick] and [findAnother]).
  Future<void> retrySubtitles() async {
    _attachedOnce = false;
    _searchDeclined = false;
    await _machine?.retry();
  }

  Future<void> searchByFilename() async {
    _attachedOnce = false;
    _searchDeclined = false;
    await _machine?.filenameSearch();
  }

  Future<void> searchSubdl() async {
    _attachedOnce = false;
    _searchDeclined = false;
    await _machine?.subdlSearch();
  }

  /// "Load subtitle file…" or a subtitle dropped on the picture.
  Future<void> loadSubtitleFile(String path) async {
    final engine = state?.engine;
    if (engine == null) return;
    _remember(_prefs.copyWith(clearSubtitle: true));
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
    // "End of this film" must let a repeating film end; any other choice gives the loop back.
    unawaited(_applyLoop(cur.engine));
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

  /// What the "Skip intro" button would do right now, if the film is inside such a chapter.
  ({String label, double toSeconds})? get skippable {
    final cur = state;
    if (cur == null || cur.threadingVisible || cur.engine.isDisposed) return null;
    final st = cur.engine.player.state;
    return skippableChapter(
      cur.chapters,
      st.position.inMilliseconds / 1000,
      st.duration.inMilliseconds / 1000,
      hasNext: cur.nextPath != null,
    );
  }

  /// The "Skip intro" button and Enter: on to the next chapter, or (closing credits with
  /// another episode waiting) straight to the next film. The label of what was skipped, or
  /// null when there was nothing to skip.
  Future<String?> skipChapter() async {
    final cur = state;
    final skip = skippable;
    if (cur == null || skip == null) return null;
    if (skip.toSeconds >= cur.engine.player.state.duration.inMilliseconds / 1000) {
      await playNeighbour(next: true);
    } else {
      await cur.engine.seekTo(Duration(milliseconds: (skip.toSeconds * 1000).round()));
    }
    return skip.label;
  }

  /// The "Up next" card: the film the end of this one leads to (the next, or, with the
  /// folder on repeat, the first again). open() is serialised, so the countdown and a tap on
  /// "Play now" landing together still start it once.
  Future<void> playUpNext() async {
    final path = state?.upNextFor(ref.read(settingsValueProvider));
    if (path != null) await openLocator(path);
  }

  /// N / P: the folder's next or previous film. With the folder on repeat, N on the last film
  /// goes round to the first.
  Future<void> playNeighbour({required bool next}) async {
    final cur = state;
    var path = next ? cur?.nextPath : cur?.previousPath;
    if (path == null && next && ref.read(settingsValueProvider).repeat == RepeatMode.all) {
      path = cur?.firstPath;
    }
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

  /// The seek bar's preview frames for the open film, made the first time they are asked for.
  /// Null when this film gets none ([seekPreviewAllowed]) or its preview has failed: the seek
  /// bar then shows the time alone.
  SeekPreview? seekPreview() {
    final cur = state;
    if (cur == null || cur.engine.isDisposed || cur.error != null) return null;
    final allowed = seekPreviewAllowed(
      enabled: ref.read(settingsValueProvider).seekPreview,
      desktop: PlayerEngine.isDesktop,
      remote: cur.file.isRemote,
      contentUri: cur.file.isContentUri,
    );
    if (!allowed) {
      _dropPreview(); // switched off in Settings while the film plays
      return null;
    }
    final existing = _preview;
    // One that failed is not made again: this film has no preview.
    if (existing != null) return existing.usable ? existing : null;
    return _preview = SeekPreview(cur.file.locator);
  }

  void _dropPreview() {
    _preview?.dispose();
    _preview = null;
  }

  /// Saves where you are (every 5 s, on close, when the app goes to the background), and any
  /// choice for this film still waiting to be written.
  Future<void> saveResumeNow() async {
    final key = _filmKey;
    if (key != null && (_prefsSave?.isActive ?? false)) {
      _prefsSave?.cancel();
      await _writePrefs(key, _prefs);
    }
    await _saveResume();
  }

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
    final db = ref.read(databaseProvider);
    await db.saveResume(key, pos.inMilliseconds, s.duration.inMilliseconds);
    // The hash arrived after the film opened by its locator: keep that key current as well.
    final byLocator = _locatorKey;
    if (byLocator != null && byLocator != key) {
      await db.saveResume(byLocator, pos.inMilliseconds, s.duration.inMilliseconds);
    }
  }

  /// House lights up: the room changes at once; the resume point, the Lobby frame and the
  /// player's disposal follow behind it.
  Future<void> close({bool toLobby = true}) async {
    final cur = state;
    _cancelTimers();
    _dropPreview();
    _machine?.dispose();
    _machine = null;
    if (cur == null) return;
    // Read everything from the player BEFORE the room changes; write it after.
    final resume = _saveResume(cur);
    final volume = (_volumeSave?.isActive ?? false) ? cur.engine.player.state.volume : null;
    _volumeSave?.cancel();
    final prefsKey = _locatorKey ?? cur.threading.hash ?? _resumeKey;
    final prefs = (_prefsSave?.isActive ?? false) ? _prefs : null;
    _prefsSave?.cancel();
    state = null;
    ref.read(boothOpenProvider.notifier).set(false);
    ref.read(cueSheetProvider.notifier).set(false);
    ref.read(pinnedProvider.notifier).set(false); // the Lobby never floats above other windows
    if (toLobby) {
      ref.read(fullscreenProvider.notifier).set(false);
      ref.read(roomProvider.notifier).go(Room.lobby);
    }
    try {
      await resume;
      if (prefs != null && prefsKey != null) await _writePrefs(prefsKey, prefs);
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
