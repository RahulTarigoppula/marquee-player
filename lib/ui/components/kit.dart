// The control kit: buttons, tags, segmented choices, sliders, fields and progress lines. Every
// one is built on [Pressable] (keyboard, focus ring, hover/pressed) and the House palette, so a
// screen made of these looks like one app. One filled tungsten control per screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/house.dart';
import '../../theme/tokens.dart';
import 'primitives.dart';

/// Lets [child] shrink (and ellipsize) only where the row has a bounded width — a flex child
/// in an unbounded Row (a button in a toolbar) would throw.
Widget _flexIf(bool bounded, Widget child) => bounded ? Flexible(child: child) : child;

enum ButtonKind {
  /// Filled tungsten: the one main action on a screen.
  primary,

  /// A lit outline on velvet: important, but not the main action.
  secondary,

  /// Text only until hovered.
  ghost,

  /// Like ghost, in the danger ink (Remove, Sign out).
  danger,
}

class HouseButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final ButtonKind kind;
  final bool large;

  /// Fill the available width (phone action rows).
  final bool expand;
  final String? semanticLabel;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;

  const HouseButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = ButtonKind.secondary,
    this.large = false,
    this.expand = false,
    this.semanticLabel,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final enabled = onPressed != null;
    return Pressable(
      onTap: onPressed,
      label: semanticLabel,
      tooltip: tooltip,
      focusNode: focusNode,
      autofocus: autofocus,
      radius: Tokens.radiusMd,
      builder: (context, s) {
        final (Color bg, Color fg, Color? edge) = switch (kind) {
          ButtonKind.primary => (
            s.pressed
                ? Color.lerp(p.accent, p.accentInk, 0.12)!
                : s.hovered
                ? Color.lerp(p.accent, h.matinee ? p.accentInk : p.ink, 0.12)!
                : p.accent,
            p.accentInk,
            null,
          ),
          ButtonKind.secondary => (
            s.pressed
                ? p.ink.withValues(alpha: 0.16)
                : s.hovered
                ? p.ink.withValues(alpha: 0.11)
                : p.ink.withValues(alpha: 0.06),
            p.ink,
            s.hovered ? p.inkFaint : p.borderStrong,
          ),
          ButtonKind.ghost => (pressWash(p, s), p.ink, null),
          ButtonKind.danger => (pressWash(p, s), h.matinee ? p.danger : p.accent2Lit, null),
        };
        final content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              LucideIcon(icon!, color: fg, size: large ? 20 : 18),
              const SizedBox(width: Tokens.space2),
            ],
            _flexIf(
              expand,
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Txt.body(
                  large ? Tokens.textLg : Tokens.textBase,
                  fg,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        return AnimatedOpacity(
          duration: Tokens.durFast,
          opacity: enabled ? 1 : 0.45,
          child: AnimatedScale(
            duration: h.reducedMotion ? Duration.zero : Tokens.durFast,
            scale: s.pressed ? 0.97 : 1,
            child: AnimatedContainer(
              duration: Tokens.durFast,
              curve: Tokens.easeOut,
              height: large ? 52 : Tokens.targetMin,
              padding: EdgeInsets.symmetric(horizontal: large ? Tokens.space6 : Tokens.space4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
                border: edge == null ? null : Border.all(color: edge),
                boxShadow: kind == ButtonKind.primary && !h.matinee
                    ? [
                        BoxShadow(
                          color: p.accent.withValues(alpha: s.lit ? 0.38 : 0.22),
                          blurRadius: s.lit ? 22 : 14,
                        ),
                      ]
                    : null,
              ),
              child: semanticLabel == null ? content : ExcludeSemantics(child: content),
            ),
          ),
        );
      },
    );
  }
}

/// A small status tag: `EN ✓` (the tick is a Lucide glyph — the bundled fonts have none),
/// `SYNC +0.15`, `WATCHED`.
class Tag extends StatelessWidget {
  final String text;
  final String? icon;
  final Color? color;
  final String? semanticLabel;
  const Tag(this.text, {super.key, this.icon, this.color, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final c = color ?? p.inkMuted;
    return Semantics(
      container: semanticLabel != null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: Txt.mono(Tokens.textXs, c, weight: FontWeight.w500)),
            if (icon != null) ...[const SizedBox(width: 3), LucideIcon(icon!, color: c, size: 12)],
          ],
        ),
      ),
    );
  }
}

/// One option of a [SegmentedChoice].
class Segment<T> {
  final T value;
  final String label;
  final String? icon;
  const Segment(this.value, this.label, {this.icon});
}

/// A row of mutually exclusive options in one slot (Auto · Night · Day). [compact] shows icons
/// only (the label stays in the tooltip and for screen readers).
class SegmentedChoice<T> extends StatelessWidget {
  final List<Segment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool compact;

  /// Spoken before each option: "Theme: Night".
  final String? groupLabel;
  final bool expand;

  const SegmentedChoice({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.groupLabel,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    Widget option(Segment<T> s) {
      final on = s.value == value;
      final fg = on ? p.ink : p.inkMuted;
      return Pressable(
        selected: on,
        inMutuallyExclusiveGroup: true,
        label: groupLabel == null ? s.label : '$groupLabel: ${s.label}',
        tooltip: compact ? s.label : null,
        radius: Tokens.radiusSm + 2,
        onTap: () {
          if (!on) {
            HapticFeedback.selectionClick();
            onChanged(s.value);
          }
        },
        builder: (context, st) => AnimatedContainer(
          duration: h.reducedMotion ? Duration.zero : Tokens.durFast,
          curve: Tokens.easeOut,
          constraints: BoxConstraints(minWidth: compact ? 40 : 64),
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: compact ? Tokens.space2 : Tokens.space3),
          decoration: BoxDecoration(
            color: on ? p.bgElevated : (st.hovered ? p.ink.withValues(alpha: 0.06) : null),
            borderRadius: BorderRadius.circular(Tokens.radiusSm + 2),
            border: on ? Border.all(color: p.borderStrong) : null,
            boxShadow: on && !h.matinee ? Tokens.shadow1 : null,
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (s.icon != null) LucideIcon(s.icon!, color: on ? p.accent : fg, size: 16),
                if (s.icon != null && !compact) const SizedBox(width: 6),
                if (!compact)
                  _flexIf(
                    expand,
                    Text(
                      s.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.body(
                        Tokens.textSm,
                        fg,
                        weight: on ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [for (final s in segments) expand ? Expanded(child: option(s)) : option(s)],
      ),
    );
  }
}

/// A slider with a label and a live value readout, themed by the House.
class HouseSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String valueText;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  const HouseSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
    this.divisions,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w500),
                ),
              ),
              Text(valueText, style: Txt.mono(Tokens.textSm, p.accent)),
            ],
          ),
        ),
        Semantics(
          label: label,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
            semanticFormatterCallback: (_) => valueText,
          ),
        ),
      ],
    );
  }
}

/// A text field: a label above, a velvet well with an underline that lights when focused, and an
/// optional plain sentence beneath (helper, or [error] in the danger ink).
class HouseField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final String? error;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  const HouseField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.error,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.onSubmitted,
    this.onChanged,
    this.autofillHints,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final bad = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The visible label is the field's name for screen readers too.
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.space1),
                child: Text(
                  label,
                  style: Txt.body(Tokens.textSm, p.inkMuted, weight: FontWeight.w500),
                ),
              ),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: autofocus,
                autocorrect: false,
                enableSuggestions: !obscure,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                autofillHints: autofillHints,
                style: Txt.body(Tokens.textBase, p.ink),
                cursorColor: p.accent,
                onSubmitted: onSubmitted,
                onChanged: onChanged,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: p.surface,
                  hintText: hint,
                  hintStyle: Txt.body(Tokens.textBase, p.inkFaint),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Tokens.space3,
                    vertical: Tokens.space3,
                  ),
                  border: UnderlineInputBorder(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(Tokens.radiusSm),
                    ),
                    borderSide: BorderSide(color: bad ? p.danger : p.borderStrong),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(Tokens.radiusSm),
                    ),
                    borderSide: BorderSide(color: bad ? p.danger : p.borderStrong),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(Tokens.radiusSm),
                    ),
                    borderSide: BorderSide(color: bad ? p.danger : p.accent, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        // An empty [error] marks the field without a sentence (the form says it once, above).
        if ((bad && error!.isNotEmpty) || helper != null)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Semantics(
              liveRegion: bad,
              child: Text(
                bad && error!.isNotEmpty ? error! : helper!,
                style: Txt.body(Tokens.textSm, bad && error!.isNotEmpty ? p.danger : p.inkMuted),
              ),
            ),
          ),
      ],
    );
  }
}

/// A thin rounded progress line (resume position).
class ProgressLine extends StatelessWidget {
  final double fraction;
  final double height;
  final Color? color;
  final Color? track;
  const ProgressLine({super.key, required this.fraction, this.height = 4, this.color, this.track});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: track ?? p.ink.withValues(alpha: 0.16)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: ColoredBox(color: color ?? p.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
