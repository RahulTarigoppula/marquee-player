enum LobbyTheme { auto, auditorium, matinee } // playback is ALWAYS auditorium

enum LibraryScanMode { none, folders, mediaStore }

/// How subtitles are drawn: an outline (cinema default) or text on a dark box (easier to read
/// over bright scenes).
enum SubtitleLook { outline, box }

/// Where subtitles sit on the picture.
enum SubtitlePlacement { bottom, lowerThird, top }

class BiasStops {
  final List<int> argb; // exactly 5, by population then darkened duplicates
  final DateTime sampledAt;
  const BiasStops({required this.argb, required this.sampledAt});
}

class Settings {
  static const maxLanguages = 3;
  static const minSubtitleScale = 0.6;
  static const maxSubtitleScale = 2.0;

  final List<String> languages; // max 3, ISO 639-1, ordered by preference
  final bool preferHearingImpaired;
  final bool saveBesideFile;
  final bool subdlEnabled;
  final bool tmdbEnabled;
  final bool roomTone, biasLight, beam, sounds, haptics;
  final LobbyTheme lobbyTheme;
  final String hwdec; // 'auto-safe' | 'no'
  final LibraryScanMode scanMode;

  // ── playback & subtitle preferences (pass 2) ──
  /// Subtitle size multiplier (mpv `sub-scale`), [minSubtitleScale]..[maxSubtitleScale].
  final double subtitleScale;
  final SubtitleLook subtitleLook;
  final SubtitlePlacement subtitlePlacement;

  /// Preferred audio languages (ISO 639-1), best first; empty = the file's default track.
  final List<String> audioLanguages;

  /// Use an embedded subtitle track in a preferred language instead of searching online.
  final bool preferEmbeddedSubtitles;

  /// When a film ends, play the next file in the same folder (series, playlists).
  final bool autoplayNext;

  /// Last volume (0..[maxVolume]), restored on the next film.
  final double volume;
  static const maxVolume = 150.0;

  const Settings({
    this.languages = const ['en'],
    this.preferHearingImpaired = false,
    this.saveBesideFile = true,
    this.subdlEnabled = false,
    this.tmdbEnabled = false,
    this.roomTone = false,
    this.biasLight = false,
    this.beam = true,
    this.sounds = true,
    this.haptics = true,
    this.lobbyTheme = LobbyTheme.auto,
    this.hwdec = 'auto-safe',
    this.scanMode = LibraryScanMode.none,
    this.subtitleScale = 1.0,
    this.subtitleLook = SubtitleLook.outline,
    this.subtitlePlacement = SubtitlePlacement.bottom,
    this.audioLanguages = const [],
    this.preferEmbeddedSubtitles = true,
    this.autoplayNext = true,
    this.volume = 100,
  });

  Settings copyWith({
    List<String>? languages,
    bool? preferHearingImpaired,
    bool? saveBesideFile,
    bool? subdlEnabled,
    bool? tmdbEnabled,
    bool? roomTone,
    bool? biasLight,
    bool? beam,
    bool? sounds,
    bool? haptics,
    LobbyTheme? lobbyTheme,
    String? hwdec,
    LibraryScanMode? scanMode,
    double? subtitleScale,
    SubtitleLook? subtitleLook,
    SubtitlePlacement? subtitlePlacement,
    List<String>? audioLanguages,
    bool? preferEmbeddedSubtitles,
    bool? autoplayNext,
    double? volume,
  }) => Settings(
    languages: languages ?? this.languages,
    preferHearingImpaired: preferHearingImpaired ?? this.preferHearingImpaired,
    saveBesideFile: saveBesideFile ?? this.saveBesideFile,
    subdlEnabled: subdlEnabled ?? this.subdlEnabled,
    tmdbEnabled: tmdbEnabled ?? this.tmdbEnabled,
    roomTone: roomTone ?? this.roomTone,
    biasLight: biasLight ?? this.biasLight,
    beam: beam ?? this.beam,
    sounds: sounds ?? this.sounds,
    haptics: haptics ?? this.haptics,
    lobbyTheme: lobbyTheme ?? this.lobbyTheme,
    hwdec: hwdec ?? this.hwdec,
    scanMode: scanMode ?? this.scanMode,
    subtitleScale: (subtitleScale ?? this.subtitleScale).clamp(minSubtitleScale, maxSubtitleScale),
    subtitleLook: subtitleLook ?? this.subtitleLook,
    subtitlePlacement: subtitlePlacement ?? this.subtitlePlacement,
    audioLanguages: audioLanguages ?? this.audioLanguages,
    preferEmbeddedSubtitles: preferEmbeddedSubtitles ?? this.preferEmbeddedSubtitles,
    autoplayNext: autoplayNext ?? this.autoplayNext,
    volume: (volume ?? this.volume).clamp(0, maxVolume),
  );

  Map<String, Object?> toJson() => {
    'languages': languages,
    'preferHearingImpaired': preferHearingImpaired,
    'saveBesideFile': saveBesideFile,
    'subdlEnabled': subdlEnabled,
    'tmdbEnabled': tmdbEnabled,
    'roomTone': roomTone,
    'biasLight': biasLight,
    'beam': beam,
    'sounds': sounds,
    'haptics': haptics,
    'lobbyTheme': lobbyTheme.name,
    'hwdec': hwdec,
    'scanMode': scanMode.name,
    'subtitleScale': subtitleScale,
    'subtitleLook': subtitleLook.name,
    'subtitlePlacement': subtitlePlacement.name,
    'audioLanguages': audioLanguages,
    'preferEmbeddedSubtitles': preferEmbeddedSubtitles,
    'autoplayNext': autoplayNext,
    'volume': volume,
  };

  /// Unknown fields are ignored and missing ones keep their defaults (the import rule, §5.5).
  factory Settings.fromJson(Map<String, Object?> j) {
    const d = Settings();
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    double num_(String k, double fallback) => j[k] is num ? (j[k] as num).toDouble() : fallback;
    List<String> langs(String k, List<String> fallback) {
      final v = j[k];
      return v is List ? v.whereType<String>().take(maxLanguages).toList() : fallback;
    }

    return Settings(
      languages: langs('languages', d.languages),
      preferHearingImpaired: pick('preferHearingImpaired', d.preferHearingImpaired),
      saveBesideFile: pick('saveBesideFile', d.saveBesideFile),
      subdlEnabled: pick('subdlEnabled', d.subdlEnabled),
      tmdbEnabled: pick('tmdbEnabled', d.tmdbEnabled),
      roomTone: pick('roomTone', d.roomTone),
      biasLight: pick('biasLight', d.biasLight),
      beam: pick('beam', d.beam),
      sounds: pick('sounds', d.sounds),
      haptics: pick('haptics', d.haptics),
      lobbyTheme: LobbyTheme.values.asNameMap()[j['lobbyTheme']] ?? d.lobbyTheme,
      hwdec: pick('hwdec', d.hwdec),
      scanMode: LibraryScanMode.values.asNameMap()[j['scanMode']] ?? d.scanMode,
      subtitleScale: num_(
        'subtitleScale',
        d.subtitleScale,
      ).clamp(minSubtitleScale, maxSubtitleScale).toDouble(),
      subtitleLook: SubtitleLook.values.asNameMap()[j['subtitleLook']] ?? d.subtitleLook,
      subtitlePlacement:
          SubtitlePlacement.values.asNameMap()[j['subtitlePlacement']] ?? d.subtitlePlacement,
      audioLanguages: langs('audioLanguages', d.audioLanguages),
      preferEmbeddedSubtitles: pick('preferEmbeddedSubtitles', d.preferEmbeddedSubtitles),
      autoplayNext: pick('autoplayNext', d.autoplayNext),
      volume: num_('volume', d.volume).clamp(0, maxVolume).toDouble(),
    );
  }
}
