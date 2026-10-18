// File picking, sidecar detection and sidecar writing. Never overwrite an existing sidecar:
// add a `.1` suffix. If the folder is not writable, fall back to app storage — honestly.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../engine/filename.dart';
import '../engine/hash.dart';
import '../engine/playback.dart';

const _videoExtensions = [
  'mkv', 'mp4', 'm4v', 'avi', 'webm', 'mov', 'ts', 'm2ts', 'mts', 'wmv', 'flv', 'mpg', //
  'mpeg', '3gp', 'ogv', 'vob',
];
const _subtitleExtensions = ['srt', 'ass', 'ssa', 'vtt', 'sub'];

/// A film the user handed us. [locator] is a filesystem path or an Android content:// URI.
class OpenedFile {
  final String locator;
  final String displayName;
  final int sizeBytes;
  const OpenedFile({required this.locator, required this.displayName, required this.sizeBytes});

  bool get isContentUri => locator.startsWith('content://');

  /// A network stream (http, https, rtsp, …): no hash, no sidecar, no resume by hash.
  bool get isRemote => remoteSchemes.any((s) => locator.toLowerCase().startsWith('$s://'));
}

const remoteSchemes = ['http', 'https', 'rtsp', 'rtmp', 'mms', 'udp', 'srt'];

/// A URL the user typed or pasted ("Open URL…"), or null when it is not a playable address.
OpenedFile? openedFromUrl(String input) {
  final url = input.trim();
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !remoteSchemes.contains(uri.scheme.toLowerCase())) {
    return null;
  }
  if (uri.host.isEmpty) return null;
  final last = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  var name = last ?? uri.host;
  try {
    name = Uri.decodeComponent(name);
  } on ArgumentError {
    // Keep the raw segment.
  }
  return OpenedFile(locator: url, displayName: name, sizeBytes: 0);
}

const _content = MethodChannel('marquee/content');

/// The system picker. On Android this is ACTION_OPEN_DOCUMENT through `marquee/content`: the
/// film stays where it is (file_picker would COPY the whole file into the cache) and the
/// persisted read grant lets a Lobby card reopen the same content:// URI after a restart.
Future<OpenedFile?> pickVideo() async {
  if (Platform.isAndroid) {
    try {
      final r = await _content.invokeMapMethod<String, Object?>('pickVideo');
      final uri = r?['uri'];
      if (r == null || uri is! String) return null;
      return OpenedFile(
        locator: uri,
        displayName: r['name'] as String? ?? 'video',
        sizeBytes: (r['size'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _videoExtensions,
    withData: false,
  );
  final f = res?.files.singleOrNull;
  final path = f?.path;
  if (f == null || path == null || isSubtitleFile(f.name)) return null;
  return OpenedFile(locator: path, displayName: f.name, sizeBytes: f.size);
}

/// "Load subtitle file…": a path mpv can `sub-add` (on Android the picker copies the small
/// file into the cache, which is exactly what mpv needs — it cannot read content:// itself).
Future<String?> pickSubtitleFile() async {
  final res = await FilePicker.platform.pickFiles(
    type: Platform.isAndroid ? FileType.any : FileType.custom,
    allowedExtensions: Platform.isAndroid ? null : _subtitleExtensions,
  );
  final path = res?.files.singleOrNull?.path;
  return path != null && isSubtitleFile(path) ? path : null;
}

/// A `file:///D:/films/x.mkv` URI ("Open with" from some file managers) as a plain path.
String locatorToPath(String locator) {
  if (!locator.toLowerCase().startsWith('file:')) return locator;
  try {
    return Uri.parse(locator).toFilePath(windows: Platform.isWindows);
  } on Object {
    return locator;
  }
}

/// A path, a file:// or content:// URI, or a stream URL → something the session can open.
/// Null when the file has moved, been deleted, or its grant was revoked.
Future<OpenedFile?> fileFromPath(String locator) async {
  if (locator.startsWith('content://')) return contentFile(locator);
  final remote = openedFromUrl(locator);
  if (remote != null) return remote;
  final path = locatorToPath(locator);
  final f = File(path);
  if (!f.existsSync() || isSubtitleFile(path)) return null;
  return OpenedFile(locator: path, displayName: p.basename(path), sizeBytes: f.lengthSync());
}

/// The video files either side of [f] in its folder, in natural order (desktop paths only;
/// a content:// URI has no folder Marquee may list).
Future<({String? previous, String? next})> siblingsOf(OpenedFile f) async {
  if (f.isContentUri || f.isRemote) return (previous: null, next: null);
  try {
    final dir = Directory(p.dirname(f.locator));
    final names = <String>[
      await for (final e in dir.list(followLinks: false))
        if (e is File && isVideoFile(e.path)) p.basename(e.path),
    ];
    final n = neighboursOf(names, p.basename(f.locator));
    String? full(String? name) => name == null ? null : p.join(dir.path, name);
    return (previous: full(n.previous), next: full(n.next));
  } on FileSystemException {
    return (previous: null, next: null);
  }
}

/// Where screenshots go: Pictures\Marquee on Windows, the app's Pictures folder on Android.
Future<Directory> screenshotDir() async {
  Directory? base;
  if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'];
    if (home != null) base = Directory(p.join(home, 'Pictures'));
  } else if (Platform.isAndroid) {
    final dirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
    base = dirs?.firstOrNull;
  }
  base ??= await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'Marquee'));
  await dir.create(recursive: true);
  return dir;
}

/// Android "Open with" / share: the URI the activity was launched with, if any.
Future<String?> initialIntentUri() async {
  if (!Platform.isAndroid) return null;
  try {
    return await _content.invokeMethod<String>('initialUri');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

Future<OpenedFile?> contentFile(String uri) async {
  try {
    final info = await _content.invokeMapMethod<String, Object?>('stat', {'uri': uri});
    if (info == null) return null;
    return OpenedFile(
      locator: uri,
      displayName: info['name'] as String? ?? 'video',
      sizeBytes: (info['size'] as num?)?.toInt() ?? 0,
    );
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Reads exactly two 64 KiB chunks — from a path via RandomAccessFile, or from a content://
/// URI through the Kotlin channel. Never streams the whole file.
Future<ChunkReader> chunkReaderFor(OpenedFile f) async {
  if (!f.isContentUri) {
    return (offset, length) async {
      final raf = await File(f.locator).open();
      try {
        await raf.setPosition(offset);
        return await raf.read(length);
      } finally {
        await raf.close();
      }
    };
  }
  return (offset, length) async {
    final b = await _content.invokeMethod<Uint8List>('read', {
      'uri': f.locator,
      'offset': offset,
      'length': length,
    });
    if (b == null) throw const FileSystemException('content read failed');
    return b;
  };
}

/// `<video>.<lang>.srt` / `.ass` beside the file — rung 0a, zero requests.
String? findSidecar(OpenedFile f, List<String> languages) {
  if (f.isContentUri || f.isRemote) return null;
  final dir = p.dirname(f.locator);
  final stem = p.basenameWithoutExtension(f.locator);
  for (final lang in languages) {
    for (final ext in ['srt', 'ass']) {
      final c = p.join(dir, '$stem.$lang.$ext');
      if (File(c).existsSync()) return c;
    }
  }
  for (final ext in ['srt', 'ass']) {
    final c = p.join(dir, '$stem.$ext');
    if (File(c).existsSync()) return c;
  }
  return null;
}

class WrittenSidecar {
  final String path;
  final bool besideFile;
  const WrittenSidecar(this.path, {required this.besideFile});
}

String _unused(String path) {
  if (!File(path).existsSync()) return path;
  final ext = p.extension(path);
  final base = path.substring(0, path.length - ext.length);
  for (var i = 1; ; i++) {
    final c = '$base.$i$ext';
    if (!File(c).existsSync()) return c;
  }
}

/// Writes beside the video when allowed and possible; otherwise in app storage.
Future<WrittenSidecar> writeSidecar(
  OpenedFile f, {
  required String language,
  required Uint8List bytes,
  required bool besideFile,
  String extension = 'srt',
}) async {
  if (besideFile && !f.isContentUri && !f.isRemote) {
    final target = _unused(
      p.join(p.dirname(f.locator), '${p.basenameWithoutExtension(f.locator)}.$language.$extension'),
    );
    try {
      await File(target).writeAsBytes(bytes, flush: true);
      return WrittenSidecar(target, besideFile: true);
    } on FileSystemException {
      // Read-only folder: fall through to app storage and say so in the Booth.
    }
  }
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'subtitles'));
  await dir.create(recursive: true);
  final stem = p.basenameWithoutExtension(f.displayName);
  final target = _unused(p.join(dir.path, '$stem.$language.$extension'));
  await File(target).writeAsBytes(bytes, flush: true);
  return WrittenSidecar(target, besideFile: false);
}

Future<bool> fileExists(String path) async => File(path).exists();

Future<String?> pickSaveLocation(String suggestedName) => FilePicker.platform.saveFile(
  fileName: suggestedName,
  type: FileType.custom,
  allowedExtensions: const ['json'],
);

Future<String?> pickJson() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  return res?.files.singleOrNull?.path;
}
