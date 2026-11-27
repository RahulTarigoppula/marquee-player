// Frames for the seek bar: a SECOND, tiny libmpv player that holds the same file paused and
// jumps to the keyframe nearest the pointer. Software decoding, a 320 px picture, no audio, no
// subtitles, no cache: it must never be felt by the film. It is its own Player, so it has its
// own lock and its own demuxer: nothing here can queue behind (or ahead of) the film's seeks.
//
// Made by the session on the first hover over the seek bar (see `seekPreviewAllowed` for
// which films get one) and disposed with it. Every failure is silent: the seek bar falls back
// to the time alone.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'engine.dart';
import 'thumbnailer.dart' show SmallFrames, kSmallFrameFilter;

/// The fastest the preview is asked to move: about eight frames a second. A slow disk or a
/// heavy keyframe makes it slower by itself (the next seek waits for the last one to land).
const Duration kPreviewEvery = Duration(milliseconds: 120);

/// libmpv coming up, and the file opening, may each take this long before the preview gives up.
const Duration kPreviewOpenTimeout = Duration(seconds: 8);

/// The file is let go (decoder, demuxer and their memory) after this long without a hover.
/// The player itself stays, so the next hover only has to open the file again.
const Duration kPreviewIdle = Duration(seconds: 45);

class SeekPreview {
  SeekPreview(this.locator);

  /// A path on disk (never a URL, never a content:// URI).
  final String locator;

  /// True while a frame of the film is on the texture: only then is there anything to show.
  final ready = EngineFlag();

  Player? _player;
  VideoController? _controller;
  Duration? _want;
  Timer? _idle;
  bool _busy = false;
  bool _loaded = false;
  bool _failed = false;
  bool _disposed = false;
  int _blank = 0;

  /// What the `Video` widget draws; null until the first [show].
  VideoController? get controller => _controller;

  /// False once it has failed or been disposed: the caller shows the time alone.
  bool get usable => !_failed && !_disposed;

  /// Options for speed over fidelity. Each is set on its own and may be refused by a libmpv
  /// build that does not know it: the default then stays.
  static const _options = <String, String>{
    'pause': 'yes',
    'mute': 'yes',
    'ao': 'null', // never opens an audio device, whatever the file holds
    'aid': 'no',
    'sid': 'no',
    'hwdec': 'no', // the film keeps the hardware decoder to itself
    'keep-open': 'yes',
    'hr-seek': 'no', // the keyframe before the pointer decodes at once; exact frames do not
    'sub-auto': 'no',
    'audio-file-auto': 'no',
    'cache': 'no',
    'demuxer-readahead-secs': '0',
    'vd-lavc-threads': '2',
    'vd-lavc-fast': 'yes',
    'vd-lavc-skiploopfilter': 'all',
  };

  /// Without the small-picture filter the preview still works at the film's own size, but
  /// only up to this width: a 4K frame copied to a CPU texture eight times a second is exactly
  /// the load the film must not feel. Wider films show the time alone.
  static const int _unscaledMaxWidth = 1920;

  /// This player's frames come out small ([kSmallFrameFilter] is on it). media_kit sizes its
  /// texture to the video's own size once that is known (the fixed width / height below only
  /// hold until then), so the picture is made small in mpv.
  bool _small = false;

  /// The frame at (the keyframe before) [at], as soon as the player can. Calls made while it
  /// is still busy replace each other: only the latest is ever sought.
  void show(Duration at) {
    if (!usable) return;
    _want = at < Duration.zero ? Duration.zero : at;
    _idle?.cancel();
    if (!_busy) unawaited(_pump());
  }

  Future<void> _pump() async {
    _busy = true;
    try {
      while (usable) {
        final at = _want;
        if (at == null) break;
        _want = null;
        final player = await _ensure().timeout(kPreviewOpenTimeout);
        final native = player.platform;
        if (!_current(player) || native is! NativePlayer) return;
        if (!_loaded) {
          await _load(player).timeout(kPreviewOpenTimeout);
          if (!_current(player)) return;
          _loaded = true;
        }
        Future<void> land() => native.command([
          'seek',
          (at.inMilliseconds / 1000).toStringAsFixed(3),
          'absolute+keyframes',
        ]);
        await land();
        var shown = await _landed(native, player);
        if (!_current(player)) return;
        // The first frame this player shows is where it can truly ask for the small-picture
        // filter (see [SmallFrames]); normally the answer is already known and the filter was
        // on from the start.
        if (shown && !_small && SmallFrames.works != false) {
          _small = await SmallFrames.apply(native);
          if (!_current(player)) return;
          if (_small) {
            // The frame on the texture was made before the filter: land again, through it.
            await land();
            shown = await _landed(native, player);
            if (!_current(player)) return;
          }
        }
        if (shown && !_small && await _width(native) > _unscaledMaxWidth) {
          throw StateError('too large to preview unscaled');
        }
        if (shown) {
          _blank = 0;
          ready.value = true;
        } else if (++_blank >= 3) {
          // No picture three times running: audio only, damaged, or a codec the software
          // decoder cannot read. Stop trying for this film.
          throw StateError('no picture');
        }
      }
    } on Object {
      _fail();
    } finally {
      _busy = false;
      if (usable && _player != null) {
        _idle?.cancel();
        _idle = Timer(kPreviewIdle, () => unawaited(_unload()));
      }
    }
  }

  bool _current(Player player) => usable && identical(_player, player);

  Future<Player> _ensure() async {
    final existing = _player;
    if (existing != null) return existing;
    PlayerEngine.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Marquee preview',
        muted: true,
        bufferSize: 2 * 1024 * 1024,
      ),
    );
    _player = player;
    _controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        width: 320,
        height: 180,
        hwdec: 'no',
        // A CPU pixel buffer: the film's own GPU surface is never shared or contended.
        enableHardwareAcceleration: false,
      ),
    );
    // media_kit creates the controller in a post-frame callback; a paused film with a still
    // pointer draws no frames, and every call below would wait for one.
    SchedulerBinding.instance.ensureVisualUpdate();
    final native = player.platform;
    // Known to work (the thumbnailer or an earlier preview asked): on from the start. Not
    // known yet: left off, and asked once this player shows its first frame (see [_pump]).
    _small = SmallFrames.works == true;
    if (native is NativePlayer) {
      final options = {..._options, if (_small) 'vf': kSmallFrameFilter};
      for (final MapEntry(:key, :value) in options.entries) {
        try {
          await native.setProperty(key, value);
        } on Object {
          // Unknown to this build.
        }
      }
    }
    return player;
  }

  /// Opens the file paused and waits until libmpv knows its length (it has loaded).
  Future<void> _load(Player player) async {
    final loaded = player.stream.duration.firstWhere((d) => d > Duration.zero);
    await player.open(Media(locator), play: false);
    await loaded;
  }

  /// Waits [kPreviewEvery], then for the seek to land. True when a picture is there.
  Future<bool> _landed(NativePlayer native, Player player) async {
    await Future<void>.delayed(kPreviewEvery);
    for (var i = 0; i < 40; i++) {
      if (!_current(player)) return false;
      if (await native.getProperty('seeking') != 'yes') {
        return await _width(native) > 0;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return false;
  }

  /// The decoded picture's own width (before any filter); 0 while there is none.
  Future<int> _width(NativePlayer native) async =>
      int.tryParse(await native.getProperty('video-params/w')) ?? 0;

  /// Nobody has hovered for a while: let the file (and the decoder's memory) go.
  Future<void> _unload() async {
    final player = _player;
    if (_busy || player == null || !usable) return;
    _busy = true; // a hover that lands mid-unload waits its turn
    try {
      ready.value = false;
      _loaded = false;
      await player.stop();
    } on Object {
      _fail();
    } finally {
      _busy = false;
      if (usable && _want != null) unawaited(_pump());
    }
  }

  void _fail() {
    _failed = true;
    _release();
  }

  /// Never awaited: a player that is still coming up finishes that first, and nothing here
  /// should wait for it.
  void _release() {
    _idle?.cancel();
    ready.value = false;
    final player = _player;
    _player = null;
    _controller = null;
    if (player == null) return;
    // Already gone, or the process is closing: either way there is nothing to do about it.
    unawaited(player.dispose().then((_) {}, onError: (Object _) {}));
  }

  /// With the film. Safe to call twice, and while a seek is in flight.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _want = null;
    _release();
    ready.dispose();
  }
}
