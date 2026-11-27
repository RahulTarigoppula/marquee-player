enum LobbyTheme { auto, auditorium, matinee } // playback is ALWAYS auditorium

enum LibraryScanMode { none, folders, mediaStore }

/// How subtitles are drawn: an outline (cinema default) or text on a dark box (easier to read
/// over bright scenes).
enum SubtitleLook { outline, box }

/// Where subtitles sit on the picture.
enum SubtitlePlacement { bottom, lowerThird, top }

/// The colour of text subtitles (styled ASS tracks keep their own colours).
enum SubtitleTint {
  white('White', '#FFFFFF'),
  yellow('Yellow', '#FFE14D'),
  warm('Warm', '#FFD9A0');

  final String label;

  /// mpv `sub-color`.
  final String mpvColor;
  const SubtitleTint(this.label, this.mpvColor);
}

/// One-tap sound profiles (a 10-band equaliser underneath, see `lib/engine/audio_fx.dart`).
enum EqPreset {
  flat('Off'),
  voiceBoost('Clear voices'),
  bassBoost('More bass'),
  trebleBoost('More treble'),
  nightMode('Night mode');

  final String label;
  const EqPreset(this.label);
}

/// What happens when a film ends.
enum RepeatMode {
  off('Off'),
  one('Repeat this video'),
  all('Repeat the folder');

  final String label;
  const RepeatMode(this.label);
}

/// The order of the device library.
enum LibrarySort {
  name('Name'),
  newest('Newest first'),
  largest('Largest first'),
  longest('Longest first');

  final String label;
  const LibrarySort(this.label);
}

class BiasStops {
  final List<int> argb; // exactly 5, by population then darkened duplicates
  final DateTime sampledAt;
  const BiasStops({required this.argb, required this.sampledAt});
}

class Settings {
  static const maxLanguages = 3;
  static const minSubtitleScale = 0.6;
  static const maxSubtitleScale = 2.0;

  /// The jump sizes offered for the ±buttons, the arrow keys' big brother and double-tap.
  static const seekSteps = [5, 10, 15, 30];

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

  // ── v2 ──
  final SubtitleTint subtitleTint;

  /// Seconds jumped by the ± buttons and a double-tap (one of [seekSteps]).
  final int seekStepSeconds;

  /// Evens out loud and quiet passages (mpv `dynaudnorm`).
  final bool audioNormalize;
  final EqPreset eqPreset;

  /// Desktop: a small live frame above the seek bar while hovering or dragging it.
  final bool seekPreview;

  /// Phone: a horizontal swipe on the picture scrubs through the film.
  final bool swipeToSeek;

  /// Ask GitHub for a newer release on start-up (off by default: no request without consent).
  final bool autoCheckUpdates;
  final RepeatMode repeat;
  final LibrarySort librarySort;

  /// The clock in the player shows time remaining instead of the total.
  final bool showRemaining;

  /// Android: the film's sound carries on when the screen goes off or another app is in front.
  /// Off, leaving the app pauses the film (the lock-screen controls can still start it again).
  final bool backgroundPlay;

  /// Phone: the one-time picture of the touch gestures has been shown and sent away. It is
  /// never shown unasked again (More › Touch gestures brings it back).
  final bool gestureHintSeen;

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
    this.subtitleTint = SubtitleTint.white,
    this.seekStepSeconds = 10,
    this.audioNormalize = false,
    this.eqPreset = EqPreset.flat,
    this.seekPreview = true,
    this.swipeToSeek = true,
    this.autoCheckUpdates = false,
    this.repeat = RepeatMode.off,
    this.librarySort = LibrarySort.name,
    this.showRemaining = false,
    this.backgroundPlay = false,
    this.gestureHintSeen = false,
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
    SubtitleTint? subtitleTint,
    int? seekStepSeconds,
    bool? audioNormalize,
    EqPreset? eqPreset,
    bool? seekPreview,
    bool? swipeToSeek,
    bool? autoCheckUpdates,
    RepeatMode? repeat,
    LibrarySort? librarySort,
    bool? showRemaining,
    bool? backgroundPlay,
    bool? gestureHintSeen,
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
    subtitleTint: subtitleTint ?? this.subtitleTint,
    seekStepSeconds: _seekStep(seekStepSeconds ?? this.seekStepSeconds),
    audioNormalize: audioNormalize ?? this.audioNormalize,
    eqPreset: eqPreset ?? this.eqPreset,
    seekPreview: seekPreview ?? this.seekPreview,
    swipeToSeek: swipeToSeek ?? this.swipeToSeek,
    autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
    repeat: repeat ?? this.repeat,
    librarySort: librarySort ?? this.librarySort,
    showRemaining: showRemaining ?? this.showRemaining,
    backgroundPlay: backgroundPlay ?? this.backgroundPlay,
    gestureHintSeen: gestureHintSeen ?? this.gestureHintSeen,
  );

  static int _seekStep(int v) => seekSteps.contains(v) ? v : 10;

  /// Value equality, so an unchanged save notifies nobody and `select`ed fields compare
  /// cheaply. Kept in step with [toJson] (every field, nothing else).
  @override
  bool operator ==(Object other) =>
      other is Settings &&
      _sameList(other.languages, languages) &&
      other.preferHearingImpaired == preferHearingImpaired &&
      other.saveBesideFile == saveBesideFile &&
      other.subdlEnabled == subdlEnabled &&
      other.tmdbEnabled == tmdbEnabled &&
      other.roomTone == roomTone &&
      other.biasLight == biasLight &&
      other.beam == beam &&
      other.sounds == sounds &&
      other.haptics == haptics &&
      other.lobbyTheme == lobbyTheme &&
      other.hwdec == hwdec &&
      other.scanMode == scanMode &&
      other.subtitleScale == subtitleScale &&
      other.subtitleLook == subtitleLook &&
      other.subtitlePlacement == subtitlePlacement &&
      _sameList(other.audioLanguages, audioLanguages) &&
      other.preferEmbeddedSubtitles == preferEmbeddedSubtitles &&
      other.autoplayNext == autoplayNext &&
      other.volume == volume &&
      other.subtitleTint == subtitleTint &&
      other.seekStepSeconds == seekStepSeconds &&
      other.audioNormalize == audioNormalize &&
      other.eqPreset == eqPreset &&
      other.seekPreview == seekPreview &&
      other.swipeToSeek == swipeToSeek &&
      other.autoCheckUpdates == autoCheckUpdates &&
      other.repeat == repeat &&
      other.librarySort == librarySort &&
      other.showRemaining == showRemaining &&
      other.backgroundPlay == backgroundPlay &&
      other.gestureHintSeen == gestureHintSeen;

  @override
  int get hashCode => Object.hashAll([
    Object.hashAll(languages),
    preferHearingImpaired,
    saveBesideFile,
    subdlEnabled,
    tmdbEnabled,
    roomTone,
    biasLight,
    beam,
    sounds,
    haptics,
    lobbyTheme,
    hwdec,
    scanMode,
    subtitleScale,
    subtitleLook,
    subtitlePlacement,
    Object.hashAll(audioLanguages),
    preferEmbeddedSubtitles,
    autoplayNext,
    volume,
    subtitleTint,
    seekStepSeconds,
    audioNormalize,
    eqPreset,
    seekPreview,
    swipeToSeek,
    autoCheckUpdates,
    repeat,
    librarySort,
    showRemaining,
    backgroundPlay,
    gestureHintSeen,
  ]);

  /// The fields that change how mpv draws text subtitles (size, look, placement, colour).
  ({double scale, SubtitleLook look, SubtitlePlacement placement, SubtitleTint tint})
  get subtitleStyle =>
      (scale: subtitleScale, look: subtitleLook, placement: subtitlePlacement, tint: subtitleTint);

  /// The fields behind mpv's audio filter chain.
  ({bool normalize, EqPreset preset}) get audioFx => (normalize: audioNormalize, preset: eqPreset);

  static bool _sameList(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

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
    'subtitleTint': subtitleTint.name,
    'seekStepSeconds': seekStepSeconds,
    'audioNormalize': audioNormalize,
    'eqPreset': eqPreset.name,
    'seekPreview': seekPreview,
    'swipeToSeek': swipeToSeek,
    'autoCheckUpdates': autoCheckUpdates,
    'repeat': repeat.name,
    'librarySort': librarySort.name,
    'showRemaining': showRemaining,
    'backgroundPlay': backgroundPlay,
    'gestureHintSeen': gestureHintSeen,
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
      subtitleTint: SubtitleTint.values.asNameMap()[j['subtitleTint']] ?? d.subtitleTint,
      seekStepSeconds: _seekStep(num_('seekStepSeconds', d.seekStepSeconds.toDouble()).round()),
      audioNormalize: pick('audioNormalize', d.audioNormalize),
      eqPreset: EqPreset.values.asNameMap()[j['eqPreset']] ?? d.eqPreset,
      seekPreview: pick('seekPreview', d.seekPreview),
      swipeToSeek: pick('swipeToSeek', d.swipeToSeek),
      autoCheckUpdates: pick('autoCheckUpdates', d.autoCheckUpdates),
      repeat: RepeatMode.values.asNameMap()[j['repeat']] ?? d.repeat,
      librarySort: LibrarySort.values.asNameMap()[j['librarySort']] ?? d.librarySort,
      showRemaining: pick('showRemaining', d.showRemaining),
      backgroundPlay: pick('backgroundPlay', d.backgroundPlay),
      gestureHintSeen: pick('gestureHintSeen', d.gestureHintSeen),
    );
  }
}
