// Screenshots of the v2 Settings: the new preferences in Subtitles and Playback, and About
// with every answer the update check can give. Tagged `screenshot` (see screenshots_test.dart).
// The update notifier is faked: nothing here may reach GitHub.
//
// The Library section is not shot here: its folders card (lib/ui/lobby/library_folders.dart)
// reads the device library, which needs that feature's own fakes.
@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/models/settings.dart';
import 'package:marquee/state/updates.dart';
import 'package:marquee/ui/ticket_office/ticket_office_screen.dart';

import 'harness.dart';

class FakeUpdates extends UpdatesNotifier {
  final UpdateState initial;
  FakeUpdates(this.initial);
  @override
  UpdateState build() => initial;
  @override
  Future<void> check() async {}
  @override
  Future<void> checkIfDue() async {}
}

const _releases = 'https://github.com/RahulTarigoppula/marquee-player/releases';

final _release = Release(
  tag: 'v2.1.0',
  name: 'Marquee 2.1',
  pageUrl: '$_releases/tag/v2.1.0',
  downloadUrl: '$_releases/download/v2.1.0/marquee-windows-x64-setup.exe',
  publishedAt: DateTime.utc(2026, 10, 12, 18),
  notes:
      'Subtitles in your colour, and sound that suits the room.\n\n'
      '• Subtitle colours: white, yellow or warm\n'
      '• Sound profiles, and a switch that evens out loud and quiet parts\n'
      '• Library folders: point Marquee at where your videos live\n'
      '• A small preview as you move along the seek bar',
);

/// The update state under test, a fixed version, and no start-up timer left pending.
List<Override> _updates(UpdateState state, {String version = '2.0.0'}) => [
  updatesProvider.overrideWith(() => FakeUpdates(state)),
  currentVersionProvider.overrideWithValue(version),
  autoUpdateCheckProvider.overrideWith((ref) {}),
];

/// Desktop and phone: (file suffix, size, platform).
const _devices = [
  ('desktop', kDesktop, TargetPlatform.windows),
  ('phone', kPhone, TargetPlatform.android),
];

Future<void> _show(WidgetTester t, String heading) async {
  await t.ensureVisible(find.text(heading));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final (device, size, platform) in _devices) {
    testWidgets('settings v2, subtitles look with a colour, $device', (t) async {
      await shoot(
        t,
        'settings_v2_subtitles_look_$device',
        const TicketOfficeScreen(initialSection: SettingsSection.subtitles),
        size: size,
        platform: platform,
        overrides: screenOverrides(
          settings: const Settings(
            languages: ['en', 'hi'],
            subtitleTint: SubtitleTint.yellow,
            subtitleScale: 1.2,
          ),
        ),
        act: (t) => _show(t, 'How subtitles look'),
      );
    });

    testWidgets('settings v2, playback, $device', (t) async {
      await shoot(
        t,
        'settings_v2_playback_$device',
        const TicketOfficeScreen(initialSection: SettingsSection.playback),
        size: size,
        platform: platform,
        overrides: screenOverrides(settings: const Settings(seekStepSeconds: 15)),
      );
    });

    testWidgets('settings v2, playback sound, $device', (t) async {
      await shoot(
        t,
        'settings_v2_playback_sound_$device',
        const TicketOfficeScreen(initialSection: SettingsSection.playback),
        size: size,
        platform: platform,
        overrides: screenOverrides(
          settings: const Settings(
            eqPreset: EqPreset.nightMode,
            audioNormalize: true,
            audioLanguages: ['en'],
          ),
        ),
        act: (t) => _show(t, 'Sound'),
      );
    });

    testWidgets('settings v2, about, nothing asked yet, $device', (t) async {
      await shoot(
        t,
        'settings_v2_about_$device',
        const TicketOfficeScreen(initialSection: SettingsSection.about),
        size: size,
        platform: platform,
        overrides: screenOverrides(extra: _updates(const UpdateIdle())),
      );
    });

    testWidgets('settings v2, about, update available, $device', (t) async {
      await shoot(
        t,
        'settings_v2_about_update_$device',
        const TicketOfficeScreen(initialSection: SettingsSection.about),
        size: size,
        platform: platform,
        overrides: screenOverrides(
          settings: const Settings(autoCheckUpdates: true),
          extra: _updates(UpdateAvailable(_release)),
        ),
        act: (t) => _show(t, 'Updates'),
      );
    });
  }

  testWidgets('settings v2, about, up to date, phone', (t) async {
    await shoot(
      t,
      'settings_v2_about_uptodate_phone',
      const TicketOfficeScreen(initialSection: SettingsSection.about),
      size: kPhone,
      overrides: screenOverrides(extra: _updates(const UpdateUpToDate(), version: '2.1.0')),
    );
  });

  testWidgets('settings v2, about, checking, desktop', (t) async {
    await shoot(
      t,
      'settings_v2_about_checking_desktop',
      const TicketOfficeScreen(initialSection: SettingsSection.about),
      platform: TargetPlatform.windows,
      overrides: screenOverrides(extra: _updates(const UpdateChecking())),
    );
  });

  testWidgets('settings v2, about, offline, desktop', (t) async {
    await shoot(
      t,
      'settings_v2_about_offline_desktop',
      const TicketOfficeScreen(initialSection: SettingsSection.about),
      platform: TargetPlatform.windows,
      overrides: screenOverrides(
        extra: _updates(const UpdateFailed("You're offline. Try again when you're connected.")),
      ),
    );
  });

  testWidgets('settings v2, about, a test build is shown the release, phone', (t) async {
    await shoot(
      t,
      'settings_v2_about_testbuild_phone',
      const TicketOfficeScreen(initialSection: SettingsSection.about),
      size: kPhone,
      overrides: screenOverrides(
        extra: _updates(UpdateAvailable(_release, newer: false), version: '0.0.412'),
      ),
    );
  });

  testWidgets('settings v2, about, narrow phone (360 px), update available', (t) async {
    await shoot(
      t,
      'settings_v2_about_update_narrow',
      const TicketOfficeScreen(initialSection: SettingsSection.about),
      size: const Size(360, 780),
      overrides: screenOverrides(extra: _updates(UpdateAvailable(_release))),
      act: (t) => _show(t, 'Updates'),
    );
  });

  testWidgets('settings v2, playback, narrow phone (360 px)', (t) async {
    await shoot(
      t,
      'settings_v2_playback_narrow',
      const TicketOfficeScreen(initialSection: SettingsSection.playback),
      size: const Size(360, 780),
      overrides: screenOverrides(),
    );
  });
}
