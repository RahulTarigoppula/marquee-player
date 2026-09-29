import 'dart:async';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'db/database.dart';
import 'platform/files.dart';
import 'platform/pip.dart';
import 'platform/window.dart';
import 'state/providers.dart';
import 'state/session.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final db = MarqueeDatabase(driftDatabase(name: 'marquee'));
  await initWindow(db);
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
  // Diagnostics are local only: a plain sentence, never a report sent anywhere.
  FlutterError.onError = (d) => FlutterError.presentError(d);

  runApp(UncontrolledProviderScope(container: container, child: const MarqueeApp()));

  // `marquee.exe "D:\films\x.mkv"` or Android "Open with" plays without passing the Lobby.
  final initial = args.where((a) => !a.startsWith('-')).firstOrNull ?? await initialIntentUri();
  if (initial != null) {
    final f = await fileFromPath(initial);
    if (f != null) unawaited(container.read(sessionProvider.notifier).open(f));
  }
  onNewIntentUri((uri) async {
    final f = await fileFromPath(uri);
    if (f != null) await container.read(sessionProvider.notifier).open(f);
  });
  container.read(accountProvider); // restores a saved sign-in
}
