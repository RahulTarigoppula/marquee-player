// Screenshots of the Auditorium's overlay controls, rendered without a Player: the controls
// are pure presentation (ControlsData in, ControlsActions out), drawn here over a stand-in
// "picture". Tagged `screenshot` like screenshots_test.dart (screenshots.yml renders them).
@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/playback.dart';
import 'package:marquee/theme/tokens.dart';
import 'package:marquee/ui/auditorium/controls/controls_bar.dart';
import 'package:marquee/ui/auditorium/controls/widgets.dart';
import 'package:marquee/ui/components/kit.dart';

import 'harness.dart';

/// A warm dusk frame with a bright sky: the controls must read over both.
Widget picture(Widget child) => Stack(
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

final _film = ControlsData(
  title: 'The Third Man (1949)',
  position: 2735,
  duration: 6240,
  buffered: 3100,
  playing: true,
  volume: 85,
  delayMs: 150,
  hasSubtitle: true,
  matched: true,
  detents: [600, 1800, 2700, 4200, 5400],
  chapterTitles: {600: 'The Porter', 2700: 'The Ferris Wheel'},
  hasPrevious: true,
  hasNext: true,
);

/// A narrow portrait phone and a small landscape one: the sizes the menus must fit.
const _phonePortrait = Size(360, 740);
const _phoneLandscape = Size(640, 360);

const _phoneFilm = ControlsData(
  title: 'Frieren S01E05',
  position: 62,
  duration: 1440,
  buffered: 300,
  playing: true,
  hasSubtitle: true,
  hasPrevious: true,
  hasNext: true,
  desktop: false,
  showPip: true,
  seekStep: 15,
  showRemaining: true,
);

/// A menu where the Auditorium puts it: bottom right on desktop, across the phone.
Widget _menuAt({required bool desktop, required Widget menu}) => Positioned(
  right: Tokens.space4,
  left: desktop ? null : Tokens.space4,
  bottom: desktop ? 104 : 132,
  child: Align(alignment: Alignment.bottomRight, child: menu),
);

/// The Audio menu as menu_panel.dart builds it: tracks, then the sound section.
Widget _audioMenu(double maxHeight) => ControlMenu(
  title: 'Audio',
  onClose: () {},
  maxHeight: maxHeight,
  rows: [
    const MenuRow(entry: MenuEntry('JA  Stereo', detail: '2.0 · AAC', selected: true)),
    MenuRow(
      entry: MenuEntry('EN  Dub', detail: '5.1 · EAC3', onTap: () {}),
    ),
    const MenuDivider(),
    MenuRow(
      entry: MenuEntry(
        'Sound',
        icon: 'sliders-horizontal',
        detail: 'Clear voices',
        opens: true,
        onTap: () {},
      ),
    ),
    MenuToggle(label: 'Even out loud and quiet parts', value: true, onChanged: (_) {}),
    MenuStepper(
      label: 'Audio delay',
      valueText: '+0.15 s',
      active: true,
      minusLabel: 'Audio 50 ms earlier',
      plusLabel: 'Audio 50 ms later',
      onMinus: () {},
      onPlus: () {},
      onReset: () {},
    ),
  ],
);

/// "Adjust picture" as menu_panel.dart builds it: four sliders and Reset.
Widget _adjustMenu(double maxHeight) => ControlMenu(
  title: 'Adjust picture',
  onClose: () {},
  onBack: () {},
  maxHeight: maxHeight,
  rows: [
    for (final (label, value) in const [
      ('Brightness', 12),
      ('Contrast', -8),
      ('Saturation', 20),
      ('Gamma', 0),
    ])
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.space1, Tokens.space2, Tokens.space1, 0),
        child: HouseSlider(
          label: label,
          value: value.toDouble(),
          min: -100,
          max: 100,
          divisions: 200,
          valueText: value > 0 ? '+$value' : '$value',
          onChanged: (_) {},
        ),
      ),
    MenuRow(
      entry: MenuEntry('Reset', icon: 'rotate-ccw', onTap: () {}),
    ),
  ],
);

final _details = videoDetailLines(const {
  'video-format': 'hevc',
  'video-params/w': '3840',
  'video-params/h': '2160',
  'video-params/pixelformat': 'yuv420p10',
  'container-fps': '23.976024',
  'estimated-vf-fps': '23.976',
  'video-bitrate': '18400000',
  'hwdec-current': 'd3d11va',
  'frame-drop-count': '3',
  'decoder-frame-drop-count': '0',
  'video-params/primaries': 'bt.2020',
  'video-params/gamma': 'pq',
  'audio-codec-name': 'eac3',
  'audio-params/channel-count': '6',
  'audio-params/samplerate': '48000',
  'audio-bitrate': '640000',
  'file-format': 'matroska,webm',
  'file-size': '4692251771',
  'demuxer-cache-duration': '12.44',
});

void main() {
  testWidgets('auditorium picture adjust panel', (t) async {
    await shoot(
      t,
      'auditorium_picture_adjust',
      picture(
        Stack(
          children: [
            AuditoriumControls(
              data: _film.copyWithMenu(AuditoriumMenu.adjust),
              actions: ControlsActions.none(),
            ),
            _menuAt(desktop: true, menu: _adjustMenu(kDesktop.height * 0.6)),
          ],
        ),
      ),
    );
  });

  testWidgets('auditorium picture adjust panel, phone landscape (scrolls)', (t) async {
    await shoot(
      t,
      'auditorium_picture_adjust_phone_landscape',
      picture(
        Stack(
          children: [
            AuditoriumControls(data: _phoneFilm, actions: ControlsActions.none()),
            _menuAt(desktop: false, menu: _adjustMenu(_phoneLandscape.height * 0.6)),
          ],
        ),
      ),
      size: _phoneLandscape,
    );
  });

  testWidgets('auditorium audio menu with the sound section', (t) async {
    await shoot(
      t,
      'auditorium_audio_menu',
      picture(
        Stack(
          children: [
            AuditoriumControls(
              data: _film.copyWithMenu(AuditoriumMenu.audio),
              actions: ControlsActions.none(),
            ),
            _menuAt(desktop: true, menu: _audioMenu(kDesktop.height * 0.6)),
          ],
        ),
      ),
    );
  });

  testWidgets('auditorium audio menu, narrow phone', (t) async {
    await shoot(
      t,
      'auditorium_audio_menu_phone',
      picture(
        Stack(
          children: [
            AuditoriumControls(data: _phoneFilm, actions: ControlsActions.none()),
            _menuAt(desktop: false, menu: _audioMenu(_phonePortrait.height * 0.6)),
          ],
        ),
      ),
      size: _phonePortrait,
    );
  });

  testWidgets('auditorium video details and skip intro, desktop', (t) async {
    await shoot(
      t,
      'auditorium_details_skip_desktop',
      picture(
        Stack(
          children: [
            AuditoriumControls(
              data: _film,
              actions: ControlsActions(
                onBack: () {},
                onPlayPause: () {},
                onMute: () {},
                onFullscreen: () {},
                onToggleSync: () {},
                onSeekBy: (_) {},
                onSeek: (_) {},
                onScrub: (_) {},
                onScrubEnd: () {},
                onVolume: (_) {},
                onMenu: (_) {},
                onPrevious: () {},
                onNext: () {},
                onToggleClock: () {},
              ),
            ),
            Positioned(
              left: Tokens.space4,
              right: Tokens.space4,
              top: 60,
              child: Align(
                alignment: Alignment.topLeft,
                child: VideoDetailsPanel(lines: _details, onClose: () {}),
              ),
            ),
            Positioned(
              right: Tokens.space4,
              bottom: 104,
              child: SkipPill(label: 'Skip intro', keyHint: 'Enter', onTap: () {}),
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('auditorium video details and skip intro, narrow phone', (t) async {
    await shoot(
      t,
      'auditorium_details_skip_phone',
      picture(
        Stack(
          children: [
            AuditoriumControls(
              data: _phoneFilm,
              actions: ControlsActions(
                onBack: () {},
                onPlayPause: () {},
                onMute: () {},
                onFullscreen: () {},
                onToggleSync: () {},
                onSeekBy: (_) {},
                onSeek: (_) {},
                onScrub: (_) {},
                onScrubEnd: () {},
                onVolume: (_) {},
                onMenu: (_) {},
                onPrevious: () {},
                onNext: () {},
                onPip: () {},
                onToggleClock: () {},
              ),
            ),
            Positioned(
              left: Tokens.space4,
              right: Tokens.space4,
              top: 60,
              child: Align(
                alignment: Alignment.topLeft,
                child: VideoDetailsPanel(lines: _details, onClose: () {}),
              ),
            ),
            Positioned(
              right: Tokens.space4,
              bottom: 132,
              child: SkipPill(label: 'Skip intro', onTap: () {}),
            ),
          ],
        ),
      ),
      size: _phonePortrait,
    );
  });

  testWidgets('auditorium skip pill, phone landscape, controls hidden', (t) async {
    await shoot(
      t,
      'auditorium_skip_phone_landscape',
      picture(
        Stack(
          children: [
            Positioned(
              right: Tokens.space4,
              bottom: 132,
              child: SkipPill(label: 'Next episode', onTap: () {}),
            ),
          ],
        ),
      ),
      size: _phoneLandscape,
    );
  });

  testWidgets('auditorium controls, desktop', (t) async {
    await shoot(
      t,
      'auditorium_controls_desktop',
      picture(AuditoriumControls(data: _film, actions: ControlsActions.none())),
    );
  });

  testWidgets('auditorium controls, desktop, paused with a loop and boost', (t) async {
    await shoot(
      t,
      'auditorium_controls_desktop_loop',
      picture(
        AuditoriumControls(
          data: const ControlsData(
            title: 'Severance S02E03',
            position: 1210,
            duration: 2880,
            buffered: 1500,
            volume: 130,
            rate: 1.25,
            hasSubtitle: true,
            loopA: 1180,
            loopB: 1260,
            fit: PictureFit.fill,
            sleeping: true,
          ),
          actions: ControlsActions.none(),
        ),
      ),
    );
  });

  testWidgets('auditorium controls, phone landscape', (t) async {
    await shoot(
      t,
      'auditorium_controls_phone',
      picture(
        AuditoriumControls(
          data: const ControlsData(
            title: 'Spirited Away',
            position: 3020,
            duration: 7500,
            buffered: 3300,
            playing: true,
            hasSubtitle: true,
            desktop: false,
            showPip: true,
          ),
          actions: ControlsActions.none(),
        ),
      ),
      size: kPhoneLandscape,
    );
  });

  testWidgets('auditorium menu and up next', (t) async {
    await shoot(
      t,
      'auditorium_menu_up_next',
      picture(
        Stack(
          children: [
            AuditoriumControls(
              data: _film.copyWithMenu(AuditoriumMenu.subtitles),
              actions: ControlsActions.none(),
            ),
            Positioned(
              right: 16,
              bottom: 104,
              child: ControlMenu(
                title: 'Subtitles',
                onClose: () {},
                entries: [
                  const MenuEntry('Off'),
                  const MenuEntry('EN  downloaded', detail: 'MATCH', selected: true),
                  const MenuEntry('FR  Forced', detail: 'IMAGE'),
                  MenuEntry('Load subtitle file…', icon: 'file-plus', onTap: () {}),
                  MenuEntry('Find, sync and style…', icon: 'search', onTap: () {}),
                ],
              ),
            ),
            Positioned(
              left: 16,
              bottom: 120,
              child: UpNextCard(
                name: 'Severance.S02E04.1080p.WEB.h264.mkv',
                onPlay: () {},
                onCancel: () {},
              ),
            ),
          ],
        ),
      ),
    );
  });
}

extension on ControlsData {
  ControlsData copyWithMenu(AuditoriumMenu m) => ControlsData(
    title: title,
    position: position,
    duration: duration,
    buffered: buffered,
    playing: playing,
    volume: volume,
    delayMs: delayMs,
    hasSubtitle: hasSubtitle,
    matched: matched,
    detents: detents,
    chapterTitles: chapterTitles,
    hasPrevious: hasPrevious,
    hasNext: hasNext,
    openMenu: m,
  );
}
