// The Subtitle Booth: everything about subtitles, over a paused frame, never above 70 %.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack;

import '../../engine/models/models.dart';
import '../../player/engine.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/primitives.dart';
import '../components/sync_rule.dart';
import '../components/ticket_strip.dart';

const double kBoothMaxFraction = 0.7;

class BoothSheet extends ConsumerStatefulWidget {
  const BoothSheet({super.key});

  @override
  ConsumerState<BoothSheet> createState() => _BoothSheetState();
}

class _BoothSheetState extends ConsumerState<BoothSheet> {
  final _search = TextEditingController();
  double _drag = 0;
  bool _wasPlaying = false;
  PlayerEngine? _engine; // captured: `ref` is unusable in dispose() (Riverpod 3)
  String _size = 'M';
  bool _outline = true;
  String _position = 'bottom';

  @override
  void initState() {
    super.initState();
    _engine = ref.read(sessionProvider)?.engine;
    final player = _engine?.player;
    _wasPlaying = player?.state.playing ?? false;
    if (_wasPlaying) unawaited(player?.pause()); // booth glass only ever sits over a paused frame
  }

  @override
  void dispose() {
    final e = _engine;
    if (_wasPlaying && e != null && !e.isDisposed) unawaited(e.player.play());
    _search.dispose();
    super.dispose();
  }

  void _close() => ref.read(boothOpenProvider.notifier).set(false);

  Future<void> _style() async {
    final e = ref.read(sessionProvider)?.engine;
    await e?.setSubStyle(
      scale: switch (_size) {
        'S' => 0.8,
        'L' => 1.3,
        _ => 1.0,
      },
      outline: _outline,
      position: _position,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox.shrink();
    final p = House.paletteOf(context);
    final pb = ref.watch(playbackProvider).value ?? s.engine.snapshot;
    final attached = s.threading.attached;
    final h = MediaQuery.sizeOf(context).height;
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
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            builder: (context, t, child) =>
                FractionalTranslation(translation: Offset(0, t), child: child),
            child: Transform.translate(
              offset: Offset(0, _drag.clamp(0, h)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: h * kBoothMaxFraction, maxWidth: 560),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(Tokens.radiusLg)),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.bgElevated.withValues(alpha: 0.78),
                        border: Border(top: BorderSide(color: p.border)),
                        boxShadow: Tokens.shadow3,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onVerticalDragUpdate: (d) =>
                                setState(() => _drag = (_drag + d.delta.dy).clamp(0, h)),
                            onVerticalDragEnd: (d) {
                              if ((d.primaryVelocity ?? 0) > 300 || _drag > 120) {
                                _close();
                              } else {
                                setState(() => _drag = 0);
                              }
                            },
                            child: Semantics(
                              label: 'Close the subtitle booth',
                              button: true,
                              onTap: _close,
                              child: SizedBox(
                                height: 28,
                                width: double.infinity,
                                child: Center(
                                  child: Container(width: 40, height: 3, color: p.borderStrong),
                                ),
                              ),
                            ),
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
                                  if (attached is ExternalSubtitle)
                                    _TrackRow(
                                      title: '${attached.language.toUpperCase()}  Marquee',
                                      chip: attached.syncedByHash
                                          ? 'synced ✓'
                                          : attached.provider == SubtitleProvider.sidecar
                                          ? 'sidecar'
                                          : 'BY NAME · CHECK SYNC',
                                      chipColor: attached.syncedByHash ? p.success : p.warning,
                                      detail: attached.besideFile
                                          ? 'saved beside file'
                                          : 'saved in app storage',
                                      selected: true,
                                      onTap: () => unawaited(
                                        s.engine.attachSubtitle(
                                          attached.path,
                                          language: attached.language,
                                        ),
                                      ),
                                    ),
                                  for (final t in pb.subtitleTracks.where((t) => t.id != 'no'))
                                    _TrackRow(
                                      title:
                                          '${(t.language ?? '—').toUpperCase()}  ${t.title ?? 'embedded'}',
                                      chip: (t.codec ?? '').contains('pgs') ? 'BITMAP' : null,
                                      selected: pb.subtitle?.id == t.id,
                                      onTap: () => unawaited(s.engine.player.setSubtitleTrack(t)),
                                    ),
                                  _TrackRow(
                                    title: 'Off',
                                    selected: !pb.hasSubtitle,
                                    onTap: () => unawaited(
                                      s.engine.player.setSubtitleTrack(SubtitleTrack.no()),
                                    ),
                                  ),
                                  const SectionLabel('Style'),
                                  Wrap(
                                    spacing: Tokens.space2,
                                    children: [
                                      for (final z in ['S', 'M', 'L'])
                                        _Choice(
                                          label: z,
                                          on: _size == z,
                                          onTap: () {
                                            setState(() => _size = z);
                                            unawaited(_style());
                                          },
                                        ),
                                      _Choice(
                                        label: 'outline',
                                        on: _outline,
                                        onTap: () {
                                          setState(() => _outline = !_outline);
                                          unawaited(_style());
                                        },
                                      ),
                                    ],
                                  ),
                                  const SectionLabel('Position'),
                                  Wrap(
                                    spacing: Tokens.space2,
                                    children: [
                                      for (final (k, l) in [
                                        ('bottom', 'bottom'),
                                        ('lower-third', 'lower third'),
                                        ('top', 'top'),
                                      ])
                                        _Choice(
                                          label: l,
                                          on: _position == k,
                                          onTap: () {
                                            setState(() => _position = k);
                                            unawaited(_style());
                                          },
                                        ),
                                    ],
                                  ),
                                  const SectionLabel('Sync'),
                                  SyncRule(
                                    delayMs: s.delayMs,
                                    onChanged: (v) =>
                                        unawaited(ref.read(sessionProvider.notifier).setDelay(v)),
                                  ),
                                  const SectionLabel('Find another print'),
                                  TextField(
                                    controller: _search,
                                    style: Txt.body(Tokens.textBase, p.ink),
                                    decoration: InputDecoration(
                                      hintText: 'Title (empty = search by filename)',
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
                                        'Find another print',
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
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  final String title;
  final String? chip;
  final Color? chipColor;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;
  const _TrackRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.chip,
    this.chipColor,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return FocusRing(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        label: title,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Tokens.targetMin),
            child: Row(
              children: [
                Bulb(lit: selected, size: 7),
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: Txt.body(Tokens.textBase, p.ink)),
                      if (detail != null) Text(detail!, style: Txt.body(Tokens.textSm, p.inkMuted)),
                    ],
                  ),
                ),
                if (chip != null)
                  Text(chip!, style: Txt.mono(Tokens.textXs, chipColor ?? p.inkMuted)),
              ],
            ),
          ),
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
    return FocusRing(
      child: Semantics(
        toggled: on,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: Tokens.targetMin,
              minWidth: Tokens.targetMin,
            ),
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: on ? p.accent : p.border)),
            ),
            child: Text(label, style: Txt.mono(Tokens.textSm, on ? p.accent : p.inkMuted)),
          ),
        ),
      ),
    );
  }
}
