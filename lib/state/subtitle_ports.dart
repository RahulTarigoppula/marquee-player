// What the threading machine may touch for ONE open film: the sidecar beside it, the hash
// cache, the film's own embedded tracks, the OpenSubtitles / Subdl search and the download
// that writes the sidecar. Built by the session; the machine (lib/engine) stays pure.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/opensubtitles.dart';
import '../api/subdl.dart';
import '../engine/models/models.dart';
import '../engine/playback.dart';
import '../engine/threading.dart';
import '../platform/files.dart';
import '../player/engine.dart';
import 'providers.dart';

class SubtitlePorts {
  final Ref ref;
  final OpenedFile file;
  final Settings settings;
  final PlayerEngine engine;

  /// The first rung knows the hash (or that there is none): record the media row then.
  final Future<void> Function(MovieHash? hash) onHashKnown;

  /// A download named the film: retitle it, if it is still the one playing.
  final Future<void> Function(String title, int? year) onFeatureTitle;

  const SubtitlePorts({
    required this.ref,
    required this.file,
    required this.settings,
    required this.engine,
    required this.onHashKnown,
    required this.onFeatureTitle,
  });

  ThreadingPorts build(Future<MovieHash> Function() hash) => ThreadingPorts(
    hash: hash,
    findExisting: _findExisting,
    search: _search,
    subdl: settings.subdlEnabled ? _subdl : null,
    download: _download,
  );

  /// A request needs the saved key and sign-in; a film opened at launch may get here first.
  Future<void> _keys() => ref.read(accountProvider.notifier).untilKeysRestored();

  Future<SubtitleTrackRef?> _findExisting(MovieHash? hash) async {
    await onHashKnown(hash);
    final side = await findSidecar(file, settings.languages);
    if (side != null) {
      return ExternalSubtitle(
        path: side,
        language: settings.languages.first,
        provider: SubtitleProvider.sidecar,
        syncedByHash: false,
      );
    }
    if (hash != null) {
      final row = await ref
          .read(databaseProvider)
          .cachedSubtitle(hash, settings.languages, exists: fileExists);
      if (row != null) {
        return ExternalSubtitle(
          path: row.sidecarPath,
          language: row.language,
          provider:
              SubtitleProvider.values.asNameMap()[row.provider] ?? SubtitleProvider.openSubtitles,
          syncedByHash: row.syncedByHash,
          besideFile: row.besideFile,
          release: row.release,
        );
      }
    }
    return settings.preferEmbeddedSubtitles ? _embedded() : null;
  }

  /// An embedded subtitle in a wanted language (best language first; a "forced" track only
  /// covers foreign dialogue, so it never counts). Waits for libmpv to list the tracks.
  Future<EmbeddedSubtitle?> _embedded() async {
    if (!await engine.whenLoaded(timeout: const Duration(seconds: 4))) return null;
    final tracks = engine.snapshot.subtitleTracks
        .where((t) => !engine.isExternal(t.id))
        .where((t) => !(t.title ?? '').toLowerCase().contains('forced'))
        .toList();
    for (final lang in settings.languages) {
      final t = tracks.where((t) => languageMatches(t.language, lang)).firstOrNull;
      if (t != null) return EmbeddedSubtitle(mpvTrackId: t.id, language: lang, title: t.title);
    }
    return null;
  }

  Future<List<SubtitleCandidate>> _search(SearchRequest req) async {
    await _keys();
    final os = ref.read(openSubtitlesProvider);
    if (!os.hasKey) throw const ThreadingException(ThreadingFailure.noApiKey);
    final db = ref.read(databaseProvider);
    final key = OpenSubtitlesClient.cacheKey(req);
    final cached = await db.cachedSearch(key);
    if (cached != null) return OpenSubtitlesClient.parseSearch(cached);
    final body = await os.searchRaw(req);
    await db.putSearch(key, body);
    return OpenSubtitlesClient.parseSearch(body);
  }

  Future<List<SubtitleCandidate>> _subdl(SearchRequest req) async {
    await _keys();
    final key = await ref.read(accountProvider.notifier).subdlKey();
    final client = SubdlClient(apiKey: key);
    try {
      return await client.search(req);
    } finally {
      client.client.close();
    }
  }

  Future<DownloadOutcome> _download(ScoredCandidate pick, MovieHash? hash) async {
    final c = pick.candidate;
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
      await _keys();
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
      await ref
          .read(databaseProvider)
          .putCachedSubtitle(
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
    final title = c.feature?.title;
    if (title != null) await onFeatureTitle(title, c.feature!.year);
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
}
