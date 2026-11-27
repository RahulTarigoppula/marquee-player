// Where the library looks: the list of library folders with Add and Remove (Windows), or a
// short explanation and the permission's state (Android, where the library is the device's own
// video collection). Self-contained and drawn as its own card: Settings › Library shows it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import 'library_view.dart' show addFolderFromPicker, openAppSettingsFor;

class LibraryFoldersCard extends ConsumerWidget {
  const LibraryFoldersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = House.of(context);
    final p = h.palette;
    final source = ref.watch(librarySourceProvider);
    final onDevice = source == LibrarySource.mediaStore;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space5,
        Tokens.space5,
        Tokens.space5,
        Tokens.space4,
      ),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: h.matinee ? 0.75 : 0.6),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              onDevice ? 'Your videos' : 'Video folders',
              style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: Tokens.space1),
          Text(
            onDevice
                ? 'The Library lists the videos Android already knows about on this device. '
                      'Marquee only reads that list; nothing leaves your device.'
                : 'The Library lists every video in these folders and the folders inside them. '
                      'Nothing is moved or changed.',
            style: Txt.body(Tokens.textSm, p.inkMuted),
          ),
          const SizedBox(height: Tokens.space3),
          if (onDevice) const _DeviceAccess() else const _FolderList(),
        ],
      ),
    );
  }
}

/// A one-line state: a tick when all is well, a warm dot when something is missing.
class _State extends StatelessWidget {
  final String text;
  final bool ok;
  const _State(this.text, {this.ok = true});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final c = ok ? p.success : p.warning;
    return Row(
      children: [
        if (ok) LucideIcon('check', color: c, size: 18) else Bulb(color: c, size: 8),
        const SizedBox(width: Tokens.space2),
        Expanded(
          child: Text(text, style: Txt.body(Tokens.textSm, c, weight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _DeviceAccess extends ConsumerWidget {
  const _DeviceAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(deviceLibraryProvider).value;
    if (library == null) return const SizedBox.shrink();
    void ask() => unawaited(ref.read(deviceLibraryProvider.notifier).requestAccess());
    // Refused once, Android stops showing its dialog: the way back is the app's own page in
    // the phone's settings.
    final refused = library.access == VideoAccess.denied && library.asked;
    final count = library.items.length;
    final (String text, bool ok, String? action) = switch (library.access) {
      VideoAccess.granted => (
        count == 1 ? 'Marquee can see 1 video.' : 'Marquee can see $count videos.',
        true,
        null,
      ),
      VideoAccess.partial => (
        'Marquee can see only the videos you picked ($count).',
        false,
        'Pick more videos',
      ),
      VideoAccess.denied => (
        refused
            ? "Marquee isn't allowed to list your videos. Open app settings, tap Permissions "
                  'and allow videos; Open file works either way.'
            : "Marquee hasn't been allowed to list your videos yet.",
        false,
        refused ? 'Open app settings' : 'Show my videos',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _State(text, ok: ok),
        const SizedBox(height: Tokens.space3),
        Wrap(
          spacing: Tokens.space3,
          runSpacing: Tokens.space3,
          children: [
            if (action != null)
              HouseButton(
                key: const ValueKey('folders-allow'),
                label: action,
                icon: refused ? 'settings-2' : 'film',
                onPressed: refused ? () => unawaited(openAppSettingsFor(ref)) : ask,
              ),
            if (library.access != VideoAccess.denied)
              HouseButton(
                label: 'Look for new videos',
                icon: 'refresh-cw',
                kind: ButtonKind.ghost,
                onPressed: () => unawaited(ref.read(deviceLibraryProvider.notifier).refresh()),
              ),
          ],
        ),
      ],
    );
  }
}

class _FolderList extends ConsumerWidget {
  const _FolderList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = House.paletteOf(context);
    final folders = ref.watch(libraryFoldersProvider).value;
    if (folders == null) return const SizedBox.shrink();
    final suggestions = folders.isEmpty
        ? (ref.watch(librarySuggestionsProvider).value ?? const <String>[])
        : const <String>[];
    final library = ref.read(deviceLibraryProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space3),
            child: Text('No folders yet.', style: Txt.body(Tokens.textBase, p.inkMuted)),
          ),
        for (final f in folders)
          _FolderRow(path: f, onRemove: () => unawaited(library.removeLibraryFolder(f))),
        const SizedBox(height: Tokens.space2),
        Wrap(
          spacing: Tokens.space3,
          runSpacing: Tokens.space3,
          children: [
            HouseButton(
              key: const ValueKey('folders-add'),
              label: 'Add folder…',
              icon: 'folder-plus',
              onPressed: () => unawaited(addFolderFromPicker(ref)),
            ),
            for (final s in suggestions)
              HouseButton(
                label: 'Add ${pathLeaf(s)}',
                icon: 'folder',
                kind: ButtonKind.ghost,
                tooltip: s,
                onPressed: () => unawaited(library.addLibraryFolder(s)),
              ),
          ],
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  const _FolderRow({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final name = pathLeaf(path);
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space1),
      child: Row(
        children: [
          LucideIcon('folder', color: p.accent, size: 20),
          const SizedBox(width: Tokens.space3),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.isEmpty ? path : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w500),
                  ),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.mono(Tokens.textXs, p.inkMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Tokens.space2),
          HouseButton(
            key: ValueKey('folders-remove-$path'),
            label: 'Remove',
            kind: ButtonKind.danger,
            semanticLabel: 'Remove the folder ${name.isEmpty ? path : name} from the library',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
