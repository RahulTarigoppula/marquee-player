// A film in the Lobby: a 16:9 frame from the film (or a title card until one is grabbed), the
// title, plain meta, the resume line and two small tags. Hover lifts it; right click, long
// press or the ⋮ button opens its menu.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/media.dart';
import '../../engine/sentences.dart';
import '../../engine/sync_rule.dart';
import '../../state/thumbnails.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import 'lobby_actions.dart';

/// Height of everything under the 16:9 frame (title, meta, tags), so rows and grids can size
/// themselves without measuring.
const double kCardTextHeight = 86;

/// The frame grabbed from the film, or [fallback] while there is none (never played long
/// enough, a stream, the folder still loading, or a decode error).
class FilmFrame extends ConsumerWidget {
  final LobbyCard card;
  final Widget fallback;
  final BoxFit fit;
  const FilmFrame({super.key, required this.card, required this.fallback, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(thumbnailEpochProvider); // a fresh grab replaces the frame
    final dir = ref.watch(thumbnailDirProvider).value;
    final file = thumbnailFor(dir, card.id);
    if (file == null) return fallback;
    return Image(
      image: FileImage(file),
      fit: fit,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, sync) => frame == null && !sync ? fallback : child,
      errorBuilder: (context, error, stack) => fallback,
    );
  }
}

/// The title card shown before a frame exists: a warm velvet ground tinted per film, and the
/// title set like a film's own opening card.
class TitleCard extends StatelessWidget {
  final LobbyCard card;
  final double fontSize;
  const TitleCard({super.key, required this.card, this.fontSize = Tokens.textXl});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final tints = [p.skyDusk, p.skyDawn, p.skyDay, p.accent2];
    final tint = tints[card.id.abs() % tints.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(p.surface, tint, 0.45)!, p.bgElevated],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space4),
        child: Center(
          child: Text(
            cardTitle(card).toUpperCase(),
            maxLines: 3,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Txt.display(fontSize, p.ink.withValues(alpha: 0.82), weight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// `1949 · 1h 44m · MKV`, or `1h 02m left · MKV` for a film in progress.
String cardMeta(LobbyCard c) {
  final left = c.durationMs == null || !isInProgress(c)
      ? null
      : (c.durationMs! * (1 - c.resumeFraction)).round();
  return [
    if (left != null)
      '${runtimeText(left)} left'
    else ...[
      if (c.year != null) '${c.year}',
      if (c.durationMs != null) runtimeText(c.durationMs!),
    ],
    ?containerText(c),
  ].join(' · ');
}

/// What a screen reader says for a card.
String cardSpoken(LobbyCard c) {
  final parts = <String>[
    cardTitle(c),
    if (c.year != null) '${c.year}',
    if (isInProgress(c)) '${(c.resumeFraction * 100).round()} percent watched',
    if (c.finished) 'watched',
    if (c.subtitleLanguage != null) '${languageName(c.subtitleLanguage!)} subtitles',
  ];
  return parts.join(', ');
}

/// The small tags under a card: subtitle language (with a tick) and a remembered sync offset.
List<Widget> cardTags(BuildContext context, LobbyCard c) {
  final p = House.paletteOf(context);
  return [
    if (c.subtitleLanguage != null)
      Tag(
        c.subtitleLanguage!.toUpperCase(),
        icon: 'check',
        color: p.success,
        semanticLabel: '${languageName(c.subtitleLanguage!)} subtitles',
      ),
    if (c.delayMs != null && c.delayMs != 0)
      Tag(
        'SYNC ${formatDelay(c.delayMs!)}',
        semanticLabel: 'Subtitle sync ${spokenDelay(c.delayMs!)}',
      ),
    if (c.finished) Tag('WATCHED', color: p.inkMuted),
  ];
}

class FilmCard extends StatelessWidget {
  final LobbyCard card;
  final double width;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;
  const FilmCard({
    super.key,
    required this.card,
    required this.width,
    required this.onOpen,
    required this.onMenu,
  });

  double get height => width * 9 / 16 + kCardTextHeight;

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final thumbH = width * 9 / 16;
    final quick = h.reducedMotion ? Duration.zero : Tokens.durBase;
    Offset centre() {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return Offset.zero;
      return box.localToGlobal(Offset(box.size.width / 2, thumbH / 2));
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Pressable(
            label: cardSpoken(card),
            hint: 'Opens the film',
            onTap: onOpen,
            onLongPress: () => onMenu(centre()),
            onContextMenu: onMenu,
            radius: Tokens.radiusLg,
            builder: (context, s) => AnimatedScale(
              duration: quick,
              curve: Tokens.easeOut,
              scale: s.pressed ? 0.98 : 1,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedContainer(
                      duration: quick,
                      curve: Tokens.easeOut,
                      height: thumbH,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Tokens.radiusLg),
                        border: Border.all(
                          color: s.lit ? p.accent.withValues(alpha: 0.7) : p.border,
                          width: s.lit ? 1.5 : 1,
                        ),
                        boxShadow: h.matinee
                            ? null
                            : (s.lit
                                  ? [
                                      ...Tokens.shadow2,
                                      BoxShadow(
                                        color: p.accent.withValues(alpha: 0.16),
                                        blurRadius: 24,
                                      ),
                                    ]
                                  : Tokens.shadow1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Tokens.radiusLg - 1),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AnimatedScale(
                              duration: h.reducedMotion ? Duration.zero : Tokens.durSlow,
                              curve: Tokens.easeOut,
                              scale: s.hovered ? 1.05 : 1,
                              child: FilmFrame(
                                card: card,
                                fallback: TitleCard(
                                  card: card,
                                  fontSize: width >= 240 ? Tokens.textXl : Tokens.textLg,
                                ),
                              ),
                            ),
                            // A floor shadow so the resume line reads on bright frames.
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x00000000), Color(0x8C000000)],
                                  stops: [0.55, 1],
                                ),
                              ),
                            ),
                            AnimatedOpacity(
                              duration: Tokens.durFast,
                              opacity: s.lit ? 1 : 0,
                              child: Center(
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Tokens.auditorium.accent,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Tokens.auditorium.accent.withValues(alpha: 0.45),
                                        blurRadius: 18,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: LucideIcon(
                                      'play',
                                      color: Tokens.auditorium.accentInk,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (card.finished || isInProgress(card))
                              Positioned(
                                left: Tokens.space3,
                                right: Tokens.space3,
                                bottom: Tokens.space3,
                                child: ProgressLine(
                                  fraction: card.finished ? 1 : card.resumeFraction,
                                  color: Tokens.auditorium.accent,
                                  track: const Color(0x52FFFFFF),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 40),
                      child: Text(
                        cardTitle(card),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(right: 40),
                      child: Text(
                        cardMeta(card),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.mono(Tokens.textXs, p.inkMuted),
                      ),
                    ),
                    const SizedBox(height: Tokens.space2),
                    SizedBox(
                      height: 22,
                      child: ClipRect(
                        child: Wrap(spacing: 6, runSpacing: 8, children: cardTags(context, card)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: thumbH + 2,
            child: Builder(
              builder: (context) => IconMark(
                key: ValueKey('card-more-${card.id}'),
                icon: 'ellipsis-vertical',
                label: 'More options for ${cardTitle(card)}',
                showTooltip: false,
                onTap: () {
                  final box = context.findRenderObject()! as RenderBox;
                  onMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
