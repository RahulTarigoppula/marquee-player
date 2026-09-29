enum LobbyTheme { auto, auditorium, matinee } // playback is ALWAYS auditorium

enum LibraryScanMode { none, folders, mediaStore }

class BiasStops {
  final List<int> argb; // exactly 5, by population then darkened duplicates
  final DateTime sampledAt;
  const BiasStops({required this.argb, required this.sampledAt});
}

class Settings {
  static const maxLanguages = 3;

  final List<String> languages; // max 3, ISO 639-1, ordered by preference
  final bool preferHearingImpaired;
  final bool saveBesideFile;
  final bool subdlEnabled;
  final bool tmdbEnabled;
  final bool roomTone, biasLight, beam, sounds, haptics;
  final LobbyTheme lobbyTheme;
  final String hwdec; // 'auto-safe' | 'no'
  final LibraryScanMode scanMode;

  const Settings({
    this.languages = const ['en'],
    this.preferHearingImpaired = false,
    this.saveBesideFile = true,
    this.subdlEnabled = false,
    this.tmdbEnabled = false,
    this.roomTone = false,
    this.biasLight = true,
    this.beam = true,
    this.sounds = true,
    this.haptics = true,
    this.lobbyTheme = LobbyTheme.auto,
    this.hwdec = 'auto-safe',
    this.scanMode = LibraryScanMode.none,
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
  };

  /// Unknown fields are ignored and missing ones keep their defaults (the import rule, §5.5).
  factory Settings.fromJson(Map<String, Object?> j) {
    const d = Settings();
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    final langs = j['languages'];
    return Settings(
      languages: langs is List
          ? langs.whereType<String>().take(maxLanguages).toList()
          : d.languages,
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
    );
  }
}
