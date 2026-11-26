// Lobby thumbnails: one JPEG per media row at <app support>/thumbs/<id>.jpg, grabbed from the
// player while a film plays. The Auditorium writes them; the Lobby reads them. A missing file
// is normal (never played long enough, or a remote stream) and shows the title card instead.
//
// The Lobby never touches the disk while it builds: [thumbnailIndexProvider] lists the folder
// once (and again only after a grab or a removal), and frames are decoded at card size
// ([thumbnailImage]), not at the film's own 1080p or 4K.
//
// Videos that were never played get their frame from the device library instead (the system's
// thumbnail on Android, a quiet background grab on Windows): one JPEG per file in the app's
// cache, named by the file's [thumbKey]. See [LibraryThumbsNotifier].
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Frames are decoded this wide (physical pixels): sharp on a 300 px card at 2x and on the
/// dimmed hero backdrop, a fraction of the memory and decode time of a full frame.
const int kThumbnailDecodeWidth = 640;

/// The folder that holds every thumbnail. Overridden in tests.
final thumbnailDirProvider = FutureProvider<Directory>((ref) async {
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'thumbs'));
  await dir.create(recursive: true);
  return dir;
});

/// Bumped after every write or delete so the index (and the cards) pick up the change.
class ThumbnailEpoch extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final thumbnailEpochProvider = NotifierProvider<ThumbnailEpoch, int>(ThumbnailEpoch.new);

String thumbnailPath(Directory dir, int mediaId) => p.join(dir.path, '$mediaId.jpg');

/// The media ids that have a saved frame. One directory listing per change, instead of a
/// `File.existsSync` per card per build (hover included).
final thumbnailIndexProvider = Provider<Set<int>>((ref) {
  ref.watch(thumbnailEpochProvider);
  final dir = ref.watch(thumbnailDirProvider).value;
  if (dir == null) return const {};
  try {
    return {
      for (final e in dir.listSync(followLinks: false))
        if (e is File) ?int.tryParse(p.basenameWithoutExtension(e.path)),
    };
  } on FileSystemException {
    return const {};
  }
});

/// The image a card draws for [file]: decoded at [kThumbnailDecodeWidth], never full size.
ImageProvider thumbnailImage(File file) =>
    ResizeImage(FileImage(file), width: kThumbnailDecodeWidth, policy: ResizeImagePolicy.fit);

Future<void> _evict(File f) async {
  await FileImage(f).evict();
  await thumbnailImage(f).evict();
}

/// Writes [jpeg] as the thumbnail for [mediaId], replacing any older frame.
Future<void> saveThumbnail(Ref ref, int mediaId, Uint8List jpeg) async {
  if (jpeg.isEmpty) return;
  final dir = await ref.read(thumbnailDirProvider.future);
  final f = File(thumbnailPath(dir, mediaId));
  await f.writeAsBytes(jpeg, flush: true);
  await _evict(f);
  ref.read(thumbnailEpochProvider.notifier).bump();
}

/// Where mpv should write the frame for [mediaId] (`screenshot-to-file`, no Dart encoding).
Future<String> thumbnailTarget(Ref ref, int mediaId) async =>
    thumbnailPath(await ref.read(thumbnailDirProvider.future), mediaId);

/// After mpv wrote [mediaId]'s file: drop the cached image so Lobby cards show the new frame.
Future<void> thumbnailWritten(Ref ref, int mediaId) async {
  final dir = await ref.read(thumbnailDirProvider.future);
  await _evict(File(thumbnailPath(dir, mediaId)));
  ref.read(thumbnailEpochProvider.notifier).bump();
}

/// Deletes the thumbnail when a film leaves the library.
Future<void> deleteThumbnail(Ref ref, int mediaId) async {
  try {
    final dir = await ref.read(thumbnailDirProvider.future);
    final f = File(thumbnailPath(dir, mediaId));
    if (await f.exists()) await f.delete();
    ref.read(thumbnailEpochProvider.notifier).bump();
  } on Object {
    // Best effort: a stale thumbnail costs a few KB.
  }
}

// ───────────────────────────── device-library frames ─────────────────────────────

/// The folder of device-library frames: `<key>.jpg` is a frame, an empty `<key>.fail` marks a
/// file that gave none (never tried again until the file itself changes, which changes its
/// key). In the app's CACHE folder: the system may clear it, and everything is re-made on
/// demand. Overridden in tests.
final libraryThumbDirProvider = FutureProvider<Directory>((ref) async {
  final dir = Directory(p.join((await getApplicationCacheDirectory()).path, 'libthumbs'));
  await dir.create(recursive: true);
  return dir;
});

String libraryThumbPath(Directory dir, String key) => p.join(dir.path, '$key.jpg');

String libraryThumbFailPath(Directory dir, String key) => p.join(dir.path, '$key.fail');

/// Mid-write name of a frame (mpv picks the format from the extension, so it still ends in
/// `.jpg`); renamed to [libraryThumbPath] once complete, so a card never decodes half a file.
String libraryThumbPartPath(Directory dir, String key) => p.join(dir.path, '$key.part.jpg');

/// Which device-library frames exist. Cards ask this, never the disk.
class LibraryThumbs {
  final Set<String> _ready;
  final Set<String> _failed;

  /// False until the folder has been listed once: nothing is requested before that, or every
  /// start-up would re-make frames that are already there.
  final bool loaded;
  const LibraryThumbs(this._ready, this._failed, {required this.loaded});

  bool has(String key) => _ready.contains(key);
  bool failed(String key) => _failed.contains(key);

  /// Nothing to show and nothing known against trying.
  bool wants(String key) => loaded && !_ready.contains(key) && !_failed.contains(key);
}

/// Frames older than this that belong to no video in the library are deleted.
const Duration kStaleThumbAfter = Duration(days: 30);

class LibraryThumbsNotifier extends Notifier<LibraryThumbs> {
  // Mutated in place and re-wrapped: a library of thousands must not copy two sets per frame.
  final _ready = <String>{};
  final _failed = <String>{};

  @override
  LibraryThumbs build() {
    unawaited(_load());
    return const LibraryThumbs({}, {}, loaded: false);
  }

  void _publish() => state = LibraryThumbs(_ready, _failed, loaded: true);

  /// One asynchronous listing at start-up (never `listSync`: the folder can hold thousands).
  Future<void> _load() async {
    try {
      final dir = await ref.read(libraryThumbDirProvider.future);
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        if (name.endsWith('.part.jpg')) {
          unawaited(e.delete().then((_) {}, onError: (Object _) {})); // a grab cut short
        } else if (name.endsWith('.jpg')) {
          _ready.add(name.substring(0, name.length - 4));
        } else if (name.endsWith('.fail')) {
          _failed.add(name.substring(0, name.length - 5));
        }
      }
    } on Object {
      // No cache folder: every card keeps its title card and nothing is requested twice.
    }
    if (ref.mounted) _publish();
  }

  /// A frame for [key] has been written.
  Future<void> markReady(String key) async {
    try {
      final dir = await ref.read(libraryThumbDirProvider.future);
      await _evict(File(libraryThumbPath(dir, key)));
    } on Object {
      // Nothing cached under that name yet.
    }
    if (!ref.mounted) return;
    _failed.remove(key);
    _ready.add(key);
    _publish();
  }

  /// [key]'s file gave no frame: remember it, here and on disk.
  Future<void> markFailed(String key) async {
    try {
      final dir = await ref.read(libraryThumbDirProvider.future);
      await File(libraryThumbFailPath(dir, key)).create();
    } on Object {
      // Remembered for this run only.
    }
    if (!ref.mounted) return;
    _failed.add(key);
    _publish();
  }

  /// Deletes frames (and failure marks) that belong to none of [live] and have not been
  /// touched for [kStaleThumbAfter]: a drive that was unplugged for a week keeps its frames.
  Future<void> prune(Set<String> live) async {
    try {
      final dir = await ref.read(libraryThumbDirProvider.future);
      final cutoff = DateTime.now().subtract(kStaleThumbAfter);
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final key = p.basename(e.path).split('.').first;
        if (live.contains(key)) continue;
        if ((await e.stat()).modified.isAfter(cutoff)) continue;
        await e.delete();
        _ready.remove(key);
        _failed.remove(key);
      }
    } on Object {
      // Best effort: a stale frame costs a few KB.
    }
  }
}

final libraryThumbsProvider = NotifierProvider<LibraryThumbsNotifier, LibraryThumbs>(
  LibraryThumbsNotifier.new,
);
