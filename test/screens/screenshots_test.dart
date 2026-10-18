// Screenshots of every room, for review and for the README. Tagged `screenshot`: normal CI
// excludes them; screenshots.yml renders them with --update-goldens and publishes the PNGs to
// the `screenshots` branch. Add a case here for every new screen or state worth looking at.
@Tags(['screenshot'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/models/settings.dart';
import 'package:marquee/state/thumbnails.dart';
import 'package:marquee/ui/lobby/lobby_screen.dart';
import 'package:marquee/ui/ticket_office/ticket_office_screen.dart';

import 'harness.dart';

void main() {
  final thumbs = thumbnailDirProvider.overrideWith(
    (ref) async => Directory.systemTemp.createTempSync('marquee-thumbs'),
  );

  testWidgets('lobby, empty, night, desktop', (t) async {
    await shoot(
      t,
      'lobby_empty_desktop',
      const LobbyScreen(),
      overrides: screenOverrides(extra: [thumbs]),
    );
  });

  testWidgets('lobby, library, night, desktop', (t) async {
    await shoot(
      t,
      'lobby_library_desktop',
      const LobbyScreen(),
      overrides: screenOverrides(library: sampleLibrary(), extra: [thumbs]),
    );
  });

  testWidgets('lobby, library, phone', (t) async {
    await shoot(
      t,
      'lobby_library_phone',
      const LobbyScreen(),
      size: kPhone,
      overrides: screenOverrides(library: sampleLibrary(), extra: [thumbs]),
    );
  });

  testWidgets('lobby, matinee, desktop', (t) async {
    await shoot(
      t,
      'lobby_matinee_desktop',
      const LobbyScreen(),
      at: kDay,
      matinee: true,
      overrides: screenOverrides(
        library: sampleLibrary(),
        settings: const Settings(lobbyTheme: LobbyTheme.matinee),
        extra: [thumbs],
      ),
    );
  });

  testWidgets('ticket office, desktop', (t) async {
    await shoot(
      t,
      'ticket_office_desktop',
      const TicketOfficeScreen(),
      overrides: screenOverrides(extra: [thumbs]),
    );
  });

  testWidgets('ticket office, phone', (t) async {
    await shoot(
      t,
      'ticket_office_phone',
      const TicketOfficeScreen(),
      size: kPhone,
      overrides: screenOverrides(extra: [thumbs]),
    );
  });
}
