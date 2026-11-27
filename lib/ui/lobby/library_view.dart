// The Lobby's Library tab: every video on the device. A search field, the sort order, folders
// (which open into their videos) or all videos at once; a grid where there is room, a list on a
// portrait phone. Lists are lazy: a library of thousands builds only what is on screen.
//
// What is not there yet is said in one plain sentence with the next step beside it: allow
// videos (Android), add a folder (Windows), or open a file the old way.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/settings.dart';
import '../../platform/library_scan.dart' show openAppSettings;
import '../../state/library.dart';
import '../../state/notice.dart';
import '../../state/providers.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import 'library_actions.dart';
import 'library_cards.dart';
import 'lobby_actions.dart';

/// Below this width videos and folders are list rows, not cards (a portrait phone).
const double kLibraryListBelow = 600;

/// Below this height the screen is a phone on its side: the Lobby closes up its header, and
/// nothing stays pinned over the little that is left.
const double kShortBelow = 520;

/// Opens Marquee's page in the phone's settings (the way back from a refused permission), with
/// the route in words when the page will not open. Coming back to the app re-reads the
/// permission (`DeviceLibraryNotifier.cameBack`), so the Library fills by itself.
Future<void> openAppSettingsFor(WidgetRef ref) async {
  final notice = ref.read(noticeProvider.notifier);
  if (await openAppSettings()) return;
  notice.show(
    'Open your phone’s Settings, then Apps, Marquee, Permissions, and allow videos.',
    duration: const Duration(seconds: 8),
  );
}

/// Adds a folder through the system picker, with a plain sentence when the picker fails.
Future<void> addFolderFromPicker(WidgetRef ref) async {
  final library = ref.read(deviceLibraryProvider.notifier);
  final notice = ref.read(noticeProvider.notifier);
  try {
    await library.pickAndAddFolder();
  } on Object {
    notice.show("The folder picker couldn't open.");
  }
}

class LibraryPane extends ConsumerStatefulWidget {
  /// The Lobby's top bar and tab switch: the first thing in the scroll.
  final Widget header;
  final Widget footer;
  final bool wide;
  final double margin;
  const LibraryPane({
    super.key,
    required this.header,
    required this.footer,
    required this.wide,
    required this.margin,
  });

  @override
  ConsumerState<LibraryPane> createState() => _LibraryPaneState();
}

class _LibraryPaneState extends ConsumerState<LibraryPane> {
  // Created in initState, not lazily: a pane that never showed its toolbar would first touch a
  // lazy field in dispose, where `ref` may no longer be used.
  late final TextEditingController _search;
  final _searchFocus = FocusNode(debugLabel: 'library search');
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(libraryBrowseProvider).query);
    HardwareKeyboard.instance.addHandler(_keys);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keys);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// F5 looks again, Ctrl+F goes to the search field, Esc steps back out of a search or a
  /// folder. Only while the Library is the page in front (no menu or dialog above it).
  bool _keys(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (ref.read(roomProvider) != Room.lobby) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.f5) {
      _refresh();
      return true;
    }
    if (key == LogicalKeyboardKey.keyF && HardwareKeyboard.instance.isControlPressed) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _searchFocus.requestFocus();
      _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_searchFocus.hasFocus && _search.text.isEmpty) {
        _searchFocus.unfocus();
        return true;
      }
      return ref.read(libraryBrowseProvider.notifier).back();
    }
    return false;
  }

  void _refresh() => unawaited(_lookAgain());

  /// F5, the refresh button, "Look again". There is no spinner, so the answer is said: one
  /// quiet sentence when the scan is back.
  Future<void> _lookAgain() async {
    final library = ref.read(deviceLibraryProvider.notifier);
    final notice = ref.read(noticeProvider.notifier);
    final before = ref.read(deviceLibraryProvider).value?.items.length ?? 0;
    await library.refresh();
    if (!mounted) return;
    final found = (ref.read(deviceLibraryProvider).value?.items.length ?? 0) - before;
    notice.show(
      found > 0
          ? (found == 1 ? 'Found 1 new video.' : 'Found $found new videos.')
          : 'Your library is up to date.',
    );
  }

  Future<void> _sortMenu(Offset at) async {
    final current = ref.read(settingsValueProvider).librarySort;
    final choice = await showHouseMenu<LibrarySort>(context, at, [
      for (final s in LibrarySort.values)
        MenuChoice(s, 'arrow-up-down', s.label, checked: s == current),
    ]);
    if (choice != null && mounted) setLibrarySort(ref, choice);
  }

  @override
  Widget build(BuildContext context) {
    final palette = House.paletteOf(context);
    final library = ref.watch(deviceLibraryProvider).value;
    final listing = ref.watch(libraryListingProvider);
    final allVideos = ref.watch(lobbyViewProvider.select((v) => v.value?.allVideos ?? false));
    final sort = ref.watch(settingsValueProvider.select((s) => s.librarySort));
    // Back (or Esc) clears the search from outside the field: keep the field in step.
    ref.listen(libraryBrowseProvider.select((b) => b.query), (_, q) {
      if (_search.text != q) _search.text = q;
    });
    final size = MediaQuery.sizeOf(context);
    final list = size.width < kLibraryListBelow;
    final margin = widget.margin;
    final onDevice = library?.source == LibrarySource.mediaStore;
    final browse = ref.read(libraryBrowseProvider.notifier);

    final slivers = <Widget>[SliverToBoxAdapter(child: widget.header)];
    if (library == null) {
      // The cache is being read: the bare room for a moment, never "empty".
    } else if (onDevice && library.access == VideoAccess.denied) {
      slivers.add(_fill(_PermissionNote(asked: library.asked)));
    } else if (library.items.isEmpty) {
      slivers.add(_fill(_EmptyNote(library: library, onRefresh: _refresh)));
    } else {
      final toolbar = _Toolbar(
        search: _search,
        searchFocus: _searchFocus,
        twoRows: list,
        showCount: widget.wide,
        margin: margin,
        allVideos: allVideos,
        sort: sort,
        total: listing.total,
        desktop: !onDevice,
        onQuery: browse.setQuery,
        onAllVideos: (all) {
          browse.closeFolder();
          ref.read(lobbyViewProvider.notifier).setAllVideos(all);
        },
        onSort: (at) => unawaited(_sortMenu(at)),
        onRefresh: _refresh,
        onAddFolder: () => unawaited(addFolderFromPicker(ref)),
      );
      slivers.add(
        SliverPersistentHeader(
          // On a short screen (a phone on its side) the toolbar scrolls away with the page.
          pinned: size.height >= kShortBelow,
          delegate: _ToolbarDelegate(
            height: _Toolbar.heightFor(twoRows: list),
            background: palette.bg,
            child: toolbar,
          ),
        ),
      );
      if (library.access == VideoAccess.partial) {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(margin, 0, margin, Tokens.space2),
            sliver: const SliverToBoxAdapter(child: _PartialAccessLine()),
          ),
        );
      }
      final folder = listing.folder;
      if (folder != null) {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(margin - Tokens.space2, 0, margin, Tokens.space2),
            sliver: SliverToBoxAdapter(
              child: _FolderHeading(folder: folder, onBack: browse.closeFolder),
            ),
          ),
        );
      } else if (listing.query.isNotEmpty) {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(margin, Tokens.space2, margin, Tokens.space3),
            sliver: SliverToBoxAdapter(
              child: Text(
                listing.videos.length == 1
                    ? '1 video found'
                    : '${listing.videos.length} videos found',
                style: Txt.mono(Tokens.textXs, palette.inkFaint),
              ),
            ),
          ),
        );
      }

      if (listing.showsFolders) {
        slivers.add(
          _tiles(
            count: listing.folders.length,
            list: list,
            builder: (context, i) {
              final f = listing.folders[i];
              return LibraryFolderTile(
                key: ValueKey('folder-${f.path}'),
                folder: f,
                list: list,
                onOpen: () {
                  browse.openFolder(f.path);
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                },
              );
            },
          ),
        );
      } else if (listing.videos.isEmpty) {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: margin, vertical: Tokens.space6),
            sliver: SliverToBoxAdapter(
              child: _NoMatch(
                query: listing.query,
                onClear: () {
                  _search.clear();
                  browse.setQuery('');
                },
              ),
            ),
          ),
        );
      } else {
        final acrossFolders = folder == null;
        slivers.add(
          _tiles(
            count: listing.videos.length,
            list: list,
            builder: (context, i) {
              final v = listing.videos[i];
              return LibraryVideoTile(
                key: ValueKey('lib-${v.locator}'),
                item: v,
                list: list,
                showFolder: acrossFolders,
              );
            },
          ),
        );
      }
      // The credits sit at the foot of the screen when the list is short (never floating
      // under the last row like stray content), and scroll away after a long one as before.
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Align(alignment: Alignment.bottomCenter, child: widget.footer),
        ),
      );
    }

    final Widget scroll = CustomScrollView(
      controller: _scroll,
      // Short lists must still pull to refresh.
      physics: onDevice ? const AlwaysScrollableScrollPhysics() : null,
      slivers: slivers,
    );
    if (!onDevice) return scroll;
    return RefreshIndicator(
      color: palette.accent,
      backgroundColor: palette.bgElevated,
      onRefresh: () => ref.read(deviceLibraryProvider.notifier).refresh(),
      child: scroll,
    );
  }

  /// A note centred in what is left of the screen under the header (and simply as tall as it
  /// needs to be when that is not enough: the page scrolls). Sized from the sliver's own
  /// constraints rather than SliverFillRemaining, which would measure the note's intrinsic
  /// height on every layout.
  Widget _fill(Widget child) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final rest = constraints.viewportMainAxisExtent - constraints.precedingScrollExtent;
      return SliverToBoxAdapter(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: rest > 0 ? rest : 0),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.margin, vertical: Tokens.space6),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: child),
            ),
          ),
        ),
      );
    },
  );

  /// Folders or videos, as lazy list rows or a lazy grid of as many columns as fit.
  Widget _tiles({
    required int count,
    required bool list,
    required NullableIndexedWidgetBuilder builder,
  }) {
    final margin = widget.margin;
    if (list) {
      return SliverPadding(
        // Rows pad themselves by space2 so their hover wash is a little wider than the text.
        padding: EdgeInsets.symmetric(horizontal: margin - Tokens.space2),
        sliver: SliverList.builder(itemCount: count, itemBuilder: builder),
      );
    }
    final textHeight = libraryCardTextHeight(context);
    // A phone on its side is wide but not tall: smaller cards there, so a whole row of videos
    // (and the top of the next) fits under the bar and the toolbar.
    final short = MediaQuery.sizeOf(context).height < kShortBelow;
    final minCard = widget.wide && !short ? 220.0 : 168.0;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(margin, Tokens.space2, margin, 0),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const gap = Tokens.space4;
          final width = constraints.crossAxisExtent;
          final columns = ((width + gap) / (minCard + gap)).floor().clamp(2, 8);
          final cardWidth = (width - gap * (columns - 1)) / columns;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: gap,
              mainAxisSpacing: Tokens.space5,
              mainAxisExtent: cardWidth * 9 / 16 + textHeight,
            ),
            delegate: SliverChildBuilderDelegate(builder, childCount: count),
          );
        },
      ),
    );
  }
}

// ───────────────────────────── the toolbar ─────────────────────────────

class _ToolbarDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Color background;
  final Widget child;
  _ToolbarDelegate({required this.height, required this.background, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      // Clear over the room at rest; a ground of its own once cards scroll under it.
      ColoredBox(
        color: overlapsContent
            ? background.withValues(alpha: 0.96)
            : background.withValues(alpha: 0),
        child: child,
      );

  @override
  bool shouldRebuild(_ToolbarDelegate old) =>
      old.height != height || old.background != background || old.child != child;
}

class _Toolbar extends StatelessWidget {
  final TextEditingController search;
  final FocusNode searchFocus;
  final bool twoRows;
  final bool showCount;
  final double margin;
  final bool allVideos;
  final LibrarySort sort;
  final int total;

  /// A folder library (Windows): a refresh button and "Add folder" (a phone pulls to refresh).
  final bool desktop;
  final ValueChanged<String> onQuery;
  final ValueChanged<bool> onAllVideos;
  final ValueChanged<Offset> onSort;
  final VoidCallback onRefresh;
  final VoidCallback onAddFolder;
  const _Toolbar({
    required this.search,
    required this.searchFocus,
    required this.twoRows,
    required this.showCount,
    required this.margin,
    required this.allVideos,
    required this.sort,
    required this.total,
    required this.desktop,
    required this.onQuery,
    required this.onAllVideos,
    required this.onSort,
    required this.onRefresh,
    required this.onAddFolder,
  });

  static const double _row = 44;
  static const double _pad = Tokens.space2;

  static double heightFor({required bool twoRows}) =>
      twoRows ? _pad + _row + Tokens.space2 + _row + _pad : _pad + _row + _pad;

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final field = _SearchField(controller: search, focusNode: searchFocus, onChanged: onQuery);
    final views = SegmentedChoice<bool>(
      key: const ValueKey('library-views'),
      groupLabel: 'Show',
      value: allVideos,
      onChanged: onAllVideos,
      segments: const [
        Segment(false, 'Folders', icon: 'folder'),
        Segment(true, 'All videos', icon: 'film'),
      ],
    );
    final sortMark = Builder(
      builder: (context) => IconMark(
        key: const ValueKey('library-sort'),
        icon: 'arrow-up-down',
        label: 'Sort: ${sort.label}',
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          onSort(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
        },
      ),
    );
    final extras = [
      if (desktop) ...[
        IconMark(
          key: const ValueKey('library-add-folder'),
          icon: 'folder-plus',
          label: 'Add folder',
          onTap: onAddFolder,
        ),
        IconMark(
          key: const ValueKey('library-refresh'),
          icon: 'refresh-cw',
          label: 'Look for new videos (F5)',
          onTap: onRefresh,
        ),
      ],
    ];
    final Widget content;
    if (twoRows) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _row,
            child: Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: Tokens.space1),
                sortMark,
                ...extras,
              ],
            ),
          ),
          const SizedBox(height: Tokens.space2),
          SizedBox(
            height: _row,
            child: Row(
              children: [
                views,
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: Text(
                    total == 1 ? '1 video' : '$total videos',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    textAlign: TextAlign.end,
                    style: Txt.mono(Tokens.textXs, p.inkFaint),
                  ),
                ),
                const SizedBox(width: Tokens.space2),
              ],
            ),
          ),
        ],
      );
    } else {
      content = SizedBox(
        height: _row,
        child: Row(
          children: [
            // The field takes what the view switch leaves, up to a comfortable width; the
            // rest of the row stays empty between them and the marks on the right.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: field,
                    ),
                  ),
                  const SizedBox(width: Tokens.space3),
                  views,
                ],
              ),
            ),
            if (showCount)
              Padding(
                padding: const EdgeInsets.only(right: Tokens.space2),
                child: Text(
                  '${total == 1 ? '1 video' : '$total videos'} · ${sort.label}',
                  maxLines: 1,
                  softWrap: false,
                  style: Txt.mono(Tokens.textXs, p.inkFaint),
                ),
              ),
            sortMark,
            ...extras,
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, _pad, margin - Tokens.space2, _pad),
      child: content,
    );
  }
}

/// The search box: one quiet line, a glass on the left and a clear button once there is text.
/// The box is drawn here, not by the text field's own decoration: that one changes height with
/// the platform's density (shorter on desktop), and this must line up with the controls beside
/// it everywhere.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.focusNode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return ListenableBuilder(
      listenable: focusNode,
      // The whole box takes the click, not only the line of text inside it.
      builder: (context, field) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onTap: focusNode.requestFocus,
        child: AnimatedContainer(
          duration: Tokens.durFast,
          height: 44,
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
            border: Border.all(
              color: focusNode.hasFocus ? p.accent : p.border,
              width: focusNode.hasFocus ? 1.5 : 1,
            ),
          ),
          child: field,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: Tokens.space3),
          LucideIcon('search', color: p.inkMuted, size: 18),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Semantics(
              label: 'Search your videos',
              child: TextField(
                key: const ValueKey('library-search'),
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 1,
                textInputAction: TextInputAction.search,
                style: Txt.body(Tokens.textBase, p.ink),
                cursorColor: p.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search videos',
                  hintStyle: Txt.body(Tokens.textBase, p.inkFaint),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: Tokens.space3)
                : Pressable(
                    label: 'Clear the search',
                    radius: Tokens.radiusFull,
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    builder: (context, s) => SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: LucideIcon('x', color: s.lit ? p.ink : p.inkMuted, size: 16),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── headings and notes ─────────────────────────────

class _FolderHeading extends StatelessWidget {
  final LibraryFolder folder;
  final VoidCallback onBack;
  const _FolderHeading({required this.folder, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Row(
      children: [
        IconMark(
          key: const ValueKey('library-folder-back'),
          icon: 'arrow-left',
          label: 'Back to folders',
          onTap: onBack,
        ),
        const SizedBox(width: Tokens.space1),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              folder.name.isEmpty ? 'Videos' : folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: Tokens.space3),
        Text(folderMeta(folder), style: Txt.mono(Tokens.textXs, p.inkFaint)),
      ],
    );
  }
}

class _NoMatch extends StatelessWidget {
  final String query;
  final VoidCallback onClear;
  const _NoMatch({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          query.isEmpty ? 'Nothing here yet.' : 'No video matches “$query”.',
          textAlign: TextAlign.center,
          style: Txt.body(Tokens.textBase, p.inkMuted),
        ),
        if (query.isNotEmpty) ...[
          const SizedBox(height: Tokens.space2),
          TextAction('Clear the search', primary: true, onTap: onClear),
        ],
      ],
    );
  }
}

/// Android 14's "selected videos": say that the list is partial, and offer more.
class _PartialAccessLine extends ConsumerWidget {
  const _PartialAccessLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = House.paletteOf(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Tokens.space1,
      children: [
        Text('Showing only the videos you picked.', style: Txt.body(Tokens.textSm, p.inkMuted)),
        TextAction(
          'Pick more',
          primary: true,
          onTap: () => unawaited(ref.read(deviceLibraryProvider.notifier).requestAccess()),
        ),
      ],
    );
  }
}

/// One plain sentence, a smaller second one, and what to do next.
class _Note extends StatelessWidget {
  final String icon;
  final String title;
  final String? body;
  final List<Widget> actions;
  const _Note({required this.icon, required this.title, this.body, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LucideIcon(icon, color: p.inkFaint, size: 32),
        const SizedBox(height: Tokens.space4),
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w500),
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: Tokens.space2),
          Text(body!, textAlign: TextAlign.center, style: Txt.body(Tokens.textSm, p.inkMuted)),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: Tokens.space6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Tokens.space3,
            runSpacing: Tokens.space3,
            children: actions,
          ),
        ],
      ],
    );
  }
}

/// Android, before (or without) the video permission.
class _PermissionNote extends ConsumerWidget {
  /// The system dialog has already been answered with a no.
  final bool asked;
  const _PermissionNote({required this.asked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void ask() => unawaited(ref.read(deviceLibraryProvider.notifier).requestAccess());
    if (!asked) {
      return _Note(
        icon: 'library',
        title: 'See every video on this device here, ready to play.',
        body: 'Marquee only reads the list. Nothing leaves your device.',
        actions: [
          HouseButton(
            key: const ValueKey('library-allow'),
            label: 'Show my videos',
            icon: 'film',
            kind: ButtonKind.primary,
            large: true,
            onPressed: ask,
          ),
        ],
      );
    }
    // Android stops showing its dialog once it has been refused, so "ask again" could do
    // nothing at all. The app's page in the phone's settings always works, and so does the
    // file picker.
    return _Note(
      icon: 'library',
      title: "Marquee isn't allowed to list your videos.",
      body:
          'To see them all here, open app settings, tap Permissions and allow videos. '
          'You can still open any one video with Open file.',
      actions: [
        HouseButton(
          key: const ValueKey('library-app-settings'),
          label: 'Open app settings',
          icon: 'settings-2',
          kind: ButtonKind.primary,
          large: true,
          onPressed: () => unawaited(openAppSettingsFor(ref)),
        ),
        HouseButton(
          key: const ValueKey('library-open-file'),
          label: 'Open file',
          icon: 'folder-open',
          large: true,
          onPressed: () => unawaited(openPickedFile(ref)),
        ),
      ],
    );
  }
}

/// Allowed to look, and nothing there (yet).
class _EmptyNote extends ConsumerWidget {
  final DeviceLibrary library;
  final VoidCallback onRefresh;
  const _EmptyNote({required this.library, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = House.paletteOf(context);
    if (library.source == LibrarySource.mediaStore) {
      // Just allowed: the first scan is still on its way, so "none yet" would be a lie.
      if (!library.scanned || (library.scanning && library.items.isEmpty)) {
        return _looking(palette);
      }
      return _Note(
        icon: 'film',
        title: 'No videos on this device yet.',
        body: library.access == VideoAccess.partial
            ? 'Marquee can only see the videos you picked.'
            : 'Videos you download or record will show up here.',
        actions: [
          if (library.access == VideoAccess.partial)
            HouseButton(
              label: 'Pick videos',
              icon: 'film',
              kind: ButtonKind.primary,
              onPressed: () => unawaited(ref.read(deviceLibraryProvider.notifier).requestAccess()),
            ),
          HouseButton(
            label: 'Open file',
            icon: 'folder-open',
            onPressed: () => unawaited(openPickedFile(ref)),
          ),
          HouseButton(label: 'Look again', kind: ButtonKind.ghost, onPressed: onRefresh),
        ],
      );
    }

    final folders = ref.watch(libraryFoldersProvider).value;
    if (folders == null) return const SizedBox.shrink();
    if (folders.isEmpty) {
      final suggestions = ref.watch(librarySuggestionsProvider).value ?? const <String>[];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Note(
            icon: 'library',
            title: 'Choose where you keep your videos.',
            body: 'Marquee lists every video in those folders, ready to play. Nothing is moved.',
          ),
          const SizedBox(height: Tokens.space5),
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space2),
              child: _SuggestedFolder(path: s),
            ),
          const SizedBox(height: Tokens.space2),
          HouseButton(
            key: const ValueKey('library-add-folder'),
            label: suggestions.isEmpty ? 'Add folder…' : 'Add another folder…',
            icon: 'folder-plus',
            kind: suggestions.isEmpty ? ButtonKind.primary : ButtonKind.secondary,
            large: suggestions.isEmpty,
            onPressed: () => unawaited(addFolderFromPicker(ref)),
          ),
        ],
      );
    }
    if (library.scanning || !library.scanned) return _looking(palette);
    return _Note(
      icon: 'film',
      title: folders.length == 1
          ? 'No videos in ${pathLeaf(folders.single)} yet.'
          : 'No videos in your ${folders.length} folders yet.',
      body: 'Add another folder, or look again after copying videos in.',
      actions: [
        HouseButton(
          key: const ValueKey('library-add-folder'),
          label: 'Add folder…',
          icon: 'folder-plus',
          kind: ButtonKind.primary,
          onPressed: () => unawaited(addFolderFromPicker(ref)),
        ),
        HouseButton(label: 'Look again', icon: 'refresh-cw', onPressed: onRefresh),
      ],
    );
  }

  /// The first scan is running. A sentence, not a spinner.
  Widget _looking(HousePalette palette) => Text(
    'Looking for your videos…',
    textAlign: TextAlign.center,
    style: Txt.body(Tokens.textBase, palette.inkMuted),
  );
}

/// A one-tap suggestion on first run: Videos, Downloads.
class _SuggestedFolder extends ConsumerWidget {
  final String path;
  const _SuggestedFolder({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = House.paletteOf(context);
    final name = pathLeaf(path);
    return Pressable(
      key: ValueKey('library-suggest-$name'),
      label: 'Add the $name folder, $path',
      onTap: () => unawaited(ref.read(deviceLibraryProvider.notifier).addLibraryFolder(path)),
      radius: Tokens.radiusMd,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4, vertical: Tokens.space2),
        decoration: BoxDecoration(
          color: s.pressed
              ? palette.ink.withValues(alpha: 0.14)
              : palette.ink.withValues(alpha: s.hovered ? 0.1 : 0.05),
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          border: Border.all(color: s.lit ? palette.inkFaint : palette.borderStrong),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              LucideIcon('folder', color: palette.accent, size: 20),
              const SizedBox(width: Tokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.body(Tokens.textBase, palette.ink, weight: FontWeight.w600),
                    ),
                    Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.mono(Tokens.textXs, palette.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.space3),
              Text(
                'Add',
                style: Txt.body(Tokens.textBase, palette.accent, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
