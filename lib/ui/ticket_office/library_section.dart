// Settings · Library: the folders Marquee watches, and the backup file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/files.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../lobby/library_folders.dart';
import 'parts.dart';

class LibrarySection extends ConsumerStatefulWidget {
  const LibrarySection({super.key});

  @override
  ConsumerState<LibrarySection> createState() => _LibraryState();
}

class _LibraryState extends ConsumerState<LibrarySection> {
  String? _sentence;
  bool _ok = true;

  void _say(String s, {bool ok = true}) {
    if (mounted) {
      setState(() {
        _sentence = s;
        _ok = ok;
      });
    }
  }

  Future<void> _export() async {
    final name = ref.read(sessionProvider.notifier).exportName();
    final actions = ref.read(libraryActionsProvider);
    try {
      final json = await actions.export(Platform.operatingSystem);
      if (!await saveJsonFile(name, prettyJson(json))) return;
    } on FileSystemException {
      _say("That folder can't be written to. Try another one.", ok: false);
      return;
    } on Object {
      _say("The library couldn't be exported.", ok: false);
      return;
    }
    _say('Library exported.');
  }

  Future<void> _import() async {
    final actions = ref.read(libraryActionsProvider);
    try {
      final path = await pickJson();
      if (path == null) return;
      final j = jsonDecode(await File(path).readAsString());
      if (j is! Map<String, Object?>) {
        throw const FormatException("That file isn't a Marquee library export.");
      }
      await actions.import(j);
      _say('Library imported and merged with this one.');
    } on FormatException catch (e) {
      _say(e.message.isEmpty ? "That file isn't a Marquee library export." : e.message, ok: false);
    } on FileSystemException {
      _say("That file couldn't be read.", ok: false);
    } on Object {
      _say("That file couldn't be imported.", ok: false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // The folders card belongs to the Lobby's library feature; the gap is a SettingsGroup's.
      const Padding(
        padding: EdgeInsets.only(top: Tokens.space4),
        child: LibraryFoldersCard(),
      ),
      SettingsGroup(
        title: 'Back up your library',
        helper:
            'One small file with the videos you have played, where you stopped in each, your '
            'subtitle timing and your settings. '
            'Use it to move to a new computer or phone; importing merges, nothing is lost.',
        children: [
          Wrap(
            spacing: Tokens.space3,
            runSpacing: Tokens.space3,
            children: [
              HouseButton(
                label: 'Export library…',
                icon: 'download',
                onPressed: () => unawaited(_export()),
              ),
              HouseButton(
                label: 'Import library…',
                icon: 'upload',
                onPressed: () => unawaited(_import()),
              ),
            ],
          ),
          if (_sentence != null) ...[
            const SizedBox(height: Tokens.space3),
            StatusLine(_sentence!, ok: _ok),
          ],
        ],
      ),
    ],
  );
}
