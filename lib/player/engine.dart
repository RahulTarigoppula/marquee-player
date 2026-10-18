// The single media_kit Player + VideoController, and the mpv property bridge (§8.1).
// Load-bearing: never set vo=mediacodec_embed (it silently disables libass on Android).
import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../engine/models/media.dart';
import '../engine/models/settings.dart';
import '../engine/playback.dart';

const Duration kStreamThrottle = Duration(milliseconds: 100); // 10 Hz — never rebuild at 60

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
    this.width = 0,
    this.height = 0,
    this.error,
  });

  AudioTrack? get audio => audioTracks.where((t) => t.id == audioId).firstOrNull;
  SubtitleTrack? get subtitle => subtitleTracks.where((t) => t.id == subtitleId).firstOrNull;

  bool get hasSubtitle =>
      subtitleId != null && subtitleId!.isNotEmpty && subtitleId != 'no' && subtitleId != 'auto';
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
  bool _muted = false;

  /// path → mpv track id of every external file we `sub-add`ed, so a second attach of the
  /// same file selects the existing track instead of adding a duplicate.
  final _external = <String, String>{};

  /// Android only: the text subtitle is drawn by Flutter (system fonts) instead of libass,
  /// which only knows the one bundled Noto Sans and shows tofu for Arabic, Hindi, CJK, …
  final systemFontSubtitles = EngineFlag();

  PlayerEngine({String hwdec = 'auto-safe'})
    : player = Player(
        configuration: const PlayerConfiguration(
          title: 'Marquee',
          libass: true,
          libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf',
          libassAndroidFontName: 'Noto Sans', // the TTF's INTERNAL family name
          bufferSize: 64 * 1024 * 1024,
        ),
      ) {
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        // Android keeps media_kit's own default (it forces software decoding on emulators).
        hwdec: hwdec == 'no' ? 'no' : (Platform.isAndroid ? null : hwdec),
        enableHardwareAcceleration: hwdec != 'no',
      ),
    );
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
      audioTracks: st.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList(),
      subtitleTracks: st.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList(),
      audioId: _aid,
      subtitleId: _sid,
      width: st.width ?? 0,
      height: st.height ?? 0,
      error: _lastError,
    );
  }

  void _markDirty() {
    _dirty = true;
    _throttle ??= Timer.periodic(kStreamThrottle, (_) {
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
      if (Directory(fonts).existsSync()) await _set('sub-fonts-dir', fonts);
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
      return false; // timed out, or the stream closed because the player was disposed
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
    if (!_disposed) await player.setRate(rate.clamp(0.25, 4));
  }

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

  /// Size, look and placement for every text subtitle of every film.
  Future<void> applySubtitleStyle(Settings s) async {
    await _set('sub-scale', s.subtitleScale.toStringAsFixed(2));
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
    switch (s.subtitlePlacement) {
      case SubtitlePlacement.bottom:
        await _set('sub-align-y', 'bottom');
        await _set('sub-pos', '100');
      case SubtitlePlacement.lowerThird:
        await _set('sub-align-y', 'bottom');
        await _set('sub-pos', '82');
      case SubtitlePlacement.top:
        await _set('sub-align-y', 'top');
        await _set('sub-pos', '100');
    }
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

  /// mpv writes the frame itself (format from the extension) — no Dart-side encoding and no
  /// player lock. [subtitles] burns the visible subtitle in.
  Future<bool> screenshotTo(String path, {bool subtitles = false}) async {
    if (_disposed) return false;
    try {
      await _native?.command(['screenshot-to-file', path, subtitles ? 'subtitles' : 'video']);
      return File(path).existsSync();
    } on Object {
      return false;
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
