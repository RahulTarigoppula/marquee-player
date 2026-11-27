import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:marquee/db/database.dart';
import 'package:marquee/engine/models/models.dart';
import 'package:test/test.dart';

const hash = MovieHash('8e245d9679d31e12');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MarqueeDatabase db;
  setUp(() => db = MarqueeDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('database', () {
    test('updates the row when the same film moves, never duplicating it', () async {
      final a = await db.upsertMedia(
        locator: r'D:\a.mkv',
        displayName: 'a.mkv',
        sizeBytes: 1,
        hash: hash,
      );
      final b = await db.upsertMedia(
        locator: r'E:\moved.mkv',
        displayName: 'moved.mkv',
        sizeBytes: 1,
        hash: hash,
      );
      expect(b, a);
      final cards = await db.watchLobby().first;
      expect(cards.single.locator, r'E:\moved.mkv');
    });

    test('reports a cache hit only while the sidecar still exists', () async {
      await db.putCachedSubtitle(
        hash: hash,
        language: 'en',
        provider: 'openSubtitles',
        sidecarPath: 'x.en.srt',
        syncedByHash: true,
        besideFile: true,
      );
      expect(await db.cachedSubtitle(hash, ['en'], exists: (_) async => true), isNotNull);
      expect(await db.cachedSubtitle(hash, ['en'], exists: (_) async => false), isNull);
      expect(await db.cachedSubtitle(hash, ['en'], exists: (_) async => true), isNull);
    });

    test('stores a position near the end as finished', () async {
      await db.saveResume(hash, 9650000, 9663000);
      final done = (await db.resumeFor(hash))!;
      expect(done.positionMs, 9663000);
      expect(done.finished, isTrue);
      await db.saveResume(hash, 4364400, 9663000);
      expect((await db.resumeFor(hash))!.positionMs, 4364400);
      expect((await db.resumeFor(hash))!.finished, isFalse);
    });

    test('never reads a film closed at the very start as finished', () async {
      expect(MarqueeDatabase.isFinished(0, 9663000), isFalse);
      expect(MarqueeDatabase.isFinished(0, 12000), isFalse);
      expect(MarqueeDatabase.isFinished(9650000, 9663000), isTrue);
      final row = 'film.mkv';
      final id = await db.upsertMedia(locator: row, displayName: row, sizeBytes: 1, hash: hash);
      await db.saveResume(hash, 0, 9663000);
      final card = (await db.watchLobby().first).single;
      expect(card.finished, isFalse);
      expect(await db.mediaIdFor(row), id);
      expect(await db.mediaIdFor('elsewhere.mkv'), isNull);
    });

    test('shows a newly cached subtitle language on the Lobby card', () async {
      await db.upsertMedia(locator: 'a.mkv', displayName: 'a.mkv', sizeBytes: 1, hash: hash);
      final seen = <String?>[];
      final first = Completer<void>();
      final tagged = Completer<void>();
      final sub = db.watchLobby().listen((cards) {
        final lang = cards.single.subtitleLanguage;
        seen.add(lang);
        if (!first.isCompleted) first.complete();
        if (lang == 'hi' && !tagged.isCompleted) tagged.complete();
      });
      addTearDown(sub.cancel);
      await first.future;
      expect(seen.single, isNull);
      await db.putCachedSubtitle(
        hash: hash,
        language: 'hi',
        provider: 'openSubtitles',
        sidecarPath: 'a.hi.srt',
        syncedByHash: true,
        besideFile: true,
      );
      await tagged.future.timeout(const Duration(seconds: 5));
      expect(seen.last, 'hi');
    });

    test('carries the saved position, so the card and the session agree on Resume', () async {
      await db.upsertMedia(locator: 'a.mkv', displayName: 'a.mkv', sizeBytes: 1, hash: hash);
      // Two minutes before the end: in progress for the Lobby AND resumable for the session.
      await db.saveResume(hash, 9663000 - 120000, 9663000);
      final card = (await db.watchLobby().first).single;
      expect(card.positionMs, 9663000 - 120000);
      expect(card.inProgress, isTrue);
      expect((await db.resumeFor(hash))!.resumable, isTrue);
    });

    test('remembers the sync offset per moviehash', () async {
      await db.saveOffset(hash, 350);
      expect(await db.offsetFor(hash), 350);
      expect(await db.offsetFor(const MovieHash('0000000000000001')), 0);
      await db.saveOffset(hash, 0);
      expect(await db.offsetFor(hash), 0);
    });

    test('expires search responses after 24 hours', () async {
      final t0 = DateTime.utc(2026, 9, 6, 15, 44);
      await withClock(Clock.fixed(t0), () => db.putSearch('k', '{}'));
      expect(
        await withClock(Clock.fixed(t0.add(const Duration(hours: 23))), () => db.cachedSearch('k')),
        '{}',
      );
      expect(
        await withClock(Clock.fixed(t0.add(const Duration(hours: 25))), () => db.cachedSearch('k')),
        isNull,
      );
    });

    test('sweeps artwork older than 180 days', () async {
      final t0 = DateTime.utc(2026, 1, 1);
      await withClock(Clock.fixed(t0), () => db.putArtwork(1092, poster: '/p.jpg'));
      expect(await withClock(Clock.fixed(t0.add(const Duration(days: 179))), db.sweepArtwork), 0);
      expect(await withClock(Clock.fixed(t0.add(const Duration(days: 181))), db.sweepArtwork), 1);
    });

    test('round-trips settings and window bounds through app state', () async {
      await db.writeSettings(const Settings(languages: ['en', 'hi'], preferHearingImpaired: true));
      await db.writeState('window_bounds', {'x': 1, 'y': 2, 'w': 3, 'h': 4, 'maximized': false});
      final s = await db.readSettings();
      expect(s.languages, ['en', 'hi']);
      expect(s.preferHearingImpaired, isTrue);
      expect((await db.readState('window_bounds'))! as Map, containsPair('w', 3));
    });

    test('exports and merges a library without secrets', () async {
      await db.upsertMedia(locator: 'a.mkv', displayName: 'a.mkv', sizeBytes: 1, hash: hash);
      await db.saveResume(hash, 1000, 9663000);
      await db.saveOffset(hash, 350);
      await db.writeState('seen_gate_nudge', true);
      final json = await db.exportLibrary(version: '1.0.0', platform: 'windows');
      expect(json.toString(), isNot(contains('token')));

      final fresh = MarqueeDatabase(NativeDatabase.memory());
      await fresh.importLibrary(json);
      expect((await fresh.watchLobby().first).single.delayMs, 350);
      expect((await fresh.resumeFor(hash))!.positionMs, 1000);
      expect(await fresh.readState('seen_gate_nudge'), isTrue);
      await fresh.close();
    });

    test('exports per-film choices and the library folders, and merges them back', () async {
      const other = MovieHash('0000000000000002');
      final t0 = DateTime.utc(2026, 9, 6, 15, 44);
      await withClock(Clock.fixed(t0), () async {
        await db.saveFilePrefs(hash, {'audio': '2', 'subtitle': 'off'});
        await db.saveFilePrefs(other, {
          'secondSubtitle': '3',
          'picture': {'rotate': 90},
        });
      });
      await db.addFolder(r'D:\Films');
      await db.addFolder(r'E:\Shows');
      final json = await db.exportLibrary(version: '2.2.0', platform: 'windows');
      expect(json['format'], MarqueeDatabase.exportFormat);
      expect(json['folders'], [r'D:\Films', r'E:\Shows']);
      expect(json['filePrefs'], hasLength(2));
      // The file a user saves is JSON text: go through it, as the app does.
      final file = jsonDecode(jsonEncode(json)) as Map<String, Object?>;

      final fresh = MarqueeDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      await fresh.addFolder(r'd:\films'); // the same folder, typed in another case
      await fresh.importLibrary(file, importFolders: true);
      expect(await fresh.filePrefsFor(hash), {'audio': '2', 'subtitle': 'off'});
      expect(await fresh.filePrefsFor(other), {
        'secondSubtitle': '3',
        'picture': {'rotate': 90},
      });
      expect(await fresh.libraryFolders(), [r'd:\films', r'E:\Shows']);
      // Importing the same file again changes nothing.
      await fresh.importLibrary(file, importFolders: true);
      expect(await fresh.libraryFolders(), [r'd:\films', r'E:\Shows']);
      expect(await fresh.exportLibrary(version: '2.2.0', platform: 'windows'), {
        ...json,
        'exportedAt': anything,
        'folders': [r'd:\films', r'E:\Shows'],
      });
    });

    test('an import keeps the newer per-film choice and leaves folders out unless asked', () async {
      final older = DateTime.utc(2026, 9, 1);
      final newer = DateTime.utc(2026, 9, 8);
      Map<String, Object?> export(DateTime at, String audio) => {
        'format': MarqueeDatabase.exportFormat,
        'filePrefs': [
          {
            'hash': hash.value,
            'prefs': {'audio': audio},
            'at': at.toIso8601String(),
          },
          {
            'hash': 'no-date',
            'prefs': <String, Object?>{'audio': '9'},
          },
          {'hash': 'not-an-object', 'prefs': 'audio', 'at': at.toIso8601String()},
          {'hash': 'nothing-chosen', 'prefs': <String, Object?>{}, 'at': at.toIso8601String()},
          {
            'prefs': <String, Object?>{'audio': '9'},
            'at': at.toIso8601String(),
          },
        ],
        'folders': [r'D:\Films', 7, '  ', null],
      };

      await withClock(
        Clock.fixed(DateTime.utc(2026, 9, 5)),
        () => db.saveFilePrefs(hash, {'audio': '1'}),
      );
      await db.importLibrary(export(older, '2'));
      expect(await db.filePrefsFor(hash), {'audio': '1'}, reason: 'the choice here is newer');
      await db.importLibrary(export(newer, '3'));
      expect(await db.filePrefsFor(hash), {'audio': '3'}, reason: 'the imported choice is newer');
      for (final broken in ['no-date', 'not-an-object', 'nothing-chosen']) {
        expect(await db.filePrefsFor(MovieHash(broken)), isNull, reason: broken);
      }
      expect(await db.libraryFolders(), isEmpty, reason: 'folders were not asked for');
      await db.importLibrary(export(newer, '3'), importFolders: true);
      expect(await db.libraryFolders(), [r'D:\Films']);
      // An export from a build that knew neither key still imports.
      await db.importLibrary({'format': MarqueeDatabase.exportFormat}, importFolders: true);
      expect(await db.libraryFolders(), [r'D:\Films']);
    });

    test('leaves unreadable per-film choices out of an export', () async {
      await db.saveFilePrefs(hash, {'audio': '2'});
      await db.customStatement(
        "INSERT INTO file_prefs (moviehash, prefs_json, at) VALUES ('broken', '{not json', 0), "
        "('a-list', '[1]', 0)",
      );
      final json = await db.exportLibrary(version: '2.2.0', platform: 'windows');
      expect((json['filePrefs']! as List).map((f) => (f as Map)['hash']), [hash.value]);
    });

    test('marks every played film for the Library, however long ago it was played', () async {
      final t0 = DateTime.utc(2026, 1, 1);
      MovieHash h(int i) => MovieHash(i.toRadixString(16).padLeft(16, '0'));
      // More films than the Home rail asks for; the first ones are the longest ago.
      const played = kLobbyRailLimit + 5;
      for (var i = 0; i < played; i++) {
        await withClock(
          Clock.fixed(t0.add(Duration(hours: i))),
          () => db.upsertMedia(
            locator: 'D:\\f\\$i.mkv',
            displayName: '$i.mkv',
            sizeBytes: 1,
            hash: h(i),
          ),
        );
      }
      await db.saveResume(h(0), 9663000, 9663000); // watched, and off the end of the rail
      await db.saveResume(h(1), 600000, 9663000); // part-way, also off the rail
      await db.updateProbe((await db.mediaIdFor('D:\\f\\2.mkv'))!, durationMs: 5000);
      await db.upsertMedia(locator: 'content://x/9', displayName: 'no hash.mp4', sizeBytes: 1);

      final rail = await db.watchLobby().first;
      expect(rail, hasLength(kLobbyRailLimit));
      expect(rail.any((c) => c.locator == 'D:\\f\\0.mkv'), isFalse);

      final marks = {for (final c in await db.playedMarks()) c.locator: c};
      expect(marks, hasLength(played + 1));
      final watched = marks['D:\\f\\0.mkv']!;
      expect(watched.finished, isTrue);
      expect(watched.resumeFraction, 1);
      expect(watched.hash?.value, h(0).value);
      expect(watched.displayName, '0.mkv');
      final partly = marks['D:\\f\\1.mkv']!;
      expect(partly.finished, isFalse);
      expect(partly.inProgress, isTrue);
      expect(partly.positionMs, 600000);
      expect(partly.resumeFraction, closeTo(600000 / 9663000, 1e-9));
      final untouched = marks['D:\\f\\2.mkv']!;
      expect(untouched.durationMs, 5000);
      expect(untouched.resumeFraction, 0);
      expect(untouched.resumePositionMs, isNull);
      expect(untouched.finished, isFalse);
      expect(marks['content://x/9']!.hash, isNull);
      // Where both answer, the narrow query and the rail agree on what a card draws.
      for (final c in rail) {
        final m = marks[c.locator]!;
        expect(
          (m.id, m.finished, m.resumeFraction, m.positionMs, m.durationMs, m.hash?.value),
          (c.id, c.finished, c.resumeFraction, c.positionMs, c.durationMs, c.hash?.value),
        );
      }
    });

    test('reads and writes a stored value as its own JSON text', () async {
      expect(await db.readStateText('library_cache'), isNull);
      await db.writeStateText('library_cache', '{"v":1,"items":[]}');
      expect(await db.readStateText('library_cache'), '{"v":1,"items":[]}');
      expect(await db.readState('library_cache'), {'v': 1, 'items': <Object?>[]});
      await db.writeState('lobby_view', {'tab': 'library'});
      expect(await db.readStateText('lobby_view'), '{"tab":"library"}');
    });

    test('refuses an unknown export format with one sentence', () async {
      expect(() => db.importLibrary({'format': 'other'}), throwsA(isA<FormatException>()));
    });
  });
}
