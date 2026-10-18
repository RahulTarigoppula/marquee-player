// Lobby thumbnails: one JPEG per media row at <app support>/thumbs/<id>.jpg, grabbed from the
// player while a film plays. The Auditorium writes them; the Lobby reads them. A missing file
// is normal (never played long enough, or a remote stream) and shows the title card instead.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The folder that holds every thumbnail. Overridden in tests.
final thumbnailDirProvider = FutureProvider<Directory>((ref) async {
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'thumbs'));
  await dir.create(recursive: true);
  return dir;
});

/// Bumped after every write so Lobby images rebuild with the new frame.
class ThumbnailEpoch extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final thumbnailEpochProvider = NotifierProvider<ThumbnailEpoch, int>(ThumbnailEpoch.new);

String thumbnailPath(Directory dir, int mediaId) => p.join(dir.path, '$mediaId.jpg');

/// The thumbnail for [mediaId] if one has been saved, else null. Synchronous on purpose: the
/// Lobby calls it while building cards.
File? thumbnailFor(Directory? dir, int mediaId) {
  if (dir == null) return null;
  final f = File(thumbnailPath(dir, mediaId));
  return f.existsSync() ? f : null;
}

/// Writes [jpeg] as the thumbnail for [mediaId], replacing any older frame.
Future<void> saveThumbnail(Ref ref, int mediaId, Uint8List jpeg) async {
  if (jpeg.isEmpty) return;
  final dir = await ref.read(thumbnailDirProvider.future);
  final f = File(thumbnailPath(dir, mediaId));
  await f.writeAsBytes(jpeg, flush: true);
  await FileImage(f).evict();
  ref.read(thumbnailEpochProvider.notifier).bump();
}

/// Deletes the thumbnail when a film leaves the library.
Future<void> deleteThumbnail(Ref ref, int mediaId) async {
  try {
    final dir = await ref.read(thumbnailDirProvider.future);
    final f = File(thumbnailPath(dir, mediaId));
    if (f.existsSync()) await f.delete();
  } on Object {
    // Best effort: a stale thumbnail costs a few KB.
  }
}
