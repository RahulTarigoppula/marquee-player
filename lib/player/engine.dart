// The single media_kit Player + VideoController, and the mpv property bridge (§8.1).
// Load-bearing: never set vo=mediacodec_embed (it silently disables libass on Android).
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../engine/models/media.dart';

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
  final List<AudioTrack> audioTracks;
  final List<SubtitleTrack> subtitleTracks;
  final AudioTrack? audio;
  final SubtitleTrack? subtitle;
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
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.audio,
    this.subtitle,
    this.error,
  });

  bool get hasSubtitle => subtitle != null && subtitle!.id != 'no';
}

class PlayerEngine {
  final Player player;
  late final VideoController controller;
  final _state = StreamController<PlaybackState>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _throttle;
  bool _dirty = false;
  bool _disposed = false;

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
      configuration: VideoControllerConfiguration(enableHardwareAcceleration: hwdec != 'no'),
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
      s.track,
    ]) {
      _subs.add(stream.listen((_) => _markDirty()));
    }
    _subs.add(s.error.listen((e) => _lastError = e));
  }

  String? _lastError;

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
      audioTracks: st.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList(),
      subtitleTracks: st.tracks.subtitle.where((t) => t.id != 'auto').toList(),
      audio: st.track.audio,
      subtitle: st.track.subtitle,
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

  Future<void> open(String locator, {Duration? start}) async {
    _lastError = null;
    await player.open(Media(locator, start: start), play: true);
  }

  Future<void> attachSubtitle(String path, {required String language, String? title}) =>
      player.setSubtitleTrack(
        SubtitleTrack.uri(path, title: title ?? language.toUpperCase(), language: language),
      );

  Future<void> setSubDelayMs(int ms) async =>
      _native?.setProperty('sub-delay', (ms / 1000).toStringAsFixed(2));

  Future<void> setSubStyle({double? scale, bool? outline, String? position}) async {
    final n = _native;
    if (n == null) return;
    if (scale != null) await n.setProperty('sub-scale', scale.toStringAsFixed(2));
    if (outline != null) await n.setProperty('sub-border-size', outline ? '2' : '0');
    if (position != null) {
      await n.setProperty('sub-pos', switch (position) {
        'top' => '10',
        'lower-third' => '80',
        _ => '96',
      });
    }
  }

  Future<String?> property(String name) async {
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

  Future<void> frameStep({required bool forward}) async =>
      _native?.command([forward ? 'frame-step' : 'frame-back-step']);

  Future<void> abLoop() async => _native?.command(['ab-loop']);

  Future<Uint8List?> screenshot() => player.screenshot(format: 'image/jpeg');

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _throttle?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _state.close();
    await player.dispose();
  }

  static bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
