// Screenshots of everything that finds, picks and styles subtitles: the opening screen, the
// subtitle options sheet over a playing video, and Settings › Subtitles in its reading order.
// Tagged `screenshot` (see screenshots_test.dart).
//
// The open video is a fixed value: no Player (libmpv is not loaded in a test), no network. The
// engine is a stand-in that answers only what these two widgets ask of it, and fails loudly
// on anything else.
//
// The opening screen's two "stalled" pictures show that screen's own layout for those
// states. In the running app a stall starts the video at once and hands the same rows to the
// subtitle options sheet (SessionNotifier._onThreading), which is shot here too.
@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/models/models.dart';
import 'package:marquee/engine/sentences.dart';
import 'package:marquee/engine/threading.dart' show fallbacksFor;
import 'package:marquee/platform/files.dart' show OpenedFile;
import 'package:marquee/player/engine.dart';
import 'package:marquee/state/providers.dart';
import 'package:marquee/state/session.dart';
import 'package:marquee/ui/booth/booth_sheet.dart';
import 'package:marquee/ui/threading/threading_overlay.dart';
import 'package:marquee/ui/ticket_office/ticket_office_screen.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack;

import 'harness.dart';

// ───────────────────────────── stand-ins ─────────────────────────────

/// What the sheet reads from the player: the subtitle list and which file is which track.
class _FakeEngine implements PlayerEngine {
  final PlaybackState playback;
  final Map<String, String> external;
  _FakeEngine(this.playback, {this.external = const {}});

  @override
  PlaybackState get snapshot => playback;

  @override
  Stream<PlaybackState> get states => Stream.value(playback);

  @override
  String? externalIdFor(String path) => external[path];

  @override
  bool isExternal(String id) => external.containsValue(id);

  @override
  bool get isDisposed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('a screenshot touched the player: ${invocation.memberName}');
}

class _FakeSession extends SessionNotifier {
  final FilmSession film;
  _FakeSession(this.film);
  @override
  FilmSession? build() => film;
}

class _FakeQuota extends QuotaNotifier {
  final Quota quota;
  _FakeQuota(this.quota);
  @override
  Quota build() => quota;
}

class _FakeAccount extends AccountNotifier {
  final Account account;
  _FakeAccount(this.account);
  @override
  Account build() => account;
  @override
  Future<String?> subdlKey() async => null;
}

// ───────────────────────────── the video and what was found ─────────────────────────────

const _path = r'D:\Films\The.Third.Man.1949.1080p.BluRay.x264.mkv';
const _subtitlePath = r'D:\Films\The.Third.Man.1949.1080p.BluRay.x264.en.srt';

FilmSession _film({
  required ThreadingState threading,
  bool started = false,
  int delayMs = 0,
  int audioDelayMs = 0,
  PlaybackState playback = const PlaybackState(),
  Map<String, String> external = const {},
}) => FilmSession(
  file: const OpenedFile(
    locator: _path,
    displayName: 'The.Third.Man.1949.1080p.BluRay.x264.mkv',
    sizeBytes: 1524713318,
  ),
  engine: _FakeEngine(playback, external: external),
  threading: threading,
  title: 'The Third Man',
  delayMs: delayMs,
  audioDelayMs: audioDelayMs,
  started: started,
);

ScoredCandidate _found(
  String id,
  String language,
  String release, {
  int downloads = 0,
  bool exact = false,
  bool hearingImpaired = false,
  bool machine = false,
  SubtitleProvider provider = SubtitleProvider.openSubtitles,
}) => ScoredCandidate(
  candidate: SubtitleCandidate(
    provider: provider,
    id: id,
    language: language,
    release: release,
    downloadCount: downloads,
    hearingImpaired: hearingImpaired,
    moviehashMatch: exact,
    machineTranslated: machine,
  ),
  score: exact ? 1 : 0.5,
  reasons: const [],
  autoPick: exact,
);

final _exact = _found(
  '101',
  'en',
  'The.Third.Man.1949.1080p.BluRay.x264-GROUP',
  downloads: 12431,
  exact: true,
);

/// Matched by the file's name only: the viewer picks. Every kind of small print is here once.
final _byName = [
  _found('201', 'en', 'The.Third.Man.1949.REMASTERED.720p.BluRay', downloads: 48210),
  _found('202', 'en', 'The Third Man (1949) Criterion', downloads: 9120, hearingImpaired: true),
  _found('203', 'hi', 'The.Third.Man.1949.WEB-DL', downloads: 312, machine: true),
  _found('204', 'en', 'The.Third.Man.1949.DVDRip', provider: SubtitleProvider.subdl),
  _found('205', 'hi', 'The.Third.Man.1949.1080p.BluRay.x264', downloads: 1),
];

Stalled _stall(ThreadingFailure failure, String sentence, {bool subdl = false}) => Stalled(
  at: LeaderPhase.searching,
  failure: failure,
  next: fallbacksFor(
    failure,
    subdlEnabled: subdl,
    filenameSearchDone: failure == ThreadingFailure.noApiKey,
    at: LeaderPhase.searching,
  ),
  sentence: sentence,
  stalledAt: kNight,
);

final _searching = ThreadingState(
  phase: LeaderPhase.searching,
  phaseStartedAt: kNight,
  hash: const MovieHash('8e245d9679d31e12'),
  sizeBytes: 1524713318,
);

/// The usual first run: an exact match was found and is on its way.
final _downloading = ThreadingState(
  phase: LeaderPhase.downloading,
  phaseStartedAt: kNight,
  candidates: [_exact, ..._byName.take(2)],
  picked: _exact,
);

final _pickOne = ThreadingState(
  phase: LeaderPhase.searching,
  phaseStartedAt: kNight,
  candidates: _byName,
  event: _stall(ThreadingFailure.noResults, kPickASubtitle, subdl: true),
);

final _noKey = ThreadingState(
  phase: LeaderPhase.searching,
  phaseStartedAt: kNight,
  event: _stall(ThreadingFailure.noApiKey, sentenceFor(ThreadingFailure.noApiKey)),
);

/// A subtitle Marquee downloaded for this exact file, shown, with two that came in the video.
final _attachedPlayback = PlaybackState(
  position: const Duration(minutes: 45, seconds: 35),
  duration: const Duration(minutes: 104),
  playing: true,
  subtitleTracks: const [
    SubtitleTrack('1', null, 'eng'),
    SubtitleTrack('2', 'Forced', 'fre'),
    SubtitleTrack('3', null, null),
  ],
  subtitleId: '4',
);

const _attached = ExternalSubtitle(
  path: _subtitlePath,
  language: 'en',
  provider: SubtitleProvider.openSubtitles,
  syncedByHash: true,
  release: 'The.Third.Man.1949.1080p.BluRay.x264-GROUP',
);

/// The video open (and faked), with [quota] downloads left.
List<Override> _open(
  FilmSession film, {
  Quota quota = Quota.anonymous,
  Settings settings = const Settings(languages: ['en', 'hi']),
}) => screenOverrides(
  settings: settings,
  extra: [
    sessionProvider.overrideWith(() => _FakeSession(film)),
    playbackProvider.overrideWith((ref) => Stream.value(film.engine.snapshot)),
    quotaProvider.overrideWith(() => _FakeQuota(quota)),
  ],
);

/// A dusk frame behind the overlays: they must read over a picture, not over black.
Widget _over(Widget child) => Stack(
  fit: StackFit.expand,
  children: [
    const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE9D7B8), Color(0xFF8A5A3C), Color(0xFF1E1410)],
        ),
      ),
    ),
    child,
  ],
);

/// Desktop, a phone, and the same phone on its side: (file suffix, size, platform).
const _devices = [
  ('desktop', kDesktop, TargetPlatform.windows),
  ('phone', kPhone, TargetPlatform.android),
  ('phone_landscape', kPhoneLandscape, TargetPlatform.android),
];

const _signedIn = Account(status: AccountStatus.signedIn, username: 'holly_martins');

Future<void> _show(WidgetTester t, String heading) => t.ensureVisible(find.text(heading));

void main() {
  for (final (device, size, platform) in _devices) {
    // ── The opening screen ──

    for (final (name, state, quota) in [
      ('searching', _searching, Quota.anonymous),
      ('downloading', _downloading, const Quota(remaining: 7, total: 10, signedIn: true)),
      ('pick', _pickOne, Quota.anonymous),
      ('no_key', _noKey, Quota.anonymous),
    ]) {
      testWidgets('opening screen, $name, $device', (t) async {
        await shoot(
          t,
          'threading_${name}_$device',
          _over(const ThreadingOverlay()),
          size: size,
          platform: platform,
          overrides: _open(_film(threading: state), quota: quota),
        );
      });
    }

    // ── Subtitle options, over the playing video ──

    testWidgets('subtitle options, a subtitle attached, $device', (t) async {
      await shoot(
        t,
        'booth_attached_$device',
        _over(const BoothSheet()),
        size: size,
        platform: platform,
        overrides: _open(
          _film(
            threading: const ThreadingState(phase: LeaderPhase.done, attached: _attached),
            started: true,
            delayMs: 350,
            playback: _attachedPlayback,
            external: const {_subtitlePath: '4'},
          ),
          quota: const Quota(remaining: 6, total: 10, signedIn: true),
        ),
      );
    });

    testWidgets('subtitle options, results to pick from, $device', (t) async {
      await shoot(
        t,
        'booth_results_$device',
        _over(const BoothSheet()),
        size: size,
        platform: platform,
        overrides: _open(_film(threading: _pickOne, started: true)),
      );
    });

    // ── Settings › Subtitles ──

    testWidgets('settings, subtitles, the account after the look, $device', (t) async {
      await shoot(
        t,
        'settings_subtitles_account_$device',
        const TicketOfficeScreen(initialSection: SettingsSection.subtitles),
        size: size,
        platform: platform,
        overrides: screenOverrides(
          settings: const Settings(languages: ['en', 'hi'], subdlEnabled: true),
        ),
        act: (t) => _show(t, 'Finding subtitles'),
      );
    });
  }

  testWidgets('subtitle options, timing and look, phone', (t) async {
    await shoot(
      t,
      'booth_timing_look_phone',
      _over(const BoothSheet()),
      size: kPhone,
      platform: TargetPlatform.android,
      overrides: _open(
        _film(
          threading: const ThreadingState(phase: LeaderPhase.done, attached: _attached),
          started: true,
          delayMs: 350,
          audioDelayMs: -150,
          playback: _attachedPlayback,
          external: const {_subtitlePath: '4'},
        ),
        settings: const Settings(subtitleTint: SubtitleTint.yellow, subtitleScale: 1.2),
      ),
      act: (t) => _show(t, 'Subtitles too early or late?'),
    );
  });

  testWidgets('subtitle options, the sound out of step, desktop', (t) async {
    await shoot(
      t,
      'booth_sound_desktop',
      _over(const BoothSheet()),
      platform: TargetPlatform.windows,
      overrides: _open(
        _film(
          threading: const ThreadingState(phase: LeaderPhase.done, attached: _attached),
          started: true,
          audioDelayMs: 150,
          playback: _attachedPlayback,
          external: const {_subtitlePath: '4'},
        ),
      ),
      act: (t) => _show(t, 'Sound too early or late?'),
    );
  });

  testWidgets('settings, subtitles, in reading order, phone landscape', (t) async {
    await shoot(
      t,
      'settings_subtitles_order_phone_landscape',
      const TicketOfficeScreen(initialSection: SettingsSection.subtitles),
      size: kPhoneLandscape,
      platform: TargetPlatform.android,
      overrides: screenOverrides(settings: const Settings(languages: ['en', 'hi'])),
    );
  });

  for (final (name, quota) in const [
    ('signed_in', Quota(remaining: 7, total: 10, signedIn: true)),
    ('nearly_out', Quota(remaining: 2, total: 10, signedIn: true)),
  ]) {
    testWidgets('settings, subtitles, account $name, phone', (t) async {
      await shoot(
        t,
        'settings_subtitles_${name}_phone',
        const TicketOfficeScreen(initialSection: SettingsSection.subtitles),
        size: kPhone,
        platform: TargetPlatform.android,
        overrides: screenOverrides(
          settings: const Settings(languages: ['en', 'hi']),
          extra: [
            accountProvider.overrideWith(() => _FakeAccount(_signedIn)),
            quotaProvider.overrideWith(() => _FakeQuota(quota)),
          ],
        ),
        act: (t) => _show(t, 'OpenSubtitles account'),
      );
    });
  }
}
