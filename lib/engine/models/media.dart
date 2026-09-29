/// 16 lowercase hex chars. A value type so it can never be confused with a path.
extension type const MovieHash(String value) {
  static final _re = RegExp(r'^[0-9a-f]{16}$');
  bool get isValid => _re.hasMatch(value);
}

enum MediaOrigin { localPath, contentUri, commandLine, browserFile }

class MediaFile {
  final int? id;
  final String locator; // Windows path OR Android content:// URI
  final String displayName; // basename — the filename parser's input
  final int sizeBytes;
  final MovieHash? moviehash; // null when sizeBytes < 131072
  final MediaOrigin origin;
  final String? container;
  final int? durationMs;
  final double? fps;
  final int? width, height;
  final String? videoCodec, audioCodec;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;

  const MediaFile({
    this.id,
    required this.locator,
    required this.displayName,
    required this.sizeBytes,
    this.moviehash,
    this.origin = MediaOrigin.localPath,
    this.container,
    this.durationMs,
    this.fps,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    required this.addedAt,
    this.lastPlayedAt,
  });
}

class Chapter {
  final int index;
  final double startSeconds;
  final String? title;
  const Chapter({required this.index, required this.startSeconds, this.title});
}

/// One per MovieHash — survives a move or rename.
class ResumePoint {
  final MovieHash hash;
  final int positionMs;
  final int durationMs;
  final DateTime at;
  const ResumePoint({
    required this.hash,
    required this.positionMs,
    required this.durationMs,
    required this.at,
  });

  double get fraction => durationMs == 0 ? 0 : positionMs / durationMs;
  bool get finished => fraction > 0.97;
}

class SyncOffset {
  final MovieHash hash;
  final int delayMs; // +ve = subtitles appear later
  const SyncOffset({required this.hash, required this.delayMs});
}

/// One row of the Lobby rail.
class LobbyCard {
  final int id;
  final String locator;
  final String displayName;
  final String? title;
  final int? year;
  final String? container;
  final int? durationMs;
  final MovieHash? hash;
  final double resumeFraction;
  final bool finished;
  final int? delayMs;
  final String? subtitleLanguage;
  final DateTime? lastPlayedAt;
  const LobbyCard({
    required this.id,
    required this.locator,
    required this.displayName,
    this.title,
    this.year,
    this.container,
    this.durationMs,
    this.hash,
    this.resumeFraction = 0,
    this.finished = false,
    this.delayMs,
    this.subtitleLanguage,
    this.lastPlayedAt,
  });
}
