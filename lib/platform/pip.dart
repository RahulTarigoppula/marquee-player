// MethodChannel('marquee/pip') → PipChannel.kt. Android only; a no-op elsewhere.
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _pip = MethodChannel('marquee/pip');

class PipNotifier extends Notifier<bool> {
  @override
  bool build() {
    if (Platform.isAndroid) {
      _pip.setMethodCallHandler((call) async {
        if (call.method == 'pipChanged') {
          final args = call.arguments;
          state = args is Map && args['inPip'] == true;
        }
      });
    }
    return false;
  }

  /// While a film plays, Home enters PiP; in the Lobby it does not.
  Future<void> setAutoEnter({required bool enabled, int w = 16, int h = 9}) async {
    if (!Platform.isAndroid) return;
    try {
      await _pip.invokeMethod<bool>('setAutoEnter', {'enabled': enabled, 'w': w, 'h': h});
    } on PlatformException {
      // Devices without PiP simply never enter it.
    }
  }

  Future<void> enter({int w = 16, int h = 9}) async {
    if (!Platform.isAndroid) return;
    try {
      await _pip.invokeMethod<bool>('enter', {'w': w, 'h': h});
    } on PlatformException {
      // Not supported: stay in the Auditorium.
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
