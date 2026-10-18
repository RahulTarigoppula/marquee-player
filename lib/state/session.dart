// The open film: one PlayerEngine + one ThreadingMachine, wired to the cache, the sidecar
// writer and the API. Libmpv opens the file (PAUSED, at the resume point) while the leader
// counts; the film starts when threading is done, skipped, or falls back to "no subtitles".
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../api/opensubtitles.dart';
import '../api/subdl.dart';
import '../engine/filename.dart';
import '../engine/hash.dart';
import '../engine/models/models.dart';
import '../engine/playback.dart';
import '../engine/threading.dart';
import '../platform/files.dart';
import '../platform/pip.dart';
import '../player/engine.dart';
import 'notice.dart';
import 'providers.dart';
import 'thumbnails.dart';

const Duration kResumeSaveEvery = Duration(seconds: 5);
const Duration kUndecodableAfter = Duration(seconds: 5);

/// The Lobby frame is grabbed this far in (or at 10 % of a shorter film), and again on close.
const Duration kThumbnailAt = Duration(minutes: 2, seconds: 30);

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
  final String? error; // "This print can't be projected." — never a code

  /// The folder's neighbours (desktop paths only), for N / P and "Up next".
  final String? previousPath, nextPath;

  /// A–B loop points; both set ⇒ looping.
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
  Future<void> _tail = Future.value();

  /// The resume key: the moviehash, or [urlResumeKey] for a stream.
  MovieHash? _resumeKey;
  Duration? _resumeAt;
  bool _pausedForOffice = false;
  Completer<int>? _mediaIdReady;

  @override
  FilmSession? build() {
    // The machine holds its own quota; keep it current (sign-in, restore, sign-out) or a pick
    // after signing in is refused as "no tickets" without a request.
    ref.listen(quotaProvider, (_, q) => _machine?.setQuota(q));
    // Subtitle look and size apply to the open film the moment they change in Settings.
    ref.listen(settingsProvider, (prev, next) {
      final s = next.value;
      final engine = state?.engine;
      if (s != null && engine != null && prev?.value != s) {
        unawaited(engine.applySubtitleStyle(s));
      }
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
    ref.read(pipProvider.notifier).onPlayPause = () => unawaited(state?.engine.playOrPause());
    ref.onDispose(() {
      _resumeTimer?.cancel();
      _undecodable?.cancel();
      _thumbTimer?.cancel();
      _sleepTimer?.cancel();
      _volumeSave?.cancel();
      unawaited(_completedSub?.cancel());
      _machine?.dispose();
    });
    return null;
  }

  ThreadingMachine? get machine => _machine;

  bool _isCurrent(PlayerEngine engine) => state?.engine == engine && !engine.isDisposed;

  // ───────────────────────────── opening ─────────────────────────────

  /// THE entry point: a picked, dropped, forwarded or "Open URL…" film.
  Future<void> open(OpenedFile file) {
    final seq = ++_openSeq;
    final run = _tail.then((_) async {
      if (seq != _openSeq) return;
      await _open(file, seq);
    });
    _tail = run.catchError((Object _) {});
    return run;
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

  Future<void> _open(OpenedFile file, int seq) async {
    if (state != null) await close(toLobby: false);
    if (seq != _openSeq) return;
    try {
      // A film opened at launch must not search before the saved API key is back.
      await ref.read(accountProvider.notifier).restored.timeout(const Duration(seconds: 3));
    } on Object {
      // A slow keyring: search without it rather than wait.
    }
    final settings = await ref.read(settingsProvider.future);
    if (seq != _openSeq) return;
    if (!file.isRemote && !file.isContentUri && !File(file.locator).existsSync()) {
      await _missing(file.locator);
      return;
    }
    final parsed = file.isRemote || file.isContentUri
        ? parseName(file.displayName)
        : parsePath(file.locator);
    final engine = PlayerEngine(hwdec: settings.hwdec);
    await engine.configure(settings);
    if (seq != _openSeq) {
      await engine.dispose();
      return;
    }
    _attachedOnce = false;
    _pausedForOffice = false;
    _resumeKey = null;
    _resumeAt = null;
    _mediaIdReady = Completer<int>();
    state = FilmSession(file: file, engine: engine, parsed: parsed);
    ref.read(roomProvider.notifier).go(Room.auditorium);
    _watchCompletion(engine);

    if (file.isRemote) {
      await _openStream(file, engine, settings, parsed);
      return;
    }

    // The hash is ~40 ms; reading it first lets libmpv open AT the resume point (a seek after
    // load is racy). The threading machine reuses the same future — one read of the file.
    final hashing = movieHashOf(await chunkReaderFor(file), file.sizeBytes);
    unawaited(hashing.then((_) {}, onError: (Object _) {}));
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

    final machine = ThreadingMachine(
      ports: _ports(file, settings, engine, () => hashing),
      config: ThreadingConfig(
        languages: settings.languages,
        preferHearingImpaired: settings.preferHearingImpaired,
        subdlEnabled: settings.subdlEnabled,
      ),
      quota: ref.read(quotaProvider),
      onChange: (t) => _onThreading(engine, t),
    );
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
    _machine = ThreadingMachine(
      ports: _ports(file, settings, engine, () => throw const HashUnavailable('a stream')),
      config: ThreadingConfig(
        languages: settings.languages,
        preferHearingImpaired: settings.preferHearingImpaired,
        subdlEnabled: settings.subdlEnabled,
      ),
      quota: ref.read(quotaProvider),
      onChange: (t) => _onThreading(engine, t),
    );
    _attachedOnce = true; // nothing automatic to attach; a manual pick resets this
    await _startPlayback(engine, file, start: _resumeAt);
    if (delay != 0) await engine.setSubDelayMs(delay);
    await _begin(engine);
  }

  Future<void> _loadResume(MovieHash key) async {
    _resumeKey = key;
    final rp = await ref.read(databaseProvider).resumeFor(key);
    if (rp != null && rp.positionMs > 10000 && !rp.finished) {
      _resumeAt = Duration(milliseconds: rp.positionMs);
    }
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
      final s = engine.snapshot;
      if (s.duration == Duration.zero && s.error != null) _fail(engine);
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
      _thumbTimer = Timer(thumbAt, () => unawaited(_grabThumbnail(engine)));
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

  Future<void> _grabThumbnail(PlayerEngine engine) async {
    final id = state?.mediaId;
    if (id == null || !_isCurrent(engine) || state!.file.isRemote) return;
    if (engine.player.state.position < const Duration(seconds: 5)) return;
    final target = await thumbnailTarget(ref, id);
    if (await engine.screenshotTo(target)) await thumbnailWritten(ref, id);
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

  ThreadingPorts _ports(
    OpenedFile file,
    Settings settings,
    PlayerEngine engine,
    Future<MovieHash> Function() hash,
  ) {
    final db = ref.read(databaseProvider);
    final os = ref.read(openSubtitlesProvider);
    return ThreadingPorts(
      hash: hash,
      findExisting: (hash) async {
        await _recordMedia(file, engine, hash);
        final side = findSidecar(file, settings.languages);
        if (side != null) {
          return ExternalSubtitle(
            path: side,
            language: settings.languages.first,
            provider: SubtitleProvider.sidecar,
            syncedByHash: false,
          );
        }
        if (hash != null) {
          final row = await db.cachedSubtitle(hash, settings.languages, exists: fileExists);
          if (row != null) {
            return ExternalSubtitle(
              path: row.sidecarPath,
              language: row.language,
              provider:
                  SubtitleProvider.values.asNameMap()[row.provider] ??
                  SubtitleProvider.openSubtitles,
              syncedByHash: row.syncedByHash,
              besideFile: row.besideFile,
              release: row.release,
            );
          }
        }
        return settings.preferEmbeddedSubtitles ? _embeddedFor(engine, settings.languages) : null;
      },
      search: (req) async {
        if (!os.hasKey) throw const ThreadingException(ThreadingFailure.noApiKey);
        final key = OpenSubtitlesClient.cacheKey(req);
        final cached = await db.cachedSearch(key);
        if (cached != null) return OpenSubtitlesClient.parseSearch(cached);
        final body = await os.searchRaw(req);
        await db.putSearch(key, body);
        return OpenSubtitlesClient.parseSearch(body);
      },
      subdl: settings.subdlEnabled
          ? (req) async {
              final key = await ref.read(accountProvider.notifier).subdlKey();
              final client = SubdlClient(apiKey: key);
              try {
                return await client.search(req);
              } finally {
                client.client.close();
              }
            }
          : null,
      download: (pick, hash) => _download(file, settings, engine, pick, hash),
    );
  }

  /// An embedded subtitle in a wanted language (best language first; a "forced" track only
  /// covers foreign dialogue, so it never counts). Waits for libmpv to list the tracks.
  Future<EmbeddedSubtitle?> _embeddedFor(PlayerEngine engine, List<String> languages) async {
    if (!await engine.whenLoaded(timeout: const Duration(seconds: 4))) return null;
    final tracks = engine.snapshot.subtitleTracks
        .where((t) => !engine.isExternal(t.id))
        .where((t) => !(t.title ?? '').toLowerCase().contains('forced'))
        .toList();
    for (final lang in languages) {
      final t = tracks.where((t) => languageMatches(t.language, lang)).firstOrNull;
      if (t != null) return EmbeddedSubtitle(mpvTrackId: t.id, language: lang, title: t.title);
    }
    return null;
  }

  Future<DownloadOutcome> _download(
    OpenedFile file,
    Settings settings,
    PlayerEngine engine,
    ScoredCandidate pick,
    MovieHash? hash,
  ) async {
    final c = pick.candidate;
    final db = ref.read(databaseProvider);
    Uint8List bytes;
    var ext = 'srt';
    int? remaining;
    DateTime? reset;
    if (c.provider == SubtitleProvider.subdl) {
      final client = SubdlClient();
      final ZipText z;
      try {
        z = await client.download(c.id);
      } finally {
        client.client.close();
      }
      bytes = z.bytes;
      if (!z.name.toLowerCase().endsWith('.srt')) ext = 'ass';
    } else {
      final os = ref.read(openSubtitlesProvider);
      if (!os.hasKey) throw const ThreadingException(ThreadingFailure.noApiKey);
      try {
        final link = await os.requestDownload(c.id);
        remaining = link.remaining;
        reset = link.resetUtc;
        ref.read(quotaProvider.notifier).afterDownload(link.remaining, link.resetUtc);
        bytes = await os.fetchLink(link.link);
      } on ThreadingException catch (e) {
        if (e.failure == ThreadingFailure.unauthorized) {
          ref.read(accountProvider.notifier).markExpired();
        }
        if (e.failure == ThreadingFailure.quotaExhausted) {
          ref.read(quotaProvider.notifier).afterDownload(0, null);
        }
        rethrow;
      }
    }
    final written = await writeSidecar(
      file,
      language: c.language,
      bytes: bytes,
      besideFile: settings.saveBesideFile,
      extension: ext,
    );
    if (hash != null) {
      await db.putCachedSubtitle(
        hash: hash,
        language: c.language,
        provider: c.provider.name,
        sidecarPath: written.path,
        syncedByHash: c.moviehashMatch,
        besideFile: written.besideFile,
        fileId: c.id,
        release: c.release,
      );
    }
    // A download that lands after its film was closed must not retitle the next one.
    final feature = c.feature;
    final cur = state;
    if (feature?.title != null && cur != null && cur.engine == engine && cur.mediaId != null) {
      await db.setTitle(cur.mediaId!, feature!.title!, feature.year);
      final now = state;
      if (now != null && now.engine == engine) state = now.copyWith(title: feature.title);
    }
    return DownloadOutcome(
      attached: ExternalSubtitle(
        path: written.path,
        language: c.language,
        provider: c.provider,
        syncedByHash: c.moviehashMatch,
        besideFile: written.besideFile,
        release: c.release,
      ),
      remaining: remaining,
      resetUtc: reset,
    );
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

  void _onThreading(PlayerEngine engine, ThreadingState t) {
    final cur = state;
    if (cur == null || cur.engine != engine) return;
    state = cur.copyWith(threading: t);
    if (t.phase != LeaderPhase.done) return;
    if (!_attachedOnce) {
      _attachedOnce = true;
      final a = t.attached;
      unawaited(() async {
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
      }());
    }
    if (!cur.started) unawaited(_begin(engine));
  }

  /// House lights fully down: the film starts — at the resume point, which a notice offers
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

  /// The volume slider, wheel, keys and swipes. Remembered for the next film.
  Future<void> setVolume(double v) async {
    final engine = state?.engine;
    if (engine == null) return;
    final value = v.clamp(0, Settings.maxVolume).toDouble();
    await engine.setVolume(value);
    _volumeSave?.cancel();
    _volumeSave = Timer(const Duration(milliseconds: 800), () => unawaited(_persistVolume(value)));
  }

  Future<void> _persistVolume(double v) async {
    final s = ref.read(settingsProvider).value;
    if (s == null || s.volume == v) return;
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(volume: v));
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

  /// L: set A, then B (the loop starts), then clear.
  Future<void> toggleLoop() async {
    final cur = state;
    if (cur == null) return;
    final pos = cur.engine.player.state.position;
    if (cur.loopA == null) {
      state = cur.copyWith(loopA: pos);
      await cur.engine.setLoop(pos, null);
      ref
          .read(noticeProvider.notifier)
          .show('Loop start set at ${shortClock(pos)} — press L again for the end.');
    } else if (cur.loopB == null) {
      final a = pos < cur.loopA! ? pos : cur.loopA!;
      final b = pos < cur.loopA! ? cur.loopA! : pos;
      if (b - a < const Duration(milliseconds: 500)) return;
      state = cur.copyWith(loopA: a, loopB: b);
      await cur.engine.setLoop(a, b);
      ref.read(noticeProvider.notifier).show('Looping ${shortClock(a)} – ${shortClock(b)}');
    } else {
      state = cur.copyWith(clearLoop: true);
      await cur.engine.setLoop(null, null);
      ref.read(noticeProvider.notifier).show('Loop off');
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

  Future<void> _saveResume() async {
    final cur = state;
    final key = cur?.threading.hash ?? _resumeKey;
    if (cur == null || key == null || !cur.started || cur.engine.isDisposed) return;
    final s = cur.engine.snapshot;
    if (s.duration == Duration.zero) return;
    final pos = s.completed ? s.duration : s.position;
    if (pos == Duration.zero) return; // never overwrite a resume point before playback moved
    await ref.read(databaseProvider).saveResume(key, pos.inMilliseconds, s.duration.inMilliseconds);
  }

  /// House lights up: save, grab the Lobby frame, dispose the Player, back to the Lobby.
  Future<void> close({bool toLobby = true}) async {
    final cur = state;
    _resumeTimer?.cancel();
    _undecodable?.cancel();
    _thumbTimer?.cancel();
    _sleepTimer?.cancel();
    unawaited(_completedSub?.cancel());
    _completedSub = null;
    _machine?.dispose();
    _machine = null;
    if (cur == null) return;
    await _saveResume();
    if (cur.started && cur.error == null) await _grabThumbnail(cur.engine);
    if (_volumeSave?.isActive ?? false) {
      _volumeSave!.cancel();
      await _persistVolume(cur.engine.player.state.volume);
    }
    state = null;
    ref.read(boothOpenProvider.notifier).set(false);
    ref.read(cueSheetProvider.notifier).set(false);
    if (toLobby) {
      ref.read(fullscreenProvider.notifier).set(false);
      ref.read(roomProvider.notifier).go(Room.lobby);
    }
    await cur.engine.dispose();
  }

  String exportName() =>
      'marquee-library-${DateTime.now().toIso8601String().substring(0, 10)}.json';
}

final sessionProvider = NotifierProvider<SessionNotifier, FilmSession?>(SessionNotifier.new);

/// position/duration/tracks at 10 Hz — never 60.
final playbackProvider = StreamProvider<PlaybackState>((ref) {
  final engine = ref.watch(sessionProvider.select((s) => s?.engine));
  if (engine == null) return Stream.value(const PlaybackState());
  return engine.states;
});

String prettyJson(Object? o) => const JsonEncoder.withIndent('  ').convert(o);
