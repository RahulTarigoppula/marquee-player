// Real playback, end to end: libmpv decodes ffmpeg-made films in the real Windows app.
// The dev machine cannot build Flutter, so CI (.github/workflows/playback.yml) is where this
// runs:
//
//   bash scripts/make-playback-fixtures.sh            # needs ffmpeg; writes build/playback-fixtures
//   flutter test integration_test -d windows
//
// The fixture folder comes from --dart-define=FIXTURES=<dir>, then MARQUEE_FIXTURES, then
// build/playback-fixtures. Without it every test SKIPS (MARQUEE_REQUIRE_FIXTURES=1, set in CI,
// turns that into a failure so a broken fixture step can never look green).
//
// Everything waits in REAL time (libmpv runs on its own threads; fake async would never see it
// move), with generous timeouts: a hosted runner has no GPU and no sound card.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marquee/app.dart';
import 'package:marquee/db/database.dart';
import 'package:marquee/engine/models/models.dart';
import 'package:marquee/player/engine.dart';
import 'package:marquee/state/notice.dart';
import 'package:marquee/state/providers.dart';
import 'package:marquee/state/session.dart';
import 'package:marquee/state/thumbnails.dart';
import 'package:marquee/ui/auditorium/auditorium_screen.dart';
import 'package:marquee/ui/lobby/lobby_screen.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

const _definedFixtures = String.fromEnvironment('FIXTURES');
const _film = 'marquee-test.mkv';
const _wait = Duration(seconds: 20);
const _perTest = Timeout(Duration(minutes: 4));

/// The folder that holds [_film], or null.
String? _findFixtures() {
  final env = Platform.environment['MARQUEE_FIXTURES'] ?? '';
  final candidates = <String>[
    if (_definedFixtures.isNotEmpty) _definedFixtures,
    if (env.isNotEmpty) env,
    p.join(Directory.current.path, 'build', 'playback-fixtures'),
  ];
  // The test exe sits in <repo>/build/windows/x64/runner/Debug: walk up to the repo.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates.add(p.join(dir.path, 'build', 'playback-fixtures'));
    dir = dir.parent;
  }
  for (final c in candidates) {
    final abs = p.normalize(p.absolute(c));
    if (File(p.join(abs, _film)).existsSync()) return abs;
  }
  return null;
}

/// mpv logs, frames and screenshots land here; CI uploads the folder.
final Directory _out = () {
  final env = Platform.environment['MARQUEE_TEST_OUT'] ?? '';
  final dir = Directory(
    env.isNotEmpty
        ? p.normalize(p.absolute(env))
        : p.join(Directory.systemTemp.path, 'marquee-playback-out'),
  );
  dir.createSync(recursive: true);
  return dir;
}();

void _say(String line) => debugPrint('[playback] $line');

/// Something worth a human's eye that is not this test's to fail on. The workflow lifts
/// every NOTE line into the run summary.
void _note(String line) => _say('NOTE: $line');

String _tell(PlayerEngine e) {
  if (e.isDisposed) return '(engine disposed)';
  final s = e.snapshot;
  final st = e.player.state;
  final audio = s.audioTracks.map((t) => '${t.id}:${t.language ?? '?'}').join(',');
  final subs = s.subtitleTracks.map((t) => '${t.id}:${t.language ?? '?'}').join(',');
  return 'position=${s.position} duration=${s.duration} playing=${s.playing} '
      'buffering=${st.buffering} completed=${st.completed} rate=${st.rate} '
      'picture=${s.width}x${s.height} aid=${s.audioId} sid=${s.subtitleId} '
      'audio=[$audio] subtitles=[$subs]';
}

/// Polls [ok] every 100 ms of real time (pumping a frame each turn) until it holds.
Future<void> _until(
  WidgetTester tester,
  String what,
  bool Function() ok, {
  Duration timeout = _wait,
  String Function()? state,
}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) {
      fail('Timed out after ${timeout.inSeconds} s waiting for $what.\n${state?.call() ?? ''}');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Everything mpv says, verbosely, into `mpv-NAME.log` under [_out]. Never fails a test.
Future<void> _mpvLog(PlayerEngine e, String name) async {
  try {
    final native = e.player.platform;
    if (native is NativePlayer) {
      await native.setProperty('log-file', p.join(_out.path, 'mpv-$name.log'));
    }
  } on Object catch (err) {
    _say('no mpv log for $name: $err');
  }
}

/// A hosted runner has no sound card, and mpv DESELECTS the audio track when no device
/// opens, so `aid` would read "no" and audio switching could not be checked. The null
/// output keeps the track selected and the clock running. MARQUEE_TEST_AUDIO=1 plays aloud.
Future<void> _silentAudio(PlayerEngine e) async {
  if (Platform.environment['MARQUEE_TEST_AUDIO'] == '1') return;
  try {
    final native = e.player.platform;
    if (native is NativePlayer) await native.setProperty('ao', 'null');
  } on Object catch (err) {
    _say('could not select the null audio output: $err');
  }
}

/// One engine on one film, with a real `Video` on screen: [body] runs once libmpv has
/// loaded [path] (paused at 0), and `dispose()` must complete afterwards.
Future<void> _withEngine(
  WidgetTester tester,
  String name,
  String path,
  Future<void> Function(PlayerEngine e) body,
) async {
  final engine = PlayerEngine(hwdec: 'no'); // no GPU on the runner: software decode and render
  final errors = <String>[];
  final logs = engine.player.stream.log.listen((l) => errors.add(l.toString()));
  var passed = false;
  try {
    await _mpvLog(engine, name);
    await _silentAudio(engine);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: const Color(0xFF000000),
          child: Video(
            controller: engine.controller,
            controls: NoVideoControls,
            wakelock: false,
            pauseUponEnteringBackgroundMode: false,
          ),
        ),
      ),
    );
    await engine.configure(const Settings());
    await engine.open(path);
    final loaded = await engine.whenLoaded(timeout: const Duration(seconds: 30));
    expect(
      loaded,
      isTrue,
      reason: 'libmpv did not load $path within 30 s.\n${_tell(engine)}\nmpv said: $errors',
    );
    _say('$name loaded: ${_tell(engine)}');
    await body(engine);
    passed = true;
  } finally {
    if (!passed) _say('$name FAILED at: ${_tell(engine)}\nmpv said: $errors');
    await logs.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    final disposed = await engine
        .dispose()
        .then((_) => true)
        .timeout(_wait, onTimeout: () => false);
    // Only when the body passed: a hung dispose must not hide the first failure.
    if (passed) expect(disposed, isTrue, reason: 'dispose() did not complete within 20 s');
  }
}

/// Plays from the start and proves the position moves, twice.
Future<void> _expectPlays(WidgetTester tester, PlayerEngine e) async {
  await e.play();
  await _until(
    tester,
    'playback to start',
    () => e.snapshot.position > const Duration(milliseconds: 300),
    state: () => _tell(e),
  );
  final then = e.snapshot.position;
  await _until(
    tester,
    'the position to keep advancing',
    () => e.snapshot.position > then + const Duration(milliseconds: 700),
    state: () => _tell(e),
  );
  expect(e.snapshot.playing, isTrue, reason: _tell(e));
}

bool _near(Duration a, Duration b, Duration within) => (a - b).abs() <= within;

/// Refuses every HTTP request made through dart:io (package:http included) and remembers it.
class _NoNetwork extends HttpOverrides {
  final attempts = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient(attempts);
}

class _BlockedClient implements HttpClient {
  _BlockedClient(this._attempts);
  final List<String> _attempts;

  static const _requests = {
    #open, #openUrl, #get, #getUrl, #post, #postUrl, #put, #putUrl, //
    #delete, #deleteUrl, #head, #headUrl, #patch, #patchUrl,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (!_requests.contains(invocation.memberName)) return null; // close(), timeouts, …
    _attempts.add(invocation.positionalArguments.join(' '));
    return Future<HttpClientRequest>.error(
      const SocketException('The network is switched off in this test'),
    );
  }
}

const _shot = ValueKey('playback-shot');

/// The app as drawn right now, to [_out]/[name]. Best effort: a missing picture is not a
/// failed test.
Future<void> _saveShot(WidgetTester tester, String name) async {
  try {
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return;
    await File(p.join(_out.path, name)).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    _say('saved $name');
  } on Object catch (err) {
    _say('no screenshot $name: $err');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The app must draw on its own between our polls, exactly as it does for a user.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final fixtures = _findFixtures();
  if (fixtures == null) {
    const why =
        'No playback fixtures found (looked for $_film via --dart-define=FIXTURES, '
        'MARQUEE_FIXTURES and build/playback-fixtures). '
        'Run: bash scripts/make-playback-fixtures.sh';
    if (Platform.environment['MARQUEE_REQUIRE_FIXTURES'] == '1') {
      test('playback fixtures exist', () => fail(why));
    } else {
      test('playback (skipped: no fixtures)', () {}, skip: why);
    }
    return;
  }

  final mkv = p.join(fixtures, _film);
  final mp4 = p.join(fixtures, 'marquee-test.mp4');
  final hevc = p.join(fixtures, 'marquee-test-hevc.mkv');
  final sidecar = p.join(fixtures, 'marquee-test.en.srt');
  final long = p.join(fixtures, 'marquee-long.mkv');
  final longSidecar = p.join(fixtures, 'marquee-long.en.srt');
  _say('fixtures: $fixtures');
  _say('output:   ${_out.path}');

  group('engine', () {
    testWidgets('opens the MKV: length, picture, tracks, chapters', (tester) async {
      await _withEngine(tester, 'open-mkv', mkv, (e) async {
        expect(
          _near(
            e.snapshot.duration,
            const Duration(seconds: 12),
            const Duration(milliseconds: 600),
          ),
          isTrue,
          reason: 'the film is 12 s long. ${_tell(e)}',
        );
        await _until(
          tester,
          'both audio tracks and the embedded subtitle to be listed',
          () => e.snapshot.audioTracks.length >= 2 && e.snapshot.subtitleTracks.isNotEmpty,
          state: () => _tell(e),
        );
        final audio = e.snapshot.audioTracks.map((t) => (t.language ?? '').toLowerCase()).toList();
        expect(audio.any((l) => l.startsWith('en')), isTrue, reason: 'audio languages: $audio');
        expect(audio.any((l) => l.startsWith('hi')), isTrue, reason: 'audio languages: $audio');
        // The embedded track is the one titled "English" (the fixture script names it).
        final subs = e.snapshot.subtitleTracks;
        final embedded = subs.where((t) => t.title == 'English').toList();
        expect(embedded, hasLength(1), reason: 'no embedded subtitle listed. ${_tell(e)}');
        expect((embedded.single.language ?? '').toLowerCase(), startsWith('en'));
        if (subs.length > 1) {
          // mpv's own sub-auto found marquee-test.en.srt beside the film.
          _note(
            'libmpv loaded the sidecar by itself (${subs.length} subtitle tracks before any '
            'attach): a film with a sidecar will list that file twice once the app attaches it.',
          );
        }

        await _until(
          tester,
          'the picture size',
          () => e.snapshot.width > 0 && e.snapshot.height > 0,
          state: () => _tell(e),
        );
        expect((e.snapshot.width, e.snapshot.height), (640, 360), reason: _tell(e));

        final chapters = await e.chapters();
        final titles = chapters.map((c) => c.title).toList();
        expect(chapters, hasLength(3), reason: 'chapter titles: $titles');
        expect(titles.first, 'Intro');
        expect(chapters[1].startSeconds, closeTo(4, 0.1));
        expect(chapters[2].startSeconds, closeTo(8, 0.1));
      });
    }, timeout: _perTest);

    testWidgets('plays, seeks, changes speed and volume, reaches the end', (tester) async {
      await _withEngine(tester, 'transport', mkv, (e) async {
        expect(e.snapshot.playing, isFalse, reason: 'open() must leave the film paused');
        await _expectPlays(tester, e);

        await e.pause();
        await _until(tester, 'pause', () => !e.snapshot.playing, state: () => _tell(e));
        await e.seekTo(const Duration(seconds: 6));
        await _until(
          tester,
          'the absolute seek to land within a second of 0:06',
          () => _near(e.snapshot.position, const Duration(seconds: 6), const Duration(seconds: 1)),
          state: () => _tell(e),
        );
        await e.seekBy(const Duration(seconds: 3));
        await _until(
          tester,
          'the relative seek to land within a second of 0:09',
          () => _near(e.snapshot.position, const Duration(seconds: 9), const Duration(seconds: 1)),
          state: () => _tell(e),
        );

        await e.setVolume(50);
        await _until(
          tester,
          'the volume to read 50',
          () => e.player.state.volume == 50,
          state: () => _tell(e),
        );
        await e.setRate(2);
        await _until(
          tester,
          'the speed to read 2x',
          () => e.player.state.rate == 2,
          state: () => _tell(e),
        );

        // Three seconds of film at 2x: the end comes quickly, and the app needs to hear it
        // (Up next, "watched", the sleep timer). Last: media_kit clears the track list at EOF.
        await e.play();
        await _until(
          tester,
          'the end of the film',
          () => e.player.state.completed,
          timeout: const Duration(seconds: 30),
          state: () => _tell(e),
        );
      });
    }, timeout: _perTest);

    testWidgets('switches audio, attaches the sidecar, selects the embedded one', (tester) async {
      await _withEngine(tester, 'tracks', mkv, (e) async {
        await _expectPlays(tester, e);
        // Paused from here on: the film is 12 s long and media_kit empties the track list
        // when it ends, which a slow runner could reach mid-test.
        await e.pause();
        bool real(String? id) => id != null && id.isNotEmpty && id != 'no' && id != 'auto';
        await _until(
          tester,
          'mpv to name the audio track it chose',
          () => real(e.snapshot.audioId) && e.snapshot.audioTracks.length >= 2,
          state: () => _tell(e),
        );
        final first = e.snapshot.audioId!;
        final other = e.snapshot.audioTracks.firstWhere((t) => t.id != first);
        await e.selectAudio(other.id);
        await _until(
          tester,
          'audio track ${other.id} (${other.language}) to be selected',
          () => e.snapshot.audioId == other.id,
          state: () => _tell(e),
        );
        await e.selectAudio(first);
        await _until(
          tester,
          'audio track $first to be selected again',
          () => e.snapshot.audioId == first,
          state: () => _tell(e),
        );

        await _until(
          tester,
          'the embedded subtitle to be listed',
          () => e.snapshot.subtitleTracks.isNotEmpty,
          state: () => _tell(e),
        );
        // Everything listed before we attach: the embedded track first, and the sidecar too if
        // mpv's sub-auto already found it beside the film.
        final before = e.snapshot.subtitleTracks.map((t) => t.id).toList();
        // media_kit lets mpv pick a subtitle on its own: start from "off".
        await e.selectSubtitle('no');
        await _until(tester, 'subtitles off', () => !e.snapshot.hasSubtitle, state: () => _tell(e));

        await e.attachSubtitle(sidecar);
        await _until(
          tester,
          'the sidecar to be the selected subtitle',
          () =>
              e.snapshot.hasSubtitle &&
              e.snapshot.subtitleTracks.length == before.length + 1 &&
              !before.contains(e.snapshot.subtitleId),
          state: () => _tell(e),
        );
        final external = e.snapshot.subtitleId;

        // The same file again selects the existing track; it must not add a second one.
        await e.selectSubtitle('no');
        await _until(tester, 'subtitles off', () => !e.snapshot.hasSubtitle, state: () => _tell(e));
        await e.attachSubtitle(sidecar);
        await _until(
          tester,
          'the sidecar to be selected again',
          () => e.snapshot.subtitleId == external,
          state: () => _tell(e),
        );
        expect(e.snapshot.subtitleTracks, hasLength(before.length + 1), reason: _tell(e));

        await e.selectSubtitle(before.first);
        await _until(
          tester,
          'the embedded subtitle to be selected',
          () => e.snapshot.subtitleId == before.first,
          state: () => _tell(e),
        );
      });
    }, timeout: _perTest);

    testWidgets('writes a frame as a JPEG', (tester) async {
      await _withEngine(tester, 'screenshot', mkv, (e) async {
        await _expectPlays(tester, e);
        await e.pause();
        final target = File(p.join(_out.path, 'frame.jpg'));
        if (target.existsSync()) target.deleteSync();
        final said = await e.screenshotTo(target.path);
        // The file is the contract (Lobby thumbnails, the screenshot key)…
        await _until(
          tester,
          'mpv to write ${target.path}',
          () => target.existsSync() && target.lengthSync() > 0,
          timeout: const Duration(seconds: 10),
          state: () => 'screenshotTo returned $said. ${_tell(e)}',
        );
        _say('frame.jpg: ${target.lengthSync()} bytes');
        // …and the answer must agree with it, or a saved frame is reported as a failure.
        expect(said, isTrue, reason: 'the file was written but screenshotTo returned false');
      });
    }, timeout: _perTest);

    testWidgets('plays the MP4', (tester) async {
      await _withEngine(tester, 'mp4', mp4, (e) async {
        expect(
          _near(
            e.snapshot.duration,
            const Duration(seconds: 12),
            const Duration(milliseconds: 600),
          ),
          isTrue,
          reason: _tell(e),
        );
        await _until(
          tester,
          'both audio tracks',
          () => e.snapshot.audioTracks.length >= 2,
          state: () => _tell(e),
        );
        await _expectPlays(tester, e);
        _say('mp4 chapters: ${(await e.chapters()).map((c) => c.title).toList()}');
      });
    }, timeout: _perTest);

    testWidgets('plays HEVC', (tester) async {
      if (!File(hevc).existsSync()) {
        markTestSkipped('No HEVC fixture: the ffmpeg that made the fixtures has no libx265.');
        return;
      }
      await _withEngine(tester, 'hevc', hevc, (e) async {
        await _expectPlays(tester, e);
        await _until(tester, 'the picture size', () => e.snapshot.width > 0, state: () => _tell(e));
        expect((e.snapshot.width, e.snapshot.height), (640, 360), reason: _tell(e));
      });
    }, timeout: _perTest);
  });

  testWidgets(
    'app: a film with a sidecar starts without the network, and resumes where it stopped',
    timeout: const Timeout(Duration(minutes: 6)),
    (tester) async {
      // The long film when it is there (a 12 s clip is "watched" the moment it is closed, so
      // it can prove a resume ROW but never a resume).
      final hasLong = File(long).existsSync() && File(longSidecar).existsSync();
      final film = hasLong ? long : mkv;
      final subtitle = hasLong ? longSidecar : sidecar;

      FlutterSecureStorage.setMockInitialValues({}); // never the runner's credential store
      final network = _NoNetwork();
      HttpOverrides.global = network;
      final db = MarqueeDatabase(NativeDatabase.memory());
      await db.writeSettings(const Settings(hwdec: 'no'));
      final thumbs = await Directory(p.join(_out.path, 'thumbs')).create(recursive: true);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          thumbnailDirProvider.overrideWith((ref) async => thumbs),
        ],
      );
      final session = container.read(sessionProvider.notifier);
      PlayerEngine? engine() => container.read(sessionProvider)?.engine;
      String tell() {
        final s = container.read(sessionProvider);
        final e = s?.engine;
        return 'room=${container.read(roomProvider)} started=${s?.started} error=${s?.error} '
            'threading=${s?.threading.phase} attached=${s?.threading.attached.runtimeType} '
            'notice=${container.read(noticeProvider)?.text} network=${network.attempts}\n'
            '${e == null ? '(no engine)' : _tell(e)}';
      }

      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const RepaintBoundary(key: _shot, child: MarqueeApp()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(container.read(roomProvider), Room.lobby);
        expect(find.byType(LobbyScreen), findsOneWidget);

        // ── first showing ──
        await session
            .openLocator(film)
            .timeout(
              const Duration(seconds: 60),
              onTimeout: () => fail('openLocator did not return within 60 s. ${tell()}'),
            );
        expect(container.read(roomProvider), Room.auditorium, reason: tell());
        await _mpvLog(engine()!, 'app-first');
        await _until(
          tester,
          'the film to start (threading done)',
          () => container.read(sessionProvider)?.started ?? false,
          timeout: const Duration(seconds: 30),
          state: tell,
        );
        final first = container.read(sessionProvider)!;
        expect(first.error, isNull, reason: tell());
        final attached = first.threading.attached;
        if (attached is! ExternalSubtitle) fail('The sidecar was not picked. ${tell()}');
        expect(p.equals(attached.path, subtitle), isTrue, reason: 'attached ${attached.path}');
        expect(attached.provider, SubtitleProvider.sidecar);
        expect(network.attempts, isEmpty, reason: 'a sidecar must cost zero requests');
        final hash = first.threading.hash;
        expect(hash, isNotNull, reason: 'the fixture is over 128 KiB, so it has a moviehash');

        await _until(
          tester,
          'the position to advance',
          () => first.engine.snapshot.position > const Duration(seconds: 1),
          timeout: const Duration(seconds: 30),
          state: tell,
        );
        await _until(
          tester,
          'libmpv to show the sidecar',
          () => first.engine.snapshot.hasSubtitle,
          state: tell,
        );
        expect(find.byType(AuditoriumScreen), findsOneWidget);
        expect(find.byType(Video), findsWidgets);
        final listed = first.engine.snapshot.subtitleTracks.length;
        if (listed > 1) {
          _note('the film with one sidecar lists $listed subtitle tracks in the Auditorium.');
        }

        if (hasLong) {
          await first.engine.seekTo(const Duration(seconds: 15));
          await _until(
            tester,
            'playback to carry on after the seek to 0:15',
            () {
              final at = first.engine.snapshot.position;
              return at > const Duration(seconds: 16) && at < const Duration(seconds: 28);
            },
            timeout: const Duration(seconds: 30),
            state: tell,
          );
        }
        await _saveShot(tester, 'auditorium.png');

        // ── house lights up ──
        await session.close().timeout(
          const Duration(seconds: 30),
          onTimeout: () => fail('close() did not complete within 30 s. ${tell()}'),
        );
        expect(container.read(roomProvider), Room.lobby);
        expect(container.read(sessionProvider), isNull);
        expect(first.engine.isDisposed, isTrue, reason: 'closing must dispose the player');
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(LobbyScreen), findsOneWidget);
        await _saveShot(tester, 'lobby-after.png');

        final saved = await db.resumeFor(hash!);
        expect(saved, isNotNull, reason: 'closing a started film must save where it was');
        _say('resume row: ${saved!.positionMs} / ${saved.durationMs} ms');
        if (hasLong) {
          expect(saved.durationMs, closeTo(60000, 1500));
          expect(saved.positionMs, inInclusiveRange(15000, 29000));
          expect(saved.resumable, isTrue);
        }

        // ── second showing: libmpv opens AT the saved position ──
        await session
            .openLocator(film)
            .timeout(
              const Duration(seconds: 60),
              onTimeout: () => fail('the second openLocator did not return within 60 s. ${tell()}'),
            );
        expect(container.read(roomProvider), Room.auditorium, reason: tell());
        await _mpvLog(engine()!, 'app-second');
        await _until(
          tester,
          'the second showing to start',
          () => container.read(sessionProvider)?.started ?? false,
          timeout: const Duration(seconds: 30),
          state: tell,
        );
        final second = container.read(sessionProvider)!;
        await _until(
          tester,
          'the second showing to report a position',
          () => second.engine.snapshot.position > Duration.zero,
          timeout: const Duration(seconds: 30),
          state: tell,
        );
        if (hasLong) {
          // The FIRST position it reports: a film that started at 0:00 would get here too,
          // given 15 seconds.
          expect(
            second.engine.snapshot.position,
            greaterThan(Duration(milliseconds: saved.positionMs - 2000)),
            reason: 'the film did not open at its resume point. ${tell()}',
          );
          final notice = container.read(noticeProvider)?.text ?? '';
          if (!notice.startsWith('Resumed at')) {
            _note('resumed, but the notice reads "$notice" instead of "Resumed at …".');
          }
        }
        expect(network.attempts, isEmpty, reason: 'the second showing made a request');
        await session.close().timeout(const Duration(seconds: 30));
        expect(container.read(roomProvider), Room.lobby);

        // Last, so that it cannot hide anything above: the Lobby frame mpv wrote on close.
        final id = await db.mediaIdFor(film);
        expect(id, isNotNull, reason: 'the film has no library row');
        final frame = File(thumbnailPath(thumbs, id!));
        if (hasLong) {
          expect(frame.existsSync(), isTrue, reason: 'no Lobby frame at ${frame.path}');
          expect(frame.lengthSync(), greaterThan(0));
        }
      } finally {
        _say('app test ended at: ${tell()}');
        // Whatever happened, leave no player behind for the next test.
        try {
          await session.close(toLobby: false).timeout(_wait);
        } on Object catch (err) {
          _say('closing the session failed: $err');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await db.close();
        HttpOverrides.global = null;
      }
    },
  );
}
