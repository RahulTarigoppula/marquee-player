import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marquee/api/updates.dart';
import 'package:test/test.dart';

const _download = 'https://github.com/RahulTarigoppula/marquee-player/releases/download/v2.1.0';
const _page = 'https://github.com/RahulTarigoppula/marquee-player/releases/tag/v2.1.0';

Map<String, Object?> releaseJson({
  String? tag = 'v2.1.0',
  String? name = 'Marquee 2.1',
  String? page = _page,
  String body = '## What changed\n\n- **Faster** start-up\n- Fixed a [bug](https://x.test/1)\n',
  List<Map<String, Object?>>? assets,
}) => {
  'tag_name': tag,
  'name': name,
  'html_url': page,
  'draft': false,
  'prerelease': false,
  'published_at': '2026-11-20T18:30:00Z',
  'body': body,
  'assets':
      assets ??
      [
        {'name': 'SHA256SUMS.txt', 'browser_download_url': '$_download/SHA256SUMS.txt'},
        {
          'name': 'marquee-android-arm64-v8a.apk',
          'browser_download_url': '$_download/marquee-android-arm64-v8a.apk',
        },
        {
          'name': 'marquee-windows-x64-setup.exe',
          'browser_download_url': '$_download/marquee-windows-x64-setup.exe',
        },
      ],
};

UpdatesClient answering(Object? json, {int status = 200, List<http.Request>? seen}) =>
    UpdatesClient(
      client: MockClient((req) async {
        seen?.add(req);
        return http.Response.bytes(
          utf8.encode(json is String ? json : jsonEncode(json)),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

Matcher failsWith(UpdateFailure f) =>
    throwsA(isA<UpdateException>().having((e) => e.failure, 'failure', f));

void main() {
  group('the request', () {
    test('is one plain GET that says nothing about the user or the device', () async {
      final seen = <http.Request>[];
      await answering(releaseJson(), seen: seen).latest(UpdateTarget.windows);
      expect(seen, hasLength(1));
      final req = seen.single;
      expect(req.method, 'GET');
      expect(
        req.url.toString(),
        'https://api.github.com/repos/RahulTarigoppula/marquee-player/releases/latest',
      );
      expect(req.url.hasQuery, isFalse);
      expect(req.body, isEmpty);
      expect(req.headers, {'Accept': 'application/vnd.github+json', 'User-Agent': 'Marquee'});
    });

    test('sends the same request whatever the platform', () async {
      final seen = <http.Request>[];
      final c = answering(releaseJson(), seen: seen);
      for (final t in UpdateTarget.values) {
        await c.latest(t);
      }
      expect(seen.map((r) => r.url).toSet(), hasLength(1));
      expect(seen.map((r) => '${r.headers}').toSet(), hasLength(1));
    });
  });

  group('a release', () {
    test('reads the tag, name, page, date and notes', () async {
      final r = await answering(releaseJson()).latest(UpdateTarget.windows);
      expect(r.tag, 'v2.1.0');
      expect(r.version, '2.1.0');
      expect(r.name, 'Marquee 2.1');
      expect(r.pageUrl, _page);
      expect(r.publishedAt, DateTime.utc(2026, 11, 20, 18, 30));
      expect(r.notes, 'What changed\n\n• Faster start-up\n• Fixed a bug');
    });

    test('offers the installer on Windows', () async {
      final r = await answering(releaseJson()).latest(UpdateTarget.windows);
      expect(r.downloadUrl, '$_download/marquee-windows-x64-setup.exe');
      expect(r.hasInstaller, isTrue);
    });

    test('offers the arm64 APK on Android', () async {
      final r = await answering(releaseJson()).latest(UpdateTarget.android);
      expect(r.downloadUrl, '$_download/marquee-android-arm64-v8a.apk');
      expect(r.hasInstaller, isTrue);
    });

    test('falls back to the release page when the installer is missing', () async {
      final json = releaseJson(
        assets: [
          {'name': 'notes.txt', 'browser_download_url': '$_download/notes.txt'},
        ],
      );
      for (final t in [UpdateTarget.android, UpdateTarget.windows]) {
        final r = await answering(json).latest(t);
        expect(r.downloadUrl, _page);
        expect(r.hasInstaller, isFalse);
      }
    });

    test('offers only the release page on any other platform', () async {
      final r = await answering(releaseJson()).latest(UpdateTarget.other);
      expect(r.downloadUrl, _page);
    });

    test('never hands the browser an address that is not https github.com', () async {
      final json = releaseJson(
        page: 'http://github.com.evil.test/release',
        assets: [
          {
            'name': 'marquee-windows-x64-setup.exe',
            'browser_download_url': 'https://evil.test/marquee-windows-x64-setup.exe',
          },
        ],
      );
      final r = await answering(json).latest(UpdateTarget.windows);
      expect(r.pageUrl, kLatestReleasePage);
      expect(r.downloadUrl, kLatestReleasePage);
      expect(r.hasInstaller, isFalse);
    });

    test('survives missing and mistyped fields', () async {
      final r = await answering({
        'tag_name': ' v3.0.0 ',
        'name': null,
        'html_url': 7,
        'published_at': 'soon',
        'body': null,
        'assets': 'none',
      }).latest(UpdateTarget.windows);
      expect(r.tag, 'v3.0.0');
      expect(r.name, 'v3.0.0');
      expect(r.pageUrl, kLatestReleasePage);
      expect(r.publishedAt, isNull);
      expect(r.notes, isEmpty);
    });

    test('shows a tag that is not a version as it is', () async {
      final r = await answering(releaseJson(tag: 'spring')).latest(UpdateTarget.other);
      expect(r.version, 'spring');
    });
  });

  group('failures are typed, with one plain sentence each', () {
    test('no release yet (404)', () {
      expect(
        answering({'message': 'Not Found'}, status: 404).latest(UpdateTarget.windows),
        failsWith(UpdateFailure.noRelease),
      );
    });

    test('rate limited (403 and 429)', () {
      for (final status in [403, 429]) {
        expect(
          answering({
            'message': 'API rate limit exceeded',
          }, status: status).latest(UpdateTarget.windows),
          failsWith(UpdateFailure.rateLimited),
        );
      }
    });

    test('a server error', () {
      expect(
        answering('oops', status: 502).latest(UpdateTarget.windows),
        failsWith(UpdateFailure.unexpected),
      );
    });

    test('an answer that is not a release', () {
      for (final body in <Object?>['<html>', '[]', '{}', releaseJson(tag: null), '"v2"']) {
        expect(
          answering(body).latest(UpdateTarget.windows),
          failsWith(UpdateFailure.unexpected),
          reason: '$body',
        );
      }
    });

    test('offline', () {
      for (final error in <Object>[
        const SocketException('no route'),
        const HttpException('connection closed'),
        http.ClientException('failed host lookup'),
      ]) {
        final c = UpdatesClient(client: MockClient((_) async => throw error));
        expect(c.latest(UpdateTarget.windows), failsWith(UpdateFailure.offline));
      }
    });

    test('no answer in time', () {
      final never = Completer<http.Response>();
      final c = UpdatesClient(
        client: MockClient((_) => never.future),
        timeout: const Duration(milliseconds: 20),
      );
      expect(c.latest(UpdateTarget.windows), failsWith(UpdateFailure.timeout));
    });

    test('does not retry', () async {
      var calls = 0;
      final c = UpdatesClient(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 429, headers: {'retry-after': '0'});
        }),
      );
      await expectLater(c.latest(UpdateTarget.windows), failsWith(UpdateFailure.rateLimited));
      expect(calls, 1);
    });

    test('every failure reads as a sentence', () {
      for (final f in UpdateFailure.values) {
        final s = UpdateException(f).sentence;
        expect(s, endsWith('.'), reason: f.name);
        expect(s, isNot(contains('—')), reason: f.name);
        expect(s, isNot(contains('Exception')), reason: f.name);
      }
      expect('${const UpdateException(UpdateFailure.offline)}', 'UpdateException(offline)');
    });

    test('waits eight seconds by default', () {
      final c = UpdatesClient(client: MockClient((_) async => http.Response('', 200)));
      expect(c.timeout, const Duration(seconds: 8));
    });
  });

  group('plainNotes', () {
    test('strips markdown and keeps the words', () {
      const md =
          '# Marquee 2.1\r\n\r\n'
          '<!-- release-notes -->\r\n'
          '## New\r\n'
          '* **Subtitle colours**: white, yellow or _warm_\r\n'
          '- `Shift+S` takes a screenshot\r\n'
          '+ See the [guide](https://example.test/guide) ![shot](https://example.test/a.png)\r\n'
          '\r\n---\r\n\r\n'
          '> Thanks to <b>everyone</b> who tested ~~nightly~~ builds.\r\n'
          '```\nmarquee my_film_file.mkv\n```\n'
          '**Full Changelog**: https://github.com/a/b/compare/v2.0.0...v2.1.0\n';
      expect(
        plainNotes(md),
        'Marquee 2.1\n\n'
        'New\n'
        '• Subtitle colours: white, yellow or warm\n'
        '• Shift+S takes a screenshot\n'
        '• See the guide\n\n'
        'Thanks to everyone who tested nightly builds.\n\n'
        'marquee my_film_file.mkv',
      );
    });

    test('is empty for empty notes', () {
      expect(plainNotes(''), '');
      expect(plainNotes('\n\n  \n'), '');
    });

    test('stops near the limit, at a word, with an ellipsis', () {
      final long = List.filled(200, 'subtitles').join(' ');
      final short = plainNotes(long);
      expect(short.length, lessThanOrEqualTo(kNotesLength + 1));
      expect(short.length, greaterThan(kNotesLength - 20));
      expect(short, endsWith('subtitles…'));
    });

    test('cuts one endless word at the limit', () {
      final short = plainNotes('x' * 2000, max: 50);
      expect(short, '${'x' * 50}…');
    });

    test('leaves short notes alone', () {
      expect(plainNotes('Small fixes.', max: 50), 'Small fixes.');
    });
  });
}
