// Small shared primitives: Lucide icons, bulbs, the focus ring, toggle bulbs, labels.
import 'package:flutter/material.dart';
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

/// Every interactive element gets a 2 px --focus ring at 2 px offset.
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

/// A glyph-plus-halo mark (never a button with a background), ≥ 44 × 44.
class Mark extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool active;
  const Mark({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => FocusRing(
    child: Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        containedInkWell: false,
        child: SizedBox(
          width: Tokens.targetMin,
          height: Tokens.targetMin,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

class IconMark extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  const IconMark({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Mark(
      label: label,
      onTap: onTap,
      active: active,
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
      child: Text(text, style: Txt.mono(Tokens.textSm, p.ink)),
    );
  }
}

/// Lit = on. role=switch semantics.
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
    return FocusRing(
      child: Semantics(
        toggled: value,
        label: label,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Tokens.targetMin),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: Txt.body(Tokens.textBase, p.ink)),
                        if (hint != null) Text(hint!, style: Txt.body(Tokens.textSm, p.inkMuted)),
                      ],
                    ),
                  ),
                  Text(
                    value ? 'ON' : 'OFF',
                    style: Txt.mono(Tokens.textXs, value ? p.accent : p.inkMuted),
                  ),
                  const SizedBox(width: Tokens.space2),
                  Bulb(lit: value, size: 9),
                ],
              ),
            ),
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
    child: Text(text.toUpperCase(), style: Txt.label(House.paletteOf(context).inkFaint)),
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

/// A plain text action: underline on focus/hover, tungsten when primary.
class TextAction extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool primary;
  const TextAction(this.text, {super.key, this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return FocusRing(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Tokens.targetMin),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  text,
                  style: Txt.body(
                    Tokens.textBase,
                    primary ? p.accent : p.ink,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The filled tungsten disc — one of only two filled controls in the app.
class OpenDisc extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const OpenDisc({super.key, required this.onTap, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return FocusRing(
      radius: size,
      child: Semantics(
        button: true,
        label: 'Open a film',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.accent,
              boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.35), blurRadius: 18)],
            ),
            child: Center(
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
