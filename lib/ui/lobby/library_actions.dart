// What a video in the device library can do: play, play from the start, show its details, show
// in its folder (Windows), share (Android), leave the play history. Kept apart from the layout,
// like lobby_actions.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/media.dart';
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

  /// Drawn in the danger ink (Remove).
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
  final choice = await showHouseMenu<ItemAction>(context, globalPosition, [
    MenuChoice(
      ItemAction.play,
      'play',
      resume != null
          ? 'Resume from ${clockText(resume)}'
          : (card?.finished ?? false ? 'Play again' : 'Play'),
    ),
    if (resume != null) const MenuChoice(ItemAction.restart, 'rotate-ccw', 'Play from the start'),
    const MenuChoice(ItemAction.details, 'info', 'Details'),
    if (source == LibrarySource.folders)
      const MenuChoice(ItemAction.reveal, 'folder-open', 'Show in folder')
    else
      const MenuChoice(ItemAction.share, 'share-2', 'Share'),
    if (card != null)
      const MenuChoice(ItemAction.forget, 'trash-2', 'Remove from history', danger: true),
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
      if (card != null) pending.remove(card);
  }
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
    final where = onDevice
        ? [if (item.folderPath.isNotEmpty) item.folderPath, item.name].join('/')
        : item.locator;
    final rows = <(String, String)>[
      ('Name', item.name),
      (onDevice ? 'Folder' : 'Path', where),
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
