import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'db/database.dart';
import 'db/open.dart';
import 'platform/files.dart';
import 'platform/pip.dart';
import 'platform/window.dart';
import 'player/engine.dart';
import 'state/providers.dart';
import 'state/session.dart';

/// Cold start, in order of what the eye needs: the Lobby's first frame, then everything else.
/// Nothing that the first frame does not draw is awaited before it.
Future<void> main(List<String> args) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Opens on a background isolate; the first query (the window bounds) waits for it.
  final db = MarqueeDatabase(openMarqueeDatabase());
  final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
  // Diagnostics are local only: a plain sentence, never a report sent anywhere.
  FlutterError.onError = (d) => FlutterError.presentError(d);

  // Restore a saved sign-in and API key (secure storage, off the UI path). Only a subtitle
  // search waits for it.
  container.read(accountProvider);
  if (Platform.isAndroid) {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  // Windows: the widget tree builds WHILE the window restores its saved bounds; the first
  // frame is held until they are applied, so the window appears once, in place, with content.
  final window = initWindow(db);
  if (Platform.isWindows) binding.deferFirstFrame();
  runApp(UncontrolledProviderScope(container: container, child: const MarqueeApp()));
  if (Platform.isWindows) {
    try {
      await window.timeout(const Duration(seconds: 3));
    } on Object {
      // Never keep the window hidden over a slow database: show it at its default size.
    } finally {
      binding.allowFirstFrame();
    }
  } else {
    await window;
  }

  // After the first frame: libmpv (a large native library), then the artwork sweep.
  binding.addPostFrameCallback((_) {
    Timer.run(PlayerEngine.ensureInitialized);
    Timer(const Duration(seconds: 10), () => unawaited(db.sweepArtwork()));
  });

  final session = container.read(sessionProvider.notifier);
  // `marquee.exe "D:\films\x.mkv"` or Android "Open with" plays without passing the Lobby.
  final initial = args.where((a) => !a.startsWith('-')).firstOrNull ?? await initialIntentUri();
  if (initial != null) unawaited(session.openLocator(initial));
  onNewIntentUri((uri) => unawaited(session.openLocator(uri)));
  // A second launch on Windows hands its file to this window (windows/runner single instance).
  onSecondInstance((path) {
    unawaited(focusWindow());
    unawaited(session.openLocator(path));
  });
}
