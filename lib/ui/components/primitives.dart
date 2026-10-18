// Small shared primitives: Lucide icons, bulbs, the focus ring, the one pressable surface every
// control is built on, marks, toggle bulbs, labels.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/house.dart';
import '../../theme/tokens.dart';

class LucideIcon extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const LucideIcon(this.name, {super.key, required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}

/// A 5 px bulb. Lit = tungsten with the only glow allowed (the bulb halo).
class Bulb extends StatelessWidget {
  final bool lit;
  final double intensity; // multiplied by the house value by callers
  final Color? color;
  final double size;
  const Bulb({super.key, this.lit = true, this.intensity = 1, this.color, this.size = 5});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final matinee = House.of(context).matinee;
    final c = color ?? p.accent;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: lit ? c.withValues(alpha: intensity.clamp(0.0, 1.0)) : p.surface2,
          border: lit ? null : Border.all(color: p.borderStrong),
          boxShadow: lit && !matinee
              ? [
                  BoxShadow(
                    color: c.withValues(alpha: 0.55 * intensity.clamp(0.0, 1.0)),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// Every interactive element gets a 2 px --focus ring at 2 px offset. For widgets that bring
/// their own InkWell; [Pressable] draws its own ring.
class FocusRing extends StatefulWidget {
  final Widget child;
  final double radius;
  const FocusRing({super.key, required this.child, this.radius = Tokens.radiusSm});

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius + 2),
          border: _focused ? Border.all(color: p.focus, width: 2) : null,
        ),
        child: Padding(padding: const EdgeInsets.all(2), child: widget.child),
      ),
    );
  }
}

/// What a [Pressable] is doing right now, for its builder.
@immutable
class PressState {
  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool enabled;
  const PressState({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.enabled = true,
  });

  /// Hovered, pressed or keyboard-focused: the moment to lift the surface.
  bool get lit => enabled && (hovered || pressed || focused);
}

/// The one interactive surface: focusable and reachable by keyboard (Enter / Space activate),
/// a pointer cursor, hover/pressed state for the builder, a 2 px --focus ring at 2 px offset
/// that never shifts layout, long-press and right-click hooks, and button semantics.
class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Right click (desktop): receives the pointer's global position.
  final ValueChanged<Offset>? onContextMenu;
  final String? label;
  final String? hint;
  final String? tooltip;
  final bool? toggled;
  final bool? selected;
  final bool button;
  final bool inMutuallyExclusiveGroup;
  final double radius;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget Function(BuildContext context, PressState state) builder;

  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.onLongPress,
    this.onContextMenu,
    this.label,
    this.hint,
    this.tooltip,
    this.toggled,
    this.selected,
    this.button = true,
    this.inMutuallyExclusiveGroup = false,
    this.radius = Tokens.radiusMd,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _set({bool? hovered, bool? pressed, bool? focused}) {
    if (!mounted) return;
    setState(() {
      _hovered = hovered ?? _hovered;
      _pressed = pressed ?? _pressed;
      _focused = focused ?? _focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final enabled = widget.onTap != null;
    final interactive = enabled || widget.onLongPress != null || widget.onContextMenu != null;
    final state = PressState(
      hovered: _hovered,
      pressed: _pressed,
      focused: _focused,
      enabled: enabled,
    );
    Widget child = Stack(
      clipBehavior: Clip.none,
      children: [
        widget.builder(context, state),
        if (_focused)
          Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius + 4),
                  border: Border.all(color: p.focus, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
    child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: widget.onTap,
      onTapDown: enabled ? (_) => _set(pressed: true) : null,
      onTapUp: enabled ? (_) => _set(pressed: false) : null,
      onTapCancel: enabled ? () => _set(pressed: false) : null,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(pressed: false);
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      onSecondaryTapUp: widget.onContextMenu == null
          ? null
          : (d) => widget.onContextMenu!(d.globalPosition),
      child: child,
    );
    child = FocusableActionDetector(
      enabled: interactive,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (v) => _set(hovered: v),
      onShowFocusHighlight: (v) => _set(focused: v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: child,
    );
    child = Semantics(
      container: true,
      button: widget.button && widget.toggled == null,
      enabled: enabled,
      label: widget.label,
      hint: widget.hint,
      toggled: widget.toggled,
      selected: widget.selected,
      inMutuallyExclusiveGroup: widget.inMutuallyExclusiveGroup ? true : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: child,
    );
    final tip = widget.tooltip;
    if (tip != null) {
      child = Tooltip(message: tip, excludeFromSemantics: true, child: child);
    }
    return child;
  }
}

/// The wash behind a lit control: none at rest, a quiet lift on hover, deeper while pressed.
Color pressWash(HousePalette p, PressState s, {bool active = false}) {
  if (s.pressed) return p.ink.withValues(alpha: 0.14);
  if (active) return p.accent.withValues(alpha: s.hovered ? 0.2 : 0.14);
  if (s.hovered || s.focused) return p.ink.withValues(alpha: 0.08);
  return p.ink.withValues(alpha: 0);
}

/// A glyph-plus-halo mark (never a button with a fill at rest). At least 44 × 44, and it grows
/// to fit its content as a pill — `SYNC +0.00` never wraps.
class Mark extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool active;
  final String? tooltip;
  const Mark({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.active = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: label,
      tooltip: tooltip,
      onTap: onTap,
      radius: Tokens.targetMin / 2,
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: Tokens.targetMin, minHeight: Tokens.targetMin),
        child: AnimatedContainer(
          duration: Tokens.durFast,
          curve: Tokens.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
          decoration: BoxDecoration(
            color: pressWash(p, s, active: active),
            borderRadius: BorderRadius.circular(Tokens.radiusFull),
          ),
          child: Center(widthFactor: 1, heightFactor: 1, child: ExcludeSemantics(child: child)),
        ),
      ),
    );
  }
}

class IconMark extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool showTooltip;
  const IconMark({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Mark(
      label: label,
      onTap: onTap,
      active: active,
      tooltip: showTooltip ? label : null,
      child: LucideIcon(icon, color: active ? p.accent : p.inkMuted),
    );
  }
}

class TextMark extends StatelessWidget {
  final String text;
  final String label;
  final VoidCallback? onTap;
  const TextMark({super.key, required this.text, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Mark(
      label: label,
      onTap: onTap,
      child: Text(text, style: Txt.mono(Tokens.textSm, p.ink), softWrap: false),
    );
  }
}

/// The switch drawn as a bulb in a slot: the bulb slides right and lights when on.
class BulbSwitch extends StatelessWidget {
  final bool value;
  final bool hovered;
  const BulbSwitch({super.key, required this.value, this.hovered = false});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final dur = h.reducedMotion ? Duration.zero : Tokens.durFast;
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: dur,
        curve: Tokens.easeOut,
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? p.accent.withValues(alpha: 0.22) : p.surface2,
          borderRadius: BorderRadius.circular(Tokens.radiusFull),
          border: Border.all(
            color: value
                ? p.accent.withValues(alpha: 0.7)
                : (hovered ? p.inkFaint : p.borderStrong),
          ),
        ),
        child: AnimatedAlign(
          duration: dur,
          curve: Tokens.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? p.accent : p.inkFaint,
              boxShadow: value && !h.matinee
                  ? [BoxShadow(color: p.accent.withValues(alpha: 0.5), blurRadius: 8)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row with a label, an optional one-line explanation and a [BulbSwitch]. Lit = on;
/// exposed to assistive tech as a switch.
class ToggleBulb extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;
  const ToggleBulb({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: label,
      hint: hint,
      toggled: value,
      onTap: () => onChanged(!value),
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space3, vertical: Tokens.space2),
        decoration: BoxDecoration(
          color: pressWash(p, s),
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w500)),
                    if (hint != null) Text(hint!, style: Txt.body(Tokens.textSm, p.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.space4),
              BulbSwitch(value: value, hovered: s.hovered),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Tokens.space5, bottom: Tokens.space2),
    child: Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: Txt.label(House.paletteOf(context).inkFaint)),
    ),
  );
}

/// One plain sentence. Never a red fill.
class Sentence extends StatelessWidget {
  final String text;
  final Color? color;
  const Sentence(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Semantics(
      liveRegion: true,
      child: Text(text, style: Txt.body(Tokens.textBase, color ?? p.ink)),
    );
  }
}

/// A plain text action: a quiet wash on hover, underline when lit, tungsten when primary.
class TextAction extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool primary;
  const TextAction(this.text, {super.key, this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final color = onTap == null ? p.inkFaint : (primary ? p.accent : p.ink);
    return Pressable(
      onTap: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
        decoration: BoxDecoration(
          color: pressWash(p, s),
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            text,
            style: Txt.body(Tokens.textBase, color, weight: FontWeight.w500).copyWith(
              decoration: s.lit ? TextDecoration.underline : TextDecoration.none,
              decorationColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// The filled tungsten disc — one of only two filled controls in the app. Focusable, with a
/// warm swell on hover and a press-in.
class OpenDisc extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const OpenDisc({super.key, required this.onTap, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    return Pressable(
      label: 'Open a film',
      onTap: onTap,
      radius: size / 2,
      builder: (context, s) => AnimatedScale(
        duration: h.reducedMotion ? Duration.zero : Tokens.durFast,
        scale: s.pressed ? 0.95 : (s.hovered ? 1.04 : 1),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.accent,
            boxShadow: [
              BoxShadow(
                color: p.accent.withValues(alpha: s.lit ? 0.5 : 0.35),
                blurRadius: s.lit ? 26 : 18,
              ),
            ],
          ),
          child: Center(
            child: ExcludeSemantics(
              child: Text(
                'OPEN',
                style: Txt.display(Tokens.textBase, p.accentInk, weight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
