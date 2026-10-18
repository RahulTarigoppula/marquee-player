// The Lobby's hero: the most recent film on the marquee, its own frame behind it as a dimmed,
// vignetted backdrop, and one tungsten action — Resume (or Play).
import 'package:flutter/material.dart';

import '../../engine/models/media.dart';
import '../../engine/sentences.dart';
import '../../engine/sync_rule.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/marquee_sign.dart';
import '../components/primitives.dart';
import 'film_card.dart';
import 'lobby_actions.dart';

class LobbyHero extends StatelessWidget {
  final LobbyCard card;
  final bool wide;
  final bool night;
  final double minHeight;

  /// The top bar, laid over the backdrop.
  final Widget top;
  final VoidCallback onPlay;
  final ValueChanged<Offset> onMenu;
  const LobbyHero({
    super.key,
    required this.card,
    required this.wide,
    required this.night,
    required this.minHeight,
    required this.top,
    required this.onPlay,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final resume = resumeMs(card);
    final details = [
      if (card.durationMs != null) runtimeText(card.durationMs!),
      ?containerText(card),
      if (card.subtitleLanguage != null) '${languageName(card.subtitleLanguage!)} subtitles',
    ].join('  ·  ');
    final left = card.durationMs == null || resume == null ? null : card.durationMs! - resume;

    return Stack(
      children: [
        Positioned.fill(child: _Backdrop(card: card)),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              top,
              Padding(
                padding: EdgeInsets.fromLTRB(
                  wide ? Tokens.space8 : Tokens.marginPhone,
                  Tokens.space6,
                  wide ? Tokens.space8 : Tokens.marginPhone,
                  Tokens.space6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MarqueeSign(
                      title: cardTitle(card),
                      meta: [if (card.year != null) '${card.year}', 'NOW SHOWING'].join(' · '),
                      identified: card.title != null,
                      night: night,
                      fontSize: wide ? Tokens.text4Xl : Tokens.text3Xl,
                    ),
                    const SizedBox(height: Tokens.space4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Tokens.space3,
                      runSpacing: Tokens.space2,
                      children: [
                        if (details.isNotEmpty)
                          Text(
                            details,
                            textAlign: TextAlign.center,
                            style: Txt.body(Tokens.textSm, p.inkMuted, weight: FontWeight.w500),
                          ),
                        if (card.delayMs != null && card.delayMs != 0)
                          Tag(
                            'SYNC ${formatDelay(card.delayMs!)}',
                            semanticLabel: 'Subtitle sync ${spokenDelay(card.delayMs!)}',
                          ),
                      ],
                    ),
                    if (resume != null) ...[
                      const SizedBox(height: Tokens.space4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Row(
                          children: [
                            Expanded(child: ProgressLine(fraction: card.resumeFraction)),
                            if (left != null) ...[
                              const SizedBox(width: Tokens.space3),
                              Text(
                                '${runtimeText(left)} left',
                                style: Txt.mono(Tokens.textXs, p.inkMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: Tokens.space5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HouseButton(
                          key: const ValueKey('hero-play'),
                          label: resume != null
                              ? 'Resume ${clockText(resume)}'
                              : (card.finished ? 'Play again' : 'Play'),
                          semanticLabel: resume != null
                              ? 'Resume ${cardTitle(card)} from ${clockText(resume)}'
                              : 'Play ${cardTitle(card)}',
                          icon: 'play',
                          kind: ButtonKind.primary,
                          large: true,
                          onPressed: onPlay,
                        ),
                        const SizedBox(width: Tokens.space3),
                        Builder(
                          builder: (context) => _MoreButton(
                            label: 'More options for ${cardTitle(card)}',
                            onTap: () {
                              final box = context.findRenderObject()! as RenderBox;
                              onMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A square secondary button for the hero's ⋮ — the same height as the large Resume.
class _MoreButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MoreButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      label: label,
      tooltip: 'More',
      onTap: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: s.pressed
              ? p.ink.withValues(alpha: 0.16)
              : p.ink.withValues(alpha: s.hovered ? 0.11 : 0.06),
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          border: Border.all(color: s.hovered ? p.inkFaint : p.borderStrong),
        ),
        child: Center(child: LucideIcon('ellipsis-vertical', color: p.ink, size: 20)),
      ),
    );
  }
}

/// The film's own frame, dimmed and vignetted into the room. Without a frame the room itself
/// (sky band, beam) is the backdrop.
class _Backdrop extends StatelessWidget {
  final LobbyCard card;
  const _Backdrop({required this.card});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: h.matinee ? 0.7 : 0.5,
              child: FilmFrame(card: card, fallback: const SizedBox.shrink()),
            ),
            // Fade into the room at the top (the bar) and the bottom (the rows).
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    p.bg.withValues(alpha: 0.7),
                    p.bg.withValues(alpha: 0.05),
                    p.bg.withValues(alpha: 0.35),
                    p.bg,
                  ],
                  stops: const [0, 0.28, 0.62, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.05,
                  colors: [p.bg.withValues(alpha: 0), p.bg.withValues(alpha: 0.75)],
                  stops: const [0.45, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
