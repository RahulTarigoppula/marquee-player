// The overlay controls: a top gradient (back, title, match) and a bottom gradient (the film
// gate, transport, volume, tracks, speed, picture, more, fullscreen) drawn ON the picture.
// Pure presentation: everything arrives in [ControlsData] and leaves through
// [ControlsActions], so the screenshot test renders it without a Player.
import 'package:flutter/material.dart';

import '../../../engine/playback.dart';
import '../../../engine/sync_rule.dart';
import '../../../theme/house.dart';
import '../../../theme/tokens.dart';
import '../../components/film_gate.dart';
import '../../components/primitives.dart';
import 'widgets.dart';

/// The menus the bar opens.
enum AuditoriumMenu { subtitles, audio, speed, picture, more, chapters, sleep }

@immutable
class ControlsData {
  final String title;
  final double position, duration, buffered;
  final bool buffering, playing;
  final double volume;
  final bool muted;
  final double rate;
  final int delayMs;
  final bool hasSubtitle, matched;
  final List<double> detents;
  final Map<double, String> chapterTitles;
  final double? loopA, loopB;
  final bool hasPrevious, hasNext;
  final bool fullscreen;

  /// Desktop (mouse + keyboard) or phone (touch) layout.
  final bool desktop;
  final bool showPip;
  final bool sleeping;
  final PictureFit fit;
  final AuditoriumMenu? openMenu;
  final bool syncOpen;

  const ControlsData({
    required this.title,
    required this.position,
    required this.duration,
    this.buffered = 0,
    this.buffering = false,
    this.playing = false,
    this.volume = 100,
    this.muted = false,
    this.rate = 1,
    this.delayMs = 0,
    this.hasSubtitle = false,
    this.matched = false,
    this.detents = const [],
    this.chapterTitles = const {},
    this.loopA,
    this.loopB,
    this.hasPrevious = false,
    this.hasNext = false,
    this.fullscreen = false,
    this.desktop = true,
    this.showPip = false,
    this.sleeping = false,
    this.fit = PictureFit.fit,
    this.openMenu,
    this.syncOpen = false,
  });
}

class ControlsActions {
  final VoidCallback onBack, onPlayPause, onMute, onFullscreen, onToggleSync;
  final VoidCallback? onPrevious, onNext, onPip, onCueSheet;
  final ValueChanged<Duration> onSeekBy;
  final ValueChanged<double> onSeek, onScrub, onVolume;
  final VoidCallback onScrubEnd;
  final ValueChanged<AuditoriumMenu> onMenu;
  const ControlsActions({
    required this.onBack,
    required this.onPlayPause,
    required this.onMute,
    required this.onFullscreen,
    required this.onToggleSync,
    required this.onSeekBy,
    required this.onSeek,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onVolume,
    required this.onMenu,
    this.onPrevious,
    this.onNext,
    this.onPip,
    this.onCueSheet,
  });

  /// For previews and tests.
  static ControlsActions none() => ControlsActions(
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
  );
}

String clockOf(double seconds) => shortClock(Duration(milliseconds: (seconds * 1000).round()));

class AuditoriumControls extends StatelessWidget {
  final ControlsData data;
  final ControlsActions actions;

  /// Extra content under the gate (the sync rule while it is open).
  final Widget? syncRule;
  const AuditoriumControls({super.key, required this.data, required this.actions, this.syncRule});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: _TopBar(data: d, actions: actions),
        ),
        if (!d.desktop || compact)
          Center(
            child: _CentreTransport(data: d, actions: actions),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _BottomBar(data: d, actions: actions, compact: compact, syncRule: syncRule),
        ),
      ],
    );
  }
}

class _Scrim extends StatelessWidget {
  final bool top;
  final Widget child;
  const _Scrim({required this.top, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
        end: top ? Alignment.bottomCenter : Alignment.topCenter,
        colors: const [Color(0xCC000000), Color(0x66000000), Color(0x00000000)],
        stops: const [0, 0.55, 1],
      ),
    ),
    child: child,
  );
}

class _TopBar extends StatelessWidget {
  final ControlsData data;
  final ControlsActions actions;
  const _TopBar({required this.data, required this.actions});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final d = data;
    return _Scrim(
      top: true,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space2,
            Tokens.space2,
            Tokens.space2,
            Tokens.space8,
          ),
          child: Row(
            children: [
              CtlButton(
                icon: 'arrow-left',
                label: 'Back to the lobby (Esc)',
                onTap: actions.onBack,
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Text(
                  d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w500),
                ),
              ),
              if (d.matched) ...[
                Bulb(color: p.success, size: 7),
                const SizedBox(width: Tokens.space2),
                Text('MATCH', style: Txt.mono(Tokens.textXs, p.success)),
                const SizedBox(width: Tokens.space3),
              ],
              if (d.sleeping) ...[
                LucideIcon('timer', size: 18, color: p.accent),
                const SizedBox(width: Tokens.space3),
              ],
              if (d.showPip && actions.onPip != null)
                CtlButton(
                  icon: 'picture-in-picture-2',
                  label: 'Picture in picture',
                  onTap: actions.onPip,
                ),
              if (d.desktop && actions.onCueSheet != null)
                CtlText(text: '?', label: 'Keyboard shortcuts (?)', onTap: actions.onCueSheet),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phones (and narrow windows): back 10, play, forward 10 in the middle of the picture.
class _CentreTransport extends StatelessWidget {
  final ControlsData data;
  final ControlsActions actions;
  const _CentreTransport({required this.data, required this.actions});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (actions.onPrevious != null && data.hasPrevious)
        CtlButton(icon: 'skip-back', label: 'Previous file', onTap: actions.onPrevious),
      const SizedBox(width: Tokens.space4),
      _Jump(back: true, onTap: () => actions.onSeekBy(const Duration(seconds: -10)), size: 56),
      const SizedBox(width: Tokens.space6),
      PlayButton(playing: data.playing, onTap: actions.onPlayPause, size: 68),
      const SizedBox(width: Tokens.space6),
      _Jump(back: false, onTap: () => actions.onSeekBy(const Duration(seconds: 10)), size: 56),
      const SizedBox(width: Tokens.space4),
      if (actions.onNext != null && data.hasNext)
        CtlButton(icon: 'skip-forward', label: 'Next file', onTap: actions.onNext),
    ],
  );
}

/// ±10 s: a circular arrow with the number inside (plain digits — every font has them).
class _Jump extends StatelessWidget {
  final bool back;
  final VoidCallback onTap;
  final double size;
  const _Jump({required this.back, required this.onTap, this.size = Tokens.targetMin});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: back ? 'Back 10 seconds' : 'Forward 10 seconds',
      tooltip: back ? 'Back 10 s' : 'Forward 10 s',
      onTap: onTap,
      radius: size / 2,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: pressWash(p, s)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            LucideIcon(back ? 'rotate-ccw' : 'rotate-cw', size: size * 0.6, color: p.ink),
            Padding(
              padding: EdgeInsets.only(top: size * 0.04),
              child: Text('10', style: Txt.mono(size * 0.2, p.ink, weight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final ControlsData data;
  final ControlsActions actions;
  final bool compact;
  final Widget? syncRule;
  const _BottomBar({
    required this.data,
    required this.actions,
    required this.compact,
    this.syncRule,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final d = data;
    final a = actions;
    final time = Text(
      d.duration > 0 ? '${clockOf(d.position)} / ${clockOf(d.duration)}' : clockOf(d.position),
      softWrap: false,
      style: Txt.mono(Tokens.textSm, p.ink),
    );
    final transport = <Widget>[
      if (!compact && d.desktop) ...[
        PlayButton(playing: d.playing, onTap: a.onPlayPause),
        const SizedBox(width: Tokens.space1),
        _Jump(back: true, onTap: () => a.onSeekBy(const Duration(seconds: -10))),
        _Jump(back: false, onTap: () => a.onSeekBy(const Duration(seconds: 10))),
        if (a.onPrevious != null)
          CtlButton(
            icon: 'skip-back',
            label: 'Previous file (P)',
            onTap: d.hasPrevious ? a.onPrevious : null,
          ),
        if (a.onNext != null)
          CtlButton(
            icon: 'skip-forward',
            label: 'Next file (N)',
            onTap: d.hasNext ? a.onNext : null,
          ),
      ],
      if (d.desktop)
        VolumeControl(
          volume: d.volume,
          muted: d.muted,
          onChanged: a.onVolume,
          onMute: a.onMute,
          width: compact ? 72 : 104,
        )
      else
        CtlButton(
          icon: VolumeControl.iconFor(d.volume, muted: d.muted),
          label: d.muted ? 'Unmute' : 'Mute',
          onTap: a.onMute,
        ),
      const SizedBox(width: Tokens.space2),
      time,
    ];
    final tools = <Widget>[
      if (d.hasSubtitle || d.delayMs != 0)
        CtlText(
          text: 'SYNC ${formatDelay(d.delayMs)}',
          label: 'Subtitle sync ${spokenDelay(d.delayMs)} (J / K)',
          active: d.syncOpen,
          onTap: a.onToggleSync,
        ),
      if (d.loopA != null)
        CtlText(
          text: d.loopB == null ? 'A-' : 'A-B',
          label: d.loopB == null ? 'Loop start set (L)' : 'Looping (L to clear)',
          active: true,
          onTap: () => a.onMenu(AuditoriumMenu.more),
        ),
      CtlButton(
        icon: 'captions',
        label: 'Subtitles (S)',
        active: d.hasSubtitle || d.openMenu == AuditoriumMenu.subtitles,
        onTap: () => a.onMenu(AuditoriumMenu.subtitles),
      ),
      CtlButton(
        icon: 'audio-lines',
        label: 'Audio track (A)',
        active: d.openMenu == AuditoriumMenu.audio,
        onTap: () => a.onMenu(AuditoriumMenu.audio),
      ),
      CtlText(
        text: speedLabel(d.rate),
        label: 'Speed ([ / ])',
        active: d.rate != 1 || d.openMenu == AuditoriumMenu.speed,
        onTap: () => a.onMenu(AuditoriumMenu.speed),
      ),
      if (!compact)
        CtlButton(
          icon: 'scan',
          label: 'Picture: ${d.fit.label}',
          active: d.fit != PictureFit.fit || d.openMenu == AuditoriumMenu.picture,
          onTap: () => a.onMenu(AuditoriumMenu.picture),
        ),
      CtlButton(
        icon: 'ellipsis-vertical',
        label: 'More',
        active: d.openMenu == AuditoriumMenu.more,
        onTap: () => a.onMenu(AuditoriumMenu.more),
      ),
      if (d.desktop)
        CtlButton(
          icon: d.fullscreen ? 'minimize-2' : 'maximize-2',
          label: d.fullscreen ? 'Exit fullscreen (F)' : 'Fullscreen (F)',
          onTap: a.onFullscreen,
        ),
    ];
    return _Scrim(
      top: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space4,
            Tokens.space10,
            Tokens.space4,
            Tokens.space2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?syncRule,
              FilmGate(
                position: d.position,
                duration: d.duration,
                buffered: d.buffered,
                buffering: d.buffering,
                detents: d.detents,
                chapterTitles: d.chapterTitles,
                loopA: d.loopA,
                loopB: d.loopB,
                height: d.desktop ? Tokens.gateHeightDesktop : Tokens.gateHeight * 0.7,
                onSeek: a.onSeek,
                onScrub: a.onScrub,
                onScrubEnd: a.onScrubEnd,
              ),
              const SizedBox(height: Tokens.space1),
              // Two groups; on a narrow phone the tools wrap under the transport, never overflow.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: transport),
                    Row(mainAxisSize: MainAxisSize.min, children: tools),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
