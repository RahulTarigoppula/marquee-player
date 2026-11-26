// Screenshots of the Lobby's Library tab (the device library): folders, a folder opened, all
// videos, search, the menus, and every "nothing here yet" state on both platforms. Tagged
// `screenshot` like screenshots_test.dart; the data is fake and no platform channel is touched.
// A layout that overflows fails here, so the narrow sizes double as overflow checks.
@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/models/settings.dart';
import 'package:marquee/state/library.dart';
import 'package:marquee/ui/lobby/library_folders.dart';
import 'package:marquee/ui/lobby/lobby_screen.dart';

import 'harness.dart';

/// The smallest phone the layouts promise to fit, and the same phone on its side.
const kSmallPhone = Size(360, 740);
const kSmallLandscape = Size(640, 360);

const _windowsFolders = [r'D:\Films', r'D:\Shows', r'C:\Users\me\Videos', r'C:\Users\me\Downloads'];

/// The Library tab over the sample library, on Windows (folders) or Android (MediaStore).
Future<void> _library(
  WidgetTester t,
  String name, {
  bool android = false,
  Size size = kDesktop,
  bool allVideos = false,
  bool matinee = false,
  Settings settings = const Settings(),
  VideoAccess access = VideoAccess.granted,
  Future<void> Function(WidgetTester t)? act,
}) async {
  final items = sampleDeviceLibrary(android: android);
  final thumbs = fakeThumbnails();
  fakeLibraryThumbnails(thumbs, items);
  await shoot(
    t,
    name,
    const LobbyScreen(),
    size: size,
    at: matinee ? kDay : null,
    matinee: matinee,
    platform: android ? TargetPlatform.android : TargetPlatform.windows,
    thumbnails: thumbs,
    overrides: screenOverrides(
      library: sampleLibraryHistory(android: android),
      settings: settings,
      thumbnails: thumbs,
      deviceLibrary: DeviceLibrary(
        source: android ? LibrarySource.mediaStore : LibrarySource.folders,
        items: items,
        access: access,
        scanned: true,
      ),
      libraryFolders: android ? const [] : _windowsFolders,
      lobbyView: LobbyView(tab: LobbyTab.library, allVideos: allVideos),
    ),
    // Two more frames than the Home tab needs: the tab, then the library, then its frames.
    act: (t) async {
      await _settle(t);
      await act?.call(t);
    },
  );
}

/// The Library tab with nothing to list.
Future<void> _empty(
  WidgetTester t,
  String name, {
  required DeviceLibrary library,
  Size size = kDesktop,
  List<String> folders = const [],
  List<String> suggestions = const [],
}) => shoot(
  t,
  name,
  const LobbyScreen(),
  size: size,
  platform: library.source == LibrarySource.mediaStore
      ? TargetPlatform.android
      : TargetPlatform.windows,
  overrides: screenOverrides(
    deviceLibrary: library,
    libraryFolders: folders,
    librarySuggestions: suggestions,
    lobbyView: const LobbyView(tab: LobbyTab.library),
  ),
  // The folder list and the suggestions arrive a frame after the library itself.
  act: _settle,
);

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _openFolder(WidgetTester t, String path) async {
  // On a short screen the card can be built but below the fold, which finders skip by default
  // (and a tap there would miss): find it anyway and bring it into view.
  final folder = find.byKey(ValueKey('folder-$path'), skipOffstage: false);
  await t.ensureVisible(folder);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(folder);
  await _settle(t);
}

Future<void> _search(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const ValueKey('library-search')), text);
  await _settle(t);
}

String _locator(String nameStart, {bool android = false}) =>
    sampleDeviceLibrary(android: android).firstWhere((i) => i.name.startsWith(nameStart)).locator;

void main() {
  // ── folders ──

  testWidgets('library, folders, desktop', (t) async {
    await _library(t, 'library_folders_desktop');
  });

  testWidgets('library, folders, phone', (t) async {
    await _library(t, 'library_folders_phone', android: true, size: kPhone);
  });

  testWidgets('library, folders, phone landscape', (t) async {
    await _library(t, 'library_folders_phone_landscape', android: true, size: kPhoneLandscape);
  });

  testWidgets('library, folders, newest first, matinee, desktop', (t) async {
    await _library(
      t,
      'library_folders_matinee_desktop',
      matinee: true,
      settings: const Settings(lobbyTheme: LobbyTheme.matinee, librarySort: LibrarySort.newest),
    );
  });

  // ── a folder, opened ──

  testWidgets('library, folder opened, desktop', (t) async {
    await _library(
      t,
      'library_folder_open_desktop',
      act: (t) => _openFolder(t, r'D:\Shows\Severance'),
    );
  });

  testWidgets('library, folder opened, phone', (t) async {
    await _library(
      t,
      'library_folder_open_phone',
      android: true,
      size: kPhone,
      act: (t) => _openFolder(t, 'Movies/Severance'),
    );
  });

  testWidgets('library, folder opened, phone landscape', (t) async {
    await _library(
      t,
      'library_folder_open_phone_landscape',
      android: true,
      size: kPhoneLandscape,
      act: (t) => _openFolder(t, 'Movies/Severance'),
    );
  });

  // ── all videos ──

  testWidgets('library, all videos, desktop', (t) async {
    await _library(t, 'library_all_videos_desktop', allVideos: true);
  });

  testWidgets('library, all videos, largest first, phone', (t) async {
    await _library(
      t,
      'library_all_videos_phone',
      android: true,
      size: kPhone,
      allVideos: true,
      settings: const Settings(librarySort: LibrarySort.largest),
    );
  });

  testWidgets('library, all videos, phone landscape', (t) async {
    await _library(
      t,
      'library_all_videos_phone_landscape',
      android: true,
      size: kPhoneLandscape,
      allVideos: true,
    );
  });

  testWidgets('library, all videos, 360 px phone', (t) async {
    await _library(
      t,
      'library_all_videos_small_phone',
      android: true,
      size: kSmallPhone,
      allVideos: true,
    );
  });

  testWidgets('library, all videos, 640 x 360 landscape', (t) async {
    await _library(
      t,
      'library_all_videos_small_landscape',
      android: true,
      size: kSmallLandscape,
      allVideos: true,
    );
  });

  testWidgets('library, all videos, scrolled (pinned toolbar), desktop', (t) async {
    await _library(
      t,
      'library_all_videos_scrolled_desktop',
      allVideos: true,
      act: (t) async {
        await t.drag(find.byType(CustomScrollView), const Offset(0, -260));
        await _settle(t);
      },
    );
  });

  // ── search ──

  testWidgets('library, search, desktop', (t) async {
    await _library(t, 'library_search_desktop', allVideos: true, act: (t) => _search(t, 'sever'));
  });

  testWidgets('library, search across folders, phone', (t) async {
    await _library(
      t,
      'library_search_phone',
      android: true,
      size: kPhone,
      act: (t) => _search(t, 'third man'),
    );
  });

  testWidgets('library, search with no match, desktop', (t) async {
    await _library(t, 'library_search_none_desktop', act: (t) => _search(t, 'casablanca'));
  });

  // ── menus ──

  testWidgets('library, video menu, desktop', (t) async {
    await _library(
      t,
      'library_item_menu_desktop',
      allVideos: true,
      act: (t) async {
        final more = find.byKey(ValueKey('lib-more-${_locator('Severance.S02E03')}'));
        await t.ensureVisible(more);
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(more);
        await _settle(t);
      },
    );
  });

  testWidgets('library, video menu, phone', (t) async {
    await _library(
      t,
      'library_item_menu_phone',
      android: true,
      size: kPhone,
      act: (t) async {
        await _openFolder(t, 'Movies');
        await t.longPress(find.byKey(ValueKey('lib-${_locator('The.Third.Man', android: true)}')));
        await _settle(t);
      },
    );
  });

  testWidgets('library, video details, desktop', (t) async {
    await _library(
      t,
      'library_details_desktop',
      allVideos: true,
      act: (t) async {
        final more = find.byKey(ValueKey('lib-more-${_locator('The.Third.Man')}'));
        await t.ensureVisible(more);
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(more);
        await _settle(t);
        await t.tap(find.text('Details'));
        await _settle(t);
      },
    );
  });

  testWidgets('library, sort menu, desktop', (t) async {
    await _library(
      t,
      'library_sort_menu_desktop',
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('library-sort')));
        await _settle(t);
      },
    );
  });

  // ── nothing to list yet ──

  testWidgets('library, first run on Windows: suggested folders, desktop', (t) async {
    await _empty(
      t,
      'library_first_run_desktop',
      library: const DeviceLibrary(source: LibrarySource.folders, scanned: true),
      suggestions: const [r'C:\Users\me\Videos', r'C:\Users\me\Downloads'],
    );
  });

  testWidgets('library, first run on Windows, no suggestions, narrow window', (t) async {
    await _empty(
      t,
      'library_first_run_narrow',
      size: kPhone,
      library: const DeviceLibrary(source: LibrarySource.folders, scanned: true),
    );
  });

  testWidgets('library, folders chosen but no videos, desktop', (t) async {
    await _empty(
      t,
      'library_no_videos_desktop',
      library: const DeviceLibrary(source: LibrarySource.folders, scanned: true),
      folders: const [r'C:\Users\me\Videos'],
    );
  });

  testWidgets('library, permission not asked yet, phone', (t) async {
    await _empty(
      t,
      'library_permission_phone',
      size: kPhone,
      library: const DeviceLibrary(
        source: LibrarySource.mediaStore,
        access: VideoAccess.denied,
        scanned: true,
      ),
    );
  });

  testWidgets('library, permission not asked yet, 640 x 360 landscape', (t) async {
    await _empty(
      t,
      'library_permission_small_landscape',
      size: kSmallLandscape,
      library: const DeviceLibrary(
        source: LibrarySource.mediaStore,
        access: VideoAccess.denied,
        scanned: true,
      ),
    );
  });

  testWidgets('library, permission refused, 360 px phone', (t) async {
    await _empty(
      t,
      'library_permission_refused_phone',
      size: kSmallPhone,
      library: const DeviceLibrary(
        source: LibrarySource.mediaStore,
        access: VideoAccess.denied,
        asked: true,
        scanned: true,
      ),
    );
  });

  testWidgets('library, allowed but no videos, phone', (t) async {
    await _empty(
      t,
      'library_no_videos_phone',
      size: kPhone,
      library: const DeviceLibrary(source: LibrarySource.mediaStore, scanned: true),
    );
  });

  testWidgets('library, only selected videos (Android 14), phone', (t) async {
    await _library(
      t,
      'library_partial_access_phone',
      android: true,
      size: kPhone,
      allVideos: true,
      access: VideoAccess.partial,
    );
  });

  // ── the folders card (Settings › Library) ──

  Widget card() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: const LibraryFoldersCard(),
      ),
    ),
  );

  testWidgets('library folders card, Windows, desktop', (t) async {
    await shoot(
      t,
      'library_folders_card_desktop',
      card(),
      overrides: screenOverrides(
        deviceLibrary: DeviceLibrary(
          source: LibrarySource.folders,
          items: sampleDeviceLibrary(),
          scanned: true,
        ),
        libraryFolders: _windowsFolders,
      ),
    );
  });

  testWidgets('library folders card, Windows, no folders yet, phone width', (t) async {
    await shoot(
      t,
      'library_folders_card_empty_narrow',
      card(),
      size: kSmallPhone,
      overrides: screenOverrides(
        librarySuggestions: const [r'C:\Users\me\Videos', r'C:\Users\me\Downloads'],
      ),
    );
  });

  for (final (name, access, asked) in const [
    ('granted', VideoAccess.granted, false),
    ('partial', VideoAccess.partial, false),
    ('not_asked', VideoAccess.denied, false),
    ('refused', VideoAccess.denied, true),
  ]) {
    testWidgets('library folders card, Android, $name, phone', (t) async {
      await shoot(
        t,
        'library_folders_card_android_$name',
        card(),
        size: kSmallPhone,
        platform: TargetPlatform.android,
        overrides: screenOverrides(
          deviceLibrary: DeviceLibrary(
            source: LibrarySource.mediaStore,
            items: access == VideoAccess.denied ? const [] : sampleDeviceLibrary(android: true),
            access: access,
            asked: asked,
            scanned: true,
          ),
        ),
      );
    });
  }
}
