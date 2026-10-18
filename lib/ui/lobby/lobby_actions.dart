// What the Lobby can do: open a file, a URL or a card; remove a card with an Undo window; the
// card's context menu; the "Open URL" dialog. Kept apart from the layout so the screen reads
// as a room, not as plumbing.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/media.dart';
import '../../platform/files.dart';
import '../../state/notice.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../state/thumbnails.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';

/// How long a removed card can be brought back before it really leaves the library.
const Duration kUndoWindow = Duration(seconds: 6);

/// A card's display title: the identified title, or the cleaned file name.
String cardTitle(LobbyCard c) => c.title ?? cleanFileName(c.displayName);

String cleanFileName(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[._]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// `1h 44m` / `48m`.
String runtimeText(int ms) {
  final m = (ms / 60000).round();
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// A play position as people say it: `42:10`, `1:02:10`.
String clockText(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// `MKV` from libmpv's `matroska,webm`, `MP4` from `mov,mp4,m4a,…`.
String? containerText(LobbyCard c) {
  final raw = c.container;
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('matroska')) return 'MKV';
  if (raw.contains('mp4')) return 'MP4';
  final ext = c.displayName.contains('.') ? c.displayName.split('.').last : '';
  if (ext.isNotEmpty && ext.length <= 4) return ext.toUpperCase();
  return raw.split(',').first.toUpperCase();
}

bool isInProgress(LobbyCard c) => c.resumeFraction > 0.01 && !c.finished;

/// The resume position of [c], when known.
int? resumeMs(LobbyCard c) {
  final d = c.durationMs;
  if (d == null || !isInProgress(c)) return null;
  return (d * c.resumeFraction).round();
}

/// Removals wait out the Undo window before they touch the library, so "Remove" is never one
/// slip of a finger: the card hides at once and a notice offers Undo.
class PendingRemovals extends Notifier<Set<int>> {
  final _timers = <int, Timer>{};

  @override
  Set<int> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
    });
    return const {};
  }

  void remove(LobbyCard card) {
    _timers[card.id]?.cancel();
    state = {...state, card.id};
    _timers[card.id] = Timer(kUndoWindow, () => unawaited(_commit(card.id)));
    ref
        .read(noticeProvider.notifier)
        .show(
          'Removed ${cardTitle(card)} from your library.',
          actionLabel: 'Undo',
          onAction: () => undo(card.id),
          duration: kUndoWindow,
        );
  }

  void undo(int id) {
    _timers.remove(id)?.cancel();
    state = {...state}..remove(id);
  }

  Future<void> _commit(int id) async {
    _timers.remove(id);
    try {
      await ref.read(libraryActionsProvider).remove(id);
      await deleteThumbnail(ref, id);
    } on Object {
      // The row is already gone (or the database is closing): nothing to undo either way.
    }
    state = {...state}..remove(id);
  }
}

final pendingRemovalsProvider = NotifierProvider<PendingRemovals, Set<int>>(PendingRemovals.new);

Future<void> openPickedFile(WidgetRef ref) async {
  final session = ref.read(sessionProvider.notifier);
  final OpenedFile? f;
  try {
    f = await pickVideo();
  } on Object {
    ref.read(noticeProvider.notifier).show("The file picker couldn't open.");
    return;
  }
  if (f != null) await session.open(f);
}

/// Opens a Lobby card. A file that has moved gets a plain sentence and a way to tidy up.
Future<void> openCard(WidgetRef ref, LobbyCard card) async {
  final session = ref.read(sessionProvider.notifier);
  final notice = ref.read(noticeProvider.notifier);
  final pending = ref.read(pendingRemovalsProvider.notifier);
  OpenedFile? f;
  try {
    f = remoteSchemes.any((s) => card.locator.toLowerCase().startsWith('$s://'))
        ? openedFromUrl(card.locator)
        : await fileFromPath(card.locator);
  } on Object {
    f = null;
  }
  if (f == null) {
    notice.show(
      'That file has moved or been deleted.',
      actionLabel: 'Remove',
      onAction: () => pending.remove(card),
    );
    return;
  }
  await session.open(f);
}

/// Asks for a web address and opens it.
Future<void> openUrl(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider.notifier);
  final house = House.of(context);
  final file = await showDialog<OpenedFile>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => house.carry(const OpenUrlDialog()),
  );
  if (file != null) await session.open(file);
}

class OpenUrlDialog extends StatefulWidget {
  /// Pre-filled text (screenshots).
  final String? initialText;
  final bool showErrorInitially;
  const OpenUrlDialog({super.key, this.initialText, this.showErrorInitially = false});

  @override
  State<OpenUrlDialog> createState() => _OpenUrlDialogState();
}

class _OpenUrlDialogState extends State<OpenUrlDialog> {
  late final _text = TextEditingController(text: widget.initialText);
  String? _error;

  static const _invalid =
      "That doesn't look like a video link. It should start with http:// or https://.";

  @override
  void initState() {
    super.initState();
    if (widget.showErrorInitially && openedFromUrl(_text.text) == null) _error = _invalid;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final f = openedFromUrl(_text.text);
    if (f == null) {
      setState(() => _error = _text.text.trim().isEmpty ? 'Paste a link first.' : _invalid);
      return;
    }
    Navigator.of(context).pop(f);
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(Tokens.space5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  LucideIcon('link', color: p.accent, size: 22),
                  const SizedBox(width: Tokens.space3),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Open a web address',
                        style: Txt.body(Tokens.textXl, p.ink, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space2),
              Text(
                'Play a video straight from the internet or your home server.',
                style: Txt.body(Tokens.textBase, p.inkMuted),
              ),
              const SizedBox(height: Tokens.space5),
              HouseField(
                controller: _text,
                label: 'Video link',
                hint: 'https://example.com/film.mp4',
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                error: _error,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: Tokens.space6),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Tokens.space3,
                runSpacing: Tokens.space3,
                children: [
                  HouseButton(
                    label: 'Cancel',
                    kind: ButtonKind.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  HouseButton(
                    key: const ValueKey('url-play'),
                    label: 'Play',
                    icon: 'play',
                    kind: ButtonKind.primary,
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum CardAction { play, remove }

/// The card menu (right click, long press, or the ⋮ button). Remove is the last item and needs
/// a deliberate second tap — and even then it can be undone.
Future<void> showCardMenu(
  BuildContext context,
  WidgetRef ref,
  LobbyCard card,
  Offset globalPosition,
) async {
  final house = House.of(context);
  final p = house.palette;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final at = overlay.globalToLocal(globalPosition);
  final pending = ref.read(pendingRemovalsProvider.notifier);
  final resume = resumeMs(card);
  PopupMenuItem<CardAction> item(CardAction v, String icon, String text, {Color? color}) =>
      PopupMenuItem<CardAction>(
        value: v,
        height: 48,
        child: house.carry(
          Row(
            children: [
              LucideIcon(icon, color: color ?? p.inkMuted, size: 18),
              const SizedBox(width: Tokens.space3),
              Text(text, style: Txt.body(Tokens.textBase, color ?? p.ink)),
            ],
          ),
        ),
      );
  final choice = await showMenu<CardAction>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    constraints: const BoxConstraints(minWidth: 220),
    items: [
      item(
        CardAction.play,
        'play',
        resume != null
            ? 'Resume from ${clockText(resume)}'
            : (card.finished ? 'Play again' : 'Play'),
      ),
      item(
        CardAction.remove,
        'trash-2',
        'Remove from library',
        color: house.matinee ? p.danger : p.accent2Lit,
      ),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case CardAction.play:
      await openCard(ref, card);
    case CardAction.remove:
      pending.remove(card);
    case null:
      break;
  }
}
