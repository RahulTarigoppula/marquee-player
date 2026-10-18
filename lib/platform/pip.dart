// MethodChannel('marquee/pip') → PipChannel.kt. Android only; a no-op elsewhere.
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _pip = MethodChannel('marquee/pip');

class PipNotifier extends Notifier<bool> {
  /// The play/pause button inside the PiP window. Set by the session while a film is open.
  void Function()? onPlayPause;

  @override
  bool build() {
    if (Platform.isAndroid) {
      _pip.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'pipChanged':
            final args = call.arguments;
            state = args is Map && args['inPip'] == true;
          case 'pipAction':
            if (call.arguments == 'playPause') onPlayPause?.call();
        }
      });
    }
    return false;
  }

  /// While a film plays, Home enters PiP; in the Lobby it does not. [w]×[h] is the picture's
  /// own size, so the PiP window has the film's shape (not always 16:9).
  Future<void> setAutoEnter({
    required bool enabled,
    int w = 16,
    int h = 9,
    bool playing = true,
  }) async {
    if (!Platform.isAndroid) return;
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
