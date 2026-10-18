import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../engine/models/models.dart';
import 'tables.dart';

part 'database.g.dart';

const Duration kSearchCacheTtl = Duration(hours: 24);
const Duration kArtworkTtl = Duration(days: 180); // TMDB terms: never cache longer than 6 months
const int kFinishedWithinMs = 30000; // a position this close to the end stores as "finished"

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
  ],
)
class MarqueeDatabase extends _$MarqueeDatabase {
  MarqueeDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await sweepArtwork();
    },
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

  Future<int?> mediaIdFor(String locator) async =>
      (await (select(mediaFiles)..where((t) => t.locator.equals(locator))).getSingleOrNull())?.id;

  /// Reactive Lobby rail: media ⋈ resume ⋈ offsets ⋈ cached subtitle language.
  Stream<List<LobbyCard>> watchLobby({int limit = 200}) {
    final q =
        select(mediaFiles).join([
            leftOuterJoin(resumePoints, resumePoints.moviehash.equalsExp(mediaFiles.moviehash)),
            leftOuterJoin(syncOffsets, syncOffsets.moviehash.equalsExp(mediaFiles.moviehash)),
          ])
          ..orderBy([OrderingTerm.desc(mediaFiles.lastPlayedAt)])
          ..limit(limit);
    return q.watch().asyncMap((rows) async {
      final langs = <String, String>{};
      for (final r in await select(hashCache).get()) {
        langs.putIfAbsent(r.moviehash, () => r.language);
      }
      return [
        for (final row in rows)
          () {
            final m = row.readTable(mediaFiles);
            final rp = row.readTableOrNull(resumePoints);
            final so = row.readTableOrNull(syncOffsets);
            final dur = rp?.durationMs ?? m.durationMs ?? 0;
            return LobbyCard(
              id: m.id,
              locator: m.locator,
              displayName: m.displayName,
              title: m.title,
              year: m.year,
              container: m.container,
              durationMs: m.durationMs,
              hash: m.moviehash == null ? null : MovieHash(m.moviehash!),
              resumeFraction: rp == null || dur == 0 ? 0 : (rp.positionMs / dur).clamp(0.0, 1.0),
              finished: rp != null && isFinished(rp.positionMs, rp.durationMs),
              delayMs: so?.delayMs,
              subtitleLanguage: m.moviehash == null ? null : langs[m.moviehash],
              lastPlayedAt: m.lastPlayedAt,
            );
          }(),
      ];
    });
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

  /// A film within [kFinishedWithinMs] of its end counts as watched. Stored as position =
  /// duration (not 0, which used to mean both "finished" and "opened and closed at once").
  static bool isFinished(int positionMs, int durationMs) =>
      durationMs > 0 && positionMs > 0 && durationMs - positionMs <= kFinishedWithinMs;

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
    final r = await (select(appState)..where((t) => t.key.equals(key))).getSingleOrNull();
    return r == null ? null : jsonDecode(r.valueJson);
  }

  Future<void> writeState(String key, Object? value) => into(
    appState,
  ).insertOnConflictUpdate(AppStateCompanion.insert(key: key, valueJson: jsonEncode(value)));

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
      'settings': (await readSettings()).toJson(),
      'windowBounds': await readState('window_bounds'),
      'seenGateNudge': await readState('seen_gate_nudge'),
    };
  }

  /// Merge, never replace. A newer `at` wins; unknown fields are ignored; secrets never travel.
  Future<void> importLibrary(Map<String, Object?> j) async {
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
