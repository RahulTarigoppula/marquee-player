// The one-time move of the Windows database out of Documents (lib/db/location.dart), against
// real folders: this is the code that carries a viewer's whole history, so every way it can be
// interrupted is played out here.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:marquee/db/database.dart';
import 'package:marquee/db/location.dart';
import 'package:marquee/engine/models/models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late String legacy; // <Documents>\marquee.sqlite
  late String path; // <app data>\Marquee\marquee.sqlite

  setUp(() {
    root = Directory.systemTemp.createTempSync('marquee-db-move');
    Directory(p.join(root.path, 'Documents')).createSync();
    legacy = p.join(root.path, 'Documents', 'marquee.sqlite');
    path = p.join(root.path, 'AppData', 'Marquee', 'marquee.sqlite');
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // A handle Windows has not let go of yet: the temp folder is cleared by the system.
    }
  });

  List<int> bytes(int seed, [int length = 3 * 1024 * 1024 + 17]) => [
    for (var i = 0; i < length; i++) (i * 31 + seed) & 0xFF,
  ];
  void put(String at, List<int> content) => File(at)
    ..createSync(recursive: true)
    ..writeAsBytesSync(content);
  List<String> left(String dir) => [
    if (Directory(dir).existsSync())
      for (final e in Directory(dir).listSync()) p.basename(e.path),
  ]..sort();

  test('a new install opens in the new place, and its folder is made', () async {
    expect(await settleDatabase(legacyPath: legacy, path: path), (path: path, legacy: false));
    expect(Directory(p.dirname(path)).existsSync(), isTrue);
    expect(File(path).existsSync(), isFalse, reason: 'SQLite creates the file, not the move');
    expect(left(p.dirname(legacy)), isEmpty);
  });

  test('a database only in the old place is moved, whole, and the old one removed', () async {
    final content = bytes(1); // larger than one copy chunk, and not a whole number of them
    put(legacy, content);
    expect(await settleDatabase(legacyPath: legacy, path: path), (path: path, legacy: false));
    expect(File(path).readAsBytesSync(), content);
    expect(left(p.dirname(path)), ['marquee.sqlite']);
    expect(left(p.dirname(legacy)), isEmpty);
    // The next start finds it settled and touches nothing.
    expect(await settleDatabase(legacyPath: legacy, path: path), (path: path, legacy: false));
    expect(File(path).readAsBytesSync(), content);
  });

  test('a moved database opens with every row it had', () async {
    const hash = MovieHash('8e245d9679d31e12');
    final before = MarqueeDatabase(NativeDatabase(File(legacy)));
    await before.upsertMedia(locator: r'D:\a.mkv', displayName: 'a.mkv', sizeBytes: 1, hash: hash);
    await before.saveResume(hash, 4364400, 9663000);
    await before.addFolder(r'D:\Films');
    await before.close();
    expect(File(legacy).existsSync(), isTrue);

    final place = await settleDatabase(legacyPath: legacy, path: path);
    expect(place, (path: path, legacy: false));
    expect(File(legacy).existsSync(), isFalse);

    // Opened the way the app opens it there: write-ahead logging.
    final after = MarqueeDatabase(
      NativeDatabase(File(place.path), setup: (db) => db.execute('PRAGMA journal_mode = WAL')),
    );
    expect((await after.resumeFor(hash))!.positionMs, 4364400);
    expect((await after.watchLobby().first).single.locator, r'D:\a.mkv');
    expect(await after.libraryFolders(), [r'D:\Films']);
    await after.saveResume(hash, 5000000, 9663000);
    expect((await after.resumeFor(hash))!.positionMs, 5000000);
    await after.close();
  });

  test(
    'a database already in the new place is never replaced, and the old one is left alone',
    () async {
      final current = bytes(2, 4096), stale = bytes(3, 8192);
      put(path, current);
      put(legacy, stale);
      put('$legacy-journal', [1, 2, 3]);
      expect(await settleDatabase(legacyPath: legacy, path: path), (path: path, legacy: false));
      expect(File(path).readAsBytesSync(), current);
      expect(File(legacy).readAsBytesSync(), stale);
      expect(left(p.dirname(legacy)), ['marquee.sqlite', 'marquee.sqlite-journal']);
      expect(left(p.dirname(path)), ['marquee.sqlite']);
    },
  );

  test('half a copy left by a start that was cut short is written over', () async {
    final content = bytes(4);
    put(legacy, content);
    // Longer than the real file, so a copy that did not start from the top would show.
    put('$path$kDatabaseMovingSuffix', bytes(9, content.length + 5000));
    expect(await settleDatabase(legacyPath: legacy, path: path), (path: path, legacy: false));
    expect(File(path).readAsBytesSync(), content);
    expect(left(p.dirname(path)), ['marquee.sqlite']);
    expect(left(p.dirname(legacy)), isEmpty);
  });

  test(
    'a journal or log left beside nothing in the new place is cleared before the move',
    () async {
      final content = bytes(5, 4096);
      put(legacy, content);
      for (final stray in ['-journal', '-wal', '-shm']) {
        put('$path$stray', [7, 7, 7]);
      }
      expect(await settleDatabase(legacyPath: legacy, path: path), (path: path, legacy: false));
      expect(File(path).readAsBytesSync(), content);
      expect(left(p.dirname(path)), ['marquee.sqlite']);
    },
  );

  test('a new place that cannot be written opens the old one, untouched', () async {
    final content = bytes(6, 4096);
    put(legacy, content);
    // A FILE where the app-data folder should be: no folder can be made inside it.
    put(p.join(root.path, 'AppData'), [0]);
    expect(await settleDatabase(legacyPath: legacy, path: path), (path: legacy, legacy: true));
    expect(File(legacy).readAsBytesSync(), content);
    expect(left(p.dirname(legacy)), ['marquee.sqlite']);
    expect(File(path).existsSync(), isFalse);
  });

  test('a new install with nowhere to write falls back to the old place too', () async {
    put(p.join(root.path, 'AppData'), [0]);
    expect(await settleDatabase(legacyPath: legacy, path: path), (path: legacy, legacy: true));
  });

  test('a new place the copy cannot be renamed into opens the old one, untouched', () async {
    final content = bytes(7, 4096);
    put(legacy, content);
    // A FOLDER with something in it sits where the database file should go.
    put(p.join(path, 'in the way.txt'), [0]);
    expect(await settleDatabase(legacyPath: legacy, path: path), (path: legacy, legacy: true));
    expect(File(legacy).readAsBytesSync(), content);
    expect(Directory(path).existsSync(), isTrue);
  });

  for (final unfinished in ['-journal', '-wal']) {
    test(
      'a write cut short in the old place ($unfinished) is left for SQLite to repair there',
      () async {
        final content = bytes(8, 4096);
        put(legacy, content);
        put('$legacy$unfinished', [1, 2, 3]);
        expect(await settleDatabase(legacyPath: legacy, path: path), (path: legacy, legacy: true));
        expect(File(legacy).readAsBytesSync(), content);
        expect(File('$legacy$unfinished').readAsBytesSync(), [1, 2, 3]);
        expect(left(p.dirname(path)), isEmpty);
        // Opened and closed cleanly since: the journal is gone and the move goes ahead.
        File('$legacy$unfinished').deleteSync();
        expect(await settleDatabase(legacyPath: legacy, path: path), (path: path, legacy: false));
        expect(File(path).readAsBytesSync(), content);
        expect(left(p.dirname(legacy)), isEmpty);
      },
    );
  }
}
