// Finding the videos on the device. Windows: a walk of the user's library folders on a
// background isolate (a sleeping network drive or a folder of 10 000 files never touches the UI
// isolate). Android: MediaStore through `marquee/content` (ContentChannel.kt), which needs the
// video permission and nothing else. Nothing here leaves the device.
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../engine/library.dart';

// ───────────────────────────── Windows: folders ─────────────────────────────

/// Every video under [roots], found on a background isolate. Unreadable folders are skipped;
/// the walk is bounded ([kScanMaxDepth], [kScanMaxItems]) and never follows links, so a
/// junction loop cannot trap it.
Future<List<LibraryItem>> scanFolders(List<String> roots) {
  if (roots.isEmpty) return Future.value(const []);
  final folders = List<String>.of(roots);
  return Isolate.run(() => scanFoldersSync(folders), debugName: 'library scan');
}

/// The walk itself (synchronous IO: only ever run it off the UI isolate).
List<LibraryItem> scanFoldersSync(
  List<String> roots, {
  int maxDepth = kScanMaxDepth,
  int maxItems = kScanMaxItems,
  int maxFolders = 50000,
}) {
  final found = <LibraryItem>[];
  // Two library folders may overlap (Videos and Videos\Series): list each folder once.
  final seen = <String>{};
  void walk(Directory dir, int depth) {
    // A whole drive added as a library folder must still end: the folder count is bounded too.
    if (found.length >= maxItems || seen.length >= maxFolders) return;
    if (!seen.add(p.canonicalize(dir.path))) return;
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      return; // no permission, an unplugged drive, a folder deleted mid-scan
    }
    final below = <Directory>[];
    for (final e in entries) {
      final name = p.basename(e.path);
      if (e is Directory) {
        if (depth < maxDepth && !isSkippedFolder(name)) below.add(e);
      } else if (e is File && isLibraryVideo(name)) {
        if (found.length >= maxItems) return;
        try {
          final stat = e.statSync();
          if (stat.type != FileSystemEntityType.file || stat.size <= 0) continue;
          // On Windows `changed` is the creation time: a film copied here today is new today,
          // whatever its original date.
          final arrived = stat.changed.isAfter(stat.modified) ? stat.changed : stat.modified;
          found.add(LibraryItem.fromPath(e.path, sizeBytes: stat.size, modifiedAt: arrived));
        } on FileSystemException {
          // Locked or gone: leave it out.
        }
      }
    }
    for (final d in below) {
      walk(d, depth + 1);
    }
  }

  for (final root in roots) {
    walk(Directory(root), 0);
  }
  return found;
}

/// The folders most people keep videos in, offered as one-tap suggestions on first run. Only
/// the ones that exist.
Future<List<String>> suggestedLibraryFolders() async {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null || home.isEmpty) return const [];
  final out = <String>[];
  for (final name in const ['Videos', 'Downloads']) {
    final dir = Directory(p.join(home, name));
    try {
      if (await dir.exists()) out.add(dir.path);
    } on FileSystemException {
      // A redirected folder that is offline: not a suggestion.
    }
  }
  return out;
}

/// The system folder picker ("Add folder"); null when cancelled.
Future<String?> pickLibraryFolder() =>
    FilePicker.platform.getDirectoryPath(dialogTitle: 'Add a folder of videos');

Future<bool> folderExists(String path) async {
  try {
    return await Directory(path).exists();
  } on FileSystemException {
    return false;
  }
}

/// Opens the file's folder in Explorer with the file selected. False when Explorer could not
/// be started.
Future<bool> revealInFolder(String path) async {
  if (!Platform.isWindows) return false;
  try {
    // `/select,` and the path are separate arguments so a path with spaces is quoted once.
    await Process.start('explorer.exe', [
      '/select,',
      p.normalize(path),
    ], mode: ProcessStartMode.detached);
    return true;
  } on Object {
    return false;
  }
}

// ───────────────────────────── Android: MediaStore ─────────────────────────────

const _content = MethodChannel('marquee/content');

/// What Android lets Marquee see. [partial] is Android 14's "selected videos only".
enum VideoAccess { granted, partial, denied }

VideoAccess _access(String? s) => switch (s) {
  'granted' => VideoAccess.granted,
  'partial' => VideoAccess.partial,
  _ => VideoAccess.denied,
};

/// The current permission, without asking.
Future<VideoAccess> videoPermission() async {
  try {
    return _access(await _content.invokeMethod<String>('videoPermission'));
  } on PlatformException {
    return VideoAccess.denied;
  } on MissingPluginException {
    return VideoAccess.denied;
  }
}

/// Shows the system permission dialog (when Android still allows it) and returns the answer.
Future<VideoAccess> requestVideoPermission() async {
  try {
    return _access(await _content.invokeMethod<String>('requestVideoPermission'));
  } on PlatformException {
    return videoPermission(); // a request was already open, or there is no activity
  } on MissingPluginException {
    return VideoAccess.denied;
  }
}

/// Every video MediaStore knows (all of them, or the ones the user selected). Empty without
/// permission. THROWS when the scan itself failed: a failure must never be taken for an empty
/// library (the caller keeps the list it has).
Future<List<LibraryItem>> scanMediaStore() async {
  final rows = await _content.invokeListMethod<Object?>('scanVideos');
  if (rows == null) return const [];
  final out = <LibraryItem>[];
  for (final r in rows) {
    if (r is! Map) continue;
    final uri = r['uri'];
    if (uri is! String) continue;
    int? positive(Object? v) => v is num && v > 0 ? v.toInt() : null;
    final folderPath = r['folderPath'] is String ? r['folderPath'] as String : '';
    final folder = r['folder'] is String ? r['folder'] as String : '';
    out.add(
      LibraryItem(
        locator: uri,
        name: r['name'] is String ? r['name'] as String : 'video',
        folderPath: folderPath,
        folderName: folder.isNotEmpty
            ? folder
            : (folderPath.isEmpty ? 'Internal storage' : p.posix.basename(folderPath)),
        sizeBytes: positive(r['size']) ?? 0,
        durationMs: positive(r['durationMs']),
        width: positive(r['width']),
        height: positive(r['height']),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(positive(r['modified']) ?? 0),
      ),
    );
  }
  return out;
}

/// The system's own thumbnail for a MediaStore video as JPEG bytes; null when there is none.
/// THROWS on a channel error (a revoked grant, a busy system): that is "not now", which the
/// caller must not remember as "this video has no thumbnail".
Future<Uint8List?> videoThumbnail(String uri, {int width = 320}) async {
  final bytes = await _content.invokeMethod<Uint8List>('videoThumbnail', {
    'uri': uri,
    'width': width,
  });
  return bytes == null || bytes.isEmpty ? null : bytes;
}

/// Copies a JPEG the app wrote (a screenshot at [path]) into the shared Pictures/Marquee album
/// as [name], so the Gallery shows it. False when it was not saved: before Android 10 (where
/// that would need a storage permission Marquee does not ask for), on other platforms, or
/// when the copy failed.
Future<bool> saveImageToGallery(String path, String name) async {
  if (!Platform.isAndroid) return false;
  try {
    return await _content.invokeMethod<bool>('saveImageToGallery', {'path': path, 'name': name}) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Opens Android's share sheet for a library video. False when it could not open.
Future<bool> shareVideo(String uri, String name) async {
  try {
    await _content.invokeMethod<void>('shareVideo', {'uri': uri, 'name': name});
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
