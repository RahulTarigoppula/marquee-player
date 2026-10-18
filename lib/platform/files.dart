// File picking, sidecar detection and sidecar writing. Never overwrite an existing sidecar:
// add a `.1` suffix. If the folder is not writable, fall back to app storage — honestly.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../engine/filename.dart';
import '../engine/hash.dart';

const _videoExtensions = [
  'mkv', 'mp4', 'm4v', 'avi', 'webm', 'mov', 'ts', 'm2ts', 'mts', 'wmv', 'flv', 'mpg', //
  'mpeg', '3gp', 'ogv', 'vob',
];

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

Future<OpenedFile?> pickVideo() async {
  final res = await FilePicker.platform.pickFiles(
    type: Platform.isAndroid ? FileType.video : FileType.custom,
    allowedExtensions: Platform.isAndroid ? null : _videoExtensions,
    withData: false,
  );
  final f = res?.files.singleOrNull;
  final path = f?.path;
  if (f == null || path == null || isSubtitleFile(f.name)) return null;
  return OpenedFile(locator: path, displayName: f.name, sizeBytes: f.size);
}

Future<OpenedFile?> fileFromPath(String path) async {
  if (path.startsWith('content://')) return contentFile(path);
  final f = File(path);
  if (!f.existsSync() || isSubtitleFile(path)) return null;
  return OpenedFile(locator: path, displayName: p.basename(path), sizeBytes: f.lengthSync());
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
  if (f.isContentUri) return null;
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
  if (besideFile && !f.isContentUri) {
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
