// The open film: one PlayerEngine + one ThreadingMachine, wired to the cache, the sidecar
// writer and the API. Libmpv opens the file CONCURRENTLY with the leader's phases.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/opensubtitles.dart';
import '../api/subdl.dart';
import '../engine/filename.dart';
import '../engine/hash.dart';
import '../engine/models/models.dart';
import '../engine/threading.dart';
import '../platform/files.dart';
import '../player/engine.dart';
import 'providers.dart';

const Duration kResumeSaveEvery = Duration(seconds: 5);
const Duration kUndecodableAfter = Duration(seconds: 5);

class FilmSession {
  final OpenedFile file;
  final PlayerEngine engine;
  final ThreadingState threading;
  final ParsedName? parsed;
  final int? mediaId;
  final int delayMs;
  final List<Chapter> chapters;
  final String? title;
  final String? error; // "This print can't be projected." — never a code

  const FilmSession({
    required this.file,
    required this.engine,
    this.threading = const ThreadingState(),
    this.parsed,
    this.mediaId,
    this.delayMs = 0,
    this.chapters = const [],
    this.title,
    this.error,
  });

  bool get threadingVisible =>
      threading.phase != LeaderPhase.done && threading.phase != LeaderPhase.idle;

  String get displayTitle => title ?? parsed?.title ?? file.displayName;

  FilmSession copyWith({
    ThreadingState? threading,
    int? mediaId,
    int? delayMs,
    List<Chapter>? chapters,
    String? title,
    String? error,
  }) => FilmSession(
    file: file,
    engine: engine,
    threading: threading ?? this.threading,
    parsed: parsed,
    mediaId: mediaId ?? this.mediaId,
    delayMs: delayMs ?? this.delayMs,
    chapters: chapters ?? this.chapters,
    title: title ?? this.title,
    error: error ?? this.error,
  );
}

class SessionNotifier extends Notifier<FilmSession?> {
  ThreadingMachine? _machine;
  Timer? _resumeTimer;
  Timer? _undecodable;
  bool _attachedOnce = false;

  @override
  FilmSession? build() {
    // The machine holds its own quota; keep it current (sign-in, restore, sign-out) or a pick
    // after signing in is refused as "no tickets" without a request.
    ref.listen(quotaProvider, (_, q) => _machine?.setQuota(q));
    ref.onDispose(() {
      _resumeTimer?.cancel();
      _undecodable?.cancel();
      _machine?.dispose();
    });
    return null;
  }

  ThreadingMachine? get machine => _machine;

  Future<void> open(OpenedFile file) async {
    if (state != null) await close(toLobby: false);
    final settings = await ref.read(settingsProvider.future);
    final db = ref.read(databaseProvider);
    final parsed = file.isContentUri ? parseName(file.displayName) : parsePath(file.locator);
    final engine = PlayerEngine(hwdec: settings.hwdec);
    _attachedOnce = false;
    state = FilmSession(file: file, engine: engine, parsed: parsed);
    ref.read(roomProvider.notifier).go(Room.auditorium);

    // Libmpv warms up while the leader counts.
    unawaited(_startPlayback(engine, file));

    final machine = ThreadingMachine(
      ports: _ports(file, settings),
      config: ThreadingConfig(
        languages: settings.languages,
        preferHearingImpaired: settings.preferHearingImpaired,
        subdlEnabled: settings.subdlEnabled,
      ),
      quota: ref.read(quotaProvider),
      onChange: _onThreading,
    );
    _machine = machine;
    await machine.open(displayName: file.displayName, sizeBytes: file.sizeBytes, parsed: parsed);
    unawaited(db.sweepArtwork());
  }

  bool _isCurrent(PlayerEngine engine) => state?.engine == engine && !engine.isDisposed;

  Future<void> _startPlayback(PlayerEngine engine, OpenedFile file) async {
    try {
      await engine.open(file.locator);
    } on Object {
      _fail(engine);
      return;
    }
    // Closed or replaced while libmpv was opening: the timers belong to the next film.
    if (!_isCurrent(engine)) return;
    _undecodable?.cancel();
    _undecodable = Timer(kUndecodableAfter, () {
      if (!_isCurrent(engine)) return;
      final s = engine.snapshot;
      if (s.duration == Duration.zero && s.error != null) _fail(engine);
    });
    _resumeTimer?.cancel();
    _resumeTimer = Timer.periodic(kResumeSaveEvery, (_) => unawaited(_saveResume()));
    unawaited(() async {
      // container-fps and chapter-list only exist once the file has loaded.
      if (!await engine.whenLoaded() || !_isCurrent(engine)) return;
      final fps = await engine.containerFps();
      if (!_isCurrent(engine)) return;
      _machine?.setContainerFps(fps);
      final chapters = await engine.chapters();
      final cur = state;
      if (cur != null && cur.engine == engine) state = cur.copyWith(chapters: chapters);
    }());
  }

  void _fail(PlayerEngine engine) {
    final cur = state;
    if (cur == null || cur.engine != engine) return;
    _machine?.skip();
    state = cur.copyWith(error: "This print can't be projected.");
  }

  ThreadingPorts _ports(OpenedFile file, Settings settings) {
    final db = ref.read(databaseProvider);
    final os = ref.read(openSubtitlesProvider);
    return ThreadingPorts(
      hash: () async => movieHashOf(await chunkReaderFor(file), file.sizeBytes),
      findExisting: (hash) async {
        await _recordMedia(file, hash);
        final side = findSidecar(file, settings.languages);
        if (side != null) {
          return ExternalSubtitle(
            path: side,
            language: settings.languages.first,
            provider: SubtitleProvider.sidecar,
            syncedByHash: false,
          );
        }
        if (hash == null) return null;
        final row = await db.cachedSubtitle(hash, settings.languages, exists: fileExists);
        if (row == null) return null;
        return ExternalSubtitle(
          path: row.sidecarPath,
          language: row.language,
          provider:
              SubtitleProvider.values.asNameMap()[row.provider] ?? SubtitleProvider.openSubtitles,
          syncedByHash: row.syncedByHash,
          besideFile: row.besideFile,
          release: row.release,
        );
      },
      search: (req) async {
        if (!os.hasKey) throw const ThreadingException(ThreadingFailure.noResults);
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
      download: (pick, hash) => _download(file, settings, pick, hash),
    );
  }

  Future<DownloadOutcome> _download(
    OpenedFile file,
    Settings settings,
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
      if (!os.hasKey) throw const ThreadingException(ThreadingFailure.noResults);
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
    final feature = c.feature;
    final id = state?.mediaId;
    if (feature?.title != null && id != null) {
      await db.setTitle(id, feature!.title!, feature.year);
      final cur = state;
      if (cur != null) state = cur.copyWith(title: feature.title);
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

  Future<void> _recordMedia(OpenedFile file, MovieHash? hash) async {
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
    var delay = 0;
    Duration? resumeAt;
    if (hash != null) {
      delay = await db.offsetFor(hash);
      final rp = await db.resumeFor(hash);
      if (rp != null && rp.positionMs > 0 && !rp.finished) {
        resumeAt = Duration(milliseconds: rp.positionMs);
      }
    }
    final cur = state;
    if (cur == null || cur.file != file) return;
    state = cur.copyWith(mediaId: id, delayMs: delay);
    final engine = cur.engine;
    if (delay != 0) await engine.setSubDelayMs(delay);
    final at = resumeAt;
    if (at != null) {
      // The hash resolves in ~40 ms, usually before libmpv has loaded the file: wait for a
      // duration before seeking, or the seek is silently dropped. NOT awaited — rung 0 (the
      // sidecar and the cache) must not wait for libmpv.
      unawaited(() async {
        try {
          if (!await engine.whenLoaded(timeout: kUndecodableAfter)) return;
          if (_isCurrent(engine)) await engine.player.seek(at);
        } on Object {
          // Closed mid-seek: nothing to resume.
        }
      }());
    }
  }

  void _onThreading(ThreadingState t) {
    final cur = state;
    if (cur == null) return;
    state = cur.copyWith(threading: t);
    if (t.phase == LeaderPhase.done && !_attachedOnce) {
      _attachedOnce = true;
      final a = t.attached;
      if (a is ExternalSubtitle) {
        final engine = cur.engine;
        unawaited(() async {
          try {
            await engine.attachSubtitle(a.path, language: a.language);
            final now = state;
            final delay = now != null && now.engine == engine ? now.delayMs : 0;
            if (delay != 0) await engine.setSubDelayMs(delay);
          } on Object {
            // The film was closed while the subtitle was being attached.
          }
        }());
      }
    }
  }

  // ───────────────────────────── controls ─────────────────────────────

  Future<void> setDelay(int ms) async {
    final cur = state;
    if (cur == null) return;
    state = cur.copyWith(delayMs: ms);
    await cur.engine.setSubDelayMs(ms);
    final h = cur.threading.hash;
    if (h != null) await ref.read(databaseProvider).saveOffset(h, ms);
  }

  Future<void> pick(ScoredCandidate c) async {
    _attachedOnce = false;
    await _machine?.pick(c);
  }

  Future<void> findAnother(String query) async {
    _attachedOnce = false;
    final m = _machine;
    if (m == null) return;
    if (query.trim().isEmpty) {
      await m.filenameSearch();
    } else {
      await m.manualSearch(query);
    }
  }

  void skipSubtitles() => _machine?.skip();

  Future<void> _saveResume() async {
    final cur = state;
    final h = cur?.threading.hash;
    if (cur == null || h == null) return;
    final s = cur.engine.snapshot;
    if (s.duration == Duration.zero) return;
    await ref
        .read(databaseProvider)
        .saveResume(h, s.position.inMilliseconds, s.duration.inMilliseconds);
  }

  /// House lights up: save, dispose the Player, back to the Lobby.
  Future<void> close({bool toLobby = true}) async {
    final cur = state;
    _resumeTimer?.cancel();
    _undecodable?.cancel();
    _machine?.dispose();
    _machine = null;
    if (cur == null) return;
    await _saveResume();
    state = null;
    if (toLobby) ref.read(roomProvider.notifier).go(Room.lobby);
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
