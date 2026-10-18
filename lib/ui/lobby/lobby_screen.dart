// The Lobby: the room you come home to. The last film on the marquee with Resume, the films you
// are part-way through, everything you have played, and two clear ways in — Open file, Open URL
// (or drop a file anywhere on desktop).
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/media.dart';
import '../../engine/models/settings.dart';
import '../../state/providers.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/marquee_sign.dart';
import '../components/primitives.dart';
import '../components/room.dart';
import '../components/theme_choice.dart';
import 'film_card.dart';
import 'lobby_actions.dart';
import 'lobby_hero.dart';

/// The Lobby switches to its wide (desktop / landscape) layout at this width.
const double kLobbyWide = 840;

/// True where files can be dragged onto the window.
bool acceptsDrops(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
  _ => false,
};

class LobbyScreen extends ConsumerStatefulWidget {
  final bool dragOver;
  const LobbyScreen({super.key, this.dragOver = false});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  Timer? _tick;
  late DateTime _now = clock.now();

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  /// The sky and the clock line move while the app stays open: wake on each new minute.
  void _scheduleTick() {
    final now = clock.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _tick = Timer(next.difference(now) + const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() => _now = clock.now());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _menu(LobbyCard c, Offset at) => unawaited(showCardMenu(context, ref, c, at));

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final pending = ref.watch(pendingRemovalsProvider);
    final library = ref.watch(libraryProvider);
    // The first read of the library takes a moment: show the bare room, not "empty".
    final loading = !library.hasValue && !library.hasError;
    final cards = [
      for (final c in library.value ?? const <LobbyCard>[])
        if (!pending.contains(c.id)) c,
    ];
    final settings = ref.watch(settingsValueProvider);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= kLobbyWide;
    final phase = skyPhaseAt(_now);
    final night = phase == SkyPhase.night || phase == SkyPhase.dusk;
    final margin = wide ? Tokens.space8 : Tokens.marginPhone;

    final bar = _TopBar(
      now: _now,
      wide: wide,
      filmCount: cards.length,
      showOpen: cards.isNotEmpty && wide,
      theme: settings.lobbyTheme,
      onTheme: (t) =>
          unawaited(ref.read(settingsProvider.notifier).edit((s) => s.copyWith(lobbyTheme: t))),
      onOpenFile: () => unawaited(openPickedFile(ref)),
      onOpenUrl: () => unawaited(openUrl(context, ref)),
      onSettings: () => ref.read(roomProvider.notifier).go(Room.ticketOffice),
    );

    final Widget body;
    if (loading) {
      body = Align(alignment: Alignment.topCenter, child: bar);
    } else if (cards.isEmpty) {
      body = LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar,
                _EmptyLobby(
                  wide: wide,
                  night: night,
                  drops: acceptsDrops(context),
                  dragOver: widget.dragOver,
                  onOpenFile: () => unawaited(openPickedFile(ref)),
                  onOpenUrl: () => unawaited(openUrl(context, ref)),
                ),
                _Footer(margin: margin),
              ],
            ),
          ),
        ),
      );
    } else {
      final latest = cards.first;
      final inProgress = [
        for (final c in cards.skip(1))
          if (isInProgress(c)) c,
      ];
      body = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: LobbyHero(
              card: latest,
              wide: wide,
              night: night,
              minHeight: wide
                  ? (size.height * 0.62).clamp(320.0, 560.0)
                  : (size.height * 0.5).clamp(380.0, 520.0),
              top: bar,
              onPlay: () => unawaited(openCard(ref, latest)),
              onMenu: (at) => _menu(latest, at),
            ),
          ),
          if (!wide)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(margin, 0, margin, Tokens.space4),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: HouseButton(
                        label: 'Open file',
                        icon: 'folder-open',
                        expand: true,
                        onPressed: () => unawaited(openPickedFile(ref)),
                      ),
                    ),
                    const SizedBox(width: Tokens.space3),
                    Expanded(
                      child: HouseButton(
                        label: 'Open URL',
                        icon: 'link',
                        expand: true,
                        onPressed: () => unawaited(openUrl(context, ref)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (inProgress.isNotEmpty) ...[
            _Heading('Continue watching', margin: margin),
            SliverToBoxAdapter(
              child: _CardRow(
                cards: inProgress,
                cardWidth: wide ? 300 : 236,
                margin: margin,
                onOpen: (c) => unawaited(openCard(ref, c)),
                onMenu: _menu,
              ),
            ),
          ],
          _Heading(
            'Recently played',
            trailing: cards.length == 1 ? '1 film' : '${cards.length} films',
            margin: margin,
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: margin),
            sliver: SliverToBoxAdapter(
              child: _CardGrid(
                cards: cards,
                minCardWidth: wide ? 232 : 150,
                onOpen: (c) => unawaited(openCard(ref, c)),
                onMenu: _menu,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _Footer(margin: margin)),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        SkyBand(now: _now),
        if (settings.beam) Beam(width: widget.dragOver ? 0.4 : 0.16),
        const Grain(),
        SafeArea(bottom: false, child: body),
        IgnorePointer(
          child: AnimatedOpacity(
            duration: h.reducedMotion ? Duration.zero : Tokens.durBase,
            opacity: widget.dragOver && cards.isNotEmpty ? 1 : 0,
            child: ColoredBox(
              color: p.bg.withValues(alpha: 0.72),
              child: Center(
                child: _DropFrame(
                  lit: true,
                  child: Text(
                    'Drop to start watching',
                    style: Txt.body(Tokens.textXl, p.ink, weight: FontWeight.w600),
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

class _TopBar extends StatelessWidget {
  final DateTime now;
  final bool wide;
  final int filmCount;
  final bool showOpen;
  final LobbyTheme theme;
  final ValueChanged<LobbyTheme> onTheme;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenUrl;
  final VoidCallback onSettings;
  const _TopBar({
    required this.now,
    required this.wide,
    required this.filmCount,
    required this.showOpen,
    required this.theme,
    required this.onTheme,
    required this.onOpenFile,
    required this.onOpenUrl,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final phase = skyPhaseAt(now);
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? Tokens.space8 : Tokens.marginPhone,
        Tokens.space4,
        wide ? Tokens.space6 : Tokens.space3,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'MARQUEE',
                    style: Txt.display(Tokens.textXl, p.ink, weight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${phase.name.toUpperCase()} · $time'
                  '${filmCount == 0 ? '' : ' · ${filmCount == 1 ? '1 FILM' : '$filmCount FILMS'}'}',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: Txt.label(p.inkFaint),
                ),
              ],
            ),
          ),
          ThemeChoice(
            key: const ValueKey('lobby-theme'),
            value: theme,
            onChanged: onTheme,
            compact: true,
          ),
          if (showOpen) ...[
            const SizedBox(width: Tokens.space4),
            HouseButton(
              key: const ValueKey('open-url'),
              label: 'Open URL',
              icon: 'link',
              kind: ButtonKind.ghost,
              onPressed: onOpenUrl,
            ),
            const SizedBox(width: Tokens.space2),
            HouseButton(
              key: const ValueKey('open-file'),
              label: 'Open file',
              icon: 'folder-open',
              onPressed: onOpenFile,
            ),
          ],
          const SizedBox(width: Tokens.space2),
          IconMark(icon: 'settings-2', label: 'Settings', onTap: onSettings),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  final String? trailing;
  final double margin;
  const _Heading(this.text, {this.trailing, required this.margin});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(margin, Tokens.space6, margin, Tokens.space3),
      sliver: SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Semantics(
              header: true,
              child: Text(text, style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w600)),
            ),
            const Spacer(),
            if (trailing != null) Text(trailing!, style: Txt.mono(Tokens.textXs, p.inkFaint)),
          ],
        ),
      ),
    );
  }
}

/// A horizontal row of cards. A mouse wheel scrolls it sideways (desktop has no other way short
/// of dragging the scrollbar); touch drags as usual.
class _CardRow extends StatefulWidget {
  final List<LobbyCard> cards;
  final double cardWidth;
  final double margin;
  final ValueChanged<LobbyCard> onOpen;
  final void Function(LobbyCard, Offset) onMenu;
  const _CardRow({
    required this.cards,
    required this.cardWidth,
    required this.margin,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  State<_CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<_CardRow> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final delta = e.scrollDelta.dy.abs() > e.scrollDelta.dx.abs()
        ? e.scrollDelta.dy
        : e.scrollDelta.dx;
    if (delta == 0 || pos.maxScrollExtent <= 0) return;
    final atEdge =
        (delta < 0 && pos.pixels <= pos.minScrollExtent) ||
        (delta > 0 && pos.pixels >= pos.maxScrollExtent);
    if (atEdge) return; // let the page scroll on
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final target = (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      _scroll.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardH = widget.cardWidth * 9 / 16 + kCardTextHeight;
    return Listener(
      onPointerSignal: _wheel,
      child: SizedBox(
        height: cardH + Tokens.space2 * 2,
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(horizontal: widget.margin, vertical: Tokens.space2),
          itemCount: widget.cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: Tokens.space4),
          itemBuilder: (context, i) {
            final c = widget.cards[i];
            return FilmCard(
              key: ValueKey('row-${c.id}'),
              card: c,
              width: widget.cardWidth,
              onOpen: () => widget.onOpen(c),
              onMenu: (at) => widget.onMenu(c, at),
            );
          },
        ),
      ),
    );
  }
}

/// Every film, as a responsive grid: as many columns as fit at [minCardWidth], at least two.
class _CardGrid extends StatelessWidget {
  final List<LobbyCard> cards;
  final double minCardWidth;
  final ValueChanged<LobbyCard> onOpen;
  final void Function(LobbyCard, Offset) onMenu;
  const _CardGrid({
    required this.cards,
    required this.minCardWidth,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = Tokens.space4;
      final cols = ((c.maxWidth + gap) / (minCardWidth + gap)).floor().clamp(2, 8);
      final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
      return Wrap(
        spacing: gap,
        runSpacing: Tokens.space6,
        children: [
          for (final card in cards)
            FilmCard(
              key: ValueKey('grid-${card.id}'),
              card: card,
              width: w,
              onOpen: () => onOpen(card),
              onMenu: (at) => onMenu(card, at),
            ),
        ],
      );
    },
  );
}

class _EmptyLobby extends StatelessWidget {
  final bool wide;
  final bool night;
  final bool drops;
  final bool dragOver;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenUrl;
  const _EmptyLobby({
    required this.wide,
    required this.night,
    required this.drops,
    required this.dragOver,
    required this.onOpenFile,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pick a video and Marquee plays it, with matching subtitles found for you.',
          textAlign: TextAlign.center,
          style: Txt.body(wide ? Tokens.textLg : Tokens.textBase, p.ink),
        ),
        const SizedBox(height: Tokens.space6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Tokens.space3,
          runSpacing: Tokens.space3,
          children: [
            HouseButton(
              key: const ValueKey('open-file'),
              label: 'Open a video',
              icon: 'folder-open',
              kind: ButtonKind.primary,
              large: true,
              onPressed: onOpenFile,
            ),
            HouseButton(
              key: const ValueKey('open-url'),
              label: 'Open URL',
              icon: 'link',
              kind: ButtonKind.ghost,
              large: true,
              onPressed: onOpenUrl,
            ),
          ],
        ),
        if (drops) ...[
          const SizedBox(height: Tokens.space5),
          Text(
            dragOver
                ? 'Let go to start watching'
                : 'or drag a video file anywhere onto this window',
            textAlign: TextAlign.center,
            style: Txt.body(Tokens.textSm, dragOver ? p.accent : p.inkMuted),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: wide ? Tokens.space8 : Tokens.marginPhone,
        vertical: Tokens.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MarqueeSign(
            title: 'Marquee',
            meta: 'THE HOUSE IS OPEN',
            night: night,
            fontSize: wide ? Tokens.text4Xl : Tokens.text3Xl,
          ),
          const SizedBox(height: Tokens.space8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: drops ? _DropFrame(lit: dragOver, child: content) : content,
          ),
        ],
      ),
    );
  }
}

/// The doors: a dashed frame that lights tungsten while a file is dragged over the window.
class _DropFrame extends StatelessWidget {
  final bool lit;
  final Widget child;
  const _DropFrame({required this.lit, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return CustomPaint(
      painter: _DashedFrame(color: lit ? p.accent : p.borderStrong),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space8, vertical: Tokens.space7),
        child: child,
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
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.6),
          const Radius.circular(Tokens.radiusLg),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame o) => o.color != color;
}

class _Footer extends StatelessWidget {
  final double margin;
  const _Footer({required this.margin});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, Tokens.space8, margin, Tokens.space5),
      child: Text(
        'Subtitles by OpenSubtitles.com · Plays with libmpv, FFmpeg and libass (LGPL) · '
        'Marquee is free and open source (MIT)',
        textAlign: TextAlign.center,
        style: Txt.body(Tokens.textXs, p.inkFaint),
      ),
    );
  }
}
