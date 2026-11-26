// The device library's cards: a video as a grid card (desktop, tablet, landscape) or a list row
// (portrait phone), and a folder likewise. Each shows a frame (the one grabbed while it played,
// else the device's own thumbnail, else a title card), what is known about the file, and where
// you are in it when the play history knows.
import 'dart:async';
import 'dart:io' show File;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/media.dart';
import '../../state/library.dart';
import '../../state/thumbnails.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import 'film_card.dart';
import 'library_actions.dart';
import 'lobby_actions.dart';

/// Height of the two text lines under a library card's frame, at the reader's text size (the
/// grid needs it before it lays a card out).
double libraryCardTextHeight(BuildContext context) =>
    Tokens.space3 + MediaQuery.textScalerOf(context).scale(46) + Tokens.space2;

/// A list row's frame (portrait phone).
const Size kLibraryRowThumb = Size(128, 72);

// ───────────────────────────── frames ─────────────────────────────

/// The title card of a video with no frame yet: the title on a warm ground, tinted per title.
class LibraryTitleCard extends StatelessWidget {
  final String title;
  final double fontSize;
  const LibraryTitleCard({super.key, required this.title, this.fontSize = Tokens.textLg});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final tints = [p.skyDusk, p.skyDawn, p.skyDay, p.accent2];
    // Not String.hashCode: the tint must be the same on every run (and in every screenshot).
    final tint = tints[title.codeUnits.fold(0, (a, b) => a + b) % tints.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(p.surface, tint, 0.45)!, p.bgElevated],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space3),
        child: Center(
          child: Text(
            title.toUpperCase(),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Txt.display(fontSize, p.ink.withValues(alpha: 0.8), weight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// A folder with no frame to show: a quiet folder mark.
class _FolderGround extends StatelessWidget {
  const _FolderGround();

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.surface2, p.bgElevated],
        ),
      ),
      child: Center(child: LucideIcon('folder', color: p.inkFaint, size: 32)),
    );
  }
}

/// A library video's picture. In order: the frame grabbed while the film played (it shows
/// where you are), the device-library frame, [fallback]. A missing device frame is asked for
/// once per card, quietly, and appears when it is ready.
class LibraryThumb extends ConsumerWidget {
  final LibraryItem item;
  final LobbyCard? card;
  final Widget fallback;
  const LibraryThumb({super.key, required this.item, required this.fallback, this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = _DeviceFrame(item: item, fallback: fallback);
    final c = card;
    return c == null ? device : FilmFrame(card: c, fallback: device);
  }
}

class _DeviceFrame extends ConsumerStatefulWidget {
  final LibraryItem item;
  final Widget fallback;
  const _DeviceFrame({required this.item, required this.fallback});

  @override
  ConsumerState<_DeviceFrame> createState() => _DeviceFrameState();
}

class _DeviceFrameState extends ConsumerState<_DeviceFrame> {
  late String _key = thumbKey(widget.item);
  bool _asked = false;

  /// Kept so dispose can withdraw the request (`ref` must not be used while unmounting).
  LibraryThumbRequests? _queue;

  @override
  void didUpdateWidget(_DeviceFrame old) {
    super.didUpdateWidget(old);
    if (!old.item.sameFileAs(widget.item)) {
      _queue?.cancel(old.item);
      _key = thumbKey(widget.item);
      _asked = false;
    }
  }

  @override
  void dispose() {
    // Scrolled away: the frames of what is on screen now come first.
    _queue?.cancel(widget.item);
    super.dispose();
  }

  /// Never from inside build: the request reads other providers and starts work.
  void _ask() {
    if (_asked) return;
    _asked = true;
    final item = widget.item;
    scheduleMicrotask(() {
      if (!mounted) return;
      _queue = ref.read(libraryThumbQueueProvider)..request(item);
    });
  }

  @override
  Widget build(BuildContext context) {
    // No disk access here: the index knows which frames exist.
    final has = ref.watch(libraryThumbsProvider.select((t) => t.has(_key)));
    final dir = ref.watch(libraryThumbDirProvider).value;
    if (!has || dir == null) {
      if (ref.watch(libraryThumbsProvider.select((t) => t.wants(_key)))) _ask();
      return widget.fallback;
    }
    return Image(
      image: thumbnailImage(File(libraryThumbPath(dir, _key))),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, sync) =>
          frame == null && !sync ? widget.fallback : child,
      errorBuilder: (context, error, stack) => widget.fallback,
    );
  }
}

/// The lit, rounded 16:9 frame every library card draws its picture in.
class _Frame extends StatelessWidget {
  final PressState state;
  final double radius;
  final List<Widget> children;
  const _Frame({required this.state, required this.children, this.radius = Tokens.radiusLg});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    return AnimatedContainer(
      duration: h.reducedMotion ? Duration.zero : Tokens.durBase,
      curve: Tokens.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: state.lit ? p.accent.withValues(alpha: 0.7) : p.border,
          width: state.lit ? 1.5 : 1,
        ),
        boxShadow: h.matinee ? null : (state.lit ? Tokens.shadow2 : Tokens.shadow1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(fit: StackFit.expand, children: children),
      ),
    );
  }
}

/// A floor shadow so the marks on a frame read on a bright picture.
const _floor = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0x99000000)],
      stops: [0.5, 1],
    ),
  ),
);

/// A small mark on a frame: `1:44:02`, `1080p`.
class _Chip extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? ink;
  const _Chip(this.text, {this.color, this.ink});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color ?? const Color(0xB8000000),
      borderRadius: BorderRadius.circular(Tokens.radiusSm),
    ),
    child: Text(
      text,
      maxLines: 1,
      softWrap: false,
      textScaler: TextScaler.noScaling, // a mark on a picture, sized with the picture
      style: Txt.mono(11, ink ?? const Color(0xFFF3E9DA), weight: FontWeight.w500),
    ),
  );
}

class _NewChip extends StatelessWidget {
  const _NewChip();

  @override
  Widget build(BuildContext context) =>
      _Chip('NEW', color: Tokens.auditorium.accent, ink: Tokens.auditorium.accentInk);
}

class _WatchedTick extends StatelessWidget {
  const _WatchedTick();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: const BoxDecoration(color: Color(0xB8000000), shape: BoxShape.circle),
    child: Center(child: LucideIcon('check', color: Tokens.auditorium.success, size: 14)),
  );
}

// ───────────────────────────── a video ─────────────────────────────

/// What a screen reader says for a library video.
String itemSpoken(LibraryItem item, LobbyCard? card, {required bool fresh}) => [
  libraryTitle(item.name),
  if (fresh) 'new',
  if (card != null && card.inProgress) '${(card.resumeFraction * 100).round()} percent watched',
  if (card != null && card.finished) 'watched',
  ?resolutionBadge(item.width, item.height),
].join(', ');

/// `42m left · 1.4 GB`, or `1.4 GB · Holiday clips` in a list across folders.
String itemMeta(
  LibraryItem item,
  LobbyCard? card, {
  bool showFolder = false,
  bool showFacts = false,
}) {
  final duration = item.durationMs ?? card?.durationMs;
  final left = card == null || duration == null || !card.inProgress
      ? null
      : (duration * (1 - card.resumeFraction)).round();
  return [
    if (left != null) '${runtimeText(left)} left',
    if (showFacts && left == null && duration != null && duration > 0) clockText(duration),
    if (showFacts) ?resolutionBadge(item.width, item.height),
    if (item.sizeBytes > 0) sizeText(item.sizeBytes),
    if (showFolder && item.folderName.isNotEmpty) item.folderName,
  ].join(' · ');
}

/// One video of the library, as a card or (with [list]) a row. Joins the play history by
/// locator: resume line, watched tick, the frame from where you stopped.
class LibraryVideoTile extends ConsumerWidget {
  final LibraryItem item;
  final bool list;

  /// Name the folder in the meta line (lists that cross folders).
  final bool showFolder;
  const LibraryVideoTile({
    super.key,
    required this.item,
    this.list = false,
    this.showFolder = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final known = ref.watch(libraryHistoryProvider.select((m) => m[historyKey(item.locator)]));
    // "Remove from history" hides the history at once (its Undo window is still open).
    final leaving =
        known != null && ref.watch(pendingRemovalsProvider.select((s) => s.contains(known.id)));
    final card = leaving ? null : known;
    final fresh = isNewItem(item, now: clock.now(), played: card != null);
    void open() => unawaited(openLibraryItem(ref, item));
    void menu(Offset at) => unawaited(showItemMenu(context, ref, item, at));
    return list
        ? _VideoRow(
            item: item,
            card: card,
            fresh: fresh,
            showFolder: showFolder,
            onOpen: open,
            onMenu: menu,
          )
        : _VideoCard(
            item: item,
            card: card,
            fresh: fresh,
            showFolder: showFolder,
            onOpen: open,
            onMenu: menu,
          );
  }
}

Offset _centreOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Offset.zero;
  return box.localToGlobal(box.size.center(Offset.zero));
}

class _MoreButton extends StatelessWidget {
  final String label;
  final ValueChanged<Offset> onMenu;
  const _MoreButton({super.key, required this.label, required this.onMenu});

  @override
  Widget build(BuildContext context) => IconMark(
    icon: 'ellipsis-vertical',
    label: label,
    showTooltip: false,
    onTap: () {
      final box = context.findRenderObject()! as RenderBox;
      onMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
    },
  );
}

class _VideoCard extends StatelessWidget {
  final LibraryItem item;
  final LobbyCard? card;
  final bool fresh;
  final bool showFolder;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;
  const _VideoCard({
    required this.item,
    required this.card,
    required this.fresh,
    required this.showFolder,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final title = libraryTitle(item.name);
    final c = card;
    final duration = item.durationMs ?? c?.durationMs;
    final badge = resolutionBadge(item.width, item.height);
    final progress = c == null
        ? null
        : (c.finished ? 1.0 : (c.inProgress ? c.resumeFraction : null));
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final thumbH = width * 9 / 16;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Pressable(
              label: itemSpoken(item, c, fresh: fresh),
              hint: 'Plays the video',
              onTap: onOpen,
              onLongPress: () => onMenu(_centreOf(context)),
              onContextMenu: onMenu,
              radius: Tokens.radiusLg,
              builder: (context, s) => AnimatedScale(
                duration: h.reducedMotion ? Duration.zero : Tokens.durBase,
                curve: Tokens.easeOut,
                scale: s.pressed ? 0.98 : 1,
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: thumbH,
                        child: _Frame(
                          state: s,
                          children: [
                            LibraryThumb(
                              item: item,
                              card: c,
                              fallback: LibraryTitleCard(
                                title: title,
                                fontSize: width >= 240 ? Tokens.textXl : Tokens.textLg,
                              ),
                            ),
                            _floor,
                            if (fresh)
                              const Positioned(
                                left: Tokens.space2,
                                top: Tokens.space2,
                                child: _NewChip(),
                              ),
                            if (c != null && c.finished)
                              const Positioned(
                                right: Tokens.space2,
                                top: Tokens.space2,
                                child: _WatchedTick(),
                              ),
                            Positioned(
                              left: Tokens.space2,
                              right: Tokens.space2,
                              bottom: Tokens.space2,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      if (badge != null) _Chip(badge),
                                      const Spacer(),
                                      if (duration != null && duration > 0)
                                        _Chip(clockText(duration)),
                                    ],
                                  ),
                                  if (progress != null) ...[
                                    const SizedBox(height: 6),
                                    ProgressLine(
                                      fraction: progress,
                                      color: Tokens.auditorium.accent,
                                      track: const Color(0x52FFFFFF),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 36),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(right: 36),
                        child: Text(
                          itemMeta(item, c, showFolder: showFolder),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.mono(Tokens.textXs, p.inkMuted),
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
              child: _MoreButton(
                key: ValueKey('lib-more-${item.locator}'),
                label: 'More options for $title',
                onMenu: onMenu,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VideoRow extends StatelessWidget {
  final LibraryItem item;
  final LobbyCard? card;
  final bool fresh;
  final bool showFolder;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;
  const _VideoRow({
    required this.item,
    required this.card,
    required this.fresh,
    required this.showFolder,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final title = libraryTitle(item.name);
    final c = card;
    final duration = item.durationMs ?? c?.durationMs;
    final progress = c == null
        ? null
        : (c.finished ? 1.0 : (c.inProgress ? c.resumeFraction : null));
    return Stack(
      children: [
        Pressable(
          label: itemSpoken(item, c, fresh: fresh),
          hint: 'Plays the video',
          onTap: onOpen,
          onLongPress: () => onMenu(_centreOf(context)),
          onContextMenu: onMenu,
          radius: Tokens.radiusMd,
          builder: (context, s) => AnimatedContainer(
            duration: Tokens.durFast,
            padding: const EdgeInsets.all(Tokens.space2),
            decoration: BoxDecoration(
              color: pressWash(p, s),
              borderRadius: BorderRadius.circular(Tokens.radiusMd),
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  SizedBox.fromSize(
                    size: kLibraryRowThumb,
                    child: _Frame(
                      state: s,
                      radius: Tokens.radiusMd,
                      children: [
                        LibraryThumb(
                          item: item,
                          card: c,
                          fallback: LibraryTitleCard(title: title, fontSize: Tokens.textSm),
                        ),
                        _floor,
                        if (fresh) const Positioned(left: 6, top: 6, child: _NewChip()),
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 6,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (duration != null && duration > 0) _Chip(clockText(duration)),
                              if (progress != null) ...[
                                const SizedBox(height: 4),
                                ProgressLine(
                                  fraction: progress,
                                  height: 3,
                                  color: Tokens.auditorium.accent,
                                  track: const Color(0x52FFFFFF),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Tokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.body(
                            Tokens.textBase,
                            p.ink,
                            weight: FontWeight.w600,
                          ).copyWith(height: 1.3),
                        ),
                        const SizedBox(height: Tokens.space1),
                        Row(
                          children: [
                            if (c != null && c.finished) ...[
                              LucideIcon('check', color: p.success, size: 14),
                              const SizedBox(width: Tokens.space1),
                            ],
                            Expanded(
                              child: Text(
                                itemMeta(item, c, showFolder: showFolder, showFacts: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.mono(Tokens.textXs, p.inkMuted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Room for the more button, which sits above this surface.
                  const SizedBox(width: Tokens.targetMin - Tokens.space2),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: _MoreButton(
              key: ValueKey('lib-more-${item.locator}'),
              label: 'More options for $title',
              onMenu: onMenu,
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── a folder ─────────────────────────────

String folderMeta(LibraryFolder f) => [
  f.count == 1 ? '1 video' : '${f.count} videos',
  if (f.totalBytes > 0) sizeText(f.totalBytes),
].join(' · ');

/// A folder of the library: its newest video's frame, its name and how much is in it.
class LibraryFolderTile extends StatelessWidget {
  final LibraryFolder folder;
  final bool list;
  final VoidCallback onOpen;
  const LibraryFolderTile({
    super.key,
    required this.folder,
    required this.onOpen,
    this.list = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final name = folder.name.isEmpty ? 'Videos' : folder.name;
    final spoken = 'Folder $name, ${folderMeta(folder)}';
    List<Widget> picture() => [
      LibraryThumb(item: folder.newest, fallback: const _FolderGround()),
      _floor,
      Positioned(
        left: Tokens.space2,
        bottom: Tokens.space2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xB8000000),
            borderRadius: BorderRadius.circular(Tokens.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LucideIcon('folder', color: Color(0xFFF3E9DA), size: 13),
              const SizedBox(width: 5),
              Text(
                '${folder.count}',
                textScaler: TextScaler.noScaling,
                style: Txt.mono(11, const Color(0xFFF3E9DA), weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    ];

    if (list) {
      return Pressable(
        label: spoken,
        hint: 'Opens the folder',
        onTap: onOpen,
        radius: Tokens.radiusMd,
        builder: (context, s) => AnimatedContainer(
          duration: Tokens.durFast,
          padding: const EdgeInsets.all(Tokens.space2),
          decoration: BoxDecoration(
            color: pressWash(p, s),
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                SizedBox.fromSize(
                  size: kLibraryRowThumb,
                  child: _Frame(state: s, radius: Tokens.radiusMd, children: picture()),
                ),
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.body(
                          Tokens.textBase,
                          p.ink,
                          weight: FontWeight.w600,
                        ).copyWith(height: 1.3),
                      ),
                      const SizedBox(height: Tokens.space1),
                      Text(
                        folderMeta(folder),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.mono(Tokens.textXs, p.inkMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                LucideIcon('chevron-right', color: p.inkFaint, size: 18),
                const SizedBox(width: Tokens.space1),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) => Pressable(
        label: spoken,
        hint: 'Opens the folder',
        onTap: onOpen,
        radius: Tokens.radiusLg,
        builder: (context, s) => AnimatedScale(
          duration: h.reducedMotion ? Duration.zero : Tokens.durBase,
          curve: Tokens.easeOut,
          scale: s.pressed ? 0.98 : 1,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: box.maxWidth * 9 / 16,
                  child: _Frame(state: s, children: picture()),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  folderMeta(folder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.mono(Tokens.textXs, p.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
