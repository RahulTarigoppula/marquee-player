// Lobby thumbnails: one JPEG per media row at <app support>/thumbs/<id>.jpg, grabbed from the
// player while a film plays. The Auditorium writes them; the Lobby reads them. A missing file
// is normal (never played long enough, or a remote stream) and shows the title card instead.
//
// The Lobby never touches the disk while it builds: [thumbnailIndexProvider] lists the folder
// once (and again only after a grab or a removal), and frames are decoded at card size
// ([thumbnailImage]), not at the film's own 1080p or 4K.
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
