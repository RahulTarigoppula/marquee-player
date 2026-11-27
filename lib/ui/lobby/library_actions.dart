// What a video can do from its menu. In the Library: play, play from the start, show its
// details, show in its folder (Windows), share (Android), forget where it stopped. On a Home
// card: the same play, start over and details, and remove the card. Both menus are drawn by
// [showHouseMenu], so they look and read alike. Kept apart from the layout, like
// lobby_actions.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/media.dart';
import '../../engine/sentences.dart';
import '../../platform/files.dart';
import '../../platform/library_scan.dart';
import '../../state/library.dart';
import '../../state/notice.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import 'lobby_actions.dart';

/// One line of a pop-up menu.
class MenuChoice<T> {
  final T value;
  final String icon;
  final String text;

  /// Drawn in the danger ink: only for taking a card off Home. Nothing in the Library is red,
  /// where red would read as "delete the video".
  final bool danger;

  /// The current choice of a pick-one menu: its icon becomes a tick.
  final bool checked;
  const MenuChoice(this.value, this.icon, this.text, {this.danger = false, this.checked = false});
}

/// The Lobby's pop-up menu (the card menu's look) at [globalPosition]; null when dismissed.
Future<T?> showHouseMenu<T>(
  BuildContext context,
  Offset globalPosition,
  List<MenuChoice<T>> choices,
) {
  final house = House.of(context);
  final p = house.palette;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final at = overlay.globalToLocal(globalPosition);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    constraints: const BoxConstraints(minWidth: 220),
    items: [
      for (final c in choices)
        PopupMenuItem<T>(
          value: c.value,
          height: 48,
          child: house.carry(
            Builder(
              builder: (context) {
                final color = c.danger ? (house.matinee ? p.danger : p.accent2Lit) : null;
                return Row(
                  children: [
                    LucideIcon(
                      c.checked ? 'check' : c.icon,
                      color: color ?? (c.checked ? p.accent : p.inkMuted),
                      size: 18,
                    ),
                    const SizedBox(width: Tokens.space3),
                    Flexible(
                      child: Text(
                        c.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.body(
                          Tokens.textBase,
                          color ?? p.ink,
                          weight: c.checked ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
    ],
  );
}

/// Plays a library video. [fromStart] forgets where it stopped first. A file that has gone
/// says so and the library looks again.
Future<void> openLibraryItem(WidgetRef ref, LibraryItem item, {bool fromStart = false}) async {
  final session = ref.read(sessionProvider.notifier);
  final notice = ref.read(noticeProvider.notifier);
  final library = ref.read(deviceLibraryProvider.notifier);
  final card = ref.read(libraryHistoryProvider)[historyKey(item.locator)];
  if (fromStart && card != null) {
    try {
      await library.forgetResume(card);
    } on Object {
      // It resumes instead: the "Start over" notice is still one tap away.
    }
  }
  if (item.locator.startsWith('content://')) {
    // A MediaStore row carries everything the session needs; no round trip to stat it.
    await session.open(
      OpenedFile(locator: item.locator, displayName: item.name, sizeBytes: item.sizeBytes),
    );
    return;
  }
  OpenedFile? file;
  try {
    file = await fileFromPath(item.locator);
  } on Object {
    file = null;
  }
  if (file == null) {
    notice.show('That file has moved or been deleted.');
    unawaited(library.refresh());
    return;
  }
  await session.open(file);
}

/// The first line of either menu: what a tap on the card itself would do.
String _playLine(LobbyCard? card) {
  final resume = card == null ? null : resumeMs(card);
  if (resume != null) return 'Resume from ${clockText(resume)}';
  return card?.finished ?? false ? 'Play again' : 'Play';
}

enum ItemAction { play, restart, details, reveal, share, forget }

/// The video menu (right click, long press, or the more button).
Future<void> showItemMenu(
  BuildContext context,
  WidgetRef ref,
  LibraryItem item,
  Offset globalPosition,
) async {
  final card = ref.read(libraryHistoryProvider)[historyKey(item.locator)];
  final source = ref.read(librarySourceProvider);
  final notice = ref.read(noticeProvider.notifier);
  final pending = ref.read(pendingRemovalsProvider.notifier);
  final resume = card == null ? null : resumeMs(card);
  // The last line takes the video out of the play history: it stays in the Library, so the
  // line says what the viewer loses (their place, or the watched tick), in ordinary ink.
  final watched = card != null && card.finished;
  final choice = await showHouseMenu<ItemAction>(context, globalPosition, [
    MenuChoice(ItemAction.play, 'play', _playLine(card)),
    if (resume != null) const MenuChoice(ItemAction.restart, 'skip-back', 'Play from the start'),
    const MenuChoice(ItemAction.details, 'info', 'Details'),
    if (source == LibrarySource.folders)
      const MenuChoice(ItemAction.reveal, 'folder-open', 'Show in folder')
    else
      const MenuChoice(ItemAction.share, 'share-2', 'Share'),
    if (card != null)
      MenuChoice(
        ItemAction.forget,
        'rotate-ccw',
        watched ? 'Mark as not watched' : 'Forget where I stopped',
      ),
  ]);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case ItemAction.play:
      await openLibraryItem(ref, item);
    case ItemAction.restart:
      await openLibraryItem(ref, item, fromStart: true);
    case ItemAction.details:
      final house = House.of(context);
      await showDialog<void>(
        context: context,
        barrierColor: const Color(0xB3000000),
        builder: (_) => house.carry(LibraryDetailsDialog(item: item, card: card)),
      );
    case ItemAction.reveal:
      if (!await revealInFolder(item.locator)) notice.show("The folder couldn't be opened.");
    case ItemAction.share:
      if (!await shareVideo(item.locator, item.name)) notice.show("That video couldn't be shared.");
    case ItemAction.forget:
      if (card != null) {
        final title = libraryTitle(item.name);
        pending.remove(
          card,
          said: watched
              ? '$title is marked as not watched.'
              : 'Forgot where you stopped in $title.',
        );
      }
  }
}

enum CardAction { play, restart, details, remove }

/// The Home card menu (right click, long press, or the ⋮ button): what the Library's menu
/// offers for the same video, then Remove — last, the only red line, and one that can be undone.
Future<void> showCardMenu(
  BuildContext context,
  WidgetRef ref,
  LobbyCard card,
  Offset globalPosition,
) async {
  final pending = ref.read(pendingRemovalsProvider.notifier);
  final item = _itemFor(ref, card);
  final choice = await showHouseMenu<CardAction>(context, globalPosition, [
    MenuChoice(CardAction.play, 'play', _playLine(card)),
    if (resumeMs(card) != null)
      const MenuChoice(CardAction.restart, 'skip-back', 'Play from the start'),
    const MenuChoice(CardAction.details, 'info', 'Details'),
    const MenuChoice(CardAction.remove, 'trash-2', 'Remove from history', danger: true),
  ]);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case CardAction.play:
      await openCard(ref, card);
    case CardAction.restart:
      await openCard(ref, card, fromStart: true);
    case CardAction.details:
      final house = House.of(context);
      await showDialog<void>(
        context: context,
        barrierColor: const Color(0xB3000000),
        builder: (_) => house.carry(LibraryDetailsDialog(item: item, card: card)),
      );
    case CardAction.remove:
      pending.remove(card);
  }
}

/// A Home card as a library video, for Details: the Library's own entry when the file is in
/// the Library, else what the play history knows (a file opened from elsewhere, or a link).
LibraryItem _itemFor(WidgetRef ref, LobbyCard card) {
  final key = historyKey(card.locator);
  for (final i in ref.read(deviceLibraryProvider).value?.items ?? const <LibraryItem>[]) {
    if (historyKey(i.locator) == key) return i;
  }
  final unknown = DateTime.fromMillisecondsSinceEpoch(0);
  if (card.locator.contains('://')) {
    return LibraryItem(
      locator: card.locator,
      name: card.displayName,
      folderPath: '',
      folderName: '',
      sizeBytes: 0,
      durationMs: card.durationMs,
      modifiedAt: unknown,
    );
  }
  return LibraryItem.fromPath(
    card.locator,
    sizeBytes: 0,
    modifiedAt: unknown,
    durationMs: card.durationMs,
  );
}

/// `English, shown 0.15 s later`: the subtitles a film was last watched with, and the timing
/// fix remembered for it.
String? _subtitlesLine(LobbyCard card) {
  final delay = card.delayMs ?? 0;
  final shift = delay == 0
      ? null
      : '${(delay.abs() / 1000).toStringAsFixed(2)} s ${delay > 0 ? 'later' : 'earlier'}';
  final code = card.subtitleLanguage;
  if (code == null) return shift == null ? null : 'Shown $shift';
  return shift == null ? languageName(code) : '${languageName(code)}, shown $shift';
}

String _date(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

/// "Details": where the file is and what is known about it.
class LibraryDetailsDialog extends StatelessWidget {
  final LibraryItem item;

  /// The play history's row for the same file, when there is one.
  final LobbyCard? card;
  const LibraryDetailsDialog({super.key, required this.item, this.card});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final duration = item.durationMs ?? card?.durationMs;
    final onDevice = item.locator.startsWith('content://');
    final online = remoteSchemes.any((s) => item.locator.toLowerCase().startsWith('$s://'));
    final format = card == null ? null : containerText(card!);
    final subtitles = card == null ? null : _subtitlesLine(card!);
    final rows = <(String, String)>[
      ('Name', item.name),
      if (online)
        ('Link', item.locator)
      else if (!onDevice)
        ('Path', item.locator)
      // A video opened through Android's picker has no folder to name.
      else if (item.folderPath.isNotEmpty)
        ('Folder', '${item.folderPath}/${item.name}'),
      if (item.sizeBytes > 0) ('Size', sizeText(item.sizeBytes)),
      if (duration != null && duration > 0) ('Length', clockText(duration)),
      if (item.width != null && item.height != null && item.width! > 0)
        (
          'Picture',
          [
            '${item.width} × ${item.height}',
            ?resolutionBadge(item.width, item.height),
          ].join('  ·  '),
        ),
      if (format != null) ('Format', format),
      if (subtitles != null) ('Subtitles', subtitles),
      if (item.modifiedAt.millisecondsSinceEpoch > 0) ('Changed', _date(item.modifiedAt)),
      if (card != null && card!.finished)
        ('Watched', 'Yes')
      else if (card != null && card!.inProgress)
        ('Watched', 'Up to ${clockText(card!.positionMs)}'),
    ];
    return Dialog(
      insetPadding: const EdgeInsets.all(Tokens.space5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  libraryTitle(item.name),
                  style: Txt.body(Tokens.textXl, p.ink, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: Tokens.space4),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.space3),
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label.toUpperCase(), style: Txt.label(p.inkFaint)),
                        const SizedBox(height: 2),
                        SelectableText(value, style: Txt.body(Tokens.textBase, p.ink)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: Tokens.space3),
              Align(
                alignment: Alignment.centerRight,
                child: HouseButton(
                  key: const ValueKey('details-close'),
                  label: 'Close',
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
