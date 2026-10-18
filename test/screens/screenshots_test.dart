// Screenshots of every room, for review and for the README. Tagged `screenshot`: normal CI
// excludes them; screenshots.yml renders them with --update-goldens and publishes the PNGs to
// the `screenshots` branch. Add a case here for every new screen or state worth looking at.
@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/models/settings.dart';
import 'package:marquee/ui/lobby/lobby_screen.dart';
import 'package:marquee/ui/ticket_office/ticket_office_screen.dart';

import 'harness.dart';

void main() {
  // ── Lobby ──

  testWidgets('lobby, empty, night, desktop', (t) async {
    await shoot(
      t,
      'lobby_empty_desktop',
      const LobbyScreen(),
      platform: TargetPlatform.windows,
      overrides: screenOverrides(),
    );
  });

  testWidgets('lobby, empty, phone', (t) async {
    await shoot(
      t,
      'lobby_empty_phone',
      const LobbyScreen(),
      size: kPhone,
      overrides: screenOverrides(),
    );
  });

  testWidgets('lobby, empty, drag over, desktop', (t) async {
    await shoot(
      t,
      'lobby_empty_dragover_desktop',
      const LobbyScreen(dragOver: true),
      platform: TargetPlatform.windows,
      overrides: screenOverrides(),
    );
  });

  testWidgets('lobby, library, night, desktop', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_library_desktop',
      const LobbyScreen(),
      platform: TargetPlatform.windows,
      thumbnails: thumbs,
      overrides: screenOverrides(library: sampleLibrary(), thumbnails: thumbs),
    );
  });

  testWidgets('lobby, library, scrolled to the grid, desktop', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_library_grid_desktop',
      const LobbyScreen(),
      platform: TargetPlatform.windows,
      thumbnails: thumbs,
      overrides: screenOverrides(library: sampleLibrary(), thumbnails: thumbs),
      act: (t) async {
        await t.ensureVisible(find.byKey(const ValueKey('grid-5')));
        await t.pump(const Duration(milliseconds: 300));
      },
    );
  });

  testWidgets('lobby, library, no frames yet (title cards), desktop', (t) async {
    await shoot(
      t,
      'lobby_library_titlecards_desktop',
      const LobbyScreen(),
      platform: TargetPlatform.windows,
      overrides: screenOverrides(library: sampleLibrary()),
    );
  });

  testWidgets('lobby, library, phone', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_library_phone',
      const LobbyScreen(),
      size: kPhone,
      thumbnails: thumbs,
      overrides: screenOverrides(library: sampleLibrary(), thumbnails: thumbs),
    );
  });

  testWidgets('lobby, library, phone scrolled', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_library_phone_scrolled',
      const LobbyScreen(),
      size: kPhone,
      thumbnails: thumbs,
      overrides: screenOverrides(library: sampleLibrary(), thumbnails: thumbs),
      act: (t) async {
        await t.ensureVisible(find.byKey(const ValueKey('grid-4')));
        await t.pump(const Duration(milliseconds: 300));
      },
    );
  });

  testWidgets('lobby, library, phone landscape', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_library_phone_landscape',
      const LobbyScreen(),
      size: kPhoneLandscape,
      thumbnails: thumbs,
      overrides: screenOverrides(library: sampleLibrary(), thumbnails: thumbs),
    );
  });

  testWidgets('lobby, empty, phone landscape', (t) async {
    await shoot(
      t,
      'lobby_empty_phone_landscape',
      const LobbyScreen(),
      size: kPhoneLandscape,
      overrides: screenOverrides(),
    );
  });

  testWidgets('lobby, matinee, desktop', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_matinee_desktop',
      const LobbyScreen(),
      at: kDay,
      matinee: true,
      platform: TargetPlatform.windows,
      thumbnails: thumbs,
      overrides: screenOverrides(
        library: sampleLibrary(),
        settings: const Settings(lobbyTheme: LobbyTheme.matinee),
        thumbnails: thumbs,
      ),
    );
  });

  testWidgets('lobby, matinee, phone', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_matinee_phone',
      const LobbyScreen(),
      size: kPhone,
      at: kDay,
      matinee: true,
      thumbnails: thumbs,
      overrides: screenOverrides(
        library: sampleLibrary(),
        settings: const Settings(lobbyTheme: LobbyTheme.matinee),
        thumbnails: thumbs,
      ),
    );
  });

  testWidgets('lobby, card menu open, desktop', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_card_menu_desktop',
      const LobbyScreen(),
      platform: TargetPlatform.windows,
      thumbnails: thumbs,
      overrides: screenOverrides(library: sampleLibrary(), thumbnails: thumbs),
      act: (t) async {
        final more = find.byKey(const ValueKey('card-more-3')).last;
        await t.ensureVisible(more);
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(more);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  });

  testWidgets('lobby, card menu open, phone', (t) async {
    final thumbs = fakeThumbnails();
    await shoot(
      t,
      'lobby_card_menu_phone',
      const LobbyScreen(),
      size: kPhone,
      thumbnails: thumbs,
      overrides: screenOverrides(library: sampleLibrary(), thumbnails: thumbs),
      act: (t) async {
        final card = find.byKey(const ValueKey('row-3'));
        await t.ensureVisible(card);
        await t.pump(const Duration(milliseconds: 300));
        await t.longPress(card);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  });

  testWidgets('lobby, open URL dialog with an invalid link, desktop', (t) async {
    await shoot(
      t,
      'lobby_open_url_desktop',
      const LobbyScreen(),
      platform: TargetPlatform.windows,
      overrides: screenOverrides(library: sampleLibrary()),
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('open-url')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.enterText(find.byType(TextField), 'my film.mkv');
        await t.tap(find.byKey(const ValueKey('url-play')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 200));
      },
    );
  });

  testWidgets('lobby, open URL dialog, phone', (t) async {
    await shoot(
      t,
      'lobby_open_url_phone',
      const LobbyScreen(),
      size: kPhone,
      overrides: screenOverrides(),
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('open-url')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  });

  // ── Settings (Ticket office) ──

  testWidgets('settings, section list, phone', (t) async {
    await shoot(
      t,
      'settings_index_phone',
      const TicketOfficeScreen(),
      size: kPhone,
      overrides: screenOverrides(),
    );
  });

  for (final section in SettingsSection.values) {
    testWidgets('settings, ${section.name}, desktop', (t) async {
      await shoot(
        t,
        'settings_${section.name}_desktop',
        TicketOfficeScreen(initialSection: section),
        overrides: screenOverrides(
          settings: const Settings(languages: ['en', 'hi'], subdlEnabled: true),
        ),
      );
    });

    testWidgets('settings, ${section.name}, phone', (t) async {
      await shoot(
        t,
        'settings_${section.name}_phone',
        TicketOfficeScreen(initialSection: section),
        size: kPhone,
        overrides: screenOverrides(
          settings: const Settings(languages: ['en', 'hi'], subdlEnabled: true),
        ),
      );
    });
  }

  testWidgets('settings, subtitles, matinee, desktop', (t) async {
    await shoot(
      t,
      'settings_subtitles_matinee_desktop',
      const TicketOfficeScreen(initialSection: SettingsSection.subtitles),
      at: kDay,
      matinee: true,
      overrides: screenOverrides(
        settings: const Settings(
          lobbyTheme: LobbyTheme.matinee,
          subtitleLook: SubtitleLook.box,
          subtitleScale: 1.4,
        ),
      ),
    );
  });
}
