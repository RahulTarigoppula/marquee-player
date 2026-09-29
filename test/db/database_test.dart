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
      expect((await db.resumeFor(hash))!.positionMs, 0);
      await db.saveResume(hash, 4364400, 9663000);
      expect((await db.resumeFor(hash))!.positionMs, 4364400);
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

    test('refuses an unknown export format with one sentence', () async {
      expect(() => db.importLibrary({'format': 'other'}), throwsA(isA<FormatException>()));
    });
  });
}
