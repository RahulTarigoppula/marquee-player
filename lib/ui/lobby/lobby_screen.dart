// The Lobby: the room you come home to. Two ways in — drop a film on the doors, or Open.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/media.dart';
import '../../engine/models/settings.dart';
import '../../engine/sync_rule.dart';
import '../../engine/timecode.dart';
import '../../platform/files.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/marquee_sign.dart';
import '../components/primitives.dart';
import '../components/room.dart';

class LobbyScreen extends ConsumerWidget {
  final bool dragOver;
  const LobbyScreen({super.key, this.dragOver = false});

  Future<void> _open(WidgetRef ref) async {
    final f = await pickVideo();
    if (f != null) await ref.read(sessionProvider.notifier).open(f);
  }

  Future<void> _openCard(WidgetRef ref, LobbyCard c) async {
    final f = await fileFromPath(c.locator);
    if (f != null) await ref.read(sessionProvider.notifier).open(f);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = House.paletteOf(context);
    final library = ref.watch(libraryProvider);
    final cards = library.value ?? const <LobbyCard>[];
    final now = clock.now();
    final phase = skyPhaseAt(now);
    final latest = cards.isEmpty ? null : cards.first;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final settings = ref.watch(settingsValueProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        const SkyBand(),
        Beam(width: dragOver ? 0.4 : 0.16),
        const Grain(),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? Tokens.space8 : Tokens.marginPhone),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Tokens.space5),
                Center(
                  child: MarqueeSign(
                    title:
                        latest?.title ?? (latest == null ? 'Marquee' : _clean(latest.displayName)),
                    meta: latest == null
                        ? null
                        : [if (latest.year != null) '${latest.year}', 'NOW SHOWING'].join(' · '),
                    identified: latest == null || latest.title != null,
                    night: phase == SkyPhase.night || phase == SkyPhase.dusk,
                    fontSize: wide ? Tokens.text4Xl : Tokens.text3Xl,
                  ),
                ),
                const SizedBox(height: Tokens.space3),
                Text(
                  '${phase.name.toUpperCase()} · ${fmtTimecode(now.hour * 3600 + now.minute * 60).substring(0, 5)} · THE HOUSE IS OPEN'
                  '${cards.isEmpty ? '' : ' · ${cards.length} PRINTS'}',
                  textAlign: TextAlign.center,
                  style: Txt.label(p.inkFaint),
                ),
                const SizedBox(height: Tokens.space7),
                if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Tokens.space6),
                    child: Text(
                      'The house is empty. Drop a film on the doors, or press Open.',
                      textAlign: TextAlign.center,
                      style: Txt.body(Tokens.textBase, p.inkMuted),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Text('NOW SHOWING & RECENT', style: Txt.label(p.inkFaint)),
                      const Spacer(),
                      Text('TAP TO PROJECT', style: Txt.mono(Tokens.textXs, p.inkFaint)),
                    ],
                  ),
                  const SizedBox(height: Tokens.space3),
                  SizedBox(
                    height: wide ? 250 : 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: cards.length,
                      separatorBuilder: (_, _) => const SizedBox(width: Tokens.space4),
                      itemBuilder: (context, i) => _NowShowingCard(
                        card: cards[i],
                        onTap: () => unawaited(_openCard(ref, cards[i])),
                        onRemove: () =>
                            unawaited(ref.read(libraryActionsProvider).remove(cards[i].id)),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _Doors(lit: dragOver, onOpen: () => unawaited(_open(ref))),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Subtitles by OpenSubtitles.com · libmpv/FFmpeg/libass (LGPL) · fonts OFL · Marquee is MIT',
                        style: Txt.body(Tokens.textXs, p.inkFaint),
                      ),
                    ),
                    IconMark(
                      icon: 'settings-2',
                      label: 'Ticket office',
                      onTap: () => ref.read(roomProvider.notifier).go(Room.ticketOffice),
                    ),
                    Mark(
                      label: 'Lobby light: ${settings.lobbyTheme.name}',
                      onTap: () => unawaited(
                        ref
                            .read(settingsProvider.notifier)
                            .edit(
                              (s) => s.copyWith(
                                lobbyTheme: LobbyTheme
                                    .values[(s.lobbyTheme.index + 1) % LobbyTheme.values.length],
                              ),
                            ),
                      ),
                      child: Text(switch (settings.lobbyTheme) {
                        LobbyTheme.auditorium => 'NIGHT',
                        LobbyTheme.matinee => 'DAY',
                        LobbyTheme.auto => 'AUTO',
                      }, style: Txt.mono(Tokens.textXs, p.inkMuted)),
                    ),
                    const SizedBox(width: Tokens.space3),
                    OpenDisc(onTap: () => unawaited(_open(ref))),
                  ],
                ),
                const SizedBox(height: Tokens.space4),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _clean(String name) {
    final dot = name.lastIndexOf('.');
    return (dot > 0 ? name.substring(0, dot) : name).replaceAll(RegExp(r'[._]'), ' ');
  }
}

class _Doors extends StatelessWidget {
  final bool lit;
  final VoidCallback onOpen;
  const _Doors({required this.lit, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Center(
      child: FocusRing(
        child: Semantics(
          button: true,
          label: 'Drop a film here, or open one',
          child: InkWell(
            onTap: onOpen,
            child: CustomPaint(
              painter: _DashedFrame(color: lit ? p.accent : p.borderStrong),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.space8,
                  vertical: Tokens.space6,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'drop a print here  ·  or  ',
                        style: Txt.body(Tokens.textBase, p.inkMuted),
                      ),
                      TextSpan(
                        text: 'Open',
                        style: Txt.body(Tokens.textBase, p.accent, weight: FontWeight.w600),
                      ),
                    ],
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

class _DashedFrame extends CustomPainter {
  final Color color;
  _DashedFrame({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    void dash(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 10) {
        canvas.drawLine(a + dir * d, a + dir * (d + 5).clamp(0, len), paint);
      }
    }

    dash(Offset.zero, Offset(size.width, 0));
    dash(Offset(size.width, 0), Offset(size.width, size.height));
    dash(Offset(size.width, size.height), Offset(0, size.height));
    dash(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(_DashedFrame o) => o.color != color;
}

class _NowShowingCard extends StatelessWidget {
  final LobbyCard card;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _NowShowingCard({required this.card, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final title = card.title ?? LobbyScreen._clean(card.displayName);
    final meta = [
      if (card.year != null) '${card.year}',
      if (card.durationMs != null) _runtime(card.durationMs!),
      if (card.container != null) card.container!.split(',').first.toUpperCase(),
    ].join(' · ');
    return FocusRing(
      radius: Tokens.radiusMd,
      child: Semantics(
        button: true,
        label:
            '$title${card.resumeFraction > 0 ? ', ${(card.resumeFraction * 100).round()} percent watched' : ''}',
        child: InkWell(
          onTap: onTap,
          onLongPress: onRemove,
          child: SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(Tokens.radiusLg),
                      border: Border.all(color: p.border),
                      boxShadow: Tokens.shadow1,
                    ),
                    padding: const EdgeInsets.all(Tokens.space3),
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.display(Tokens.textXl, p.ink, weight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: Tokens.space2),
                _Sprocket(fraction: card.finished ? 1 : card.resumeFraction),
                const SizedBox(height: Tokens.space2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.mono(Tokens.textXs, p.inkMuted),
                ),
                const SizedBox(height: Tokens.space1),
                Wrap(
                  spacing: Tokens.space2,
                  children: [
                    if (card.subtitleLanguage != null)
                      _Chip('${card.subtitleLanguage!.toUpperCase()} ✓', color: p.success),
                    if (card.delayMs != null && card.delayMs != 0)
                      _Chip('±${formatDelay(card.delayMs!.abs()).substring(1)}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _runtime(int ms) {
    final m = ms ~/ 60000;
    return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color? color;
  const _Chip(this.text, {this.color});
  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Text(text, style: Txt.mono(Tokens.textXs, color ?? p.inkMuted));
  }
}

/// The resume sprocket track: a thin strip of film filling with tungsten.
class _Sprocket extends StatelessWidget {
  final double fraction;
  const _Sprocket({required this.fraction});
  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return ExcludeSemantics(
      child: Container(
        height: 6,
        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(1)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          child: Container(color: p.accent.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}
