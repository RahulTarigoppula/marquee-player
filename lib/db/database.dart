import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../engine/models/models.dart';
import 'tables.dart';

part 'database.g.dart';

/// How many films the Home rail asks for, newest first. The Library does not stop there: see
/// [MarqueeDatabase.playedMarks].
const int kLobbyRailLimit = 200;

const Duration kSearchCacheTtl = Duration(hours: 24);
const Duration kArtworkTtl = Duration(days: 180); // TMDB terms: never cache longer than 6 months

@DriftDatabase(
  tables: [
    MediaFiles,
    HashCache,
    ResumePoints,
    SyncOffsets,
    Folders,
    Artwork,
    SearchCache,
    AppState,
    FilePrefs,
  ],
)
class MarqueeDatabase extends _$MarqueeDatabase {
  MarqueeDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(filePrefs);
    },
    // Only what every query needs. The artwork sweep runs after the first frame (main.dart):
    // opening the database is on the cold-start path.
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );

  // ───────────────────────────── media files ─────────────────────────────

  /// The same film at a new path UPDATES the row (matched by hash), never duplicates it.
  Future<int> upsertMedia({
    required String locator,
    required String displayName,
    required int sizeBytes,
    MovieHash? hash,
    String origin = 'localPath',
    String? title,
    int? year,
  }) async {
    final now = clock.now();
    MediaRow? existing = await (select(
      mediaFiles,
    )..where((t) => t.locator.equals(locator))).getSingleOrNull();
    if (existing == null && hash != null) {
      existing =
          await (select(mediaFiles)
                ..where((t) => t.moviehash.equals(hash.value))
                ..limit(1))
              .getSingleOrNull();
    }
    final data = MediaFilesCompanion(
      locator: Value(locator),
      displayName: Value(displayName),
      sizeBytes: Value(sizeBytes),
      moviehash: Value(hash?.value ?? existing?.moviehash),
      origin: Value(origin),
      title: Value(title ?? existing?.title),
      year: Value(year ?? existing?.year),
      lastPlayedAt: Value(now),
    );
    if (existing == null) {
      return into(mediaFiles).insert(data.copyWith(addedAt: Value(now)));
    }
    await (update(mediaFiles)..where((t) => t.id.equals(existing!.id))).write(data);
    return existing.id;
  }

  Future<void> updateProbe(
    int id, {
    int? durationMs,
    double? fps,
    String? container,
    int? width,
    int? height,
  }) => (update(mediaFiles)..where((t) => t.id.equals(id))).write(
    MediaFilesCompanion(
      durationMs: Value.absentIfNull(durationMs),
      fps: Value.absentIfNull(fps),
      container: Value.absentIfNull(container),
      width: Value.absentIfNull(width),
      height: Value.absentIfNull(height),
    ),
  );

  Future<void> setTitle(int id, String title, int? year) =>
      (update(mediaFiles)..where((t) => t.id.equals(id))).write(
        MediaFilesCompanion(title: Value(title), year: Value(year)),
      );

  Future<void> removeMedia(int id) => (delete(mediaFiles)..where((t) => t.id.equals(id))).go();

  /// The fingerprint this locator had the last time it was opened, if it was hashed then.
  Future<MovieHash?> hashForLocator(String locator) async {
    final row = await (select(
      mediaFiles,
    )..where((t) => t.locator.equals(locator))).getSingleOrNull();
    final h = row?.moviehash;
    return h == null || h.isEmpty ? null : MovieHash(h);
  }

  Future<int?> mediaIdFor(String locator) async =>
      (await (select(mediaFiles)..where((t) => t.locator.equals(locator))).getSingleOrNull())?.id;

  /// Reactive Lobby rail: media ⋈ resume ⋈ offsets, with the cached subtitle language as a
  /// correlated subquery (the hash_cache primary key answers it). ONE query per change, and a
  /// subtitle download refreshes the card too: hash_cache is one of the watched tables.
  Stream<List<LobbyCard>> watchLobby({int limit = kLobbyRailLimit}) {
    final language = subqueryExpression<String>(
      selectOnly(hashCache)
        ..addColumns([hashCache.language])
        ..where(hashCache.moviehash.equalsExp(mediaFiles.moviehash))
        ..limit(1),
    );
    final q =
        select(mediaFiles).join([
            leftOuterJoin(resumePoints, resumePoints.moviehash.equalsExp(mediaFiles.moviehash)),
            leftOuterJoin(syncOffsets, syncOffsets.moviehash.equalsExp(mediaFiles.moviehash)),
          ])
          ..addColumns([language])
          ..orderBy([OrderingTerm.desc(mediaFiles.lastPlayedAt)])
          ..limit(limit);
    return q.watch().map(
      (rows) => [for (final row in rows) _card(row, language: row.read(language))],
    );
  }

  LobbyCard _card(TypedResult row, {String? language}) {
    final m = row.readTable(mediaFiles);
    final rp = row.readTableOrNull(resumePoints);
    final so = row.readTableOrNull(syncOffsets);
    return LobbyCard(
      id: m.id,
      locator: m.locator,
      displayName: m.displayName,
      title: m.title,
      year: m.year,
      container: m.container,
      durationMs: m.durationMs,
      hash: m.moviehash == null ? null : MovieHash(m.moviehash!),
      resumeFraction: _resumeFraction(rp?.positionMs, rp?.durationMs, m.durationMs),
      resumePositionMs: rp?.positionMs,
      finished: rp != null && isFinished(rp.positionMs, rp.durationMs),
      delayMs: so?.delayMs,
      subtitleLanguage: language,
      lastPlayedAt: m.lastPlayedAt,
    );
  }

  /// How far in a film is, 0 to 1, from its resume row ([positionMs] is null without one). The
  /// length saved with the position counts before the one the file was probed with.
  static double _resumeFraction(int? positionMs, int? resumeDurationMs, int? mediaDurationMs) {
    final dur = resumeDurationMs ?? mediaDurationMs ?? 0;
    return positionMs == null || dur == 0 ? 0 : (positionMs / dur).clamp(0.0, 1.0);
  }

  /// What the Library needs to mark a video as part-watched or watched, for EVERY file ever
  /// played: the Home rail stops at [kLobbyRailLimit], and a library video played longer ago
  /// than that used to lose its progress line and its tick. Narrow on purpose (seven columns,
  /// one join, no subtitle look-up, no order): this can be thousands of rows. The cards carry
  /// no title, sync offset, subtitle language or play date.
  Future<List<LobbyCard>> playedMarks() async {
    final q =
        selectOnly(mediaFiles).join([
          leftOuterJoin(
            resumePoints,
            resumePoints.moviehash.equalsExp(mediaFiles.moviehash),
            useColumns: false,
          ),
        ])..addColumns([
          mediaFiles.id,
          mediaFiles.locator,
          mediaFiles.displayName,
          mediaFiles.moviehash,
          mediaFiles.durationMs,
          resumePoints.positionMs,
          resumePoints.durationMs,
        ]);
    final marks = <LobbyCard>[];
    for (final row in await q.get()) {
      final hash = row.read(mediaFiles.moviehash);
      final durationMs = row.read(mediaFiles.durationMs);
      // Both null when the film has no resume row (the join found nothing).
      final positionMs = row.read(resumePoints.positionMs);
      final resumeDurationMs = row.read(resumePoints.durationMs);
      marks.add(
        LobbyCard(
          id: row.read(mediaFiles.id)!,
          locator: row.read(mediaFiles.locator)!,
          displayName: row.read(mediaFiles.displayName)!,
          durationMs: durationMs,
          hash: hash == null ? null : MovieHash(hash),
          resumeFraction: _resumeFraction(positionMs, resumeDurationMs, durationMs),
          resumePositionMs: positionMs,
          finished:
              positionMs != null &&
              resumeDurationMs != null &&
              isFinished(positionMs, resumeDurationMs),
        ),
      );
    }
    return marks;
  }

  Future<MediaRow?> latestPlayed() =>
      (select(mediaFiles)
            ..orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)])
            ..limit(1))
          .getSingleOrNull();

  // ───────────────────────────── hash cache ─────────────────────────────

  /// A hit only if the cached file still exists; a vanished sidecar invalidates the row.
  Future<HashCacheRow?> cachedSubtitle(
    MovieHash hash,
    List<String> languages, {
    required Future<bool> Function(String path) exists,
  }) async {
    for (final lang in languages) {
      final row = await (select(
        hashCache,
      )..where((t) => t.moviehash.equals(hash.value) & t.language.equals(lang))).getSingleOrNull();
      if (row == null) continue;
      if (await exists(row.sidecarPath)) return row;
      await (delete(
        hashCache,
      )..where((t) => t.moviehash.equals(hash.value) & t.language.equals(lang))).go();
    }
    return null;
  }

  Future<void> putCachedSubtitle({
    required MovieHash hash,
    required String language,
    required String provider,
    required String sidecarPath,
    required bool syncedByHash,
    required bool besideFile,
    String? fileId,
    String? release,
  }) => into(hashCache).insertOnConflictUpdate(
    HashCacheCompanion.insert(
      moviehash: hash.value,
      language: language,
      provider: provider,
      sidecarPath: sidecarPath,
      syncedByHash: syncedByHash,
      besideFile: Value(besideFile),
      fileId: Value(fileId),
      release: Value(release),
      fetchedAt: clock.now(),
    ),
  );

  // ───────────────────────────── resume + sync ─────────────────────────────

  /// A film within [kFinishedWithinMs] of its end counts as watched ([isFinishedAt], the one
  /// rule). Stored as position = duration (not 0, which used to mean both "finished" and
  /// "opened and closed at once").
  static bool isFinished(int positionMs, int durationMs) => isFinishedAt(positionMs, durationMs);

  Future<void> saveResume(MovieHash hash, int positionMs, int durationMs) {
    return into(resumePoints).insertOnConflictUpdate(
      ResumePointsCompanion.insert(
        moviehash: hash.value,
        positionMs: isFinished(positionMs, durationMs) ? durationMs : positionMs,
        durationMs: durationMs,
        at: clock.now(),
      ),
    );
  }

  Future<ResumePoint?> resumeFor(MovieHash hash) async {
    final r = await (select(
      resumePoints,
    )..where((t) => t.moviehash.equals(hash.value))).getSingleOrNull();
    return r == null
        ? null
        : ResumePoint(hash: hash, positionMs: r.positionMs, durationMs: r.durationMs, at: r.at);
  }

  Future<void> saveOffset(MovieHash hash, int delayMs) => delayMs == 0
      ? (delete(syncOffsets)..where((t) => t.moviehash.equals(hash.value))).go()
      : into(syncOffsets).insertOnConflictUpdate(
          SyncOffsetsCompanion.insert(moviehash: hash.value, delayMs: delayMs),
        );

  Future<int> offsetFor(MovieHash hash) async =>
      (await (select(
        syncOffsets,
      )..where((t) => t.moviehash.equals(hash.value))).getSingleOrNull())?.delayMs ??
      0;

  // ───────────────────────────── per-film preferences ─────────────────────────────

  /// The viewer's choices for one film (see [FilePrefs]); null when nothing was ever chosen.
  Future<Map<String, Object?>?> filePrefsFor(MovieHash hash) async {
    final r = await (select(
      filePrefs,
    )..where((t) => t.moviehash.equals(hash.value))).getSingleOrNull();
    if (r == null) return null;
    try {
      final v = jsonDecode(r.prefsJson);
      return v is Map<String, Object?> ? v : null;
    } on FormatException {
      return null;
    }
  }

  /// An empty map forgets the film's preferences.
  Future<void> saveFilePrefs(MovieHash hash, Map<String, Object?> prefs) => prefs.isEmpty
      ? (delete(filePrefs)..where((t) => t.moviehash.equals(hash.value))).go()
      : into(filePrefs).insertOnConflictUpdate(
          FilePrefsCompanion.insert(
            moviehash: hash.value,
            prefsJson: jsonEncode(prefs),
            at: clock.now(),
          ),
        );

  // ───────────────────────────── library folders ─────────────────────────────

  /// The folders the device library scans (Windows paths), oldest first.
  Stream<List<String>> watchFolders() => (select(folders)..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch()
      .map((rows) => [for (final r in rows) r.locator]);

  Future<List<String>> libraryFolders() async => [
    for (final r in await (select(folders)..orderBy([(t) => OrderingTerm.asc(t.id)])).get())
      r.locator,
  ];

  Future<void> addFolder(String locator) => into(
    folders,
  ).insert(FoldersCompanion.insert(locator: locator), mode: InsertMode.insertOrIgnore);

  Future<void> removeFolder(String locator) =>
      (delete(folders)..where((t) => t.locator.equals(locator))).go();

  // ───────────────────────────── search cache ─────────────────────────────

  Future<String?> cachedSearch(String key) async {
    final r = await (select(searchCache)..where((t) => t.queryKey.equals(key))).getSingleOrNull();
    if (r == null) return null;
    if (clock.now().difference(r.fetchedAt) > kSearchCacheTtl) {
      await (delete(searchCache)..where((t) => t.queryKey.equals(key))).go();
      return null;
    }
    return r.bodyJson;
  }

  Future<void> putSearch(String key, String body) => into(searchCache).insertOnConflictUpdate(
    SearchCacheCompanion.insert(queryKey: key, bodyJson: body, fetchedAt: clock.now()),
  );

  // ───────────────────────────── artwork ─────────────────────────────

  Future<void> putArtwork(int tmdbId, {String? poster, String? backdrop, int? accent}) {
    final now = clock.now();
    return into(artwork).insertOnConflictUpdate(
      ArtworkCompanion.insert(
        tmdbId: Value(tmdbId),
        posterPath: Value(poster),
        backdropPath: Value(backdrop),
        accentArgb: Value(accent),
        fetchedAt: now,
        expiresAt: now.add(kArtworkTtl),
      ),
    );
  }

  /// Startup sweep: nothing older than 180 days survives a launch.
  Future<int> sweepArtwork() =>
      (delete(artwork)..where((t) => t.expiresAt.isSmallerOrEqualValue(clock.now()))).go();

  // ───────────────────────────── app state ─────────────────────────────

  Future<Object?> readState(String key) async {
    final text = await readStateText(key);
    return text == null ? null : jsonDecode(text);
  }

  Future<void> writeState(String key, Object? value) => writeStateText(key, jsonEncode(value));

  /// A value as its stored JSON text, undecoded: for the one value large enough (the library
  /// cache, thousands of rows) that the caller decodes it off the UI isolate.
  Future<String?> readStateText(String key) async =>
      (await (select(appState)..where((t) => t.key.equals(key))).getSingleOrNull())?.valueJson;

  /// Stores [json], which must already be JSON text (see [readStateText]).
  Future<void> writeStateText(String key, String json) =>
      into(appState).insertOnConflictUpdate(AppStateCompanion.insert(key: key, valueJson: json));

  Future<Settings> readSettings() async {
    final v = await readState('settings');
    return v is Map<String, Object?> ? Settings.fromJson(v) : const Settings();
  }

  Future<void> writeSettings(Settings s) => writeState('settings', s.toJson());

  // ───────────────────────────── export / import (§5.5) ─────────────────────────────

  static const exportFormat = 'marquee.library.v1';

  Future<Map<String, Object?>> exportLibrary({
    required String version,
    required String platform,
  }) async {
    String iso(DateTime? d) => d?.toUtc().toIso8601String() ?? '';
    return {
      'format': exportFormat,
      'exportedAt': clock.now().toUtc().toIso8601String(),
      'app': {'version': version, 'platform': platform},
      'mediaFiles': [
        for (final m in await select(mediaFiles).get())
          {
            'locator': m.locator,
            'displayName': m.displayName,
            'sizeBytes': m.sizeBytes,
            'moviehash': m.moviehash,
            'title': m.title,
            'year': m.year,
            'container': m.container,
            'durationMs': m.durationMs,
            'fps': m.fps,
            'addedAt': iso(m.addedAt),
            'lastPlayedAt': iso(m.lastPlayedAt),
          },
      ],
      'resumePoints': [
        for (final r in await select(resumePoints).get())
          {
            'hash': r.moviehash,
            'positionMs': r.positionMs,
            'durationMs': r.durationMs,
            'at': iso(r.at),
          },
      ],
      'syncOffsets': [
        for (final s in await select(syncOffsets).get())
          {'hash': s.moviehash, 'delayMs': s.delayMs},
      ],
      'hashCache': [
        for (final h in await select(hashCache).get())
          {
            'hash': h.moviehash,
            'language': h.language,
            'provider': h.provider,
            'fileId': h.fileId,
            'release': h.release,
            'sidecarPath': h.sidecarPath,
            'syncedByHash': h.syncedByHash,
          },
      ],
      // What the viewer chose per film (audio track, second subtitle, picture), and the
      // folders the library scans. Added without a new format id: a reader only looks up the
      // keys it knows, so an older build skips these two.
      'filePrefs': [
        for (final f in await select(filePrefs).get())
          if (_prefsOf(f.prefsJson) case final prefs?)
            {'hash': f.moviehash, 'prefs': prefs, 'at': iso(f.at)},
      ],
      'folders': await libraryFolders(),
      'settings': (await readSettings()).toJson(),
      'windowBounds': await readState('window_bounds'),
      'seenGateNudge': await readState('seen_gate_nudge'),
    };
  }

  /// A film's stored preferences as a JSON object; null when the text is not one.
  static Map<String, Object?>? _prefsOf(String json) {
    try {
      final v = jsonDecode(json);
      return v is Map<String, Object?> && v.isNotEmpty ? v : null;
    } on FormatException {
      return null;
    }
  }

  /// Merge, never replace. A newer `at` wins; unknown fields are ignored; secrets never travel.
  ///
  /// [importFolders] adds the export's library folders to this device's (never removes one).
  /// They are Windows paths: the caller passes true only where folders are what the library
  /// is made of (Windows), and an Android import leaves them out.
  Future<void> importLibrary(Map<String, Object?> j, {bool importFolders = false}) async {
    if (j['format'] != exportFormat) {
      throw const FormatException("That file isn't a Marquee library export.");
    }
    List<Map<String, Object?>> rows(String k) =>
        (j[k] is List ? j[k]! as List : const []).whereType<Map<String, Object?>>().toList();
    DateTime? dt(Object? v) => v is String ? DateTime.tryParse(v) : null;

    await transaction(() async {
      for (final m in rows('mediaFiles')) {
        final locator = m['locator'];
        if (locator is! String) continue;
        final exists = await (select(
          mediaFiles,
        )..where((t) => t.locator.equals(locator))).getSingleOrNull();
        if (exists != null) continue;
        await into(mediaFiles).insert(
          MediaFilesCompanion.insert(
            locator: locator,
            displayName: m['displayName'] as String? ?? locator,
            sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
            moviehash: Value(m['moviehash'] as String?),
            title: Value(m['title'] as String?),
            year: Value((m['year'] as num?)?.toInt()),
            container: Value(m['container'] as String?),
            durationMs: Value((m['durationMs'] as num?)?.toInt()),
            fps: Value((m['fps'] as num?)?.toDouble()),
            addedAt: dt(m['addedAt']) ?? clock.now(),
            lastPlayedAt: Value(dt(m['lastPlayedAt'])),
          ),
        );
      }
      for (final r in rows('resumePoints')) {
        final hash = r['hash'];
        final at = dt(r['at']);
        if (hash is! String || at == null) continue;
        final cur = await (select(
          resumePoints,
        )..where((t) => t.moviehash.equals(hash))).getSingleOrNull();
        if (cur != null && !cur.at.isBefore(at)) continue;
        await into(resumePoints).insertOnConflictUpdate(
          ResumePointsCompanion.insert(
            moviehash: hash,
            positionMs: (r['positionMs'] as num?)?.toInt() ?? 0,
            durationMs: (r['durationMs'] as num?)?.toInt() ?? 0,
            at: at,
          ),
        );
      }
      for (final s in rows('syncOffsets')) {
        final hash = s['hash'];
        final d = s['delayMs'];
        if (hash is String && d is num) await saveOffset(MovieHash(hash), d.toInt());
      }
      for (final h in rows('hashCache')) {
        final hash = h['hash'];
        final lang = h['language'];
        final path = h['sidecarPath'];
        if (hash is! String || lang is! String || path is! String) continue;
        await into(hashCache).insertOnConflictUpdate(
          HashCacheCompanion.insert(
            moviehash: hash,
            language: lang,
            provider: h['provider'] as String? ?? 'openSubtitles',
            sidecarPath: path,
            syncedByHash: h['syncedByHash'] == true,
            fileId: Value(h['fileId'] as String?),
            release: Value(h['release'] as String?),
            fetchedAt: clock.now(),
          ),
        );
      }
      for (final f in rows('filePrefs')) {
        final hash = f['hash'];
        final prefs = f['prefs'];
        final at = dt(f['at']);
        if (hash is! String || prefs is! Map<String, Object?> || prefs.isEmpty || at == null) {
          continue;
        }
        final cur = await (select(
          filePrefs,
        )..where((t) => t.moviehash.equals(hash))).getSingleOrNull();
        if (cur != null && !cur.at.isBefore(at)) continue;
        await into(filePrefs).insertOnConflictUpdate(
          FilePrefsCompanion.insert(moviehash: hash, prefsJson: jsonEncode(prefs), at: at),
        );
      }
      final exported = j['folders'];
      if (importFolders && exported is List) {
        // The same folder in another letter case is the same folder on Windows.
        final have = {for (final f in await libraryFolders()) f.toLowerCase()};
        for (final folder in exported.whereType<String>()) {
          if (folder.trim().isEmpty || !have.add(folder.toLowerCase())) continue;
          await addFolder(folder);
        }
      }
      final settings = j['settings'];
      if (settings is Map<String, Object?>) {
        final cur = (await readSettings()).toJson()..addAll(settings);
        await writeSettings(Settings.fromJson(cur));
      }
      if (j['windowBounds'] != null) await writeState('window_bounds', j['windowBounds']);
      if (j['seenGateNudge'] != null) await writeState('seen_gate_nudge', j['seenGateNudge']);
    });
  }
}
