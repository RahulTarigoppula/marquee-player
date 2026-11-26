// The device library: every video on the device (Windows: the user's library folders; Android:
// MediaStore), kept beside the play history in the Lobby. The Lobby's first frame never waits
// for it: the last scan is shown at once from a small cache, and a fresh scan runs behind it
// on app start, on refresh, when the folders change and after a minute away.
import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/library.dart';
import '../engine/models/media.dart';
import '../engine/models/settings.dart';
import '../platform/library_scan.dart';
import '../player/thumbnailer.dart';
import 'providers.dart';
import 'session.dart';
import 'thumbnails.dart';

export '../engine/library.dart';
export '../platform/library_scan.dart' show VideoAccess;

const _cacheKey = 'library_cache';
const _askedKey = 'library_permission_asked';
const _viewKey = 'lobby_view';

/// Back in the app after this long away: look for new videos.
const Duration kRescanAfterAway = Duration(minutes: 1);

/// Where the library comes from on this device.
enum LibrarySource {
  /// Folders the user chose (Windows).
  folders,

  /// The system's video collection, behind the video permission (Android).
  mediaStore,
}

/// Overridden in tests to draw the other platform's states.
final librarySourceProvider = Provider<LibrarySource>(
  (ref) => Platform.isAndroid ? LibrarySource.mediaStore : LibrarySource.folders,
);

/// The user's library folders (Windows paths), oldest first.
final libraryFoldersProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(databaseProvider).watchFolders(),
);

/// Videos and Downloads, when they exist and are not library folders yet: the first-run
/// one-tap suggestions.
final librarySuggestionsProvider = FutureProvider<List<String>>((ref) async {
  if (ref.watch(librarySourceProvider) != LibrarySource.folders) return const [];
  final have = {
    for (final f in ref.watch(libraryFoldersProvider).value ?? const <String>[]) f.toLowerCase(),
  };
  return [
    for (final s in await suggestedLibraryFolders())
      if (!have.contains(s.toLowerCase())) s,
  ];
});

class DeviceLibrary {
  final LibrarySource source;
  final List<LibraryItem> items;

  /// Android only; a folder library is always [VideoAccess.granted].
  final VideoAccess access;

  /// The system's permission dialog has been answered with a no: Android may not show it
  /// again, so the Lobby offers the file picker instead of asking twice.
  final bool asked;
  final bool scanning;

  /// A scan (or the cache of an earlier one) has answered: an empty list means "no videos",
  /// not "not looked yet".
  final bool scanned;

  const DeviceLibrary({
    required this.source,
    this.items = const [],
    this.access = VideoAccess.granted,
    this.asked = false,
    this.scanning = false,
    this.scanned = false,
  });

  DeviceLibrary copyWith({
    List<LibraryItem>? items,
    VideoAccess? access,
    bool? asked,
    bool? scanning,
    bool? scanned,
  }) => DeviceLibrary(
    source: source,
    items: items ?? this.items,
    access: access ?? this.access,
    asked: asked ?? this.asked,
    scanning: scanning ?? this.scanning,
    scanned: scanned ?? this.scanned,
  );
}

class DeviceLibraryNotifier extends AsyncNotifier<DeviceLibrary> {
  Timer? _first;
  Timer? _probeFlush;
  final _probes = <String, FrameProbe>{};
  int _scanSeq = 0;
  DateTime? _leftAt;

  /// A rescan was due while a film was playing: it runs when the film closes.
  bool _stale = false;

  @override
  Future<DeviceLibrary> build() async {
    final source = ref.watch(librarySourceProvider);
    ref.onDispose(() {
      _first?.cancel();
      _probeFlush?.cancel();
    });
    List<LibraryItem>? cached;
    var asked = false;
    try {
      final db = ref.read(databaseProvider);
      cached = decodeLibraryCache(await db.readState(_cacheKey));
      asked = await db.readState(_askedKey) == true;
    } on Object {
      cached = null; // an unreadable cache is no cache: the scan below fills the library
    }
    var access = VideoAccess.granted;
    if (source == LibrarySource.mediaStore) {
      try {
        access = await videoPermission();
      } on Object {
        access = VideoAccess.denied;
      }
    }

    if (source == LibrarySource.folders) {
      // A folder added or removed (here or in Settings) rescans. The first load is not a
      // change: the start-up scan below covers it.
      ref.listen(libraryFoldersProvider, (prev, next) {
        if (prev?.value != null && next.value != null && !_same(prev!.value!, next.value!)) {
          unawaited(refresh());
        }
      });
    }
    ref.listen(sessionProvider.select((s) => s != null), (_, playing) {
      if (!playing && _stale) unawaited(refresh());
    });
    // After the frame that shows the cache, never before it.
    _first = Timer(const Duration(milliseconds: 250), () => unawaited(refresh()));
    return DeviceLibrary(
      source: source,
      items: access == VideoAccess.denied ? const [] : (cached ?? const []),
      access: access,
      asked: asked,
      scanning: true,
      scanned: cached != null,
    );
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Looks again. Never throws: a scan that fails leaves the library as it was. The newest
  /// call wins; an older scan still running is ignored when it lands.
  Future<void> refresh() async {
    final seq = ++_scanSeq;
    _stale = false;
    final DeviceLibrary before;
    try {
      before = await future;
    } on Object {
      return;
    }
    if (seq != _scanSeq || !ref.mounted) return;
    state = AsyncData((state.value ?? before).copyWith(scanning: true));
    List<LibraryItem>? found;
    var access = before.access;
    try {
      if (before.source == LibrarySource.mediaStore) {
        access = await videoPermission();
        found = access == VideoAccess.denied ? const [] : await scanMediaStore();
      } else {
        found = await scanFolders(await ref.read(libraryFoldersProvider.future));
      }
    } on Object {
      found = null;
    }
    if (seq != _scanSeq || !ref.mounted) return;
    final now = state.value ?? before;
    if (found == null) {
      state = AsyncData(now.copyWith(scanning: false, access: access));
      return;
    }
    final items = carryProbes(found, now.items);
    final changed = !sameLibrary(items, now.items);
    // An unchanged scan keeps the SAME list, so nothing downstream regroups or resorts.
    state = AsyncData(
      now.copyWith(
        items: changed ? items : now.items,
        access: access,
        scanning: false,
        scanned: true,
      ),
    );
    if (changed) {
      unawaited(_saveCache(items));
      unawaited(
        ref.read(libraryThumbsProvider.notifier).prune({for (final i in items) thumbKey(i)}),
      );
    }
  }

  Future<void> _saveCache(List<LibraryItem> items) async {
    try {
      await ref.read(databaseProvider).writeState(_cacheKey, encodeLibraryCache(items));
    } on Object {
      // The next start-up scans without a head start.
    }
  }

  /// Android: shows the system dialog (when Android still allows one) and scans on a yes.
  Future<void> requestAccess() async {
    final DeviceLibrary before;
    try {
      before = await future;
    } on Object {
      return;
    }
    final access = await requestVideoPermission();
    if (!ref.mounted) return;
    final asked = access == VideoAccess.denied;
    state = AsyncData((state.value ?? before).copyWith(access: access, asked: asked));
    try {
      await ref.read(databaseProvider).writeState(_askedKey, asked);
    } on Object {
      // Remembered for this run only.
    }
    if (access != VideoAccess.denied) await refresh();
  }

  /// The app lost the foreground (or the window its focus).
  void wentAway() => _leftAt ??= clock.now();

  /// Back in front: look again after [kRescanAfterAway]. Android re-reads the permission
  /// either way (it may have been changed in the system settings a moment ago).
  void cameBack() {
    final left = _leftAt;
    _leftAt = null;
    final cur = state.value;
    if (left == null || cur == null) return;
    final longAway = clock.now().difference(left) >= kRescanAfterAway;
    if (ref.read(sessionProvider) != null) {
      _stale = _stale || longAway;
      return;
    }
    if (longAway) {
      unawaited(refresh());
    } else if (cur.source == LibrarySource.mediaStore) {
      unawaited(_recheckAccess(cur.access));
    }
  }

  Future<void> _recheckAccess(VideoAccess had) async {
    final access = await videoPermission();
    if (ref.mounted && access != had) await refresh();
  }

  /// What the thumbnailer learned about a file (the Windows scan knows names and sizes only).
  /// Batched: frames arrive a few a second, the list should not be rebuilt for each.
  void applyProbe(String locator, FrameProbe probe) {
    if (probe.durationMs == null && probe.width == null && probe.height == null) return;
    _probes[locator] = probe;
    _probeFlush ??= Timer(const Duration(seconds: 3), _flushProbes);
  }

  void _flushProbes() {
    _probeFlush = null;
    final cur = state.value;
    if (cur == null || _probes.isEmpty || !ref.mounted) return;
    final probes = Map.of(_probes);
    _probes.clear();
    final items = [
      for (final i in cur.items)
        switch (probes[i.locator]) {
          final p? => i.withProbe(durationMs: p.durationMs, width: p.width, height: p.height),
          null => i,
        },
    ];
    state = AsyncData((state.value ?? cur).copyWith(items: items));
    unawaited(_saveCache(items));
  }

  // ───────────────────────────── folders (Windows) ─────────────────────────────

  /// Adds a library folder; the scan follows by itself. A folder already in the list (in any
  /// letter case, with or without a trailing slash) is not added twice.
  Future<void> addLibraryFolder(String path) async {
    var clean = path.trim();
    while (clean.length > 3 && (clean.endsWith(r'\') || clean.endsWith('/'))) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.isEmpty) return;
    final db = ref.read(databaseProvider);
    final have = await db.libraryFolders();
    if (have.any((f) => f.toLowerCase() == clean.toLowerCase())) return;
    await db.addFolder(clean);
  }

  Future<void> removeLibraryFolder(String path) => ref.read(databaseProvider).removeFolder(path);

  /// The system folder picker, then [addLibraryFolder]. False when nothing was added.
  Future<bool> pickAndAddFolder() async {
    final path = await pickLibraryFolder();
    if (path == null) return false;
    await addLibraryFolder(path);
    return true;
  }

  /// "Play from the start": forget where [card] stopped, so the film opens at the beginning.
  Future<void> forgetResume(LobbyCard card) async {
    final hash = card.hash;
    if (hash == null) return;
    await ref.read(databaseProvider).saveResume(hash, 0, card.durationMs ?? 0);
  }
}

final deviceLibraryProvider = AsyncNotifierProvider<DeviceLibraryNotifier, DeviceLibrary>(
  DeviceLibraryNotifier.new,
);

/// The folder's previous and next video and its first one, for a film that is in the device
/// library; all null when it is not. On Android this is the only way to know a film's
/// neighbours (a content:// URI has no folder to list).
final libraryNeighboursProvider =
    Provider<({String? previous, String? next, String? first}) Function(String locator)>((ref) {
      final items =
          ref.watch(deviceLibraryProvider.select((s) => s.value?.items)) ?? const <LibraryItem>[];
      return (locator) => libraryNeighbours(items, locator);
    });

// ───────────────────────────── play history, joined by locator ─────────────────────────────

/// Windows paths compare without case; a content:// URI is exact.
String historyKey(String locator) => locator.contains('://') ? locator : locator.toLowerCase();

/// What the database knows about each file that has been played, by [historyKey]: resume
/// position, watched, the grabbed frame's id.
final libraryHistoryProvider = Provider<Map<String, LobbyCard>>((ref) {
  final cards = ref.watch(libraryProvider).value ?? const <LobbyCard>[];
  return {for (final c in cards) historyKey(c.locator): c};
});

// ───────────────────────────── what the Lobby shows ─────────────────────────────

enum LobbyTab { home, library }

/// The Lobby's remembered choices: the tab, and folders versus all videos.
class LobbyView {
  final LobbyTab tab;
  final bool allVideos;
  const LobbyView({this.tab = LobbyTab.home, this.allVideos = false});
}

class LobbyViewNotifier extends AsyncNotifier<LobbyView> {
  @override
  Future<LobbyView> build() async {
    try {
      final v = await ref.read(databaseProvider).readState(_viewKey);
      if (v is Map) {
        return LobbyView(
          tab: LobbyTab.values.asNameMap()[v['tab']] ?? LobbyTab.home,
          allVideos: v['allVideos'] == true,
        );
      }
    } on Object {
      // Defaults.
    }
    return const LobbyView();
  }

  void _set(LobbyView v) {
    state = AsyncData(v);
    unawaited(
      ref
          .read(databaseProvider)
          .writeState(_viewKey, {'tab': v.tab.name, 'allVideos': v.allVideos})
          .then((_) {}, onError: (Object _) {}),
    );
  }

  void setTab(LobbyTab tab) {
    final cur = state.value ?? const LobbyView();
    if (cur.tab != tab) _set(LobbyView(tab: tab, allVideos: cur.allVideos));
  }

  void setAllVideos(bool all) {
    final cur = state.value ?? const LobbyView();
    if (cur.allVideos != all) _set(LobbyView(tab: cur.tab, allVideos: all));
  }
}

final lobbyViewProvider = AsyncNotifierProvider<LobbyViewNotifier, LobbyView>(
  LobbyViewNotifier.new,
);

/// Where the Library tab is right now (not remembered across launches): the search text and
/// the folder that is open.
class LibraryBrowse {
  final String query;
  final String? folder;
  const LibraryBrowse({this.query = '', this.folder});
}

class LibraryBrowseNotifier extends Notifier<LibraryBrowse> {
  @override
  LibraryBrowse build() => const LibraryBrowse();

  void setQuery(String q) {
    if (q != state.query) state = LibraryBrowse(query: q, folder: state.folder);
  }

  void openFolder(String path) => state = LibraryBrowse(folder: path);

  void closeFolder() => state = LibraryBrowse(query: state.query);

  /// One step back (Android Back, Esc): out of the search, then out of the folder. False when
  /// there was nothing to step out of.
  bool back() {
    if (state.query.isNotEmpty) {
      state = LibraryBrowse(folder: state.folder);
      return true;
    }
    if (state.folder != null) {
      state = const LibraryBrowse();
      return true;
    }
    return false;
  }
}

final libraryBrowseProvider = NotifierProvider<LibraryBrowseNotifier, LibraryBrowse>(
  LibraryBrowseNotifier.new,
);

/// True while Back in the Lobby has a step to undo before it may leave the app.
final lobbyCanGoBackProvider = Provider<bool>((ref) {
  final onLibrary = ref.watch(lobbyViewProvider.select((v) => v.value?.tab == LobbyTab.library));
  final browse = ref.watch(libraryBrowseProvider);
  return onLibrary && (browse.folder != null || browse.query.isNotEmpty);
});

/// What the Library tab lists, already grouped, filtered and sorted (never in a build method:
/// the library can be thousands of videos).
class LibraryListing {
  /// The folder cards; empty whenever [videos] is what shows.
  final List<LibraryFolder> folders;
  final List<LibraryItem> videos;

  /// The folder that is open, when one is.
  final LibraryFolder? folder;
  final bool showsFolders;

  /// Every video in the library, before any filter.
  final int total;
  final String query;
  const LibraryListing({
    this.folders = const [],
    this.videos = const [],
    this.folder,
    this.showsFolders = false,
    this.total = 0,
    this.query = '',
  });
}

final libraryListingProvider = Provider<LibraryListing>((ref) {
  final items =
      ref.watch(deviceLibraryProvider.select((s) => s.value?.items)) ?? const <LibraryItem>[];
  final sort = ref.watch(settingsValueProvider.select((s) => s.librarySort));
  final browse = ref.watch(libraryBrowseProvider);
  final all = ref.watch(lobbyViewProvider.select((v) => v.value?.allVideos ?? false));
  final query = browse.query.trim();
  final folderPath = browse.folder;
  if (folderPath != null) {
    final inside = inFolder(items, folderPath);
    // The folder vanished in a rescan: fall back to the list it was opened from.
    if (inside.isNotEmpty) {
      return LibraryListing(
        videos: sortLibrary(searchLibrary(inside, query), sort),
        folder: groupFolders(inside).first,
        total: items.length,
        query: query,
      );
    }
  }
  if (query.isNotEmpty) {
    return LibraryListing(
      videos: sortLibrary(searchLibrary(items, query), sort),
      total: items.length,
      query: query,
    );
  }
  if (all) return LibraryListing(videos: sortLibrary(items, sort), total: items.length);
  return LibraryListing(
    folders: groupFolders(items, sort: sort),
    showsFolders: true,
    total: items.length,
  );
});

/// Changes the library's order (kept in Settings).
void setLibrarySort(WidgetRef ref, LibrarySort sort) =>
    unawaited(ref.read(settingsProvider.notifier).edit((s) => s.copyWith(librarySort: sort)));

// ───────────────────────────── frames for unplayed videos ─────────────────────────────

/// Where a card asks for a frame it does not have. Overridden in tests with one that does
/// nothing.
abstract interface class LibraryThumbRequests {
  void request(LibraryItem item);

  /// The card that asked has left the screen: its frame can wait until it is back.
  void cancel(LibraryItem item);
}

/// A sanity bound on waiting requests (cards cancel theirs as they scroll away, so the queue
/// is normally just what is on screen); beyond it the oldest are dropped.
const int kThumbBacklog = 400;

/// Windows grabs at most this many frames per run of the app: a huge library fills in over a
/// few sessions instead of keeping the disk busy for an hour.
const int kThumbsPerRun = 400;

/// Frames are made one at a time, in the order the cards on screen asked (top to bottom), with
/// a pause between them, and not at all while a film is playing or the app is out of sight.
class LibraryThumbQueue implements LibraryThumbRequests {
  LibraryThumbQueue(this._ref);
  final Ref _ref;

  /// Waiting requests by [thumbKey], oldest first (a Dart map keeps insertion order).
  final _pending = <String, LibraryItem>{};
  String? _inHand;
  FrameGrabber? _grabber;
  bool _running = false;
  bool _paused = false;
  bool _disposed = false;
  int _made = 0;

  @override
  void request(LibraryItem item) {
    if (_disposed) return;
    final key = thumbKey(item);
    if (key == _inHand || _pending.containsKey(key)) return;
    if (!_ref.read(libraryThumbsProvider).wants(key)) return;
    _pending[key] = item;
    if (_pending.length > kThumbBacklog) _pending.remove(_pending.keys.first);
    unawaited(_pump());
  }

  @override
  void cancel(LibraryItem item) => _pending.remove(thumbKey(item));

  /// A film is about to play: stop after the frame in hand and give libmpv back.
  void pause() {
    _paused = true;
    unawaited(_grabber?.release());
  }

  void resume() {
    _paused = false;
    unawaited(_pump());
  }

  /// Back in sight: carry on, unless a film is still playing.
  void kick() => unawaited(_pump());

  bool get _inSight {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty && !_paused && !_disposed && _inSight) {
        final source = _ref.read(librarySourceProvider);
        if (source == LibrarySource.folders && (_made >= kThumbsPerRun || !Platform.isWindows)) {
          _pending.clear();
          break;
        }
        final key = _pending.keys.first;
        final item = _pending.remove(key)!;
        _inHand = key;
        try {
          await (source == LibrarySource.mediaStore ? _fromSystem(item, key) : _grab(item, key));
        } on Object {
          // Silent by design: the card keeps its title card.
        }
        _inHand = null;
        // Low priority: leave the UI a moment between frames.
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      _running = false;
    }
  }

  /// Android: the system already has a thumbnail for every MediaStore video.
  Future<void> _fromSystem(LibraryItem item, String key) async {
    final thumbs = _ref.read(libraryThumbsProvider.notifier);
    final bytes = await videoThumbnail(item.locator, width: 480);
    if (_disposed) return;
    if (bytes == null) {
      await thumbs.markFailed(key);
      return;
    }
    final dir = await _ref.read(libraryThumbDirProvider.future);
    final part = File(libraryThumbPartPath(dir, key));
    await part.writeAsBytes(bytes);
    await part.rename(libraryThumbPath(dir, key));
    await thumbs.markReady(key);
  }

  /// Windows: one hidden player reads a frame out of the file.
  Future<void> _grab(LibraryItem item, String key) async {
    final thumbs = _ref.read(libraryThumbsProvider.notifier);
    final dir = await _ref.read(libraryThumbDirProvider.future);
    final grabber = _grabber ??= FrameGrabber();
    final result = await grabber.grab(
      item.locator,
      libraryThumbPath(dir, key),
      partPath: libraryThumbPartPath(dir, key),
    );
    if (_disposed) return;
    switch (result.outcome) {
      case GrabOutcome.done:
        _made++;
        await thumbs.markReady(key);
        final probe = result.probe;
        if (probe != null) {
          _ref.read(deviceLibraryProvider.notifier).applyProbe(item.locator, probe);
        }
      case GrabOutcome.failed:
        _made++;
        await thumbs.markFailed(key);
      case GrabOutcome.aborted:
        break; // asked again the next time its card is built
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    unawaited(_grabber?.dispose());
  }
}

final libraryThumbQueueProvider = Provider<LibraryThumbRequests>((ref) {
  final queue = LibraryThumbQueue(ref);
  ref.listen(sessionProvider.select((s) => s != null), (_, playing) {
    if (playing) {
      queue.pause();
    } else {
      queue.resume();
    }
  }, fireImmediately: true);
  // Frames stop while the window is hidden (libmpv's hidden player needs a drawn frame to
  // start); pick the queue up again when it is back.
  final lifecycle = AppLifecycleListener(onResume: queue.kick, onShow: queue.kick);
  ref.onDispose(() {
    lifecycle.dispose();
    queue.dispose();
  });
  return queue;
});
