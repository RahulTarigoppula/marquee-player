// The single media_kit Player + VideoController, and the mpv property bridge (§8.1).
// Load-bearing: never set vo=mediacodec_embed (it silently disables libass on Android).
import 'dart:async';
import 'dart:io' show Directory, File, FileSystemEntityType, Platform;
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../engine/audio_fx.dart';
import '../engine/models/media.dart';
import '../engine/models/settings.dart';
import '../engine/picture.dart';
import '../engine/playback.dart';

const Duration kStreamThrottle = Duration(milliseconds: 100); // 10 Hz, never 60

class PlaybackState {
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final bool playing;
  final bool buffering;
  final bool completed;
  final double rate;
  final double volume;
  final bool muted;
  final List<AudioTrack> audioTracks;
  final List<SubtitleTrack> subtitleTracks;

  /// mpv's own `aid` / `sid` ('no' when off). media_kit only knows what WE selected, so the
  /// engine observes these instead: they are the truth, auto-selection included.
  final String? audioId;
  final String? subtitleId;

  /// mpv's `secondary-sid`: a second text subtitle drawn at the top ('no' when off).
  final String? secondarySubtitleId;
  final int width, height;
  final String? error;

  const PlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.rate = 1,
    this.volume = 100,
    this.muted = false,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.audioId,
    this.subtitleId,
    this.secondarySubtitleId,
    this.width = 0,
    this.height = 0,
    this.error,
  });

  AudioTrack? get audio => audioTracks.where((t) => t.id == audioId).firstOrNull;
  SubtitleTrack? get subtitle => subtitleTracks.where((t) => t.id == subtitleId).firstOrNull;

  bool get hasSubtitle => _isTrack(subtitleId);

  bool get hasSecondarySubtitle => _isTrack(secondarySubtitleId);

  static bool _isTrack(String? id) => id != null && id.isNotEmpty && id != 'no' && id != 'auto';
}

/// A subtitle drawn as a bitmap (PGS, VobSub, DVB): libass is not involved.
bool isBitmapSubtitle(SubtitleTrack? t) {
  if (t == null) return false;
  if (t.image == true) return true;
  final c = (t.codec ?? '').toLowerCase();
  return c.contains('pgs') || c.contains('dvd') || c.contains('dvb') || c.contains('vobsub');
}

class PlayerEngine {
  final Player player;
  late final VideoController controller;
  final _state = StreamController<PlaybackState>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _throttle;
  bool _dirty = false;
  bool _disposed = false;
  String? _lastError;
  String? _aid;
  String? _sid;
  String? _sid2;
  bool _muted = false;

  /// What mpv was last sent, so a slider drag sets one property, not seven.
  final _pictureSent = {...PictureAdjust.neutral.mpvProperties};

  /// The `af` chain mpv accepted ('' = none).
  String _audioFx = '';

  /// path → mpv track id of every external file we `sub-add`ed, so a second attach of the
  /// same file selects the existing track instead of adding a duplicate.
  final _external = <String, String>{};

  /// Android only: the text subtitle is drawn by Flutter (system fonts) instead of libass,
  /// which only knows the one bundled Noto Sans and shows tofu for Arabic, Hindi, CJK, …
  final systemFontSubtitles = EngineFlag();

  /// Loads libmpv (a large native library) once. main() calls it after the first frame so
  /// the Lobby never waits for it; the first film calls it too, in case it comes sooner.
  static void ensureInitialized() {
    if (_libraryReady) return;
    MediaKit.ensureInitialized();
    _libraryReady = true;
  }

  static bool _libraryReady = false;

  static Player _newPlayer() {
    ensureInitialized();
    return Player(
      configuration: const PlayerConfiguration(
        title: 'Marquee',
        libass: true,
        libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf',
        libassAndroidFontName: 'Noto Sans', // the TTF's INTERNAL family name
        bufferSize: 64 * 1024 * 1024,
      ),
    );
  }

  PlayerEngine({String hwdec = 'auto-safe'}) : player = _newPlayer() {
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        // Android keeps media_kit's own default (it forces software decoding on emulators).
        hwdec: hwdec == 'no' ? 'no' : (Platform.isAndroid ? null : hwdec),
        enableHardwareAcceleration: hwdec != 'no',
      ),
    );
    // media_kit creates the video output in a post-frame callback, and every player call
    // (open, play, even dispose) waits for it. Unseen (the screen off, the window minimised)
    // Flutter draws no frames, so a film opened from the lock screen or by "Up next" would
    // wait for ever. A warm-up frame runs whatever the lifecycle says.
    final scheduler = SchedulerBinding.instance;
    if (!scheduler.framesEnabled) scheduler.scheduleWarmUpFrame();
    final s = player.stream;
    for (final stream in <Stream<Object?>>[
      s.position,
      s.duration,
      s.buffer,
      s.playing,
      s.buffering,
      s.completed,
      s.rate,
      s.volume,
      s.tracks,
      s.width,
      s.height,
    ]) {
      _subs.add(stream.listen((_) => _markDirty()));
    }
    _subs.add(s.error.listen((e) => _lastError = e));
    if (Platform.isAndroid) {
      _subs.add(
        s.subtitle.listen((lines) {
          if (!systemFontSubtitles.value && needsSystemFonts(lines.join('\n'))) {
            unawaited(_useSystemFonts(true));
          }
        }),
      );
    }
  }

  Stream<PlaybackState> get states => _state.stream;

  PlaybackState get snapshot {
    final st = player.state;
    _syncTracks(st.tracks);
    return PlaybackState(
      position: st.position,
      duration: st.duration,
      buffer: st.buffer,
      playing: st.playing,
      buffering: st.buffering,
      completed: st.completed,
      rate: st.rate,
      volume: st.volume,
      muted: _muted,
      audioTracks: _audioTracks,
      subtitleTracks: _subtitleTracks,
      audioId: _aid,
      subtitleId: _sid,
      secondarySubtitleId: _sid2,
      width: st.width ?? 0,
      height: st.height ?? 0,
      error: _lastError,
    );
  }

  // The track lists are rebuilt only when mpv's own list changes, so consecutive snapshots
  // share them and a `select` on the tracks (menus, the Booth) sees "unchanged" between ticks.
  Tracks? _tracksSeen;
  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];

  void _syncTracks(Tracks tracks) {
    if (identical(tracks, _tracksSeen)) return;
    _tracksSeen = tracks;
    bool real(String id) => id != 'auto' && id != 'no';
    _audioTracks = List.unmodifiable(tracks.audio.where((t) => real(t.id)));
    _subtitleTracks = List.unmodifiable(tracks.subtitle.where((t) => real(t.id)));
  }

  /// At most one snapshot per [kStreamThrottle], and none at all while nothing changes (a
  /// paused film has no timer running).
  void _markDirty() {
    _dirty = true;
    _throttle ??= Timer(kStreamThrottle, () {
      _throttle = null;
      if (!_dirty || _disposed) return;
      _dirty = false;
      _state.add(snapshot);
    });
  }

  NativePlayer? get _native =>
      player.platform is NativePlayer ? player.platform as NativePlayer : null;

  bool get isDisposed => _disposed;

  Future<void> _set(String name, String value) async {
    if (_disposed) return;
    try {
      await _native?.setProperty(name, value);
    } on Object {
      // An option this libmpv build does not know: the default stays.
    }
  }

  Future<void> _command(List<String> args) async {
    if (_disposed) return;
    try {
      await _native?.command(args);
    } on Object {
      // A command mpv refused (no file loaded, a bad path): nothing to undo.
    }
  }

  /// Everything that must be in place before the file opens: volume range, the remembered
  /// volume, audio language preference, subtitle look, and the track observers.
  Future<void> configure(Settings s) async {
    final n = _native;
    if (n == null) return;
    await _set('volume-max', Settings.maxVolume.toStringAsFixed(0));
    await _set('volume', s.volume.toStringAsFixed(0));
    if (s.audioLanguages.isNotEmpty) {
      await _set('alang', mpvLanguageList(s.audioLanguages).join(','));
    }
    // Marquee attaches the file beside the film itself (rung 0): left on, mpv would add the
    // same file a second time. An embedded track is only worth showing in a wanted language.
    // media_kit asks mpv to fall back to ANY first track (a commentary, signs and songs).
    // mpv's own default is kinder: a wanted language, else only a track the file itself
    // marks as its default (which also covers the usual single untagged track).
    await _set('sub-auto', 'no');
    await _set('subs-fallback', 'default');
    if (s.languages.isNotEmpty) await _set('slang', mpvLanguageList(s.languages).join(','));
    if (Platform.isWindows) {
      // The installed app ships Noto Sans beside the exe; libass finds the rest of the world's
      // scripts through DirectWrite's fallback.
      final fonts = p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        'assets',
        'fonts',
      );
      if (await Directory(fonts).exists()) await _set('sub-fonts-dir', fonts);
      await _set('sub-font', 'Noto Sans');
    }
    await applySubtitleStyle(s);
    try {
      await n.observeProperty('aid', (v) async {
        _aid = v;
        _markDirty();
      });
      await n.observeProperty('sid', (v) async {
        _sid = v;
        await _syncSubtitleVisibility();
        _markDirty();
      });
      await n.observeProperty('secondary-sid', (v) async {
        _sid2 = v;
        _markDirty();
      });
      await n.observeProperty('mute', (v) async {
        _muted = v == 'yes';
        _markDirty();
      });
    } on Object {
      // Observing twice (a second configure) is harmless.
    }
  }

  Future<void> open(String locator, {Duration? start, bool play = false}) async {
    _lastError = null;
    // media_kit switches mpv's stream cache on for everything, 64 MiB ahead and 64 MiB behind,
    // and asks for it on disk. That is right for a link and wasteful for a file: up to 128 MiB
    // of a phone's memory, and a long read after every seek on an SD card or a network share.
    // A file on the device gets mpv's own rule back (cache network streams only).
    final lower = locator.toLowerCase();
    final local =
        !lower.contains('://') || lower.startsWith('content://') || lower.startsWith('file://');
    if (local) {
      await _set('cache', 'auto');
      await _set('cache-on-disk', 'no');
    }
    await player.open(Media(locator, start: start), play: play);
  }

  /// Completes true once libmpv has loaded the file (a duration is known). `open()` returns
  /// before that, and `sub-add`, `seek` and the chapter/fps properties are lost or unavailable
  /// until then. False on timeout or when the engine is disposed first.
  Future<bool> whenLoaded({Duration timeout = const Duration(seconds: 10)}) async {
    if (_disposed) return false;
    if (player.state.duration > Duration.zero) return true;
    try {
      await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(timeout);
      return !_disposed;
    } on Object {
      // Timed out, or the stream closed because the player was disposed. A live stream never
      // has a length: it counts as loaded once mpv lists its tracks ("auto" and "no" are
      // always there, so more than two means real ones).
      if (_disposed) return false;
      final t = player.state.tracks;
      return t.video.length > 2 || t.audio.length > 2;
    }
  }

  // ───────────────────────────── transport ─────────────────────────────

  Future<void> play() async {
    if (!_disposed) await player.play();
  }

  Future<void> pause() async {
    if (!_disposed) await player.pause();
  }

  Future<void> playOrPause() async {
    if (!_disposed) await player.playOrPause();
  }

  /// Absolute seek, clamped to the film.
  Future<void> seekTo(Duration target) async {
    if (_disposed) return;
    await player.seek(clampSeek(target, player.state.duration));
  }

  /// Relative seek for buttons, double-taps and (held) arrow keys: mpv coalesces queued
  /// relative seeks, so a held key accumulates instead of re-seeking from a stale position.
  Future<void> seekBy(Duration delta) async {
    if (_disposed) return;
    final st = player.state;
    final target = st.position + delta;
    if (st.duration > Duration.zero && target >= st.duration - const Duration(seconds: 1)) {
      await seekTo(target); // clamps one second short of the end
      return;
    }
    await _command(['seek', (delta.inMilliseconds / 1000).toStringAsFixed(3), 'relative']);
  }

  Future<void> setRate(double rate) async {
    if (!_disposed) await player.setRate(rate.clamp(kMinSpeed, kMaxSpeed));
  }

  /// "Repeat this video": mpv starts the file again by itself and never reports an end.
  Future<void> setLoopFile(bool on) => _set('loop-file', on ? 'inf' : 'no');

  Future<void> setVolume(double v) async {
    if (_disposed) return;
    await player.setVolume(v.clamp(0, Settings.maxVolume).toDouble());
    if (_muted && v > 0) await setMuted(false);
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    _markDirty();
    await _set('mute', muted ? 'yes' : 'no');
  }

  Future<void> toggleMute() => setMuted(!_muted);

  bool get muted => _muted;

  // ───────────────────────────── tracks ─────────────────────────────

  Future<void> selectAudio(String id) => _set('aid', id);

  Future<void> selectSubtitle(String id) async {
    await _set('sid', id);
    final t = snapshot.subtitleTracks.where((t) => t.id == id).firstOrNull;
    if (isNonLatinLanguage(t?.language)) await _useSystemFonts(true);
  }

  Future<void> subtitlesOff() => _set('sid', 'no');

  /// A second text subtitle (mpv draws it at the top), or null for none. On Android the
  /// Flutter-drawn path (system_subtitles.dart) only ever draws the primary: a second one in
  /// a script the bundled font lacks stays with libass and shows boxes. That is the trade.
  Future<void> setSecondarySubtitle(String? id) => _set('secondary-sid', id ?? 'no');

  /// The ids mpv itself lists for [type] ('audio' or 'sub'), asked directly: media_kit's own
  /// track list arrives a moment after the file loads, too late for restoring a remembered one.
  Future<Set<String>> trackIds(String type) async {
    final count = int.tryParse(await property('track-list/count') ?? '') ?? 0;
    return {
      for (var i = 0; i < count; i++)
        if (await property('track-list/$i/type') == type) ?await property('track-list/$i/id'),
    };
  }

  /// The mpv track id an external file was added as, if it was.
  String? externalIdFor(String path) => _external[path];

  bool isExternal(String id) => _external.containsValue(id);

  /// Adds (once) and selects an external subtitle — only after the file has loaded, or mpv
  /// drops it.
  Future<void> attachSubtitle(String path, {String? language, String? title}) async {
    if (!await whenLoaded()) return;
    final known = _external[path];
    if (known != null && snapshot.subtitleTracks.any((t) => t.id == known)) {
      await _set('sid', known);
    } else {
      await _command([
        'sub-add',
        path,
        'select',
        title ?? (language ?? p.basename(path)).toUpperCase(),
        ?language,
      ]);
      final sid = await property('sid');
      if (sid != null && sid != 'no') {
        _sid = sid;
        _external[path] = sid;
        _markDirty();
      }
    }
    if (isNonLatinLanguage(language)) await _useSystemFonts(true);
  }

  Future<void> setSubDelayMs(int ms) => _set('sub-delay', (ms / 1000).toStringAsFixed(2));

  Future<void> setAudioDelayMs(int ms) => _set('audio-delay', (ms / 1000).toStringAsFixed(2));

  // ───────────────────────────── picture and sound ─────────────────────────────

  /// Levels, rotation, zoom and deinterlacing. Only what changed is sent; a property this
  /// libmpv build lacks is skipped and the picture stays as it was.
  Future<void> applyPicture(PictureAdjust picture) async {
    for (final MapEntry(key: name, :value) in picture.mpvProperties.entries) {
      if (_pictureSent[name] == value) continue;
      _pictureSent[name] = value;
      await _set(name, value);
    }
  }

  /// The equaliser preset and loudness evening as mpv's `af` chain. False when this libmpv
  /// build refused it (a filter it was built without): the chain is then cleared, so the film
  /// keeps its sound, and the caller says so. Call it once the file has loaded: a chain set
  /// before the audio output exists is only checked later, and a refusal then costs the sound.
  Future<bool> applyAudioFx(({bool normalize, EqPreset preset}) fx) =>
      // One at a time: two quick taps must not interleave their clear / set / read back.
      _audioFxTail = _audioFxTail.then((_) => _applyAudioFx(fx));

  Future<bool> _audioFxTail = Future.value(true);

  Future<bool> _applyAudioFx(({bool normalize, EqPreset preset}) fx) async {
    final want = audioFilterChain(normalize: fx.normalize, preset: fx.preset);
    if (_disposed || _native == null || want == _audioFx) return true;
    // Through the `af` COMMAND, never the property: a property write only checks the outer
    // syntax and keeps a chain the build cannot make (which costs the sound at the next audio
    // re-init), while the command builds the chain now and rolls back when it cannot. So clear
    // first: whatever is read back afterwards is the new chain or nothing.
    if (_audioFx.isNotEmpty) await _command(['af', 'clr', '']);
    _audioFx = '';
    if (want.isEmpty) return true;
    await _command(['af', 'set', want]);
    final got = await property('af');
    if (got != null && got.trim().isNotEmpty) {
      _audioFx = want;
      return true;
    }
    await _command(['af', 'clr', '']);
    return false;
  }

  /// "Fill (crop)" cuts [percent] of the picture off the top and bottom: the subtitle line
  /// moves in by as much (see [subtitleOffsets]). Zero puts it back.
  Future<void> setSubtitleCrop(double percent) async {
    if (percent == _subtitleCrop) return;
    _subtitleCrop = percent;
    await _placeSubtitles();
  }

  double _subtitleCrop = 0;
  SubtitlePlacement _placement = SubtitlePlacement.bottom;

  Future<void> _placeSubtitles() async {
    final at = subtitleOffsets(_placement, _subtitleCrop);
    await _set('sub-align-y', _placement == SubtitlePlacement.top ? 'top' : 'bottom');
    await _set('sub-pos', '${at.subPos}');
    await _set('sub-margin-y', '${at.marginY}');
  }

  /// Size, look, placement and colour for every text subtitle of every film.
  Future<void> applySubtitleStyle(Settings s) async {
    await _set('sub-scale', s.subtitleScale.toStringAsFixed(2));
    await _set('sub-color', s.subtitleTint.mpvColor);
    switch (s.subtitleLook) {
      case SubtitleLook.outline:
        await _set('sub-border-style', 'outline-and-shadow');
        await _set('sub-border-size', '3');
        await _set('sub-shadow-offset', '1');
        await _set('sub-outline-color', '#000000');
        await _set('sub-border-color', '#000000'); // the pre-0.38 name of the same option
      case SubtitleLook.box:
        // opaque-box draws the outline as a box in the outline colour.
        await _set('sub-border-style', 'opaque-box');
        await _set('sub-border-size', '6');
        await _set('sub-shadow-offset', '0');
        await _set('sub-outline-color', '#C0000000');
        await _set('sub-border-color', '#C0000000');
        await _set('sub-back-color', '#C0000000');
    }
    _placement = s.subtitlePlacement;
    await _placeSubtitles();
  }

  /// Android: hand text subtitles to Flutter (system fonts). Bitmap subtitles stay with mpv.
  Future<void> _useSystemFonts(bool on) async {
    if (!Platform.isAndroid || _disposed || systemFontSubtitles.value == on) return;
    systemFontSubtitles.value = on;
    await _syncSubtitleVisibility();
  }

  /// Android: a subtitle language the bundled font cannot draw switches before the first cue.
  Future<void> hintSubtitleLanguage(String? language) async {
    if (isNonLatinLanguage(language)) await _useSystemFonts(true);
  }

  Future<void> _syncSubtitleVisibility() async {
    if (!Platform.isAndroid) return;
    final bitmap = isBitmapSubtitle(snapshot.subtitle);
    await _set('sub-visibility', systemFontSubtitles.value && !bitmap ? 'no' : 'yes');
  }

  /// True while Flutter must draw the current subtitle (see [systemFontSubtitles]).
  bool get drawsSubtitlesInFlutter =>
      Platform.isAndroid && systemFontSubtitles.value && !isBitmapSubtitle(snapshot.subtitle);

  // ───────────────────────────── properties ─────────────────────────────

  Future<String?> property(String name) async {
    if (_disposed) return null;
    try {
      return await _native?.getProperty(name);
    } on Object {
      return null;
    }
  }

  Future<double?> containerFps() async => double.tryParse(await property('container-fps') ?? '');

  Future<List<Chapter>> chapters() async {
    final count = int.tryParse(await property('chapter-list/count') ?? '') ?? 0;
    return [
      for (var i = 0; i < count; i++)
        Chapter(
          index: i,
          startSeconds: double.tryParse(await property('chapter-list/$i/time') ?? '') ?? 0,
          title: await property('chapter-list/$i/title'),
        ),
    ];
  }

  /// Raw values for the video details overlay ([kDetailProperties] by name). Whatever mpv
  /// does not know (no audio track, an older build) is left out.
  Future<Map<String, String>> stats() async {
    final out = <String, String>{};
    for (final name in kDetailProperties) {
      final v = await property(name);
      if (v != null && v.isNotEmpty) out[name] = v;
    }
    return out;
  }

  /// What the Lobby card shows: container, width × height.
  Future<({String? container, int? width, int? height})> probe() async {
    final container = await property('file-format');
    return (
      container: container == null || container.isEmpty ? null : container,
      width: int.tryParse(await property('width') ?? ''),
      height: int.tryParse(await property('height') ?? ''),
    );
  }

  Future<void> frameStep({required bool forward}) =>
      _command([forward ? 'frame-step' : 'frame-back-step']);

  /// A–B loop: both points set ⇒ loops; null clears that point.
  Future<void> setLoop(Duration? a, Duration? b) async {
    await _set('ab-loop-a', a == null ? 'no' : (a.inMilliseconds / 1000).toStringAsFixed(3));
    await _set('ab-loop-b', b == null ? 'no' : (b.inMilliseconds / 1000).toStringAsFixed(3));
  }

  /// mpv writes the frame itself (format from the extension): no Dart-side encoding and no
  /// player lock, and media_kit sends it as an async command, so the UI never waits on the
  /// JPEG encoder. [subtitles] burns the visible subtitle in.
  ///
  /// With hardware decoding straight to the surface (Android) mpv cannot read the frame back
  /// and `video` fails: the one retry asks for `window`, which is what is on screen.
  Future<bool> screenshotTo(String path, {bool subtitles = false}) async {
    final file = File(path);
    // The Lobby frame is rewritten in place, so "the file exists" proves nothing by itself.
    final before = await _stamp(file);
    for (final what in [subtitles ? 'subtitles' : 'video', 'window']) {
      if (_disposed) return false;
      try {
        await _native?.command(['screenshot-to-file', path, what]);
        final after = await _stamp(file);
        if (after != null && after != before) return true;
      } on Object {
        // Try the other source, then give up.
      }
    }
    return false;
  }

  static Future<(DateTime, int)?> _stamp(File f) async {
    try {
      final s = await f.stat();
      return s.type == FileSystemEntityType.notFound ? null : (s.modified, s.size);
    } on Object {
      return null;
    }
  }

  /// A small JPEG for the bias light, taken WITHOUT the player's lock (a locked screenshot
  /// queues ahead of seeks and pauses, which is what made the controls lag).
  Future<Uint8List?> biasFrame() async {
    if (_disposed) return null;
    try {
      return await _native?.screenshot(format: 'image/jpeg', synchronized: false);
    } on Object {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _throttle?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _state.close();
    systemFontSubtitles.dispose();
    await player.dispose();
  }

  static bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

/// A tiny listenable bool, so the player layer stays free of Flutter's foundation types.
class EngineFlag {
  bool _value = false;
  final _changes = StreamController<bool>.broadcast();
  bool get value => _value;
  set value(bool v) {
    if (v == _value) return;
    _value = v;
    if (!_changes.isClosed) _changes.add(v);
  }

  Stream<bool> get changes => _changes.stream;
  void dispose() => unawaited(_changes.close());
}
