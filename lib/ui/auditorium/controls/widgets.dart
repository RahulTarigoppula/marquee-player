// The Auditorium's own small controls, drawn ON the picture: glyph buttons with a soft wash,
// the volume slider, the menu panel and its rows, the swipe readouts, the "Skip intro" pill,
// the "Unlock" pill, the video details panel and the "Up next" card. They read the Auditorium
// palette only (playback is always the Auditorium). Pure presentation: the screenshot tests
// draw them.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../engine/models/settings.dart';
import '../../../theme/house.dart';
import '../../../theme/tokens.dart';
import '../../components/primitives.dart';

/// A glyph button over the picture: ink at rest (not muted — it sits on moving images),
/// tungsten when [active], a round wash on hover / press / focus.
class CtlButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  final double iconSize;
  final bool tooltip;
  const CtlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.size = Tokens.targetMin,
    this.iconSize = 22,
    this.tooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: label,
      tooltip: tooltip ? label : null,
      onTap: onTap,
      radius: size / 2,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pressWash(p, s, active: active),
        ),
        child: Center(
          child: LucideIcon(
            icon,
            size: iconSize,
            color: onTap == null ? p.inkFaint : (active ? p.accent : p.ink),
          ),
        ),
      ),
    );
  }
}

/// A short text control over the picture (`1.25×`, `SYNC +0.35`, `A-B`).
class CtlText extends StatelessWidget {
  final String text;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  const CtlText({
    super.key,
    required this.text,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: label,
      tooltip: label,
      onTap: onTap,
      radius: Tokens.radiusFull,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minWidth: Tokens.targetMin, minHeight: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Tokens.radiusFull),
          color: pressWash(p, s, active: active),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            softWrap: false,
            style: Txt.mono(Tokens.textSm, active ? p.accent : p.ink, weight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

/// The big round play / pause in the middle of a phone screen, or at the start of the bar.
class PlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  final double size;
  const PlayButton({super.key, required this.playing, required this.onTap, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: playing ? 'Pause' : 'Play',
      tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
      onTap: onTap,
      radius: size / 2,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: s.pressed ? Color.lerp(p.accent, p.bg, 0.15) : p.accent,
          boxShadow: [
            BoxShadow(color: p.accent.withValues(alpha: s.lit ? 0.5 : 0.3), blurRadius: 16),
          ],
        ),
        child: Center(
          child: LucideIcon(playing ? 'pause' : 'play', color: p.accentInk, size: size * 0.45),
        ),
      ),
    );
  }
}

/// The volume: a mute glyph and a slider to 150 % (the part above 100 % is "boost").
class VolumeControl extends StatelessWidget {
  final double volume;
  final bool muted;
  final ValueChanged<double> onChanged;
  final VoidCallback onMute;
  final double width;
  const VolumeControl({
    super.key,
    required this.volume,
    required this.muted,
    required this.onChanged,
    required this.onMute,
    this.width = 104,
  });

  static String iconFor(double volume, {required bool muted}) => muted || volume <= 0
      ? 'volume-x'
      : volume < 50
      ? 'volume-1'
      : 'volume-2';

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final v = muted ? 0.0 : volume.clamp(0.0, Settings.maxVolume);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CtlButton(
          icon: iconFor(volume, muted: muted),
          label: muted ? 'Unmute (M)' : 'Mute (M)',
          onTap: onMute,
        ),
        SizedBox(
          width: width,
          child: Semantics(
            label: 'Volume',
            value: '${v.round()} percent',
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: v > 100 ? p.warning : p.accent,
                inactiveTrackColor: p.ink.withValues(alpha: 0.25),
                thumbColor: v > 100 ? p.warning : p.accent,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(value: v, max: Settings.maxVolume, onChanged: onChanged),
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of a [ControlMenu].
class MenuEntry {
  final String label;
  final String? detail;
  final bool selected;
  final String? icon;
  final VoidCallback? onTap;

  /// Opens a sub-list instead of acting (a chevron is drawn).
  final bool opens;
  const MenuEntry(
    this.label, {
    this.detail,
    this.selected = false,
    this.icon,
    this.onTap,
    this.opens = false,
  });
}

/// The panel the subtitle / audio / speed / picture / more buttons open, above the bar.
/// It scrolls: a landscape phone shows three rows of it.
class ControlMenu extends StatelessWidget {
  final String title;
  final List<MenuEntry> entries;

  /// Rows of any kind ([MenuRow], [MenuToggle], [MenuStepper], [MenuDivider], a slider),
  /// drawn instead of [entries] for a menu that is more than a list of choices.
  final List<Widget>? rows;
  final VoidCallback? onBack;
  final VoidCallback onClose;
  final double maxHeight;
  const ControlMenu({
    super.key,
    required this.title,
    required this.onClose,
    this.entries = const [],
    this.rows,
    this.onBack,
    this.maxHeight = 420,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Container(
      constraints: BoxConstraints(maxWidth: 340, maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: p.bgElevated.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: p.border),
        boxShadow: Tokens.shadow3,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.space2, Tokens.space1, Tokens.space1, 0),
            child: Row(
              children: [
                if (onBack != null)
                  CtlButton(icon: 'arrow-left', label: 'Back', onTap: onBack, iconSize: 18)
                else
                  const SizedBox(width: Tokens.space3),
                Expanded(child: Text(title.toUpperCase(), style: Txt.label(p.inkFaint))),
                CtlButton(icon: 'x', label: 'Close', onTap: onClose, iconSize: 18),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, Tokens.space2),
              children: rows ?? [for (final e in entries) MenuRow(entry: e)],
            ),
          ),
        ],
      ),
    );
  }
}

class MenuRow extends StatelessWidget {
  final MenuEntry entry;
  const MenuRow({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final e = entry;
    return Pressable(
      label: e.label,
      selected: e.selected,
      inMutuallyExclusiveGroup: !e.opens && e.icon == null,
      onTap: e.onTap,
      radius: 0,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        color: pressWash(p, s),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: e.icon != null
                  ? LucideIcon(e.icon!, size: 18, color: p.inkMuted)
                  : e.selected
                  ? LucideIcon('check', size: 18, color: p.accent)
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
                child: Text(
                  e.label,
                  style: Txt.body(
                    Tokens.textBase,
                    e.onTap == null ? p.inkFaint : (e.selected ? p.accent : p.ink),
                    weight: e.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            if (e.detail != null) ...[
              const SizedBox(width: Tokens.space2),
              Text(e.detail!, style: Txt.mono(Tokens.textXs, p.inkMuted)),
            ],
            if (e.opens) ...[
              const SizedBox(width: Tokens.space1),
              LucideIcon('chevron-right', size: 16, color: p.inkMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// A hairline between two groups of rows (the tracks, then what is done to them).
class MenuDivider extends StatelessWidget {
  const MenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: Tokens.space1),
    color: House.paletteOf(context).border,
  );
}

/// A menu row that switches something on or off, without closing the menu.
class MenuToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? icon;
  const MenuToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: label,
      toggled: value,
      onTap: () => onChanged(!value),
      radius: 0,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        color: pressWash(p, s),
        child: ExcludeSemantics(
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: icon == null ? null : LucideIcon(icon!, size: 18, color: p.inkMuted),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
                  child: Text(label, style: Txt.body(Tokens.textBase, p.ink)),
                ),
              ),
              const SizedBox(width: Tokens.space2),
              BulbSwitch(value: value, hovered: s.hovered),
            ],
          ),
        ),
      ),
    );
  }
}

/// A menu row that nudges a value down or up and shows it (audio delay, zoom). A null
/// [onMinus] / [onPlus] is the end of the range; [onReset] appears once the value has moved.
class MenuStepper extends StatelessWidget {
  final String label;
  final String valueText;
  final String minusLabel, plusLabel;
  final VoidCallback? onMinus, onPlus, onReset;
  final String? icon;

  /// Off its resting value: the readout lights.
  final bool active;
  const MenuStepper({
    super.key,
    required this.label,
    required this.valueText,
    required this.minusLabel,
    required this.plusLabel,
    required this.onMinus,
    required this.onPlus,
    this.onReset,
    this.icon,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Tokens.targetMin),
      child: Padding(
        padding: const EdgeInsets.only(left: Tokens.space4, right: Tokens.space2),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: icon == null ? null : LucideIcon(icon!, size: 18, color: p.inkMuted),
            ),
            Expanded(child: Text(label, style: Txt.body(Tokens.textBase, p.ink))),
            CtlButton(icon: 'minus', label: minusLabel, onTap: onMinus, size: 40, iconSize: 18),
            SizedBox(
              width: 60,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  valueText,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: Txt.mono(Tokens.textSm, active ? p.accent : p.inkMuted),
                ),
              ),
            ),
            CtlButton(icon: 'plus', label: plusLabel, onTap: onPlus, size: 40, iconSize: 18),
            if (onReset != null)
              CtlButton(
                icon: 'rotate-ccw',
                label: 'Reset ${label.toLowerCase()}',
                onTap: onReset,
                size: 36,
                iconSize: 16,
              ),
          ],
        ),
      ),
    );
  }
}

/// "Skip intro": a pill that sits bottom-right above the controls while the film is inside
/// an intro, recap, credits or preview chapter, whether or not the controls are showing.
class SkipPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// The key that does the same (desktop), drawn after the label.
  final String? keyHint;
  const SkipPill({super.key, required this.label, required this.onTap, this.keyHint});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: label,
      onTap: onTap,
      radius: Tokens.radiusFull,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        decoration: BoxDecoration(
          color: Color.alphaBlend(pressWash(p, s), p.bgElevated.withValues(alpha: 0.92)),
          borderRadius: BorderRadius.circular(Tokens.radiusFull),
          border: Border.all(color: s.lit ? p.inkFaint : p.borderStrong),
          boxShadow: Tokens.shadow3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w600)),
            const SizedBox(width: Tokens.space2),
            LucideIcon('skip-forward', size: 18, color: p.accent),
            if (keyHint != null) ...[
              const SizedBox(width: Tokens.space3),
              Text(keyHint!, style: Txt.mono(Tokens.textXs, p.inkMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The video details overlay: what the file is and how it is being played, in mono, top-left.
/// [lines] come from `videoDetailLines`; a value mpv did not give is simply not in them.
///
/// [wide] lays the rows out in two columns with no heading: a phone on its side has a band
/// only a few rows tall between the title and the play button, and the panel must stay in it.
class VideoDetailsPanel extends StatelessWidget {
  final List<({String label, String value})> lines;
  final VoidCallback? onClose;
  final bool wide;

  /// The widest the panel may be (the room's width, less its margins).
  final double maxWidth;
  const VideoDetailsPanel({
    super.key,
    required this.lines,
    this.onClose,
    this.wide = false,
    this.maxWidth = 400,
  });

  /// About how tall the one-column panel is with every row present: the screen uses it to
  /// decide whether the panel fits above the centre transport.
  static const double tallHeight = 240;

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    Widget row(({String label, String value}) l) => Padding(
      padding: const EdgeInsets.only(top: 2, right: Tokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: wide ? 104 : 116,
            child: Text(l.label, style: Txt.mono(Tokens.textXs, p.inkMuted)),
          ),
          Flexible(
            child: Text(
              l.value,
              maxLines: wide ? 1 : null,
              overflow: wide ? TextOverflow.ellipsis : null,
              style: Txt.mono(Tokens.textXs, p.ink),
            ),
          ),
        ],
      ),
    );
    final close = onClose == null
        ? null
        : CtlButton(
            icon: 'x',
            label: 'Close video details',
            onTap: onClose,
            size: 36,
            iconSize: 16,
          );
    final empty = Text('Nothing to show yet.', style: Txt.mono(Tokens.textXs, p.inkMuted));
    final half = (lines.length + 1) ~/ 2;
    return Container(
      constraints: BoxConstraints(maxWidth: wide ? maxWidth.clamp(280.0, 720.0) : maxWidth),
      padding: wide
          ? const EdgeInsets.fromLTRB(Tokens.space3, Tokens.space1, Tokens.space1, Tokens.space2)
          : const EdgeInsets.fromLTRB(Tokens.space3, Tokens.space1, Tokens.space1, Tokens.space3),
      decoration: BoxDecoration(
        color: p.bg.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: p.border),
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lines.isEmpty) Expanded(child: empty),
                for (final column in [lines.take(half), lines.skip(half)])
                  if (column.isNotEmpty)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [for (final l in column) row(l)],
                      ),
                    ),
                ?close,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('VIDEO DETAILS', style: Txt.label(p.inkFaint))),
                    close ?? const SizedBox(height: 36),
                  ],
                ),
                if (lines.isEmpty) empty,
                for (final l in lines) row(l),
              ],
            ),
    );
  }
}

/// The readout a swipe or a wheel shows ("Volume 120 %"), with a thin level bar.
class LevelReadout extends StatelessWidget {
  final String icon;
  final String text;
  final double? level; // 0..1, or null for a plain message ("+10 s")
  const LevelReadout({super.key, required this.icon, required this.text, this.level});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space4, vertical: Tokens.space3),
      decoration: BoxDecoration(
        color: p.bg.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LucideIcon(icon, size: 20, color: p.ink),
              const SizedBox(width: Tokens.space2),
              Text(text, style: Txt.mono(Tokens.textBase, p.ink, weight: FontWeight.w500)),
            ],
          ),
          if (level != null) ...[
            const SizedBox(height: Tokens.space2),
            SizedBox(
              width: 140,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: level!.clamp(0.0, 1.0),
                  backgroundColor: p.ink.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(p.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The readout of a sideways swipe on the picture: where the film will land when the finger
/// lifts, and how far that is from where it was (`+0:42`).
class SeekReadout extends StatelessWidget {
  final String time;
  final String delta;
  const SeekReadout({super.key, required this.time, required this.delta});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space5, vertical: Tokens.space3),
      decoration: BoxDecoration(
        color: p.bg.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(time, style: Txt.mono(Tokens.textXl, p.ink, weight: FontWeight.w500)),
          const SizedBox(height: Tokens.space1),
          Text(delta, style: Txt.mono(Tokens.textSm, p.accent, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// The one thing a locked screen shows, and only for a moment after a tap: the way out.
/// A tap or a hold unlocks.
class UnlockPill extends StatelessWidget {
  final VoidCallback onUnlock;
  const UnlockPill({super.key, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: 'Unlock the screen',
      onTap: onUnlock,
      onLongPress: onUnlock,
      radius: Tokens.radiusFull,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        decoration: BoxDecoration(
          color: Color.alphaBlend(pressWash(p, s), p.bgElevated.withValues(alpha: 0.92)),
          borderRadius: BorderRadius.circular(Tokens.radiusFull),
          border: Border.all(color: s.lit ? p.inkFaint : p.borderStrong),
          boxShadow: Tokens.shadow3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LucideIcon('lock-open', size: 18, color: p.accent),
            const SizedBox(width: Tokens.space2),
            Text('Unlock', style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// "Up next" at the end of a film: counts down, then plays the folder's next file.
class UpNextCard extends StatefulWidget {
  final String name;
  final VoidCallback onPlay;
  final VoidCallback onCancel;
  final Duration countdown;
  const UpNextCard({
    super.key,
    required this.name,
    required this.onPlay,
    required this.onCancel,
    this.countdown = const Duration(seconds: 6),
  });

  @override
  State<UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends State<UpNextCard> {
  late int _left = widget.countdown.inSeconds;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _tick?.cancel();
        widget.onPlay();
        return;
      }
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Container(
      width: 340,
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: p.bgElevated.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: p.borderStrong),
        boxShadow: Tokens.shadow3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UP NEXT · IN $_left S', style: Txt.label(p.accent)),
          const SizedBox(height: Tokens.space2),
          Text(
            widget.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w500),
          ),
          const SizedBox(height: Tokens.space3),
          Row(
            children: [
              TextAction('Play now', primary: true, onTap: widget.onPlay),
              const SizedBox(width: Tokens.space2),
              TextAction('Cancel', onTap: widget.onCancel),
            ],
          ),
        ],
      ),
    );
  }
}
