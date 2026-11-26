// Android audio focus. libmpv plays through OpenSL ES, which never asks for focus: without
// this, other apps' music keeps playing over the film, an answered call mixes with it, and
// pulling out the headphones carries on at full volume on the speaker.
//
// The rule is the one every video player follows: taking focus silences the others; losing it
// (a call, another player) or losing the headphones PAUSES the film, and resuming is the
// viewer's call. Windows mixes per app and needs none of this.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';

class AudioFocus {
  /// Called when the film must pause: focus was taken away, or the audio became "noisy"
  /// (headphones unplugged, Bluetooth dropped).
  final void Function() onPause;

  AudioSession? _session;
  final _subs = <StreamSubscription<Object?>>[];
  bool _held = false;
  bool _disposed = false;

  AudioFocus({required this.onPause});

  static bool get supported => Platform.isAndroid;

  Future<AudioSession?>? _opening;

  /// One session and ONE pair of listeners, however many calls race for the first.
  Future<AudioSession?> _ready() => _opening ??= _open();

  Future<AudioSession?> _open() async {
    if (!supported || _disposed) return null;
    try {
      final s = await AudioSession.instance;
      await s.configure(const AudioSessionConfiguration.music());
      if (_disposed) return null;
      _subs
        ..add(
          s.interruptionEventStream.listen((e) {
            // A notification "duck" is the system's business; anything else stops the film.
            if (e.begin && e.type != AudioInterruptionType.duck) _lost();
          }),
        )
        ..add(s.becomingNoisyEventStream.listen((_) => onPause()));
      return _session = s;
    } on Object {
      return null; // no plugin (tests) or a refusing device: play on without focus
    }
  }

  void _lost() {
    _held = false; // the system already took it: nothing to give back
    onPause();
  }

  /// Follows the player: focus is held exactly while the film plays.
  Future<void> setPlaying(bool playing) async {
    if (playing == _held) return;
    final s = await _ready();
    if (s == null || _disposed || playing == _held) return;
    _held = playing;
    try {
      await s.setActive(playing);
    } on Object {
      // Refused (a call in progress): the film still plays; the interruption stream decides.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    final held = _held;
    _held = false;
    if (held) {
      try {
        await _session?.setActive(false);
      } on Object {
        // Going away either way.
      }
    }
  }
}
