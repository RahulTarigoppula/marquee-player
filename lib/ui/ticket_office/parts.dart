// What every Settings section is built from: the card, its labels and status lines, and the
// few choice controls the kit does not have (a radio list, single-choice chips, language chips).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../engine/models/models.dart';
import '../../engine/sentences.dart';
import '../../state/notice.dart';
import '../../state/providers.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/primitives.dart';

/// Languages offered for subtitles and audio, most requested first.
const kOfferedLanguages = [
  'en', 'hi', 'ta', 'te', 'ml', 'bn', 'mr', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'ja', 'ko', //
  'zh', 'ar', 'nl', 'sv', 'pl', 'tr',
];

/// A card of related settings: a heading, one line of help, then the controls.
class SettingsGroup extends StatelessWidget {
  final String title;
  final String? helper;
  final List<Widget> children;
  const SettingsGroup({super.key, required this.title, this.helper, required this.children});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    return Container(
      margin: const EdgeInsets.only(top: Tokens.space4),
      padding: const EdgeInsets.fromLTRB(
        Tokens.space5,
        Tokens.space5,
        Tokens.space5,
        Tokens.space4,
      ),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: h.matinee ? 0.75 : 0.6),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w600)),
          ),
          if (helper != null) ...[
            const SizedBox(height: Tokens.space1),
            Text(helper!, style: Txt.body(Tokens.textSm, p.inkMuted)),
          ],
          const SizedBox(height: Tokens.space3),
          ...children,
        ],
      ),
    );
  }
}

/// A labelled control inside a group ("Style", "Jump size"): the label, one optional line of
/// help, then the control. Inset like a [ToggleBulb] row, so a card that mixes the two keeps
/// one left edge.
class ControlBlock extends StatelessWidget {
  final String label;
  final String? help;
  final Widget child;
  const ControlBlock({super.key, required this.label, this.help, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space3, vertical: Tokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w500)),
          if (help != null) Text(help!, style: Txt.body(Tokens.textSm, p.inkMuted)),
          const SizedBox(height: Tokens.space2),
          child,
        ],
      ),
    );
  }
}

/// A one-line status with a tick (saved, signed in) or a warning dot.
class StatusLine extends StatelessWidget {
  final String text;
  final bool ok;
  const StatusLine(this.text, {super.key, this.ok = true});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final c = ok ? p.success : p.warning;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          if (ok) LucideIcon('check', color: c, size: 18) else Bulb(color: c, size: 8),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Text(text, style: Txt.body(Tokens.textSm, c, weight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

void editSettings(WidgetRef ref, Settings Function(Settings) f) =>
    unawaited(ref.read(settingsProvider.notifier).edit(f));

/// Language chips with names and a preference number; up to [Settings.maxLanguages].
class LanguagePicker extends StatelessWidget {
  final List<String> selected;
  final bool allowEmpty;
  final String semanticPrefix;
  final ValueChanged<List<String>> onChanged;
  const LanguagePicker({
    super.key,
    required this.selected,
    required this.allowEmpty,
    required this.semanticPrefix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final full = selected.length >= Settings.maxLanguages;
    return Wrap(
      spacing: Tokens.space2,
      runSpacing: Tokens.space2,
      children: [
        for (final code in kOfferedLanguages)
          _LangChip(
            code: code,
            order: selected.indexOf(code),
            dim: full && !selected.contains(code),
            semanticPrefix: semanticPrefix,
            onTap: () {
              final l = [...selected];
              if (l.contains(code)) {
                if (allowEmpty || l.length > 1) l.remove(code);
              } else if (l.length < Settings.maxLanguages) {
                l.add(code);
              } else {
                return;
              }
              onChanged(l);
            },
          ),
      ],
    );
  }
}

class _LangChip extends StatelessWidget {
  final String code;
  final int order;
  final bool dim;
  final String semanticPrefix;
  final VoidCallback onTap;
  const _LangChip({
    required this.code,
    required this.order,
    required this.dim,
    required this.semanticPrefix,
    required this.onTap,
  });

  static const _ordinals = ['1st', '2nd', '3rd'];

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final on = order >= 0;
    final name = languageName(code);
    return Pressable(
      toggled: on,
      label: '$semanticPrefix $name${on ? ', ${_ordinals[order.clamp(0, 2)]} choice' : ''}',
      onTap: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        height: 40,
        padding: EdgeInsets.only(left: on ? 6 : Tokens.space3, right: Tokens.space3),
        decoration: BoxDecoration(
          color: on
              ? p.accent.withValues(alpha: s.hovered ? 0.2 : 0.14)
              : (s.lit ? p.ink.withValues(alpha: 0.08) : p.ink.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          border: Border.all(color: on ? p.accent.withValues(alpha: 0.7) : p.border),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
                  child: Center(
                    child: Text(
                      '${order + 1}',
                      style: Txt.mono(Tokens.textXs, p.accentInk, weight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.space2),
              ],
              Text(
                name,
                style: Txt.body(
                  Tokens.textSm,
                  on ? p.ink : (dim ? p.inkFaint : p.inkMuted),
                  weight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option of a [ChoiceList] or [OptionChips].
class Choice<T> {
  final T value;
  final String label;

  /// One plain sentence under the label ([ChoiceList] only).
  final String? hint;
  const Choice(this.value, this.label, {this.hint});
}

/// One answer out of a few, each a full row with its own line of help: a radio list. For
/// options too long for a [SegmentedChoice], which must fit a 360 px phone.
class ChoiceList<T> extends StatelessWidget {
  /// Spoken before each option: "When a video ends: Stop".
  final String groupLabel;
  final List<Choice<T>> choices;
  final T value;
  final ValueChanged<T> onChanged;
  const ChoiceList({
    super.key,
    required this.groupLabel,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in choices)
          Pressable(
            selected: c.value == value,
            inMutuallyExclusiveGroup: true,
            label: '$groupLabel: ${c.label}',
            hint: c.hint,
            onTap: () {
              if (c.value == value) return;
              HapticFeedback.selectionClick();
              onChanged(c.value);
            },
            builder: (context, s) {
              final on = c.value == value;
              return AnimatedContainer(
                duration: Tokens.durFast,
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.space3,
                  vertical: Tokens.space2,
                ),
                decoration: BoxDecoration(
                  color: pressWash(p, s),
                  borderRadius: BorderRadius.circular(Tokens.radiusMd),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      // The radio: an empty socket, or a lit bulb in it.
                      AnimatedContainer(
                        duration: h.reducedMotion ? Duration.zero : Tokens.durFast,
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? p.accent.withValues(alpha: 0.22) : p.surface2,
                          border: Border.all(
                            color: on
                                ? p.accent.withValues(alpha: 0.7)
                                : (s.hovered ? p.inkFaint : p.borderStrong),
                          ),
                        ),
                        child: on ? Bulb(size: 10, color: p.accent) : null,
                      ),
                      const SizedBox(width: Tokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.label,
                              style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w500),
                            ),
                            if (c.hint != null)
                              Text(c.hint!, style: Txt.body(Tokens.textSm, p.inkMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// One answer out of a few short ones, as chips that wrap: five sound profiles do not fit a
/// phone in one [SegmentedChoice] row.
class OptionChips<T> extends StatelessWidget {
  final String groupLabel;
  final List<Choice<T>> choices;
  final T value;
  final ValueChanged<T> onChanged;
  const OptionChips({
    super.key,
    required this.groupLabel,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Wrap(
      spacing: Tokens.space2,
      runSpacing: Tokens.space2,
      children: [
        for (final c in choices)
          Pressable(
            selected: c.value == value,
            inMutuallyExclusiveGroup: true,
            label: '$groupLabel: ${c.label}',
            onTap: () {
              if (c.value == value) return;
              HapticFeedback.selectionClick();
              onChanged(c.value);
            },
            builder: (context, s) {
              final on = c.value == value;
              return AnimatedContainer(
                duration: Tokens.durFast,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
                decoration: BoxDecoration(
                  color: on
                      ? p.accent.withValues(alpha: s.hovered ? 0.2 : 0.14)
                      : p.ink.withValues(alpha: s.lit ? 0.08 : 0.03),
                  borderRadius: BorderRadius.circular(Tokens.radiusMd),
                  border: Border.all(color: on ? p.accent.withValues(alpha: 0.7) : p.border),
                ),
                child: ExcludeSemantics(
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      c.label,
                      style: Txt.body(
                        Tokens.textSm,
                        on ? p.ink : p.inkMuted,
                        weight: on ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// A mouse and a keyboard: Windows, and the desktops a developer runs it on.
bool get onDesktop => switch (defaultTargetPlatform) {
  TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
  _ => false,
};

bool get onAndroid => defaultTargetPlatform == TargetPlatform.android;

/// Opens [url] in the user's own browser: the only way Settings leaves the app, and only on a
/// tap. With no browser to open, the notice spells the address out instead.
Future<void> openInBrowser(WidgetRef ref, String url) async {
  final notice = ref.read(noticeProvider.notifier); // the row may be gone when this returns
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } on Object {
    // No handler for web links, or the plugin is missing: said below.
  }
  if (!opened) {
    notice.show(
      "Couldn't open your browser. The address is ${url.replaceFirst('https://', '')}",
      duration: const Duration(seconds: 8),
    );
  }
}
