// Screenshots of the Auditorium's overlay controls, rendered without a Player: the controls
// are pure presentation (ControlsData in, ControlsActions out), drawn here over a stand-in
// "picture". Tagged `screenshot` like screenshots_test.dart (screenshots.yml renders them).
@Tags(['screenshot'])
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/app.dart' show NoticePill;
import 'package:marquee/engine/models/leader.dart' show ThreadingFailure;
import 'package:marquee/engine/playback.dart';
import 'package:marquee/engine/sentences.dart' show sentenceFor;
import 'package:marquee/state/notice.dart';
import 'package:marquee/theme/tokens.dart';
import 'package:marquee/ui/auditorium/controls/controls_bar.dart';
import 'package:marquee/ui/auditorium/controls/widgets.dart';
import 'package:marquee/ui/auditorium/layers.dart' show Undecodable;
import 'package:marquee/ui/auditorium/menu_panel.dart'
    show attachedSubtitleLabel, delayLabel, kSubtitleOptions, kSubtitleTiming, trackName;
import 'package:marquee/ui/components/film_gate.dart';
import 'package:marquee/ui/components/kit.dart';
import 'package:marquee/ui/components/sync_rule.dart';

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

/// A menu where the Auditorium puts it (the screen uses the same [MenuSlot]): bottom right on
/// desktop, across an upright phone, a sheet down the right edge of a phone held sideways.
Widget _menuAt({required bool desktop, required Widget Function(double, bool) menu}) =>
    MenuSlot(desktop: desktop, builder: menu);

/// A row of choices as menu_panel.dart builds one (tappable, so the chosen row is lit).
MenuRow _row(
  String label, {
  String? detail,
  String? icon,
  bool selected = false,
  bool opens = false,
}) => MenuRow(
  entry: MenuEntry(
    label,
    detail: detail,
    icon: icon,
    selected: selected,
    opens: opens,
    onTap: () {},
  ),
);

/// The Subtitles menu as menu_panel.dart builds it, with its own words for the tracks.
Widget _subtitlesMenu(double maxHeight, {bool fill = false, int delayMs = 350}) => ControlMenu(
  title: 'Subtitles',
  onClose: () {},
  maxHeight: maxHeight,
  fill: fill,
  rows: [
    _row('Off'),
    _row(attachedSubtitleLabel('en', sidecar: false), selected: true),
    _row(trackName('fr', 'Forced', fallback: 'Track 2')),
    _row(trackName('ja', null, fallback: 'Track 3')),
    _row('Second subtitle', icon: 'captions', detail: 'Japanese', opens: true),
    _row(kSubtitleTiming, icon: 'timer', detail: delayLabel(delayMs)),
    _row('Load subtitle file…', icon: 'file-plus'),
    _row(kSubtitleOptions, icon: 'sliders-horizontal'),
  ],
);

/// The More menu as a phone gets it: no key hints, "Turn the screen" and "Touch gestures".
Widget _moreMenu(double maxHeight, {bool fill = false}) => ControlMenu(
  title: 'More',
  onClose: () {},
  maxHeight: maxHeight,
  fill: fill,
  rows: [
    _row('Chapters', icon: 'list', detail: '12', opens: true),
    _row('Set loop start (A)', icon: 'repeat'),
    _row('Repeat', icon: 'repeat-1', opens: true),
    _row('Screenshot', icon: 'camera'),
    _row('Sleep timer', icon: 'timer', opens: true),
    _row('Picture', icon: 'scan', detail: PictureFit.fit.label, opens: true),
    _row('Turn the screen', icon: 'rotate-ccw-square', detail: 'Auto'),
    _row('Video details', icon: 'info'),
    _row('Load subtitle file…', icon: 'file-plus'),
    _row(kSubtitleOptions, icon: 'sliders-horizontal'),
    _row('Touch gestures', icon: 'info'),
  ],
);

/// The Picture menu as menu_panel.dart builds it: the fits, then what is done to the picture.
Widget _pictureMenu(double maxHeight, {bool fill = false}) => ControlMenu(
  title: 'Picture',
  onClose: () {},
  onBack: () {},
  maxHeight: maxHeight,
  fill: fill,
  rows: [
    for (final f in PictureFit.values) _row(f.label, selected: f == PictureFit.fit),
    const MenuDivider(),
    _row('Rotate 90°', icon: 'rotate-cw'),
    MenuStepper(
      label: 'Zoom',
      icon: 'zoom-in',
      valueText: '100 %',
      minusLabel: 'Zoom out',
      plusLabel: 'Zoom in',
      onMinus: () {},
      onPlus: () {},
    ),
    MenuToggle(label: 'Fix comb lines (deinterlace)', value: false, onChanged: (_) {}),
    _row('Adjust picture', icon: 'sliders-horizontal', opens: true),
  ],
);

/// The Audio menu as menu_panel.dart builds it: tracks, then the sound section.
Widget _audioMenu(double maxHeight, {bool fill = false}) => ControlMenu(
  title: 'Audio',
  onClose: () {},
  maxHeight: maxHeight,
  fill: fill,
  rows: [
    _row(trackName('ja', 'Stereo', fallback: 'Track 1'), detail: '2.0 · AAC', selected: true),
    _row(trackName('en', 'Dub', fallback: 'Track 2'), detail: '5.1 · EAC3'),
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
Widget _adjustMenu(double maxHeight, {bool fill = false}) => ControlMenu(
  title: 'Adjust picture',
  onClose: () {},
  onBack: () {},
  maxHeight: maxHeight,
  fill: fill,
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

/// The video details where the Auditorium puts them: under the title and, where the play
/// button is in the middle of the picture, above it (two columns when the room is short,
/// scaled down when even that does not fit).
Widget _detailsAt(Size room, {required bool desktop}) {
  const top = 56.0;
  final band = !desktop || room.width < 720
      ? math.max(room.height / 2 - 34 - Tokens.space2 - top, 48.0)
      : null;
  final wide = band != null && band < VideoDetailsPanel.tallHeight && room.width >= 560;
  final width = room.width - Tokens.space4 * 2;
  return Positioned(
    left: Tokens.space4,
    right: Tokens.space4,
    top: top,
    height: band,
    child: Align(
      alignment: Alignment.topLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: VideoDetailsPanel(
          lines: _details,
          onClose: () {},
          wide: wide,
          maxWidth: wide ? width : math.min(400.0, width),
        ),
      ),
    ),
  );
}

/// A phone's actions: everything the touch layout draws, the lock and rotate buttons included.
ControlsActions _phoneActions() => ControlsActions(
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
  onLock: () {},
  onRotate: () {},
);

/// A stand-in for the preview player's frame: a night street, one lamp.
const _previewFrame = DecoratedBox(
  decoration: BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0.4, -0.3),
      radius: 0.9,
      colors: [Color(0xFFE8C88A), Color(0xFF1C2230), Color(0xFF0B0B0F)],
      stops: [0, 0.35, 1],
    ),
  ),
);

void main() {
  testWidgets('auditorium seek preview above the pointer, desktop', (t) async {
    await shoot(
      t,
      'auditorium_seek_preview_desktop',
      picture(
        AuditoriumControls(
          data: _film,
          actions: ControlsActions.none(),
          seekPreview: _previewFrame,
        ),
      ),
      act: (t) async {
        // A mouse over the seek bar, in the "Ferris Wheel" chapter.
        final gate = t.getRect(find.byType(FilmGate));
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(Offset(gate.left + gate.width * 0.47, gate.bottom - 8));
        await t.pump();
      },
    );
  });

  testWidgets('auditorium seek preview bubble and the time-only label', (t) async {
    await shoot(
      t,
      'auditorium_seek_preview_bubble',
      picture(
        const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SeekPreviewBubble(
                picture: _previewFrame,
                time: '00:48:53',
                chapter: 'The Ferris Wheel',
              ),
              SizedBox(width: Tokens.space6),
              SeekPreviewBubble(picture: _previewFrame, time: '00:03:10'),
            ],
          ),
        ),
      ),
      size: const Size(520, 260),
    );
  });

  testWidgets('auditorium locked: only the unlock pill, phone landscape', (t) async {
    await shoot(
      t,
      'auditorium_locked_phone_landscape',
      picture(
        Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: Tokens.space9,
              child: Center(child: UnlockPill(onUnlock: () {})),
            ),
          ],
        ),
      ),
      size: _phoneLandscape,
    );
  });

  testWidgets('auditorium swipe to seek readout, phone landscape', (t) async {
    await shoot(
      t,
      'auditorium_swipe_seek_phone_landscape',
      picture(
        Align(
          alignment: const Alignment(0, -0.45),
          child: SeekReadout(time: clockOf(62 + 42), delta: signedClock(42)),
        ),
      ),
      size: _phoneLandscape,
    );
  });

  testWidgets('auditorium video details above the play button, phone landscape', (t) async {
    await shoot(
      t,
      'auditorium_details_phone_landscape',
      picture(
        Stack(
          children: [
            AuditoriumControls(data: _phoneFilm, actions: _phoneActions()),
            _detailsAt(_phoneLandscape, desktop: false),
          ],
        ),
      ),
      size: _phoneLandscape,
    );
  });

  testWidgets('auditorium top bar with rotate and lock, narrow phone', (t) async {
    await shoot(
      t,
      'auditorium_controls_phone_portrait',
      picture(
        AuditoriumControls(
          data: const ControlsData(
            title: 'Frieren S01E05 - Phantoms of the Dead',
            position: 62,
            duration: 1440,
            buffered: 300,
            playing: true,
            hasSubtitle: true,
            matched: true,
            sleeping: true,
            hasPrevious: true,
            hasNext: true,
            desktop: false,
            showPip: true,
            orientation: FilmOrientation.landscape,
          ),
          actions: _phoneActions(),
        ),
      ),
      size: _phonePortrait,
    );
  });

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
            _menuAt(desktop: true, menu: (h, fill) => _adjustMenu(h, fill: fill)),
          ],
        ),
      ),
    );
  });

  testWidgets('auditorium picture adjust, phone landscape: a sheet down the right edge', (t) async {
    await shoot(
      t,
      'auditorium_picture_adjust_phone_landscape',
      picture(
        Stack(
          children: [
            AuditoriumControls(
              data: _phoneFilm.withState(menu: AuditoriumMenu.adjust),
              actions: _phoneActions(),
            ),
            _menuAt(desktop: false, menu: (h, fill) => _adjustMenu(h, fill: fill)),
          ],
        ),
      ),
      size: _phoneLandscape,
    );
  });

  // The three menus a phone held sideways could show three rows of: now the full height.
  for (final (name, menu, build) in <(String, AuditoriumMenu, Widget Function(double, bool))>[
    ('more', AuditoriumMenu.more, (h, fill) => _moreMenu(h, fill: fill)),
    ('subtitles', AuditoriumMenu.subtitles, (h, fill) => _subtitlesMenu(h, fill: fill)),
    ('picture', AuditoriumMenu.picture, (h, fill) => _pictureMenu(h, fill: fill)),
  ]) {
    testWidgets('auditorium $name menu, phone landscape: a sheet down the right edge', (t) async {
      await shoot(
        t,
        'auditorium_menu_${name}_phone_landscape',
        picture(
          Stack(
            children: [
              AuditoriumControls(
                data: _phoneFilm.withState(menu: menu, delayMs: 350),
                actions: _phoneActions(),
              ),
              _menuAt(desktop: false, menu: build),
            ],
          ),
        ),
        size: _phoneLandscape,
      );
    });
  }

  testWidgets('auditorium more menu, narrow phone: turn the screen and touch gestures', (t) async {
    await shoot(
      t,
      'auditorium_menu_more_phone',
      picture(
        Stack(
          children: [
            AuditoriumControls(
              data: _phoneFilm.withState(menu: AuditoriumMenu.more),
              actions: _phoneActions(),
            ),
            _menuAt(desktop: false, menu: (h, fill) => _moreMenu(h, fill: fill)),
          ],
        ),
      ),
      size: _phonePortrait,
    );
  });

  testWidgets('auditorium touch gestures guide, phone landscape', (t) async {
    await shoot(
      t,
      'auditorium_gestures_phone_landscape',
      picture(
        Stack(
          fit: StackFit.expand,
          children: [
            AuditoriumControls(data: _phoneFilm, actions: _phoneActions()),
            GestureGuide(seekStep: 15, onDone: () {}),
          ],
        ),
      ),
      size: _phoneLandscape,
    );
  });

  testWidgets('auditorium touch gestures guide, narrow phone', (t) async {
    await shoot(
      t,
      'auditorium_gestures_phone',
      picture(
        Stack(
          fit: StackFit.expand,
          children: [
            AuditoriumControls(data: _phoneFilm, actions: _phoneActions()),
            GestureGuide(seekStep: 15, onDone: () {}),
          ],
        ),
      ),
      size: _phonePortrait,
    );
  });

  testWidgets('auditorium touch gestures guide without swipe to seek or brightness', (t) async {
    await shoot(
      t,
      'auditorium_gestures_fewer_phone_landscape',
      picture(GestureGuide(brightness: false, swipeToSeek: false, onDone: () {})),
      size: _phoneLandscape,
    );
  });

  // The timing rule open on subtitles that come 0.35 s late: the sentence, Earlier / Later,
  // Reset, and the chip in the bar.
  for (final (name, size, film) in [
    ('desktop', kDesktop, _film),
    ('phone', _phonePortrait, _phoneFilm),
    ('phone_landscape', _phoneLandscape, _phoneFilm),
  ]) {
    testWidgets('auditorium subtitle timing rule open, $name', (t) async {
      await shoot(
        t,
        'auditorium_sync_$name',
        picture(
          AuditoriumControls(
            data: film.withState(syncOpen: true, delayMs: 350),
            actions: film.desktop ? ControlsActions.none() : _phoneActions(),
            syncRule: Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space2),
              child: SyncRule(delayMs: 350, onChanged: (_) {}, onClose: () {}),
            ),
          ),
        ),
        size: size,
      );
    });
  }

  testWidgets('auditorium subtitle timing rule at 0: no Reset', (t) async {
    await shoot(
      t,
      'auditorium_sync_zero_phone',
      picture(
        AuditoriumControls(
          data: _phoneFilm.withState(syncOpen: true),
          actions: _phoneActions(),
          syncRule: Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space2),
            child: SyncRule(delayMs: 0, onChanged: (_) {}, onClose: () {}),
          ),
        ),
      ),
      size: _phonePortrait,
    );
  });

  for (final (name, size) in [('desktop', kDesktop), ('phone_landscape', _phoneLandscape)]) {
    testWidgets("auditorium can't play this file, $name", (t) async {
      await shoot(
        t,
        'auditorium_cant_play_$name',
        Undecodable(
          sentence: sentenceFor(ThreadingFailure.decodeFailed),
          fileName: 'Severance.S02E04.1080p.WEB.h264-GROUP.mkv',
          onRetry: () {},
          onBack: () {},
        ),
        size: size,
      );
    });
  }

  // 640 x 320 is the phone the notice was seen on, drawn across the play button: it now sits
  // under the top bar. An upright phone keeps it above the bottom bar.
  for (final (name, size) in [
    ('phone_landscape', const Size(640, 320)),
    ('phone', _phonePortrait),
  ]) {
    testWidgets('auditorium notice clear of the play button, $name', (t) async {
      await shoot(
        t,
        'auditorium_notice_$name',
        picture(
          Stack(
            fit: StackFit.expand,
            children: [
              AuditoriumControls(data: _phoneFilm, actions: _phoneActions()),
              const NoticePill(raised: true),
            ],
          ),
        ),
        size: size,
        overrides: [noticeProvider.overrideWith(_ApiKeyNotice.new)],
      );
    });
  }

  testWidgets('auditorium up next, phone landscape', (t) async {
    await shoot(
      t,
      'auditorium_up_next_phone_landscape',
      picture(
        Stack(
          children: [
            AuditoriumControls(data: _phoneFilm, actions: _phoneActions()),
            Positioned(
              right: Tokens.space5,
              bottom: 108,
              child: UpNextCard(
                name: 'Severance S02E04',
                at: kNight.add(const Duration(seconds: 6)),
                onPlay: () {},
                onCancel: () {},
              ),
            ),
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
            _menuAt(desktop: true, menu: (h, fill) => _audioMenu(h, fill: fill)),
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
            AuditoriumControls(
              data: _phoneFilm.withState(menu: AuditoriumMenu.audio),
              actions: ControlsActions.none(),
            ),
            _menuAt(desktop: false, menu: (h, fill) => _audioMenu(h, fill: fill)),
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
            _detailsAt(kDesktop, desktop: true),
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
            AuditoriumControls(data: _phoneFilm, actions: _phoneActions()),
            _detailsAt(_phonePortrait, desktop: false),
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
            _menuAt(desktop: true, menu: (h, fill) => _subtitlesMenu(h, fill: fill, delayMs: 150)),
            // The card's real corner is the menu's: it is drawn on the left here so one
            // picture shows both. The session owns the countdown; the card shows what is left.
            Positioned(
              left: 16,
              bottom: 120,
              child: UpNextCard(
                name: 'Severance S02E04',
                at: kNight.add(const Duration(seconds: 6)),
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

/// The notice a first film opens with when no API key is set: the long one.
class _ApiKeyNotice extends NoticeNotifier {
  @override
  Notice? build() => Notice(
    sentenceFor(ThreadingFailure.noApiKey),
    actionLabel: 'Subtitles…',
    duration: const Duration(seconds: 8),
    serial: 1,
  );
}

extension on ControlsData {
  ControlsData copyWithMenu(AuditoriumMenu m) => withState(menu: m);

  /// The same film with a menu or the timing rule open.
  ControlsData withState({AuditoriumMenu? menu, bool syncOpen = false, int? delayMs}) =>
      ControlsData(
        title: title,
        position: position,
        duration: duration,
        buffered: buffered,
        buffering: buffering,
        playing: playing,
        volume: volume,
        muted: muted,
        rate: rate,
        delayMs: delayMs ?? this.delayMs,
        hasSubtitle: hasSubtitle,
        matched: matched,
        detents: detents,
        chapterTitles: chapterTitles,
        loopA: loopA,
        loopB: loopB,
        hasPrevious: hasPrevious,
        hasNext: hasNext,
        fullscreen: fullscreen,
        desktop: desktop,
        showPip: showPip,
        sleeping: sleeping,
        fit: fit,
        pictureAdjusted: pictureAdjusted,
        pinned: pinned,
        seekStep: seekStep,
        showRemaining: showRemaining,
        orientation: orientation,
        openMenu: menu,
        syncOpen: syncOpen,
      );
}
