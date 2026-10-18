// The Subtitle Booth: everything about subtitles (and the audio delay), never above 70 %.
// The film keeps playing behind the glass. Style choices are Settings — they persist and
// apply to every film.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/models.dart';
import '../../platform/files.dart';
import '../../player/engine.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/primitives.dart';
import '../components/sync_rule.dart';
import '../components/ticket_strip.dart';

const double kBoothMaxFraction = 0.7;

/// S / M / L / XL → mpv `sub-scale`.
const Map<String, double> kSubtitleSizes = {'S': 0.8, 'M': 1.0, 'L': 1.3, 'XL': 1.6};

class BoothSheet extends ConsumerStatefulWidget {
  const BoothSheet({super.key});

  @override
  ConsumerState<BoothSheet> createState() => _BoothSheetState();
}

class _BoothSheetState extends ConsumerState<BoothSheet> {
  final _search = TextEditingController();
  double _drag = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _close() => ref.read(boothOpenProvider.notifier).set(false);

  void _edit(Settings Function(Settings) f) =>
      unawaited(ref.read(settingsProvider.notifier).edit(f));

  Future<void> _loadFile() async {
    final path = await pickSubtitleFile();
    if (path != null) await ref.read(sessionProvider.notifier).loadSubtitleFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox.shrink();
    final p = House.paletteOf(context);
    final settings = ref.watch(settingsValueProvider);
    final pb = ref.watch(playbackProvider).value ?? s.engine.snapshot;
    final attached = s.threading.attached;
    final engine = s.engine;
    final attachedId = attached is ExternalSubtitle ? engine.externalIdFor(attached.path) : null;
    final h = MediaQuery.sizeOf(context).height;
    // The on-screen keyboard (Android) must never cover the search field.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final size = kSubtitleSizes.entries
        .reduce(
          (a, b) =>
              (a.value - settings.subtitleScale).abs() <= (b.value - settings.subtitleScale).abs()
              ? a
              : b,
        )
        .key;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _close,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, t, child) =>
                  FractionalTranslation(translation: Offset(0, t), child: child),
              child: Transform.translate(
                offset: Offset(0, _drag.clamp(0, h)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (h - keyboard) * kBoothMaxFraction,
                    maxWidth: 560,
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(Tokens.radiusLg),
                    ),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.bgElevated.withValues(alpha: 0.86),
                          border: Border(top: BorderSide(color: p.border)),
                          boxShadow: Tokens.shadow3,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Handle(
                              onDrag: (dy) => setState(() => _drag = (_drag + dy).clamp(0, h)),
                              onRelease: (v) {
                                if (v > 300 || _drag > 120) {
                                  _close();
                                } else {
                                  setState(() => _drag = 0);
                                }
                              },
                              onClose: _close,
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  Tokens.space5,
                                  0,
                                  Tokens.space5,
                                  Tokens.space5,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SectionLabel('Tracks'),
                                    _TrackRow(
                                      title: 'Off',
                                      selected: !pb.hasSubtitle,
                                      onTap: () => unawaited(engine.subtitlesOff()),
                                    ),
                                    if (attached is ExternalSubtitle)
                                      _TrackRow(
                                        title: '${attached.language.toUpperCase()}  Marquee',
                                        chip: attached.syncedByHash
                                            ? 'SYNCED'
                                            : attached.provider == SubtitleProvider.sidecar
                                            ? 'SIDECAR'
                                            : 'BY NAME · CHECK SYNC',
                                        chipIcon: attached.syncedByHash ? 'check' : null,
                                        chipColor: attached.syncedByHash ? p.success : p.warning,
                                        detail: attached.besideFile
                                            ? 'saved beside the file'
                                            : 'saved in app storage',
                                        selected: attachedId != null && pb.subtitleId == attachedId,
                                        onTap: () => unawaited(
                                          engine.attachSubtitle(
                                            attached.path,
                                            language: attached.language,
                                          ),
                                        ),
                                      ),
                                    for (final t in pb.subtitleTracks.where(
                                      (t) => t.id != attachedId,
                                    ))
                                      _TrackRow(
                                        title:
                                            '${(t.language ?? '—').toUpperCase()}  ${t.title ?? (engine.isExternal(t.id) ? 'file' : 'embedded')}',
                                        chip: isBitmapSubtitle(t) ? 'IMAGE' : null,
                                        selected: pb.subtitleId == t.id,
                                        onTap: () => unawaited(engine.selectSubtitle(t.id)),
                                      ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextAction(
                                        'Load subtitle file…',
                                        onTap: () => unawaited(_loadFile()),
                                      ),
                                    ),
                                    const SectionLabel('Size'),
                                    Wrap(
                                      spacing: Tokens.space2,
                                      children: [
                                        for (final MapEntry(key: z, value: scale)
                                            in kSubtitleSizes.entries)
                                          _Choice(
                                            label: z,
                                            on: size == z,
                                            onTap: () =>
                                                _edit((x) => x.copyWith(subtitleScale: scale)),
                                          ),
                                      ],
                                    ),
                                    const SectionLabel('Look'),
                                    Wrap(
                                      spacing: Tokens.space2,
                                      children: [
                                        for (final (look, label) in [
                                          (SubtitleLook.outline, 'outline'),
                                          (SubtitleLook.box, 'dark box'),
                                        ])
                                          _Choice(
                                            label: label,
                                            on: settings.subtitleLook == look,
                                            onTap: () =>
                                                _edit((x) => x.copyWith(subtitleLook: look)),
                                          ),
                                      ],
                                    ),
                                    const SectionLabel('Position'),
                                    Wrap(
                                      spacing: Tokens.space2,
                                      children: [
                                        for (final (at, label) in [
                                          (SubtitlePlacement.bottom, 'bottom'),
                                          (SubtitlePlacement.lowerThird, 'lower third'),
                                          (SubtitlePlacement.top, 'top'),
                                        ])
                                          _Choice(
                                            label: label,
                                            on: settings.subtitlePlacement == at,
                                            onTap: () =>
                                                _edit((x) => x.copyWith(subtitlePlacement: at)),
                                          ),
                                      ],
                                    ),
                                    const SectionLabel('Subtitle sync'),
                                    SyncRule(
                                      delayMs: s.delayMs,
                                      onChanged: (v) =>
                                          unawaited(ref.read(sessionProvider.notifier).setDelay(v)),
                                    ),
                                    const SectionLabel('Audio delay'),
                                    _AudioDelay(
                                      ms: s.audioDelayMs,
                                      onChanged: (v) => unawaited(
                                        ref.read(sessionProvider.notifier).setAudioDelay(v),
                                      ),
                                    ),
                                    const SectionLabel('Find another print'),
                                    TextField(
                                      controller: _search,
                                      style: Txt.body(Tokens.textBase, p.ink),
                                      scrollPadding: const EdgeInsets.only(bottom: 120),
                                      decoration: InputDecoration(
                                        hintText: 'Title (leave empty to search by file name)',
                                        hintStyle: Txt.body(Tokens.textBase, p.inkFaint),
                                        enabledBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: p.borderStrong),
                                        ),
                                        focusedBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: p.accent),
                                        ),
                                      ),
                                      onSubmitted: (q) => unawaited(
                                        ref.read(sessionProvider.notifier).findAnother(q),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        TextAction(
                                          'Search',
                                          primary: true,
                                          onTap: () => unawaited(
                                            ref
                                                .read(sessionProvider.notifier)
                                                .findAnother(_search.text),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.space3),
                                        Flexible(
                                          child: TicketStripView(
                                            strip: ref.watch(ticketStripProvider),
                                            count: ref.watch(quotaProvider).remaining,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Handle extends StatelessWidget {
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onRelease;
  final VoidCallback onClose;
  const _Handle({required this.onDrag, required this.onRelease, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return GestureDetector(
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      onVerticalDragEnd: (d) => onRelease(d.primaryVelocity ?? 0),
      child: Semantics(
        label: 'Close the subtitle booth',
        button: true,
        onTap: onClose,
        child: SizedBox(
          height: 28,
          width: double.infinity,
          child: Center(child: Container(width: 40, height: 3, color: p.borderStrong)),
        ),
      ),
    );
  }
}

/// Audio earlier / later in 50 ms steps (a film whose sound is out of step with the picture).
class _AudioDelay extends StatelessWidget {
  final int ms;
  final ValueChanged<int> onChanged;
  const _AudioDelay({required this.ms, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final sign = ms > 0 ? '+' : (ms < 0 ? '-' : '');
    return Row(
      children: [
        IconMark(icon: 'minus', label: 'Audio 50 ms earlier', onTap: () => onChanged(ms - 50)),
        SizedBox(
          width: 96,
          child: Text(
            '$sign${(ms.abs() / 1000).toStringAsFixed(2)} s',
            textAlign: TextAlign.center,
            style: Txt.mono(Tokens.textBase, ms == 0 ? p.inkMuted : p.accent),
          ),
        ),
        IconMark(icon: 'plus', label: 'Audio 50 ms later', onTap: () => onChanged(ms + 50)),
        const SizedBox(width: Tokens.space2),
        if (ms != 0) TextAction('Reset', onTap: () => onChanged(0)),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  final String title;
  final String? chip;
  final String? chipIcon;
  final Color? chipColor;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;
  const _TrackRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.chip,
    this.chipIcon,
    this.chipColor,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: title,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      radius: Tokens.radiusSm,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
        color: pressWash(p, s),
        child: Row(
          children: [
            Bulb(lit: selected, size: 7),
            const SizedBox(width: Tokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Txt.body(Tokens.textBase, selected ? p.accent : p.ink)),
                  if (detail != null) Text(detail!, style: Txt.body(Tokens.textSm, p.inkMuted)),
                ],
              ),
            ),
            if (chipIcon != null) ...[
              LucideIcon(chipIcon!, size: 14, color: chipColor ?? p.inkMuted),
              const SizedBox(width: Tokens.space1),
            ],
            if (chip != null) Text(chip!, style: Txt.mono(Tokens.textXs, chipColor ?? p.inkMuted)),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Choice({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: label,
      toggled: on,
      onTap: onTap,
      radius: Tokens.radiusSm,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: Tokens.targetMin, minWidth: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressWash(p, s, active: on),
          border: Border(bottom: BorderSide(color: on ? p.accent : p.border)),
        ),
        child: Text(label, style: Txt.mono(Tokens.textSm, on ? p.accent : p.inkMuted)),
      ),
    );
  }
}
