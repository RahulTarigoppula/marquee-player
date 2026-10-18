// Screenshots of the Auditorium's overlay controls, rendered without a Player: the controls
// are pure presentation (ControlsData in, ControlsActions out), drawn here over a stand-in
// "picture". Tagged `screenshot` like screenshots_test.dart (screenshots.yml renders them).
@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/playback.dart';
import 'package:marquee/ui/auditorium/controls/controls_bar.dart';
import 'package:marquee/ui/auditorium/controls/widgets.dart';

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

void main() {
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
