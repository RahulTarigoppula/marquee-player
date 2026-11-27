// MethodChannel('marquee/media') → MediaChannel.kt: the Android media session (lock screen,
// notification shade, headset and Bluetooth buttons) and the service that keeps the film's
// sound alive behind them. Android only; a no-op elsewhere.
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../engine/now_playing.dart';

const _media = MethodChannel('marquee/media');

/// What the system's controls ask for. Each is the viewer's own tap, somewhere outside the app.
class NowPlayingCommands {
  final void Function() play, pause, rewind, forward, previous, next;
  final void Function(Duration position) seekTo;

  const NowPlayingCommands({
    required this.play,
    required this.pause,
    required this.rewind,
    required this.forward,
    required this.previous,
    required this.next,
    required this.seekTo,
  });
}

class NowPlayingChannel {
  static bool get supported => Platform.isAndroid;

  /// Routes the system's controls to [commands] from now on.
  void listen(NowPlayingCommands commands) {
    if (!supported) return;
    _media.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'play':
          commands.play();
        case 'pause':
          commands.pause();
        case 'rewind':
          commands.rewind();
        case 'forward':
          commands.forward();
        case 'previous':
          commands.previous();
        case 'next':
          commands.next();
        case 'seekTo':
          final ms = call.arguments;
          if (ms is int) commands.seekTo(Duration(milliseconds: ms));
      }
    });
  }

  void stopListening() {
    if (supported) _media.setMethodCallHandler(null);
  }

  /// False when the device refused (no session, no service): the film plays without them.
  Future<bool> show(NowPlayingInfo info) => _invoke('update', info.toMap());

  Future<bool> clear() => _invoke('clear');

  Future<bool> _invoke(String method, [Object? arguments]) async {
    if (!supported) return false;
    try {
      await _media.invokeMethod<void>(method, arguments);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false; // a build without the channel (widget tests)
    }
  }
}
