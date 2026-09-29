import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marquee/api/net.dart';
import 'package:marquee/api/opensubtitles.dart';
import 'package:marquee/api/subdl.dart';
import 'package:marquee/engine/filename.dart';
import 'package:marquee/engine/models/models.dart';
import 'package:marquee/engine/threading.dart';
import 'package:test/test.dart';

String fx(String name) => File('test/fixtures/os/$name').readAsStringSync();

/// A stored (uncompressed) zip with the given entries.
Uint8List makeZip(Map<String, List<int>> entries) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  for (final e in entries.entries) {
    final name = utf8.encode(e.key);
    final offset = out.length;
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint32(18, e.value.length, Endian.little)
      ..setUint32(22, e.value.length, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(e.value);
    final c = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint32(20, e.value.length, Endian.little)
      ..setUint32(24, e.value.length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(c.buffer.asUint8List())
      ..add(name);
    count++;
  }
  final cdOffset = out.length;
  final cd = central.takeBytes();
  out.add(cd);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, count, Endian.little)
    ..setUint16(10, count, Endian.little)
    ..setUint32(12, cd.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

void main() {
  group('opensubtitles client', () {
    test('sorts query parameters alphabetically', () async {
      late Uri seen;
      final c = OpenSubtitlesClient(
        apiKey: 'k',
        client: MockClient((req) async {
          seen = req.url;
          return http.Response(fx('search-hash-hit.json'), 200);
        }),
      );
      await c.search(
        const SearchRequest(hash: MovieHash('8e245d9679d31e12'), languages: ['hi', 'en']),
      );
      final keys = seen.query.split('&').map((kv) => kv.split('=').first).toList();
      expect(keys, [...keys]..sort());
      expect(seen.queryParameters['languages'], 'en,hi');
      expect(seen.queryParameters['moviehash_match'], 'include');
    });

    test('sends the mandatory headers', () async {
      late http.BaseRequest seen;
      final c = OpenSubtitlesClient(
        apiKey: 'k',
        jwt: 'jwt',
        client: MockClient((req) async {
          seen = req;
          return http.Response(fx('search-miss.json'), 200);
        }),
      );
      await c.search(const SearchRequest(query: 'x', languages: ['en']));
      expect(seen.headers['Api-Key'], 'k');
      expect(seen.headers['User-Agent'], startsWith('Marquee v'));
      expect(seen.headers['Authorization'], 'Bearer jwt');
    });

    test('searches by parsed title, year and episode when there is no hash', () {
      final p = parseName('Severance.S02E04.1080p.WEB.H264-NTb.mkv');
      final params = OpenSubtitlesClient.searchParams(
        SearchRequest(parsed: p, languages: const ['en']),
      );
      expect(params['query'], 'Severance');
      expect(params['season_number'], '2');
      expect(params['episode_number'], '4');
      expect(params.containsKey('moviehash'), isFalse);
    });

    test('maps 401, 406, 410 and 429 to typed failures', () async {
      for (final (status, failure) in [
        (401, ThreadingFailure.unauthorized),
        (406, ThreadingFailure.quotaExhausted),
        (410, ThreadingFailure.linkExpired),
      ]) {
        final c = OpenSubtitlesClient(
          apiKey: 'k',
          client: MockClient((_) async => http.Response('{}', status)),
        );
        await expectLater(
          c.requestDownload('1'),
          throwsA(isA<ThreadingException>().having((e) => e.failure, 'failure', failure)),
        );
      }
    });

    test('honours Retry-After once, then stalls with the wait', () async {
      var calls = 0;
      final waits = <Duration>[];
      final c = OpenSubtitlesClient(
        apiKey: 'k',
        wait: (d) async => waits.add(d),
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 429, headers: {'retry-after': '2'});
        }),
      );
      await expectLater(
        c.search(const SearchRequest(query: 'x', languages: ['en'])),
        throwsA(
          isA<ThreadingException>()
              .having((e) => e.failure, 'failure', ThreadingFailure.rateLimited)
              .having((e) => e.retryAfterSeconds, 'retryAfter', 2),
        ),
      );
      expect(calls, 2);
      expect(waits, [const Duration(seconds: 2)]);
    });

    test('maps a dropped connection to offline', () async {
      final c = OpenSubtitlesClient(
        apiKey: 'k',
        client: MockClient((_) async => throw const SocketException('down')),
      );
      await expectLater(
        c.search(const SearchRequest(query: 'x', languages: ['en'])),
        throwsA(isA<ThreadingException>().having((e) => e.failure, 'f', ThreadingFailure.offline)),
      );
    });

    test('reads the quota from login and download responses', () async {
      final c = OpenSubtitlesClient(
        apiKey: 'k',
        client: MockClient(
          (req) async => http.Response(
            req.url.path.endsWith('/login') ? fx('login-ok.json') : fx('download-ok.json'),
            200,
          ),
        ),
      );
      final login = await c.login('u', 'p');
      expect(login.quota.total, 20);
      expect(login.token, isNotEmpty);
      final dl = await c.requestDownload('1234567');
      expect(dl.remaining, 7);
      expect(dl.resetUtc, DateTime.utc(2026, 9, 7));
    });

    test('returns the VIP base url from login', () async {
      final c = OpenSubtitlesClient(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(fx('login-vip.json'), 200)),
      );
      final login = await c.login('u', 'p');
      expect(login.baseUrl, 'vip-api.opensubtitles.com');
      expect(login.quota.vip, isTrue);
    });

    test('builds the cache key from the exact sorted request', () {
      const r = SearchRequest(hash: MovieHash('8e245d9679d31e12'), languages: ['en']);
      expect(
        OpenSubtitlesClient.cacheKey(r),
        'languages=en&moviehash=8e245d9679d31e12&moviehash_match=include&order_by=download_count',
      );
      expect(sortedQuery({'b': '1', 'a': '2', 'c': ''}), 'a=2&b=1');
    });
  });

  group('subdl', () {
    test('parses search results that can never light MATCH', () {
      final cs = SubdlClient.parseSearch(fx('subdl-search.json'));
      expect(cs, hasLength(1));
      expect(cs.single.moviehashMatch, isFalse);
      expect(cs.single.provider, SubtitleProvider.subdl);
    });

    test('takes the single srt out of a zip in memory', () {
      final z = makeZip({
        'readme.txt': [1, 2],
        'film.srt': utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nhi\n'),
      });
      final e = extractSubtitle(z);
      expect(e.name, 'film.srt');
      expect(utf8.decode(e.bytes), contains('hi'));
    });

    test('rejects a zip with a path-traversal entry', () {
      expect(
        () => extractSubtitle(
          makeZip({
            '../evil.srt': [1],
          }),
        ),
        throwsA(isA<UnsafeZip>()),
      );
      expect(
        () => extractSubtitle(
          makeZip({
            r'C:\evil.srt': [1],
          }),
        ),
        throwsA(isA<UnsafeZip>()),
      );
    });

    test('rejects an entry over 2 MB and a zip with no subtitle', () {
      expect(
        () => extractSubtitle(makeZip({'big.srt': List.filled(kMaxZipEntryBytes + 1, 65)})),
        throwsA(isA<UnsafeZip>()),
      );
      expect(
        () => extractSubtitle(
          makeZip({
            'a.txt': [1],
          }),
        ),
        throwsA(isA<UnsafeZip>()),
      );
    });

    test('downloads anonymously without the api key', () async {
      late Uri seen;
      final c = SubdlClient(
        apiKey: 'secret-key',
        client: MockClient((req) async {
          seen = req.url;
          return http.Response.bytes(makeZip({'a.srt': utf8.encode('x')}), 200);
        }),
      );
      await c.download('/subtitle/1234-5678.zip');
      expect(seen.host, 'dl.subdl.com');
      expect(seen.toString(), isNot(contains('secret-key')));
    });
  });
}
