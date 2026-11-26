// MethodChannel('marquee/pip') → PipChannel.kt. Android only; a no-op elsewhere.
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _pip = MethodChannel('marquee/pip');

class PipNotifier extends Notifier<bool> {
  /// The play/pause button inside the PiP window. Set by the session while a film is open.
  void Function()? onPlayPause;

  /// The PiP window was closed (its X, or swiped away): the film must not keep playing
  /// unseen. Set by the session.
  void Function()? onDismissed;

  @override
  bool build() {
    if (Platform.isAndroid) {
      _pip.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'pipChanged':
            final args = call.arguments;
            state = args is Map && args['inPip'] == true;
          case 'pipDismissed':
            state = false;
            onDismissed?.call();
          case 'pipAction':
            if (call.arguments == 'playPause') onPlayPause?.call();
        }
      });
    }
    return false;
  }

  /// Runs [pick] (a file picker: our own activity, not a trip Home) with auto-enter off, so
  /// Android 8-11 does not take the picker's launch for Home and shrink the film into PiP.
  /// Auto-enter comes back as it was.
  Future<T> withoutAutoEnter<T>(Future<T> Function() pick) async {
    final was = _autoEnter;
    if (!Platform.isAndroid || !was) return pick();
    await setAutoEnter(enabled: false, w: _w, h: _h, playing: _playing);
    try {
      return await pick();
    } finally {
      await setAutoEnter(enabled: true, w: _w, h: _h, playing: _playing);
    }
  }

  bool _autoEnter = false;
  int _w = 16, _h = 9;
  bool _playing = true;

  /// While a film plays, Home enters PiP; in the Lobby it does not. [w]×[h] is the picture's
  /// own size, so the PiP window has the film's shape (not always 16:9).
  Future<void> setAutoEnter({
    required bool enabled,
    int w = 16,
    int h = 9,
    bool playing = true,
  }) async {
    if (!Platform.isAndroid) return;
    _w = w;
    _h = h;
    _playing = playing;
    _autoEnter = enabled;
    try {
      await _pip.invokeMethod<bool>('setAutoEnter', {
        'enabled': enabled,
        'w': w,
        'h': h,
        'playing': playing,
      });
    } on PlatformException {
      // Devices without PiP simply never enter it.
    } on MissingPluginException {
      // A build without the channel.
    }
  }

  Future<void> enter({int w = 16, int h = 9, bool playing = true}) async {
    if (!Platform.isAndroid) return;
    _autoEnter = true; // entering by hand turns auto-enter on natively too (PipChannel.kt)
    try {
      await _pip.invokeMethod<bool>('enter', {'w': w, 'h': h, 'playing': playing});
    } on PlatformException {
      // Not supported: stay in the Auditorium.
    } on MissingPluginException {
      // A build without the channel.
    }
  }
}

/// True while Android shows the film in a PiP window — the UI drops ALL chrome.
final pipProvider = NotifierProvider<PipNotifier, bool>(PipNotifier.new);

const _content = MethodChannel('marquee/content');

/// A file arriving via "Open with" while the app is already running.
void onNewIntentUri(void Function(String uri) handler) {
  if (!Platform.isAndroid) return;
  _content.setMethodCallHandler((call) async {
    if (call.method == 'uriChanged' && call.arguments is String) handler(call.arguments as String);
  });
}

const _instance = MethodChannel('marquee/instance');

/// Windows: a second `marquee.exe <file>` forwards its file to this window and exits
/// (windows/runner: named mutex + WM_COPYDATA).
void onSecondInstance(void Function(String path) handler) {
  if (!Platform.isWindows) return;
  _instance.setMethodCallHandler((call) async {
    if (call.method == 'open' && call.arguments is String) handler(call.arguments as String);
  });
}
