// Settings · About: the version, updates (asked for, never assumed), links, privacy, credits.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/updates.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import 'parts.dart';

const String kTmdbNotice =
    'This product uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.';

/// The promise next to the switch. Keep it true: lib/api/updates.dart is what it describes.
const String kAutoUpdateHelp =
    'Asks GitHub once a day whether a newer version exists. '
    'Nothing about you or your files is sent.';

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = House.paletteOf(context);
    final tmdb = ref.watch(settingsValueProvider.select((s) => s.tmdbEnabled));
    final auto = ref.watch(settingsValueProvider.select((s) => s.autoCheckUpdates));
    // Turning the switch on here starts the daily check even if the shell has not yet.
    ref.watch(autoUpdateCheckProvider);
    Widget line(String t, {Color? c}) => Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      child: Text(t, style: Txt.body(Tokens.textSm, c ?? p.inkMuted)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Marquee',
          children: [
            Text(
              'Version ${ref.watch(currentVersionProvider)}',
              style: Txt.mono(Tokens.textSm, p.ink),
            ),
            const SizedBox(height: Tokens.space2),
            line('A free, open-source video player that finds the subtitles for you. MIT licence.'),
            const SizedBox(height: Tokens.space2),
            Wrap(
              spacing: Tokens.space3,
              runSpacing: Tokens.space3,
              children: [
                HouseButton(
                  key: const ValueKey('project-page'),
                  label: 'Project page',
                  icon: 'external-link',
                  tooltip: 'Opens github.com in your browser',
                  onPressed: () => unawaited(openInBrowser(ref, kProjectPage)),
                ),
                HouseButton(
                  key: const ValueKey('report-problem'),
                  label: 'Report a problem',
                  icon: 'external-link',
                  tooltip: 'Opens github.com in your browser',
                  onPressed: () => unawaited(openInBrowser(ref, kIssuesPage)),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space1),
          ],
        ),
        SettingsGroup(
          title: 'Updates',
          // Only true while the switch below is off: beside a lit switch it would be a lie.
          helper: auto ? null : 'Marquee never looks for updates unless you ask it to.',
          children: [
            // Inset like the switch under it, so the card keeps one left edge.
            const Padding(
              padding: EdgeInsets.fromLTRB(Tokens.space3, 0, Tokens.space3, Tokens.space2),
              child: _UpdateCheck(),
            ),
            ToggleBulb(
              key: const ValueKey('auto-update'),
              label: 'Check for updates automatically',
              hint: kAutoUpdateHelp,
              value: auto,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(autoCheckUpdates: v)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Privacy',
          children: [
            line(
              'No ads, no tracking, no usage statistics: nothing is measured or reported.',
              c: p.ink,
            ),
            line(
              'To find subtitles, only three things leave this device: the file\'s fingerprint '
              '(a 16-character hash), its size, and a title guessed from the file name. They go '
              'to OpenSubtitles (and to Subdl if you turn it on). Never the video, a frame, a '
              'file path or anything about your device.',
            ),
            line(
              'Checking for updates asks GitHub which version is the latest, and only when you '
              'tap the button or turn the daily check on. The request says nothing about you, '
              'your files or this device. Like any website, GitHub sees your internet address.',
            ),
            line(
              'Your OpenSubtitles sign-in token and API keys stay in your device\'s secure '
              'storage. Your password is never stored.',
            ),
          ],
        ),
        SettingsGroup(
          title: 'Credits and licences',
          children: [
            line('Subtitles by OpenSubtitles.com', c: p.ink),
            if (tmdb) line(kTmdbNotice, c: p.ink),
            line(
              'Playback: libmpv (LGPL-2.1+), FFmpeg (LGPL-3.0, built --disable-gpl '
              '--enable-version3) and libass (ISC), dynamically linked. Build scripts: '
              'github.com/media-kit/libmpv-android-video-build (default flavour) and '
              'github.com/media-kit/libmpv-win32-video-cmake. Licence texts ship in LICENSES/.',
            ),
            line(
              'Fonts: Big Shoulders Display, Geist, Geist Mono, Noto Sans (SIL OFL 1.1). '
              'Icons: Lucide (ISC).',
            ),
          ],
        ),
      ],
    );
  }
}

/// "Check for updates" and, right under it, what the check found.
class _UpdateCheck extends ConsumerWidget {
  const _UpdateCheck();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updatesProvider);
    final checking = state is UpdateChecking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: HouseButton(
            key: const ValueKey('check-updates'),
            // No spinner: the label says what is happening.
            label: checking ? 'Checking…' : 'Check for updates',
            icon: 'refresh-cw',
            onPressed: checking
                ? null
                : () => unawaited(ref.read(updatesProvider.notifier).check()),
          ),
        ),
        switch (state) {
          UpdateIdle() || UpdateChecking() => const SizedBox.shrink(),
          UpdateUpToDate() => const Padding(
            padding: EdgeInsets.only(top: Tokens.space3),
            child: StatusLine('You have the latest version.'),
          ),
          UpdateFailed(:final sentence) => Padding(
            padding: const EdgeInsets.only(top: Tokens.space3),
            child: StatusLine(sentence, ok: false),
          ),
          UpdateAvailable(:final release, newer: true) => _NewVersion(release),
          UpdateAvailable(:final release) => _LatestRelease(release),
        },
      ],
    );
  }
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', //
  'October', 'November', 'December',
];

String _day(DateTime utc) {
  final d = utc.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// A newer version: what it is, what changed, and one button that hands the download to the
/// browser. Marquee never downloads or runs an installer itself.
class _NewVersion extends ConsumerWidget {
  final Release release;
  const _NewVersion(this.release);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = House.paletteOf(context);
    final published = release.publishedAt;
    return Container(
      key: const ValueKey('update-available'),
      margin: const EdgeInsets.only(top: Tokens.space4),
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: p.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              'Version ${release.version} is available',
              style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w600),
            ),
          ),
          if (published != null)
            Text('Released ${_day(published)}', style: Txt.body(Tokens.textSm, p.inkMuted)),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: Tokens.space3),
            Text("What's new", style: Txt.body(Tokens.textSm, p.ink, weight: FontWeight.w600)),
            const SizedBox(height: Tokens.space1),
            Text(release.notes, style: Txt.body(Tokens.textSm, p.inkMuted)),
          ],
          const SizedBox(height: Tokens.space4),
          Wrap(
            spacing: Tokens.space3,
            runSpacing: Tokens.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HouseButton(
                key: const ValueKey('download-update'),
                // A HouseButton cannot shrink: both labels fit the 220 px a 360 px phone leaves.
                label: release.hasInstaller ? 'Download' : 'Download page',
                icon: release.hasInstaller ? 'download' : 'external-link',
                kind: ButtonKind.primary,
                onPressed: () => unawaited(openInBrowser(ref, release.downloadUrl)),
              ),
              if (release.hasInstaller)
                TextAction(
                  'See the release page',
                  onTap: () => unawaited(openInBrowser(ref, release.pageUrl)),
                ),
            ],
          ),
          const SizedBox(height: Tokens.space2),
          Text(
            release.hasInstaller
                ? 'Your browser downloads the installer. Open it to update; '
                      'your library and settings stay.'
                : 'Opens in your browser.',
            style: Txt.body(Tokens.textSm, p.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// A test build cannot tell whether the latest release is newer: it shows the release, plainly.
class _LatestRelease extends ConsumerWidget {
  final Release release;
  const _LatestRelease(this.release);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = House.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              'The latest release is ${release.version}. This is a test build, so Marquee '
              "can't tell whether it is older.",
              style: Txt.body(Tokens.textSm, p.ink),
            ),
          ),
          const SizedBox(height: Tokens.space3),
          HouseButton(
            label: 'See the release',
            icon: 'external-link',
            onPressed: () => unawaited(openInBrowser(ref, release.pageUrl)),
          ),
        ],
      ),
    );
  }
}
