import 'dart:convert';

import 'package:marquee/engine/library.dart';
import 'package:marquee/engine/models/settings.dart';
import 'package:test/test.dart';

final _t0 = DateTime(2026, 10, 17, 21);

LibraryItem item(
  String path, {
  int size = 1000,
  int? durationMs,
  int? width,
  int? height,
  DateTime? modified,
}) => LibraryItem.fromPath(
  path,
  sizeBytes: size,
  modifiedAt: modified ?? _t0,
  durationMs: durationMs,
  width: width,
  height: height,
);

void main() {
  group('LibraryItem', () {
    test('reads the name and folder out of a Windows path', () {
      final i = item(r'D:\Films\Noir\The.Third.Man.1949.mkv');
      expect(i.name, 'The.Third.Man.1949.mkv');
      expect(i.folderPath, r'D:\Films\Noir');
      expect(i.folderName, 'Noir');
    });

    test('reads a POSIX path and a drive root', () {
      expect(item('/home/me/Videos/a.mp4').folderName, 'Videos');
      final root = item(r'D:\a.mp4');
      expect(root.folderPath, 'D:');
      expect(root.folderName, 'D:');
      final bare = item('a.mp4');
      expect(bare.name, 'a.mp4');
      expect(bare.folderPath, '');
      expect(bare.folderName, '');
    });

    test('has value equality and keeps a probe', () {
      final a = item(r'D:\a.mkv');
      expect(a, item(r'D:\a.mkv'));
      expect(a.hashCode, item(r'D:\a.mkv').hashCode);
      expect(a == item(r'D:\a.mkv', size: 2), isFalse);
      final probed = a.withProbe(durationMs: 60000, width: 1920, height: 1080);
      expect(probed.durationMs, 60000);
      expect(probed.width, 1920);
      expect(probed.withProbe().height, 1080);
      expect(probed == a, isFalse);
      expect(probed.sameFileAs(a), isTrue);
      expect(
        a.sameFileAs(item(r'D:\a.mkv', modified: _t0.add(const Duration(seconds: 1)))),
        isFalse,
      );
    });
  });

  group('the start-up cache', () {
    final items = [
      item(r'D:\Films\a.mkv', size: 5, durationMs: 1000, width: 1920, height: 1080),
      item(r'D:\Films\b.mkv', size: 7),
    ];

    test('round-trips through JSON text', () {
      final text = jsonEncode(encodeLibraryCache(items));
      expect(decodeLibraryCache(jsonDecode(text)), items);
    });

    test('is capped', () {
      final decoded = decodeLibraryCache(encodeLibraryCache(items, limit: 1));
      expect(decoded, [items.first]);
    });

    test('ignores a missing cache, another version and broken rows', () {
      expect(decodeLibraryCache(null), isNull);
      expect(decodeLibraryCache('nope'), isNull);
      expect(decodeLibraryCache({'v': 99, 'items': <Object?>[]}), isNull);
      expect(decodeLibraryCache({'v': 1, 'items': 'x'}), isNull);
      final rows = [
        items.first.toRow(),
        'not a row',
        [1, 2, 3],
        [1, 'n', 'p', 'f', 1, null, null, null, 0], // locator is not text
        ['l', 'n', 'p', 'f', 'big', null, null, null, 0], // size is not a number
      ];
      expect(decodeLibraryCache({'v': 1, 'items': rows}), [items.first]);
    });
  });

  group('carryProbes and sameLibrary', () {
    test('a rescan keeps what was learned about an unchanged file', () {
      final known = [item(r'D:\a.mkv', durationMs: 9, width: 4, height: 3), item(r'D:\b.mkv')];
      final fresh = [item(r'D:\a.mkv'), item(r'D:\b.mkv', size: 2), item(r'D:\c.mkv')];
      final merged = carryProbes(fresh, known);
      expect(merged[0].durationMs, 9);
      expect(merged[0].width, 4);
      expect(merged[1].sizeBytes, 2);
      expect(merged[2].durationMs, isNull);
      expect(identical(carryProbes(fresh, const []), fresh), isTrue);
    });

    test('a replaced file starts again', () {
      final known = [item(r'D:\a.mkv', durationMs: 9)];
      final fresh = [item(r'D:\a.mkv', size: 77)];
      expect(carryProbes(fresh, known).single.durationMs, isNull);
    });

    test('sameLibrary ignores order and sees every change', () {
      final a = [item(r'D:\a.mkv'), item(r'D:\b.mkv')];
      expect(sameLibrary(a, a.reversed.toList()), isTrue);
      expect(sameLibrary(a, [a.first]), isFalse);
      expect(sameLibrary(a, [a.first, item(r'D:\b.mkv', durationMs: 1)]), isFalse);
      expect(sameLibrary(a, [a.first, item(r'D:\c.mkv')]), isFalse);
    });
  });

  group('sortLibrary', () {
    final a = item(r'D:\x\Episode 10.mkv', size: 30, durationMs: 100, modified: _t0);
    final b = item(
      r'D:\x\episode 2.mkv',
      size: 10,
      durationMs: 300,
      modified: _t0.add(const Duration(days: 1)),
    );
    final c = item(r'D:\x\Zebra.mkv', size: 20, modified: _t0.subtract(const Duration(days: 1)));

    test('name uses the natural order', () {
      expect(sortLibrary([a, b, c], LibrarySort.name), [b, a, c]);
    });

    test('newest, largest and longest', () {
      expect(sortLibrary([a, b, c], LibrarySort.newest), [b, a, c]);
      expect(sortLibrary([a, b, c], LibrarySort.largest), [a, c, b]);
      // An unknown length sorts last.
      expect(sortLibrary([c, a, b], LibrarySort.longest), [b, a, c]);
    });

    test('ties fall back to the name, then the path, and the input is left alone', () {
      final one = item(r'D:\one\same.mkv');
      final two = item(r'D:\two\same.mkv');
      final input = [two, one];
      for (final sort in LibrarySort.values) {
        expect(sortLibrary(input, sort), [one, two], reason: sort.name);
      }
      expect(input, [two, one]);
    });
  });

  group('folders', () {
    final items = [
      item(r'D:\Shows\Severance\S02E10.mkv', size: 10, durationMs: 50, modified: _t0),
      item(
        r'D:\Shows\Severance\S02E02.mkv',
        size: 10,
        durationMs: 50,
        modified: _t0.add(const Duration(days: 2)),
      ),
      item(r'D:\Films\big.mkv', size: 500, modified: _t0.add(const Duration(days: 1))),
      item(r'E:\Other\Films\x.mkv', size: 1, durationMs: 400, modified: _t0),
    ];

    test('groups by folder path with counts, sizes and the newest video', () {
      final folders = groupFolders(items);
      expect(folders.map((f) => f.path), [r'D:\Films', r'E:\Other\Films', r'D:\Shows\Severance']);
      final sev = folders.last;
      expect(sev.name, 'Severance');
      expect(sev.count, 2);
      expect(sev.totalBytes, 20);
      expect(sev.totalDurationMs, 100);
      expect(sev.newest.name, 'S02E02.mkv');
      expect(sev.newestAt, _t0.add(const Duration(days: 2)));
    });

    test('orders folders by the chosen sort', () {
      List<String> order(LibrarySort s) => [for (final f in groupFolders(items, sort: s)) f.path];
      expect(order(LibrarySort.newest).first, r'D:\Shows\Severance');
      expect(order(LibrarySort.largest).first, r'D:\Films');
      expect(order(LibrarySort.longest).first, r'E:\Other\Films');
      expect(groupFolders(const []), isEmpty);
    });

    test('the newest video of a tie is the first by name', () {
      final same = [item(r'D:\f\b.mkv'), item(r'D:\f\a.mkv')];
      expect(groupFolders(same).single.newest.name, 'a.mkv');
    });

    test('inFolder keeps only that folder', () {
      expect(inFolder(items, r'D:\Films').single.name, 'big.mkv');
      expect(inFolder(items, r'D:\Nowhere'), isEmpty);
    });
  });

  group('libraryNeighbours', () {
    final items = [
      item(r'D:\S\Show.E10.mkv'),
      item(r'D:\S\Show.E2.mkv'),
      item(r'D:\S\Show.E1.mkv'),
      item(r'D:\Other\Show.E3.mkv'),
    ];

    test('walks the folder in natural order', () {
      expect(libraryNeighbours(items, r'D:\S\Show.E2.mkv'), (
        previous: r'D:\S\Show.E1.mkv',
        next: r'D:\S\Show.E10.mkv',
        first: r'D:\S\Show.E1.mkv',
      ));
    });

    test('stops at both ends and never leaves the folder', () {
      expect(libraryNeighbours(items, r'D:\S\Show.E1.mkv').previous, isNull);
      expect(libraryNeighbours(items, r'D:\S\Show.E10.mkv').next, isNull);
      expect(libraryNeighbours(items, r'D:\Other\Show.E3.mkv'), (
        previous: null,
        next: null,
        first: r'D:\Other\Show.E3.mkv',
      ));
    });

    test('is all null for a file outside the library', () {
      expect(libraryNeighbours(items, r'D:\elsewhere.mkv'), (
        previous: null,
        next: null,
        first: null,
      ));
    });
  });

  group('search', () {
    final third = item(r'D:\Films\Noir\The.Third_Man-1949.1080p.mkv');
    final clip = item(r'D:\Camera Roll\VID_20240101.mp4');

    test('folds case and release punctuation', () {
      expect(searchFold('  The.Third_Man-[1949] '), 'the third man 1949');
      expect(matchesSearch(third, 'third man'), isTrue);
      expect(matchesSearch(third, 'THIRD.MAN'), isTrue);
      expect(matchesSearch(third, 'man third'), isTrue);
      expect(matchesSearch(third, 'thirdman'), isTrue);
      expect(matchesSearch(third, 'fourth'), isFalse);
    });

    test('matches the folder name and treats an empty query as everything', () {
      expect(matchesSearch(third, 'noir'), isTrue);
      expect(matchesSearch(clip, 'camera'), isTrue);
      expect(matchesSearch(clip, 'noir'), isFalse);
      expect(matchesSearch(clip, '  . '), isTrue);
    });

    test('searchLibrary filters and keeps the order', () {
      expect(searchLibrary([third, clip], 'vid'), [clip]);
      expect(searchLibrary([third, clip], ''), [third, clip]);
    });
  });

  group('what a card says', () {
    test('new means arrived in the last week and never played', () {
      final fresh = item(r'D:\a.mkv', modified: _t0.subtract(const Duration(days: 6)));
      final old = item(r'D:\b.mkv', modified: _t0.subtract(const Duration(days: 8)));
      expect(isNewItem(fresh, now: _t0, played: false), isTrue);
      expect(isNewItem(fresh, now: _t0, played: true), isFalse);
      expect(isNewItem(old, now: _t0, played: false), isFalse);
      expect(
        isNewItem(item(r'D:\c.mkv', modified: _t0.subtract(kNewFor)), now: _t0, played: false),
        isTrue,
      );
    });

    test('resolution badges', () {
      expect(resolutionBadge(7680, 4320), '8K');
      expect(resolutionBadge(3840, 2160), '4K');
      expect(resolutionBadge(3840, 1600), '4K');
      expect(resolutionBadge(2560, 1440), '1440p');
      expect(resolutionBadge(1920, 1080), '1080p');
      expect(resolutionBadge(1920, 800), '1080p');
      expect(resolutionBadge(1080, 1920), '1080p');
      expect(resolutionBadge(1280, 720), '720p');
      expect(resolutionBadge(960, 720), '720p');
      expect(resolutionBadge(854, 480), '480p');
      expect(resolutionBadge(320, 240), isNull);
      expect(resolutionBadge(null, 1080), isNull);
      expect(resolutionBadge(1920, null), isNull);
      expect(resolutionBadge(0, 0), isNull);
    });

    test('sizes read like a file manager', () {
      expect(sizeText(0), '');
      expect(sizeText(-1), '');
      expect(sizeText(100), '1 KB');
      expect(sizeText(512 * 1024), '512 KB');
      expect(sizeText(700 * 1024 * 1024), '700 MB');
      expect(sizeText((1.44 * 1024 * 1024 * 1024).round()), '1.4 GB');
      expect(sizeText(120 * 1024 * 1024 * 1024), '120 GB');
    });

    test('titles: release names are cleaned, everything else keeps its name', () {
      expect(libraryTitle('The.Third.Man.1949.1080p.BluRay.x264.mkv'), 'The Third Man (1949)');
      expect(libraryTitle('Severance.S02E03.1080p.WEB.h264.mkv'), 'Severance S02E03');
      expect(libraryTitle('The Third Man (1949).mkv'), 'The Third Man (1949)');
      expect(libraryTitle('Some.Film.720p.WEB-DL.mkv'), 'Some Film');
      expect(libraryTitle('[Group] Some Show - 05 [1080p].mkv'), 'Some Show E05');
      expect(libraryTitle('holiday_2024_beach.mp4'), 'holiday 2024 beach');
      expect(libraryTitle('VID_20240101_123456.mp4'), 'VID 20240101 123456');
      expect(libraryTitle('My wedding.mov'), 'My wedding');
      expect(libraryTitle('notes.final'), 'notes final');
      expect(libraryTitle('subs.srt'), 'subs srt');
      expect(libraryTitle('...'), '...');
    });

    test('pathLeaf names a folder by its last segment', () {
      expect(pathLeaf(r'C:\Users\me\Videos'), 'Videos');
      expect(pathLeaf('C:\\Users\\me\\Videos\\'), 'Videos');
      expect(pathLeaf('/home/me/Downloads'), 'Downloads');
      expect(pathLeaf('D:\\'), 'D:');
      expect(pathLeaf(''), '');
    });

    test('thumbnail keys follow the file, not the scan', () {
      final a = item(r'D:\a.mkv');
      expect(thumbKey(a), thumbKey(item(r'D:\a.mkv').withProbe(durationMs: 5)));
      expect(thumbKey(a), matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(thumbKey(a) == thumbKey(item(r'D:\a.mkv', size: 2)), isFalse);
      expect(
        thumbKey(a) == thumbKey(item(r'D:\a.mkv', modified: _t0.add(const Duration(seconds: 1)))),
        isFalse,
      );
      expect(thumbKey(a) == thumbKey(item(r'D:\b.mkv')), isFalse);
    });
  });

  group('scanning rules', () {
    test('skips hidden, system and application folders', () {
      for (final name in ['.git', r'$RECYCLE.BIN', 'System Volume Information', 'AppData', '']) {
        expect(isSkippedFolder(name), isTrue, reason: name);
      }
      expect(isSkippedFolder('Films'), isFalse);
      expect(isSkippedFolder('Windows 95 nostalgia'), isFalse);
    });

    test('lists video containers only', () {
      expect(isLibraryVideo('a.MKV'), isTrue);
      expect(isLibraryVideo('a.mp4'), isTrue);
      expect(isLibraryVideo('a.srt'), isFalse);
      expect(isLibraryVideo('a.txt'), isFalse);
      expect(isLibraryVideo('.hidden.mkv'), isFalse);
      expect(isLibraryVideo('~temp.mkv'), isFalse);
    });

    test('limits are sane', () {
      expect(kScanMaxDepth, greaterThan(2));
      expect(kScanMaxItems, greaterThan(1000));
      expect(kLibraryCacheLimit, lessThanOrEqualTo(kScanMaxItems));
    });
  });
}
