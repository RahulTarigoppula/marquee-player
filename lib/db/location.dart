// Where the Windows database file lives, and its one-time move out of Documents.
//
// It used to sit in the user's Documents folder (drift_flutter's default), which Windows 11
// very often keeps inside OneDrive: the file was then re-uploaded all through a film (the
// resume point is saved every five seconds), two PCs on one account overwrote each other's
// history, and it lay where a tidy-up could delete it. It belongs in the application's own
// data folder.
//
// This is the one place in the app that moves the viewer's whole history, so it is written to
// lose nothing: the old file is COPIED under a temporary name, forced to disk, renamed into
// place, and only then deleted. A crash at any point leaves at least one complete copy; a
// database already in the new place is never overwritten; and anything that goes wrong opens
// the old place, exactly as the app always did. Plain dart:io, no plugins: the unit tests in
// test/db run it against real folders.
import 'dart:io';

/// Added to the new path while the copy is being written.
const String kDatabaseMovingSuffix = '.moving';

/// What SQLite keeps beside a database: its rollback journal, or its write-ahead log and that
/// log's index.
const List<String> _sidecars = ['-journal', '-wal', '-shm'];

/// The file to open: [path], or [legacyPath] with [legacy] set when the database stays where
/// it always was for this run (it is then opened as it always was, too).
typedef DatabasePlace = ({String path, bool legacy});

/// Decides where the database is opened, moving it from [legacyPath] to [path] when it is
/// only at the old place. Never throws.
///
///  * a database at [path]: that one, and whatever is at [legacyPath] is left alone;
///  * nothing at either: [path] (a new install);
///  * only at [legacyPath]: moved, then [path];
///  * a journal or log beside the old file (its last write was cut short): the old place for
///    this run. Only SQLite can repair that, and it does so on opening the file where it
///    lies; the move happens on the next start;
///  * any failure (no room, no permission, a file held by a sync client): the old place.
Future<DatabasePlace> settleDatabase({required String legacyPath, required String path}) async {
  final DatabasePlace settled = (path: path, legacy: false);
  final DatabasePlace stay = (path: legacyPath, legacy: true);
  try {
    final target = File(path);
    if (await target.exists()) return settled;
    final old = File(legacyPath);
    if (!await old.exists()) {
      await target.parent.create(recursive: true);
      return settled;
    }
    for (final unfinished in const ['-journal', '-wal']) {
      if (await File('$legacyPath$unfinished').exists()) return stay;
    }
    await target.parent.create(recursive: true);
    // A copy left by a start that was cut short is half a file: written over from the top.
    final moving = File('$path$kDatabaseMovingSuffix');
    await _copyToDisk(old, moving);
    if (await moving.length() != await old.length()) return stay;
    // A journal or log left here by a database that is gone would be read as this one's.
    for (final sidecar in _sidecars) {
      final stray = File('$path$sidecar');
      if (await stray.exists()) await stray.delete();
    }
    // dart:io's rename replaces a file that is in the way: look once more, so a database that
    // appeared meanwhile (a second copy of the app starting) is never the one replaced.
    if (await target.exists()) {
      await _discard(moving.path);
      return settled;
    }
    await moving.rename(path);
  } on Object {
    return stay;
  }
  // The new file is complete and in place: only now may the old one go. Best effort: an old
  // file that will not delete is simply never looked at again.
  await _discard(legacyPath);
  await _discard('$legacyPath-journal');
  return settled;
}

/// Deletes [path] if it is there and can be deleted (a file held open by a sync client, or
/// marked read-only, stays where it is).
Future<void> _discard(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } on Object {
    // Left behind; nothing reads it.
  }
}

/// Copies [from] over [to] and does not return until the bytes are on the disk itself (a plain
/// copy may still be in the system's cache when the original is deleted a moment later).
Future<void> _copyToDisk(File from, File to) async {
  final input = await from.open();
  try {
    final output = await to.open(mode: FileMode.write);
    try {
      while (true) {
        final chunk = await input.read(1 << 20);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
  } finally {
    await input.close();
  }
}
