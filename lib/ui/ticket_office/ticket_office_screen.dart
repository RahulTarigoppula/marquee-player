// The Ticket Office: account, settings, backup — and the licence trail, typeset, not hidden.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/models.dart';
import '../../engine/sentences.dart';
import '../../platform/files.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/primitives.dart';
import '../components/room.dart';
import '../components/ticket_strip.dart';

const String kTmdbNotice =
    'This product uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.';

class TicketOfficeScreen extends ConsumerStatefulWidget {
  const TicketOfficeScreen({super.key});

  @override
  ConsumerState<TicketOfficeScreen> createState() => _TicketOfficeScreenState();
}

class _TicketOfficeScreenState extends ConsumerState<TicketOfficeScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _subdl = TextEditingController();
  final _osKey = TextEditingController();
  String? _backupSentence;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _subdl.dispose();
    _osKey.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final pass = _pass.text;
    _pass.clear(); // the password is never kept — not even in the field
    await ref.read(accountProvider.notifier).signIn(_user.text.trim(), pass);
  }

  Future<void> _export() async {
    final name = ref.read(sessionProvider.notifier).exportName();
    final json = await ref.read(libraryActionsProvider).export(Platform.operatingSystem);
    final path = await pickSaveLocation(name);
    if (path == null || !mounted) return;
    try {
      await File(path).writeAsString(prettyJson(json));
    } on FileSystemException {
      if (mounted) setState(() => _backupSentence = "That folder can't be written to.");
      return;
    }
    if (mounted) setState(() => _backupSentence = 'Library exported.');
  }

  Future<void> _import() async {
    final actions = ref.read(libraryActionsProvider);
    final path = await pickJson();
    if (path == null || !mounted) return;
    try {
      final j = jsonDecode(await File(path).readAsString());
      if (j is! Map<String, Object?>) {
        throw const FormatException("That file isn't a Marquee library export.");
      }
      await actions.import(j);
      if (mounted) setState(() => _backupSentence = 'Library imported and merged.');
    } on FormatException catch (e) {
      if (mounted) setState(() => _backupSentence = e.message);
    } on FileSystemException {
      if (mounted) setState(() => _backupSentence = "That file couldn't be read.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final settings = ref.watch(settingsValueProvider);
    final account = ref.watch(accountProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final filmOpen = ref.watch(sessionProvider.select((s) => s != null));
    void edit(Settings Function(Settings) f) =>
        unawaited(ref.read(settingsProvider.notifier).edit(f));

    final left = <Widget>[
      const SectionLabel('OpenSubtitles'),
      TicketStripView(
        strip: ref.watch(ticketStripProvider),
        count: ref.watch(quotaProvider).remaining,
      ),
      const SizedBox(height: Tokens.space3),
      if (!buildHasApiKey) ...[
        Text(
          ref.watch(osKeyProvider)
              ? 'Using your own API key.'
              : 'This build has no OpenSubtitles API key. Create a free one at '
                    'opensubtitles.com → Profile → API consumers, and paste it here.',
          style: Txt.body(Tokens.textSm, ref.watch(osKeyProvider) ? p.inkMuted : p.warning),
        ),
        _Underline(
          controller: _osKey,
          hint: 'OpenSubtitles API key (kept in secure storage)',
          obscure: true,
          onSubmit: (k) => unawaited(ref.read(accountProvider.notifier).setApiKey(k)),
        ),
        const SizedBox(height: Tokens.space3),
      ],
      if (account.status == AccountStatus.signedIn) ...[
        Text(
          'Signed in${account.username == null ? '' : ' as ${account.username}'}',
          style: Txt.body(Tokens.textBase, p.ink),
        ),
        TextAction(
          'Sign out',
          onTap: () => unawaited(ref.read(accountProvider.notifier).signOut()),
        ),
      ] else ...[
        if (account.sentence != null)
          Sentence(
            account.sentence!,
            color: account.status == AccountStatus.expired ? p.warning : p.danger,
          ),
        _Underline(
          controller: _user,
          hint: 'Username',
          error: account.status == AccountStatus.error,
        ),
        _Underline(
          controller: _pass,
          hint: 'Password',
          obscure: true,
          error: account.status == AccountStatus.error,
          onSubmit: (_) => unawaited(_signIn()),
        ),
        TextAction(
          account.status == AccountStatus.signingIn
              ? 'Signing in…'
              : 'Sign in (free, more tickets)',
          primary: true,
          onTap: account.status == AccountStatus.signingIn ? null : () => unawaited(_signIn()),
        ),
      ],
      const SectionLabel('Languages'),
      Wrap(
        spacing: Tokens.space2,
        children: [
          for (final code in [
            'en',
            'hi',
            'ta',
            'te',
            'ml',
            'bn',
            'es',
            'fr',
            'de',
            'ja',
            'ko',
            'pt',
          ])
            _LangChip(
              code: code,
              order: settings.languages.indexOf(code),
              onTap: () => edit((s) {
                final l = [...s.languages];
                if (l.contains(code)) {
                  if (l.length > 1) l.remove(code);
                } else if (l.length < Settings.maxLanguages) {
                  l.add(code);
                }
                return s.copyWith(languages: l);
              }),
            ),
        ],
      ),
      ToggleBulb(
        label: 'Prefer hearing-impaired',
        value: settings.preferHearingImpaired,
        onChanged: (v) => edit((s) => s.copyWith(preferHearingImpaired: v)),
      ),
      ToggleBulb(
        label: 'Save beside file',
        hint: 'Otherwise subtitles live in app storage',
        value: settings.saveBesideFile,
        onChanged: (v) => edit((s) => s.copyWith(saveBesideFile: v)),
      ),
      ToggleBulb(
        label: 'Subdl slot',
        hint: 'Fallback provider — your own free key',
        value: settings.subdlEnabled,
        onChanged: (v) => edit((s) => s.copyWith(subdlEnabled: v)),
      ),
      if (settings.subdlEnabled)
        _Underline(
          controller: _subdl,
          hint: 'Subdl API key (stored in secure storage)',
          obscure: true,
          onSubmit: (k) => unawaited(ref.read(accountProvider.notifier).setSubdlKey(k.trim())),
        ),
    ];

    final right = <Widget>[
      const SectionLabel('Projection'),
      ToggleBulb(
        label: 'Hardware decode',
        hint: settings.hwdec,
        value: settings.hwdec != 'no',
        onChanged: (v) => edit((s) => s.copyWith(hwdec: v ? 'auto-safe' : 'no')),
      ),
      const SectionLabel('Ambience'),
      ToggleBulb(
        label: 'Bias light',
        value: settings.biasLight,
        onChanged: (v) => edit((s) => s.copyWith(biasLight: v)),
      ),
      ToggleBulb(
        label: 'Beam',
        value: settings.beam,
        onChanged: (v) => edit((s) => s.copyWith(beam: v)),
      ),
      ToggleBulb(
        label: 'Haptics',
        value: settings.haptics,
        onChanged: (v) => edit((s) => s.copyWith(haptics: v)),
      ),
      ToggleBulb(
        label: 'Matinee lobby',
        hint: 'Daylight palette for the lobby only; playback is always dark',
        value: settings.lobbyTheme == LobbyTheme.matinee,
        onChanged: (v) =>
            edit((s) => s.copyWith(lobbyTheme: v ? LobbyTheme.matinee : LobbyTheme.auto)),
      ),
      const SectionLabel('Backup'),
      Wrap(
        children: [
          TextAction('Export library', onTap: () => unawaited(_export())),
          TextAction('Import library', onTap: () => unawaited(_import())),
        ],
      ),
      if (_backupSentence != null) Sentence(_backupSentence!),
      const SectionLabel('About'),
      _About(tmdb: settings.tmdbEnabled),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        const Grain(),
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(Tokens.space3),
                child: Row(
                  children: [
                    IconMark(
                      icon: 'arrow-left',
                      label: filmOpen ? 'Back to the film' : 'Back to the lobby',
                      // Reached mid-film from the threading "Sign in" row: go back to the film.
                      onTap: () => ref
                          .read(roomProvider.notifier)
                          .go(filmOpen ? Room.auditorium : Room.lobby),
                    ),
                    Text(
                      'TICKET OFFICE',
                      style: Txt.display(Tokens.text2Xl, p.ink, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.space5,
                    vertical: Tokens.space3,
                  ),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: left,
                              ),
                            ),
                            const SizedBox(width: Tokens.space8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: right,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [...left, ...right],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Underline extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool error;
  final ValueChanged<String>? onSubmit;
  const _Underline({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.error = false,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: !obscure,
        style: Txt.body(Tokens.textBase, p.ink),
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          labelText: hint,
          labelStyle: Txt.body(Tokens.textSm, p.inkMuted),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: error ? p.danger : p.borderStrong),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: error ? p.danger : p.accent, width: 2),
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String code;
  final int order;
  final VoidCallback onTap;
  const _LangChip({required this.code, required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final on = order >= 0;
    return FocusRing(
      child: Semantics(
        toggled: on,
        label: languageName(code),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: Tokens.targetMin,
              minWidth: Tokens.targetMin,
            ),
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: on ? p.accent : p.border)),
            ),
            child: Text(
              on ? '${code.toUpperCase()} ${order + 1}' : code.toUpperCase(),
              style: Txt.mono(Tokens.textSm, on ? p.accent : p.inkMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _About extends StatelessWidget {
  final bool tmdb;
  const _About({required this.tmdb});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    Widget line(String t, {Color? c, bool mono = false}) => Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      child: Text(
        t,
        style: mono
            ? Txt.mono(Tokens.textXs, c ?? p.inkMuted)
            : Txt.body(Tokens.textSm, c ?? p.inkMuted),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('Subtitles by OpenSubtitles.com', c: p.ink),
        if (tmdb) line(kTmdbNotice, c: p.ink),
        line(
          'Playback: libmpv (LGPL-2.1+), FFmpeg (LGPL-3.0, built --disable-gpl --enable-version3) and '
          'libass (ISC), dynamically linked. Build scripts: '
          'github.com/media-kit/libmpv-android-video-build (default flavour) and '
          'github.com/media-kit/libmpv-win32-video-cmake. Licence texts ship in LICENSES/.',
        ),
        line(
          'Fonts: Big Shoulders Display, Geist, Geist Mono, Noto Sans — SIL OFL 1.1. Icons: Lucide (ISC).',
        ),
        line(
          'What leaves this device: the 16-hex moviehash, the file size, a filename-derived query, '
          'the chosen file id and your own OpenSubtitles token — to OpenSubtitles only. Subdl receives a '
          'title query when you enable it. Never the file, a frame, a path or a device id. Nothing is measured or reported.',
        ),
        line('Marquee v$appVersion · MIT', mono: true),
      ],
    );
  }
}
