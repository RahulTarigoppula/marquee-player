// Frames for videos that were never played (Windows): ONE hidden libmpv player that opens a
// file paused, jumps about a tenth of the way in, waits for a decoded frame and has mpv write
// it as a small JPEG. Software decoding, a 320 px picture (full size, more compressed, on a
// libmpv build without the `scale` filter: see [SmallFrames]), no audio, no subtitles, two
// decoder threads: it must never be felt. The queue that feeds it (lib/state/library.dart)
// runs one file at a time and stops while a film plays. Every failure is silent: the card
// keeps its title card.
import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'engine.dart';

/// What opening the file taught us, beyond the frame.
class FrameProbe {
  final int? durationMs;
  final int? width, height;
  const FrameProbe({this.durationMs, this.width, this.height});
}

enum GrabOutcome {
  /// The frame is at the target path.
  done,

  /// This file gives no frame (not a video, damaged, unreadable): do not try it again.
  failed,

  /// Nothing was learned about the file (the grabber was released, or libmpv was not ready):
  /// it may be tried again later.
  aborted,
}

class GrabResult {
  final GrabOutcome outcome;
  final FrameProbe? probe;
  const GrabResult(this.outcome, [this.probe]);
}

/// The frame is taken this far into the film (past logos and black leaders)…
const double kGrabAtFraction = 0.1;

/// …or here when the length is unknown.
const Duration kGrabAtUnknown = Duration(seconds: 60);

/// One file may take this long before it is given up on.
const Duration kGrabTimeout = Duration(seconds: 12);

/// libmpv is unloaded again after this long without work.
const Duration kGrabberIdle = Duration(seconds: 20);

/// The filter that makes the picture small inside mpv: a 4K frame would be a 2 MB JPEG nobody
/// looks at, and a 4K texture behind a 320 px seek-bar preview.
const String kSmallFrameFilter = 'lavfi=[scale=320:-2]';

/// Whether this libmpv build can make [kSmallFrameFilter], asked ONCE per run of the app and
/// shared by the two hidden players (this one and the seek-bar preview).
///
/// The filter used to be set as a plain option before any file was open. mpv only checks such
/// an option when the picture starts: a build without the `scale` filter then gives no picture
/// at all, for every file, and a whole library would have been marked "gives no frame". So it
/// goes through the `vf` COMMAND instead, on a player that is already showing a frame: the
/// command builds the chain there and then, and rolls back when it cannot. What is read back
/// afterwards is the filter or nothing. (The film's own player does the same for `af`.)
abstract final class SmallFrames {
  /// Null until a player with a picture has asked.
  static bool? works;

  /// Puts the filter on [native], which must already be showing a frame of its file. True
  /// when frames are small from the next seek on; false when this build cannot (it is then
  /// never asked again in this run) or the question could not be put just now.
  static Future<bool> apply(NativePlayer native) async {
    if (works == false) return false;
    try {
      await native.command(['vf', 'set', kSmallFrameFilter]);
      if (works == true) return true;
      final made = (await native.getProperty('vf')).trim().isNotEmpty;
      if (!made) await native.command(['vf', 'clr', '']);
      return works = made;
    } on Object {
      return false; // the player went away mid-question: nothing was learned
    }
  }
}

class FrameGrabber {
  Player? _player;
  // Held so the player keeps a render target; never shown.
  // ignore: unused_field
  VideoController? _controller;
  Timer? _idle;
  bool _busy = false;
  bool _disposed = false;

  /// This player's frames come out small ([kSmallFrameFilter] is on it).
  bool _small = false;

  /// Options for speed over fidelity. Each is set on its own and may be refused by a libmpv
  /// build that does not know it: the default then stays.
  static const _options = <String, String>{
    'pause': 'yes',
    'mute': 'yes',
    'aid': 'no',
    'sid': 'no',
    'hwdec': 'no',
    'keep-open': 'yes', // a clip shorter than the seek target still shows its last frame
    'hr-seek': 'no', // the nearest keyframe is a fine thumbnail and decodes at once
    'sub-auto': 'no',
    'audio-file-auto': 'no',
    'cache': 'no',
    'demuxer-readahead-secs': '0',
    'vd-lavc-threads': '2',
    'vd-lavc-fast': 'yes',
    'vd-lavc-skiploopfilter': 'all',
    'screenshot-tag-colorspace': 'no',
  };

  /// A small frame can afford a good JPEG; a full-size one (no `scale` in this build) is kept
  /// from growing past a few hundred KB.
  static const _smallQuality = '82', _fullQuality = '70';

  Future<Player> _ensure() async {
    final existing = _player;
    if (existing != null) return existing;
    PlayerEngine.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Marquee thumbnails',
        muted: true,
        bufferSize: 4 * 1024 * 1024,
      ),
    );
    _player = player;
    _controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        width: 320,
        height: 180,
        hwdec: 'no',
        enableHardwareAcceleration: false,
      ),
    );
    // media_kit creates the controller in a post-frame callback, and an idle Lobby draws no
    // frames: without this every call below would wait for a frame that never comes.
    SchedulerBinding.instance.ensureVisualUpdate();
    final native = player.platform;
    // Known to work (an earlier player asked): on from the start, as a plain option. Not
    // known yet: left off, and asked once this player shows its first frame (see [_grab]).
    final small = SmallFrames.works;
    _small = small == true;
    if (native is NativePlayer) {
      final options = {
        ..._options,
        if (_small) 'vf': kSmallFrameFilter,
        'screenshot-jpeg-quality': small == false ? _fullQuality : _smallQuality,
      };
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

  /// Writes a frame of [source] to [target] (a `.jpg` path; a `.part.jpg` beside it is used
  /// while writing). One call at a time: a second call while busy is [GrabOutcome.aborted].
  Future<GrabResult> grab(String source, String target, {required String partPath}) async {
    if (_busy || _disposed) return const GrabResult(GrabOutcome.aborted);
    _busy = true;
    _idle?.cancel();
    try {
      final Player player;
      try {
        player = await _ensure().timeout(kGrabTimeout);
      } on Object {
        await _release(); // libmpv never came up (a hidden window draws no frames): later
        return const GrabResult(GrabOutcome.aborted);
      }
      try {
        return await _grab(player, source, target, partPath).timeout(kGrabTimeout);
      } on TimeoutException {
        // The stray attempt must not touch the next file: start over with a new player.
        await _release();
        return const GrabResult(GrabOutcome.failed);
      } on Object {
        await _release();
        return const GrabResult(GrabOutcome.aborted);
      }
    } finally {
      _busy = false;
      if (!_disposed && _player != null) {
        _idle = Timer(kGrabberIdle, () => unawaited(_release()));
      }
    }
  }

  bool _current(Player player) => !_disposed && identical(_player, player);

  Future<GrabResult> _grab(Player player, String source, String target, String partPath) async {
    const aborted = GrabResult(GrabOutcome.aborted);
    const failed = GrabResult(GrabOutcome.failed);
    final native = player.platform;
    if (native is! NativePlayer) return aborted;

    // Listen BEFORE opening: the length is announced once, as the file loads.
    // No length in time (or not a media file at all) is null: the checks below decide.
    final loaded = player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(const Duration(seconds: 6))
        .then<Duration?>((d) => d, onError: (Object _) => null);
    await player.open(Media(source), play: false);
    final duration = await loaded;
    if (!_current(player)) return aborted;

    final at = duration == null ? kGrabAtUnknown : duration * kGrabAtFraction;
    Future<void> land() => native.command([
      'seek',
      (at.inMilliseconds / 1000).toStringAsFixed(3),
      'absolute+keyframes',
    ]);
    if (at > const Duration(milliseconds: 500)) await land();

    // A paused player still decodes and shows the frame it landed on; wait for that.
    int? width, height;
    var ready = false;
    for (var i = 0; i < 60 && !ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!_current(player)) return aborted;
      width = int.tryParse(await native.getProperty('video-params/w'));
      height = int.tryParse(await native.getProperty('video-params/h'));
      final seeking = await native.getProperty('seeking');
      ready = (width ?? 0) > 0 && (height ?? 0) > 0 && seeking != 'yes';
    }
    if (!ready) {
      await _unload(player);
      return failed; // audio only, a damaged file, or a codec this build cannot decode
    }

    // A frame is showing, so the picture chain exists: the moment (the only one) at which
    // asking for the small-picture filter gets a true answer. Once per run, normally: every
    // later player is created with what was learned here.
    if (!_small && SmallFrames.works != false) {
      _small = await SmallFrames.apply(native);
      if (!_current(player)) return aborted;
      if (_small) {
        // The frame on screen was made before the filter: land on it again, through it.
        await land();
        for (var i = 0; i < 60; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          if (!_current(player)) return aborted;
          if (await native.getProperty('seeking') != 'yes') break;
        }
      } else if (SmallFrames.works == false) {
        try {
          await native.setProperty('screenshot-jpeg-quality', _fullQuality);
        } on Object {
          // Unknown to this build: the frame is written at mpv's own quality.
        }
      }
    }

    final part = File(partPath);
    try {
      if (await part.exists()) await part.delete();
      await native.command(['screenshot-to-file', partPath, 'video']);
      if (!_current(player)) return aborted;
      if (!await part.exists() || await part.length() == 0) {
        await _unload(player);
        return failed;
      }
      await part.rename(target);
    } on FileSystemException {
      await _unload(player);
      return aborted; // the cache folder is the problem, not the film
    }
    await _unload(player);
    return GrabResult(
      GrabOutcome.done,
      FrameProbe(durationMs: duration?.inMilliseconds, width: width, height: height),
    );
  }

  /// Lets go of the file (its handle would otherwise block a rename or delete in Explorer).
  Future<void> _unload(Player player) async {
    try {
      if (_current(player)) await player.stop();
    } on Object {
      // Already gone.
    }
  }

  Future<void> _release() async {
    _idle?.cancel();
    final player = _player;
    _player = null;
    _controller = null;
    if (player == null) return;
    try {
      await player.dispose();
    } on Object {
      // The process is closing.
    }
  }

  /// Frees libmpv now (a film is about to play). The grabber can be used again afterwards.
  Future<void> release() => _release();

  Future<void> dispose() async {
    _disposed = true;
    await _release();
  }
}
