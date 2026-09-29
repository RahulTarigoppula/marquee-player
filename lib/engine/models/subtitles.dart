enum NameConfidence { high, medium, low } // low ⇒ send the RAW filename as `query`

enum FeatureKind { movie, episode }

class ParsedName {
  final String title;
  final int? year;
  final int? season, episode;
  final String? resolution;
  final String? source;
  final String? videoCodecToken; // VERBATIM token: 'x264' ≠ 'H264' (R4)
  final String? group;
  final bool remastered, proper, extended;
  final FeatureKind kind;
  final NameConfidence confidence;
  final String raw;

  const ParsedName({
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.resolution,
    this.source,
    this.videoCodecToken,
    this.group,
    this.remastered = false,
    this.proper = false,
    this.extended = false,
    this.kind = FeatureKind.movie,
    this.confidence = NameConfidence.low,
    required this.raw,
  });
}

enum SubtitleProvider { openSubtitles, subdl, embedded, sidecar }

class FeatureDetails {
  final String featureType; // 'Movie' | 'Episode'
  final String? title;
  final int? year;
  final int? seasonNumber, episodeNumber;
  final int? imdbId;
  final int? tmdbId;

  const FeatureDetails({
    required this.featureType,
    this.title,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.imdbId,
    this.tmdbId,
  });

  factory FeatureDetails.fromJson(Map<String, Object?> j) => FeatureDetails(
    featureType: j['feature_type'] as String? ?? 'Movie',
    title: j['title'] as String?,
    year: (j['year'] as num?)?.toInt(),
    seasonNumber: (j['season_number'] as num?)?.toInt(),
    episodeNumber: (j['episode_number'] as num?)?.toInt(),
    imdbId: (j['imdb_id'] as num?)?.toInt(),
    tmdbId: (j['tmdb_id'] as num?)?.toInt(),
  );
}

class SubtitleCandidate {
  final SubtitleProvider provider;
  final String id; // OS: files[0].file_id as String; Subdl: the `url` path
  final String language; // ISO 639-1 lowercase
  final String? release;
  final int downloadCount;
  final bool hearingImpaired;
  final bool moviehashMatch;
  final bool machineTranslated, aiTranslated;
  final double? fps;
  final DateTime? uploadDate;
  final FeatureDetails? feature;

  const SubtitleCandidate({
    required this.provider,
    required this.id,
    required this.language,
    this.release,
    this.downloadCount = 0,
    this.hearingImpaired = false,
    this.moviehashMatch = false,
    this.machineTranslated = false,
    this.aiTranslated = false,
    this.fps,
    this.uploadDate,
    this.feature,
  });

  /// One entry of an OpenSubtitles `/subtitles` response's `data[]`.
  /// Returns null for entries with no downloadable file.
  static SubtitleCandidate? fromOpenSubtitles(Map<String, Object?> entry) {
    final a = entry['attributes'];
    if (a is! Map<String, Object?>) return null;
    final files = a['files'];
    if (files is! List || files.isEmpty) return null;
    final first = files.first;
    if (first is! Map<String, Object?>) return null;
    final fileId = first['file_id'];
    if (fileId is! num) return null;
    final fd = a['feature_details'];
    final fps = (a['fps'] as num?)?.toDouble();
    return SubtitleCandidate(
      provider: SubtitleProvider.openSubtitles,
      id: fileId.toInt().toString(),
      language: (a['language'] as String? ?? '').toLowerCase(),
      release: a['release'] as String?,
      downloadCount: (a['download_count'] as num?)?.toInt() ?? 0,
      hearingImpaired: a['hearing_impaired'] == true,
      moviehashMatch: a['moviehash_match'] == true,
      machineTranslated: a['machine_translated'] == true,
      aiTranslated: a['ai_translated'] == true,
      fps: fps == null || fps == 0 ? null : fps,
      uploadDate: DateTime.tryParse(a['upload_date'] as String? ?? ''),
      feature: fd is Map<String, Object?> ? FeatureDetails.fromJson(fd) : null,
    );
  }
}

/// Output of scoring.dart — never mutates the candidate.
class ScoredCandidate {
  final SubtitleCandidate candidate;
  final double score;
  final List<String> reasons;
  final bool autoPick; // ALWAYS false for machine/AI translated
  const ScoredCandidate({
    required this.candidate,
    required this.score,
    required this.reasons,
    required this.autoPick,
  });
}

/// What is actually attached to the player right now.
sealed class SubtitleTrackRef {
  const SubtitleTrackRef();
}

class NoSubtitle extends SubtitleTrackRef {
  const NoSubtitle();
}

class EmbeddedSubtitle extends SubtitleTrackRef {
  final String mpvTrackId;
  final String? language, title;
  const EmbeddedSubtitle({required this.mpvTrackId, this.language, this.title});
}

class ExternalSubtitle extends SubtitleTrackRef {
  final String path; // sidecar beside the file, or app storage
  final String language;
  final SubtitleProvider provider;
  final bool syncedByHash; // true ⇒ green MATCH bulb; false ⇒ 'BY NAME · CHECK SYNC'
  final bool besideFile; // false ⇒ 'saved in app storage'
  final String? release;
  const ExternalSubtitle({
    required this.path,
    required this.language,
    required this.provider,
    required this.syncedByHash,
    this.besideFile = true,
    this.release,
  });
}
