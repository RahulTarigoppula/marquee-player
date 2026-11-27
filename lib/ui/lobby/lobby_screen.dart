// The Lobby: the room you come home to. Two tabs. Home: the last film on the marquee with
// Resume, the films you are part-way through, the rest of what you have played, and two clear
// ways in — Open file, Open link (or drop a file anywhere on desktop). Library: every video on
// the device (library_view.dart).
//
// Three shapes. A desktop window: the bar with the theme switch and both Open buttons, the tabs
// under it. A phone upright: a bare bar with one Open button, and Home | Library as a full-width
// row a thumb can hit. A phone on its side: all of it in one row, because there the height is
// what is scarce and the first thing on screen must be the button that plays something.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/media.dart';
import '../../engine/models/settings.dart';
import '../../state/library.dart';
import '../../state/providers.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/marquee_sign.dart';
import '../components/primitives.dart';
import '../components/room.dart';
import '../components/theme_choice.dart';
import 'film_card.dart';
import 'library_actions.dart';
import 'library_view.dart';
import 'lobby_actions.dart';
import 'lobby_hero.dart';

/// The Lobby switches to its wide (desktop / landscape) layout at this width.
const double kLobbyWide = 840;

/// A short screen at least this wide has room for the title, the tabs and the actions in one
/// row; a narrower one (a small split-screen window) keeps the tabs on a row of their own.
const double kLobbyOneRow = 560;

/// The two ways in behind the phone bar's one Open button.
enum _OpenWay { file, link }

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

  /// The phone bar's Open button: two plain lines under it.
  Future<void> _openMenu(Offset at) async {
    final way = await showHouseMenu<_OpenWay>(context, at, const [
      MenuChoice(_OpenWay.file, 'folder-open', 'Open file'),
      MenuChoice(_OpenWay.link, 'link', 'Open link'),
    ]);
    if (!mounted) return;
    switch (way) {
      case _OpenWay.file:
        await openPickedFile(ref);
      case _OpenWay.link:
        await openUrl(context, ref);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final pending = ref.watch(pendingRemovalsProvider);
    final library = ref.watch(libraryProvider);
    // Which tab was open last is read from the database too; until it is known (a frame or
    // two) the room is bare, so the Lobby never opens on Home and jumps to the Library.
    final view = ref.watch(lobbyViewProvider);
    final tab = view.value?.tab ?? LobbyTab.home;
    final onLibrary = tab == LobbyTab.library;
    // The first read of the library takes a moment: show the bare room, not "empty".
    final loading =
        (!view.hasValue && !view.hasError) ||
        (!onLibrary && !library.hasValue && !library.hasError);
    final cards = [
      for (final c in library.value ?? const <LobbyCard>[])
        if (!pending.contains(c.id)) c,
    ];
    final settings = ref.watch(settingsValueProvider);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= kLobbyWide;
    // A phone on its side: plenty of width, very little height.
    final short = size.height < kShortBelow;
    // A phone either way up. Its bar carries one Open button with a menu, and no theme switch
    // (that is in Settings › Appearance): the room goes to the tabs.
    final phone = !wide || short;
    final oneRow = short && size.width >= kLobbyOneRow;
    final phase = skyPhaseAt(_now);
    final night = phase == SkyPhase.night || phase == SkyPhase.dusk;
    final margin = wide ? Tokens.space8 : Tokens.marginPhone;

    Widget tabs({required bool fill}) => SegmentedChoice<LobbyTab>(
      key: const ValueKey('lobby-tabs'),
      groupLabel: 'Show',
      value: tab,
      onChanged: (t) => ref.read(lobbyViewProvider.notifier).setTab(t),
      expand: fill,
      tall: phone,
      segments: const [
        Segment(LobbyTab.home, 'Home', icon: 'house'),
        Segment(LobbyTab.library, 'Library', icon: 'library'),
      ],
    );
    Widget bar({Widget? tabs}) => _TopBar(
      now: _now,
      wide: wide,
      phone: phone,
      showClock: !short,
      tabs: tabs,
      // With nothing played yet Home's own two buttons are the way in; the Library has none.
      showOpen: cards.isNotEmpty || onLibrary,
      theme: settings.lobbyTheme,
      onTheme: (t) =>
          unawaited(ref.read(settingsProvider.notifier).edit((s) => s.copyWith(lobbyTheme: t))),
      onOpenFile: () => unawaited(openPickedFile(ref)),
      onOpenUrl: () => unawaited(openUrl(context, ref)),
      onOpenMenu: (at) => unawaited(_openMenu(at)),
      onSettings: () => ref.read(roomProvider.notifier).go(Room.ticketOffice),
    );
    // The bar and the tab switch travel together at the top of whichever tab is showing.
    final Widget header = oneRow
        ? bar(tabs: tabs(fill: true))
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bar(),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  margin,
                  phone ? Tokens.space3 : Tokens.space4,
                  margin,
                  Tokens.space2,
                ),
                // Upright on a phone the tabs are the app's main navigation: the full width,
                // 48 px tall. On desktop they sit under the title, in line with it.
                child: wide
                    ? Align(alignment: Alignment.centerLeft, child: tabs(fill: false))
                    : tabs(fill: true),
              ),
            ],
          );

    final Widget body;
    if (loading) {
      body = Align(alignment: Alignment.topCenter, child: bar());
    } else if (onLibrary) {
      body = LibraryPane(
        header: header,
        footer: _Footer(margin: margin),
        wide: wide,
        margin: margin,
      );
    } else if (cards.isEmpty) {
      body = LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                _EmptyLobby(
                  wide: wide,
                  short: short,
                  night: night,
                  drops: acceptsDrops(context),
                  dragOver: widget.dragOver,
                  onOpenFile: () => unawaited(openPickedFile(ref)),
                  onOpenUrl: () => unawaited(openUrl(context, ref)),
                  onLibrary: () => ref.read(lobbyViewProvider.notifier).setTab(LobbyTab.library),
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
      // Each film is on Home once: the hero and Continue watching have theirs already, and
      // Recently played is whatever is left (and is not there at all when nothing is).
      final recent = [
        for (final c in cards.skip(1))
          if (!isInProgress(c)) c,
      ];
      // A whole number of pixels: a hero that ends between two rows of pixels draws its
      // backdrop's edge as a hairline across the screen (seen in the light theme).
      final heroMin = short
          ? 0.0
          : (wide
                    ? (size.height * 0.62).clamp(320.0, 560.0)
                    : (size.height * 0.5).clamp(380.0, 520.0))
                .roundToDouble();
      body = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: LobbyHero(
              card: latest,
              wide: wide,
              short: short,
              night: night,
              minHeight: heroMin,
              top: header,
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
                        label: 'Open link',
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
          if (recent.isNotEmpty) ...[
            _Heading(
              'Recently played',
              trailing: recent.length == 1 ? '1 video' : '${recent.length} videos',
              margin: margin,
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: margin),
              sliver: _CardGrid(
                cards: recent,
                minCardWidth: wide ? 232 : 150,
                onOpen: (c) => unawaited(openCard(ref, c)),
                onMenu: _menu,
              ),
            ),
          ],
          // The credits: at the foot of the screen when there is little above them, at the
          // end of the page (as before) when there is a lot.
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _Footer(margin: margin),
            ),
          ),
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
            opacity: widget.dragOver && (cards.isNotEmpty || onLibrary) ? 1 : 0,
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

  /// A phone, upright or on its side: one Open button with a menu, no theme switch.
  final bool phone;

  /// The line under the title (`NIGHT · 21:30`). Dropped on a short screen.
  final bool showClock;

  /// Home | Library, when it rides in the bar itself (a phone on its side).
  final Widget? tabs;
  final bool showOpen;
  final LobbyTheme theme;
  final ValueChanged<LobbyTheme> onTheme;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenUrl;

  /// The phone's Open button was tapped: where to hang its menu.
  final ValueChanged<Offset> onOpenMenu;
  final VoidCallback onSettings;
  const _TopBar({
    required this.now,
    required this.wide,
    required this.phone,
    required this.showClock,
    required this.tabs,
    required this.showOpen,
    required this.theme,
    required this.onTheme,
    required this.onOpenFile,
    required this.onOpenUrl,
    required this.onOpenMenu,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final phase = skyPhaseAt(now);
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final inline = tabs;
    final title = Semantics(
      header: true,
      child: Text('MARQUEE', style: Txt.display(Tokens.textXl, p.ink, weight: FontWeight.w800)),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? Tokens.space8 : Tokens.marginPhone,
        inline == null ? Tokens.space4 : Tokens.space2,
        wide ? Tokens.space6 : Tokens.space3,
        inline == null ? 0 : Tokens.space1,
      ),
      child: Row(
        children: [
          if (inline == null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  // The time of day only. How many videos there are is the Library's to say
                  // (it counts every video; this bar used to count the ones played).
                  if (showClock)
                    Text(
                      '${phase.name.toUpperCase()} · $time',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Txt.label(p.inkFaint),
                    ),
                ],
              ),
            )
          else ...[
            title,
            const SizedBox(width: Tokens.space5),
            // The tabs take what the title and the buttons leave, up to a comfortable width.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: inline,
                ),
              ),
            ),
            const SizedBox(width: Tokens.space2),
          ],
          if (!phone)
            ThemeChoice(
              key: const ValueKey('lobby-theme'),
              value: theme,
              onChanged: onTheme,
              compact: true,
            ),
          if (showOpen && !phone) ...[
            const SizedBox(width: Tokens.space4),
            HouseButton(
              key: const ValueKey('open-url'),
              label: 'Open link',
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
          if (showOpen && phone)
            Builder(
              builder: (context) => IconMark(
                key: const ValueKey('open-menu'),
                icon: 'folder-open',
                label: 'Open a video',
                onTap: () {
                  final box = context.findRenderObject()! as RenderBox;
                  onOpenMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                },
              ),
            ),
          if (!phone) const SizedBox(width: Tokens.space2),
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

/// The rest of the films, as a lazy grid (a sliver): as many columns as fit at [minCardWidth],
/// at least two. Only the cards on screen are built and only their pictures decoded, so a long
/// history costs the first frame nothing — the Library's grid is made the same way.
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
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      const gap = Tokens.space4;
      final width = constraints.crossAxisExtent;
      final cols = ((width + gap) / (minCardWidth + gap)).floor().clamp(2, 8);
      final w = (width - gap * (cols - 1)) / cols;
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: gap,
          mainAxisSpacing: Tokens.space6,
          mainAxisExtent: w * 9 / 16 + kCardTextHeight,
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          final card = cards[i];
          return FilmCard(
            key: ValueKey('grid-${card.id}'),
            card: card,
            width: w,
            onOpen: () => onOpen(card),
            onMenu: (at) => onMenu(card, at),
          );
        }, childCount: cards.length),
      );
    },
  );
}

class _EmptyLobby extends StatelessWidget {
  final bool wide;

  /// A phone on its side: a small sign and close gaps, so "Open a video" is on the first
  /// screen and not under it.
  final bool short;
  final bool night;
  final bool drops;
  final bool dragOver;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenUrl;
  final VoidCallback onLibrary;
  const _EmptyLobby({
    required this.wide,
    required this.short,
    required this.night,
    required this.drops,
    required this.dragOver,
    required this.onOpenFile,
    required this.onOpenUrl,
    required this.onLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final big = wide && !short;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pick a video and Marquee plays it, with matching subtitles found for you.',
          textAlign: TextAlign.center,
          style: Txt.body(big ? Tokens.textLg : Tokens.textBase, p.ink),
        ),
        SizedBox(height: short ? Tokens.space3 : Tokens.space6),
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
              label: 'Open link',
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
        // Nothing played yet: the videos already on the device are one tap away.
        const SizedBox(height: Tokens.space3),
        TextAction('Browse the videos on this device', onTap: onLibrary),
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: wide ? Tokens.space8 : Tokens.marginPhone,
        vertical: short ? Tokens.space3 : Tokens.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MarqueeSign(
            title: 'Marquee',
            meta: 'THE HOUSE IS OPEN',
            night: night,
            fontSize: big ? Tokens.text4Xl : Tokens.text3Xl,
          ),
          SizedBox(height: short ? Tokens.space3 : Tokens.space8),
          ConstrainedBox(
            // Wider on a short screen, so the sentence stays on one line there.
            constraints: BoxConstraints(maxWidth: short ? 640 : 560),
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
