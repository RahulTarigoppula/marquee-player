// The Ticket Office · Settings. Five plain sections — Subtitles, Playback, Appearance, Library,
// About — each a few cards with a heading and one line of explanation. Desktop: the sections
// down the left, one open on the right. Phone: a list of sections, each opening on its own.
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
import '../components/kit.dart';
import '../components/primitives.dart';
import '../components/room.dart';
import '../components/theme_choice.dart';
import '../components/ticket_strip.dart';

const String kTmdbNotice =
    'This product uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.';

/// Settings switch to the two-pane layout at this width.
const double kSettingsWide = 840;

enum SettingsSection {
  subtitles('Subtitles', 'captions', 'Account, languages, size and style'),
  playback('Playback', 'circle-play', 'Audio language, next episode, decoding'),
  appearance('Appearance', 'sun-moon', 'Theme, projector beam, sounds'),
  library('Library', 'library', 'Back up or move your watch history'),
  about('About', 'info', 'Version, privacy and licences');

  final String title;
  final String icon;
  final String blurb;
  const SettingsSection(this.title, this.icon, this.blurb);
}

/// Languages offered for subtitles and audio, most requested first.
const kOfferedLanguages = [
  'en', 'hi', 'ta', 'te', 'ml', 'bn', 'mr', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'ja', 'ko', //
  'zh', 'ar', 'nl', 'sv', 'pl', 'tr',
];

class TicketOfficeScreen extends ConsumerStatefulWidget {
  /// The section to open on (screenshots, deep links). Phone: null shows the section list.
  final SettingsSection? initialSection;
  const TicketOfficeScreen({super.key, this.initialSection});

  @override
  ConsumerState<TicketOfficeScreen> createState() => _TicketOfficeScreenState();
}

class _TicketOfficeScreenState extends ConsumerState<TicketOfficeScreen> {
  late SettingsSection? _section = widget.initialSection;

  void _leave() {
    final filmOpen = ref.read(sessionProvider) != null;
    // Reached mid-film from the threading "Sign in" row: go back to the film.
    ref.read(roomProvider.notifier).go(filmOpen ? Room.auditorium : Room.lobby);
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final wide = MediaQuery.sizeOf(context).width >= kSettingsWide;
    final filmOpen = ref.watch(sessionProvider.select((s) => s != null));
    final open = wide ? (_section ?? SettingsSection.subtitles) : _section;
    final inSection = !wide && open != null;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? Tokens.space5 : Tokens.space2,
        Tokens.space3,
        Tokens.space5,
        Tokens.space3,
      ),
      child: Row(
        children: [
          IconMark(
            key: const ValueKey('settings-back'),
            icon: 'arrow-left',
            label: inSection
                ? 'Back to all settings'
                : (filmOpen ? 'Back to the film' : 'Back to the lobby'),
            onTap: inSection ? () => setState(() => _section = null) : _leave,
          ),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(inSection ? 'SETTINGS' : 'TICKET OFFICE', style: Txt.label(p.inkFaint)),
                Semantics(
                  header: true,
                  child: Text(
                    inSection ? open.title : 'Settings',
                    style: Txt.body(Tokens.text2Xl, p.ink, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (wide)
            HouseButton(
              label: filmOpen ? 'Back to the film' : 'Done',
              kind: ButtonKind.ghost,
              icon: 'x',
              onPressed: _leave,
            ),
        ],
      ),
    );

    final Widget body;
    if (wide) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 272,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space5,
                Tokens.space2,
                Tokens.space3,
                Tokens.space5,
              ),
              children: [
                for (final s in SettingsSection.values)
                  _NavItem(
                    section: s,
                    selected: s == open,
                    onTap: () => setState(() => _section = s),
                  ),
              ],
            ),
          ),
          Container(width: 1, color: p.border),
          Expanded(
            child: SingleChildScrollView(
              key: PageStorageKey('settings-${open!.name}'),
              padding: const EdgeInsets.fromLTRB(
                Tokens.space8,
                Tokens.space2,
                Tokens.space8,
                Tokens.space10,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _SectionBody(section: open),
                ),
              ),
            ),
          ),
        ],
      );
    } else if (open == null) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.marginPhone,
          Tokens.space2,
          Tokens.marginPhone,
          Tokens.space8,
        ),
        children: [
          for (final s in SettingsSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space2),
              child: _SectionTile(section: s, onTap: () => setState(() => _section = s)),
            ),
        ],
      );
    } else {
      body = SingleChildScrollView(
        key: PageStorageKey('settings-${open.name}'),
        padding: const EdgeInsets.fromLTRB(
          Tokens.marginPhone,
          Tokens.space2,
          Tokens.marginPhone,
          Tokens.space10,
        ),
        child: _SectionBody(section: open),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const Grain(),
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(child: body),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.section, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space1),
      child: Pressable(
        key: ValueKey('nav-${section.name}'),
        selected: selected,
        label: section.title,
        onTap: onTap,
        builder: (context, s) => AnimatedContainer(
          duration: Tokens.durFast,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
          decoration: BoxDecoration(
            color: selected ? p.surface2 : pressWash(p, s),
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                LucideIcon(section.icon, color: selected ? p.accent : p.inkMuted, size: 20),
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: Text(
                    section.title,
                    style: Txt.body(
                      Tokens.textBase,
                      selected ? p.ink : p.inkMuted,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final SettingsSection section;
  final VoidCallback onTap;
  const _SectionTile({required this.section, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Pressable(
      key: ValueKey('tile-${section.name}'),
      label: section.title,
      hint: section.blurb,
      onTap: onTap,
      radius: Tokens.radiusLg,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4, vertical: Tokens.space4),
        decoration: BoxDecoration(
          color: s.lit ? p.surface2 : p.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          border: Border.all(color: p.border),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.ink.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(Tokens.radiusMd),
                ),
                child: Center(child: LucideIcon(section.icon, color: p.accent, size: 20)),
              ),
              const SizedBox(width: Tokens.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w600),
                    ),
                    Text(section.blurb, style: Txt.body(Tokens.textSm, p.inkMuted)),
                  ],
                ),
              ),
              LucideIcon('chevron-right', color: p.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card of related settings: a heading, one line of help, then the controls.
class _Group extends StatelessWidget {
  final String title;
  final String? helper;
  final List<Widget> children;
  const _Group({required this.title, this.helper, required this.children});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    return Container(
      margin: const EdgeInsets.only(top: Tokens.space4),
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
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w600)),
          ),
          if (helper != null) ...[
            const SizedBox(height: Tokens.space1),
            Text(helper!, style: Txt.body(Tokens.textSm, p.inkMuted)),
          ],
          const SizedBox(height: Tokens.space3),
          ...children,
        ],
      ),
    );
  }
}

/// A small label above a control inside a group ("Style", "Position").
class _ControlLabel extends StatelessWidget {
  final String text;
  const _ControlLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Tokens.space2),
    child: Text(
      text,
      style: Txt.body(Tokens.textBase, House.paletteOf(context).ink, weight: FontWeight.w500),
    ),
  );
}

/// A one-line status with a tick (saved, signed in) or a warning dot.
class _Status extends StatelessWidget {
  final String text;
  final bool ok;
  const _Status(this.text, {this.ok = true});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final c = ok ? p.success : p.warning;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          if (ok) LucideIcon('check', color: c, size: 18) else Bulb(color: c, size: 8),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Text(text, style: Txt.body(Tokens.textSm, c, weight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  final SettingsSection section;
  const _SectionBody({required this.section});

  @override
  Widget build(BuildContext context) => switch (section) {
    SettingsSection.subtitles => const _SubtitlesSection(),
    SettingsSection.playback => const _PlaybackSection(),
    SettingsSection.appearance => const _AppearanceSection(),
    SettingsSection.library => const _LibrarySection(),
    SettingsSection.about => const _AboutSection(),
  };
}

void _edit(WidgetRef ref, Settings Function(Settings) f) =>
    unawaited(ref.read(settingsProvider.notifier).edit(f));

// ───────────────────────────── Subtitles ─────────────────────────────

class _SubtitlesSection extends ConsumerStatefulWidget {
  const _SubtitlesSection();

  @override
  ConsumerState<_SubtitlesSection> createState() => _SubtitlesSectionState();
}

class _SubtitlesSectionState extends ConsumerState<_SubtitlesSection> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _osKey = TextEditingController();
  final _subdl = TextEditingController();
  bool _osKeyJustSaved = false;
  bool _subdlSaved = false;
  bool _subdlJustSaved = false;
  double? _scaleDraft;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSubdl());
  }

  Future<void> _loadSubdl() async {
    try {
      final k = await ref.read(accountProvider.notifier).subdlKey();
      if (mounted) setState(() => _subdlSaved = k != null && k.isNotEmpty);
    } on Object {
      // Secure storage unavailable: show the field as empty.
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _osKey.dispose();
    _subdl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final pass = _pass.text;
    _pass.clear(); // the password is never kept — not even in the field
    await ref.read(accountProvider.notifier).signIn(_user.text.trim(), pass);
  }

  Future<void> _saveOsKey({bool remove = false}) async {
    final key = remove ? '' : _osKey.text.trim();
    if (!remove && key.isEmpty) return;
    await ref.read(accountProvider.notifier).setApiKey(key);
    _osKey.clear();
    if (mounted) setState(() => _osKeyJustSaved = !remove);
  }

  Future<void> _saveSubdl({bool remove = false}) async {
    final key = remove ? '' : _subdl.text.trim();
    if (!remove && key.isEmpty) return;
    try {
      await ref.read(accountProvider.notifier).setSubdlKey(key);
    } on Object {
      return;
    }
    _subdl.clear();
    if (mounted) {
      setState(() {
        _subdlSaved = !remove;
        _subdlJustSaved = !remove;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final settings = ref.watch(settingsValueProvider);
    final account = ref.watch(accountProvider);
    final hasKey = ref.watch(osKeyProvider);
    final signedIn = account.status == AccountStatus.signedIn;
    final signingIn = account.status == AccountStatus.signingIn;
    final scale = _scaleDraft ?? settings.subtitleScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          title: 'OpenSubtitles account',
          helper:
              'Marquee finds subtitles on OpenSubtitles.com. It works without an account; '
              'a free account gives you more downloads each day.',
          children: [
            TicketStripView(
              strip: ref.watch(ticketStripProvider),
              count: ref.watch(quotaProvider).remaining,
            ),
            const SizedBox(height: Tokens.space4),
            if (signedIn)
              Row(
                children: [
                  LucideIcon('user', color: p.inkMuted, size: 20),
                  const SizedBox(width: Tokens.space2),
                  Expanded(
                    child: Text(
                      account.username == null ? 'Signed in' : 'Signed in as ${account.username}',
                      style: Txt.body(Tokens.textBase, p.ink, weight: FontWeight.w500),
                    ),
                  ),
                  HouseButton(
                    label: 'Sign out',
                    kind: ButtonKind.danger,
                    onPressed: () => unawaited(ref.read(accountProvider.notifier).signOut()),
                  ),
                ],
              )
            else ...[
              if (account.sentence != null) ...[
                Sentence(
                  account.sentence!,
                  color: account.status == AccountStatus.expired ? p.warning : p.danger,
                ),
                const SizedBox(height: Tokens.space3),
              ],
              HouseField(
                controller: _user,
                label: 'Username',
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                error: account.status == AccountStatus.error ? '' : null,
              ),
              const SizedBox(height: Tokens.space3),
              HouseField(
                controller: _pass,
                label: 'Password',
                obscure: true,
                autofillHints: const [AutofillHints.password],
                helper: 'Used once to sign in. Marquee never stores your password.',
                error: account.status == AccountStatus.error ? '' : null,
                onSubmitted: (_) => unawaited(_signIn()),
              ),
              const SizedBox(height: Tokens.space4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Tokens.space4,
                runSpacing: Tokens.space2,
                children: [
                  HouseButton(
                    key: const ValueKey('sign-in'),
                    label: signingIn ? 'Signing in…' : 'Sign in',
                    kind: ButtonKind.primary,
                    onPressed: signingIn ? null : () => unawaited(_signIn()),
                  ),
                  Text(
                    'No account? Create one free at opensubtitles.com',
                    style: Txt.body(Tokens.textSm, p.inkMuted),
                  ),
                ],
              ),
            ],
          ],
        ),
        if (!buildHasApiKey)
          _Group(
            title: 'OpenSubtitles API key',
            helper:
                'This copy of Marquee was built without a key, so it needs yours (free). '
                'Sign in at opensubtitles.com, open your profile, choose "API consumers", create '
                'a consumer and paste its key here.',
            children: [
              if (hasKey)
                _Status(
                  _osKeyJustSaved
                      ? 'Saved. Subtitle search is on.'
                      : 'A key is saved. Subtitle search is on.',
                )
              else
                const _Status('No key yet, so subtitles cannot be searched.', ok: false),
              const SizedBox(height: Tokens.space3),
              HouseField(
                controller: _osKey,
                label: hasKey ? 'Replace the key' : 'API key',
                hint: 'Paste your key',
                obscure: true,
                helper: 'Kept in your device\'s secure storage.',
                onSubmitted: (_) => unawaited(_saveOsKey()),
              ),
              const SizedBox(height: Tokens.space3),
              Wrap(
                spacing: Tokens.space2,
                runSpacing: Tokens.space2,
                children: [
                  HouseButton(
                    key: const ValueKey('save-os-key'),
                    label: 'Save key',
                    icon: 'check',
                    onPressed: () => unawaited(_saveOsKey()),
                  ),
                  if (hasKey)
                    HouseButton(
                      label: 'Remove key',
                      kind: ButtonKind.danger,
                      onPressed: () => unawaited(_saveOsKey(remove: true)),
                    ),
                ],
              ),
            ],
          ),
        _Group(
          title: 'Languages',
          helper:
              'Pick up to ${Settings.maxLanguages}, in the order you prefer. '
              'Tap a language again to remove it.',
          children: [
            _LanguagePicker(
              selected: settings.languages,
              allowEmpty: false,
              semanticPrefix: 'Subtitle language',
              onChanged: (l) => _edit(ref, (s) => s.copyWith(languages: l)),
            ),
          ],
        ),
        _Group(
          title: 'Finding subtitles',
          children: [
            ToggleBulb(
              label: 'Use subtitles inside the video first',
              hint:
                  'If the file already has subtitles in your language, use them instead of '
                  'searching online.',
              value: settings.preferEmbeddedSubtitles,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(preferEmbeddedSubtitles: v)),
            ),
            ToggleBulb(
              label: 'Prefer subtitles for the hard of hearing',
              hint: 'These also describe sounds, like [door slams].',
              value: settings.preferHearingImpaired,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(preferHearingImpaired: v)),
            ),
            ToggleBulb(
              label: 'Save subtitles next to the video',
              hint: 'Other players will find them too. Off: Marquee keeps them to itself.',
              value: settings.saveBesideFile,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(saveBesideFile: v)),
            ),
          ],
        ),
        _Group(
          title: 'How subtitles look',
          helper: 'Changes show here right away, and on the film next time it plays.',
          children: [
            _SubtitlePreview(
              scale: scale,
              look: settings.subtitleLook,
              placement: settings.subtitlePlacement,
            ),
            const SizedBox(height: Tokens.space5),
            const _ControlLabel('Style'),
            SegmentedChoice<SubtitleLook>(
              key: const ValueKey('subtitle-look'),
              groupLabel: 'Subtitle style',
              value: settings.subtitleLook,
              expand: true,
              segments: const [
                Segment(SubtitleLook.outline, 'Outlined text'),
                Segment(SubtitleLook.box, 'Text on a dark box'),
              ],
              onChanged: (v) => _edit(ref, (s) => s.copyWith(subtitleLook: v)),
            ),
            const SizedBox(height: Tokens.space5),
            HouseSlider(
              label: 'Size',
              value: scale,
              min: Settings.minSubtitleScale,
              max: Settings.maxSubtitleScale,
              divisions: 14,
              valueText: '${(scale * 100).round()}%',
              onChanged: (v) => setState(() => _scaleDraft = v),
              onChangeEnd: (v) {
                setState(() => _scaleDraft = null);
                _edit(ref, (s) => s.copyWith(subtitleScale: v));
              },
            ),
            const SizedBox(height: Tokens.space4),
            const _ControlLabel('Position'),
            SegmentedChoice<SubtitlePlacement>(
              key: const ValueKey('subtitle-placement'),
              groupLabel: 'Subtitle position',
              value: settings.subtitlePlacement,
              expand: true,
              segments: const [
                Segment(SubtitlePlacement.bottom, 'Bottom'),
                Segment(SubtitlePlacement.lowerThird, 'Higher'),
                Segment(SubtitlePlacement.top, 'Top'),
              ],
              onChanged: (v) => _edit(ref, (s) => s.copyWith(subtitlePlacement: v)),
            ),
          ],
        ),
        _Group(
          title: 'Backup source: Subdl',
          helper:
              'A second free subtitle site, searched when OpenSubtitles has nothing. '
              'It needs your own free key from subdl.com.',
          children: [
            ToggleBulb(
              label: 'Also search Subdl',
              value: settings.subdlEnabled,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(subdlEnabled: v)),
            ),
            if (settings.subdlEnabled) ...[
              const SizedBox(height: Tokens.space3),
              if (_subdlSaved)
                _Status(_subdlJustSaved ? 'Saved.' : 'A Subdl key is saved.')
              else
                const _Status('No Subdl key yet.', ok: false),
              const SizedBox(height: Tokens.space3),
              HouseField(
                controller: _subdl,
                label: _subdlSaved ? 'Replace the Subdl key' : 'Subdl API key',
                hint: 'Paste your key',
                obscure: true,
                onSubmitted: (_) => unawaited(_saveSubdl()),
              ),
              const SizedBox(height: Tokens.space3),
              Wrap(
                spacing: Tokens.space2,
                runSpacing: Tokens.space2,
                children: [
                  HouseButton(
                    label: 'Save key',
                    icon: 'check',
                    onPressed: () => unawaited(_saveSubdl()),
                  ),
                  if (_subdlSaved)
                    HouseButton(
                      label: 'Remove key',
                      kind: ButtonKind.danger,
                      onPressed: () => unawaited(_saveSubdl(remove: true)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Language chips with names and a preference number; up to [Settings.maxLanguages].
class _LanguagePicker extends StatelessWidget {
  final List<String> selected;
  final bool allowEmpty;
  final String semanticPrefix;
  final ValueChanged<List<String>> onChanged;
  const _LanguagePicker({
    required this.selected,
    required this.allowEmpty,
    required this.semanticPrefix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final full = selected.length >= Settings.maxLanguages;
    return Wrap(
      spacing: Tokens.space2,
      runSpacing: Tokens.space2,
      children: [
        for (final code in kOfferedLanguages)
          _LangChip(
            code: code,
            order: selected.indexOf(code),
            dim: full && !selected.contains(code),
            semanticPrefix: semanticPrefix,
            onTap: () {
              final l = [...selected];
              if (l.contains(code)) {
                if (allowEmpty || l.length > 1) l.remove(code);
              } else if (l.length < Settings.maxLanguages) {
                l.add(code);
              } else {
                return;
              }
              onChanged(l);
            },
          ),
      ],
    );
  }
}

class _LangChip extends StatelessWidget {
  final String code;
  final int order;
  final bool dim;
  final String semanticPrefix;
  final VoidCallback onTap;
  const _LangChip({
    required this.code,
    required this.order,
    required this.dim,
    required this.semanticPrefix,
    required this.onTap,
  });

  static const _ordinals = ['1st', '2nd', '3rd'];

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final on = order >= 0;
    final name = languageName(code);
    return Pressable(
      toggled: on,
      label: '$semanticPrefix $name${on ? ', ${_ordinals[order.clamp(0, 2)]} choice' : ''}',
      onTap: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        height: 40,
        padding: EdgeInsets.only(left: on ? 6 : Tokens.space3, right: Tokens.space3),
        decoration: BoxDecoration(
          color: on
              ? p.accent.withValues(alpha: s.hovered ? 0.2 : 0.14)
              : (s.lit ? p.ink.withValues(alpha: 0.08) : p.ink.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          border: Border.all(color: on ? p.accent.withValues(alpha: 0.7) : p.border),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
                  child: Center(
                    child: Text(
                      '${order + 1}',
                      style: Txt.mono(Tokens.textXs, p.accentInk, weight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.space2),
              ],
              Text(
                name,
                style: Txt.body(
                  Tokens.textSm,
                  on ? p.ink : (dim ? p.inkFaint : p.inkMuted),
                  weight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A still "frame" with a line of dialogue drawn the way the player will draw it.
class _SubtitlePreview extends StatelessWidget {
  final double scale;
  final SubtitleLook look;
  final SubtitlePlacement placement;
  const _SubtitlePreview({required this.scale, required this.look, required this.placement});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Semantics(
      label:
          'Preview of subtitles at ${(scale * 100).round()} percent, '
          '${look == SubtitleLook.box ? 'on a dark box' : 'outlined'}, '
          '${switch (placement) {
            SubtitlePlacement.bottom => 'at the bottom',
            SubtitlePlacement.lowerThird => 'a little higher',
            SubtitlePlacement.top => 'at the top',
          }}',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final hgt = (w * 9 / 16).clamp(150.0, 300.0);
          // libass scales by picture height; ~5.5 % of the height at 100 %.
          final size = hgt * 0.055 * scale;
          final line = 'Where are you going at this hour?';
          final Widget text = switch (look) {
            SubtitleLook.outline => Stack(
              children: [
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: Tokens.fontSubtitle,
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = (size / 9).clamp(1.5, 5)
                      ..color = const Color(0xFF000000),
                  ),
                ),
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: Tokens.fontSubtitle,
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ],
            ),
            SubtitleLook.box => Container(
              padding: EdgeInsets.symmetric(horizontal: size * 0.4, vertical: size * 0.12),
              color: const Color(0xC8000000),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Tokens.fontSubtitle,
                  fontSize: size,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ),
          };
          return ClipRRect(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
            child: SizedBox(
              height: hgt,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF3B4A63),
                      const Color(0xFFB98A5C),
                      Color.lerp(const Color(0xFF2A2320), p.bg, 0.2)!,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
                child: Align(
                  alignment: switch (placement) {
                    SubtitlePlacement.bottom => const Alignment(0, 0.86),
                    SubtitlePlacement.lowerThird => const Alignment(0, 0.4),
                    SubtitlePlacement.top => const Alignment(0, -0.86),
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
                    child: text,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────────── Playback ─────────────────────────────

class _PlaybackSection extends ConsumerWidget {
  const _PlaybackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsValueProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          title: 'Audio language',
          helper:
              'When a video has several audio tracks, play these first (best first). '
              'Choose none to keep each file\'s own default.',
          children: [
            _LanguagePicker(
              selected: settings.audioLanguages,
              allowEmpty: true,
              semanticPrefix: 'Audio language',
              onChanged: (l) => _edit(ref, (s) => s.copyWith(audioLanguages: l)),
            ),
          ],
        ),
        _Group(
          title: 'While watching',
          children: [
            ToggleBulb(
              label: 'Play the next video in the folder',
              hint: 'Handy for series: when an episode ends, the next file starts.',
              value: settings.autoplayNext,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(autoplayNext: v)),
            ),
            ToggleBulb(
              label: 'Hardware decoding',
              hint:
                  'Smoother and cooler on most devices. Turn off if the picture flickers or '
                  'shows green blocks.',
              value: settings.hwdec != 'no',
              onChanged: (v) => _edit(ref, (s) => s.copyWith(hwdec: v ? 'auto-safe' : 'no')),
            ),
            ToggleBulb(
              label: 'Bias light',
              hint:
                  'Tints the walls around the picture with the film\'s colours. '
                  'Uses extra CPU and battery.',
              value: settings.biasLight,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(biasLight: v)),
            ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────────── Appearance ─────────────────────────────

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsValueProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          title: 'Theme',
          helper:
              'Auto is light by day and dark at night (and follows your device). '
              'Films always play in the dark.',
          children: [
            ThemeChoice(
              value: settings.lobbyTheme,
              expand: true,
              onChanged: (t) => _edit(ref, (s) => s.copyWith(lobbyTheme: t)),
            ),
          ],
        ),
        _Group(
          title: 'The room',
          children: [
            ToggleBulb(
              label: 'Projector beam',
              hint: 'The soft cone of light in the lobby at night.',
              value: settings.beam,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(beam: v)),
            ),
            ToggleBulb(
              label: 'Sounds',
              hint: 'Quiet cues when a film opens and its subtitles arrive.',
              value: settings.sounds,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(sounds: v)),
            ),
            ToggleBulb(
              label: 'Vibration',
              hint: 'Small taps on phones when you seek or change the sync.',
              value: settings.haptics,
              onChanged: (v) => _edit(ref, (s) => s.copyWith(haptics: v)),
            ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────────── Library ─────────────────────────────

class _LibrarySection extends ConsumerStatefulWidget {
  const _LibrarySection();

  @override
  ConsumerState<_LibrarySection> createState() => _LibrarySectionState();
}

class _LibrarySectionState extends ConsumerState<_LibrarySection> {
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
      final path = await pickSaveLocation(name);
      if (path == null) return;
      await File(path).writeAsString(prettyJson(json));
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
      _Group(
        title: 'Back up your library',
        helper:
            'One small file with your films, resume points, subtitle sync and settings. '
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
            _Status(_sentence!, ok: _ok),
          ],
        ],
      ),
    ],
  );
}

// ───────────────────────────── About ─────────────────────────────

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = House.paletteOf(context);
    final tmdb = ref.watch(settingsValueProvider.select((s) => s.tmdbEnabled));
    Widget line(String t, {Color? c}) => Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      child: Text(t, style: Txt.body(Tokens.textSm, c ?? p.inkMuted)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          title: 'Marquee',
          children: [
            Text('Version $appVersion', style: Txt.mono(Tokens.textSm, p.ink)),
            const SizedBox(height: Tokens.space2),
            line('A free, open-source video player that finds the subtitles for you. MIT licence.'),
          ],
        ),
        _Group(
          title: 'Privacy',
          children: [
            line('No ads, no tracking, no analytics: nothing is measured or reported.', c: p.ink),
            line(
              'To find subtitles, only three things leave this device: the file\'s fingerprint '
              '(a 16-character hash), its size, and a title guessed from the file name. They go '
              'to OpenSubtitles (and to Subdl if you turn it on). Never the video, a frame, a '
              'file path or anything about your device.',
            ),
            line(
              'Your OpenSubtitles sign-in token and API keys stay in your device\'s secure '
              'storage. Your password is never stored.',
            ),
          ],
        ),
        _Group(
          title: 'Credits and licences',
          children: [
            line('Subtitles by OpenSubtitles.com', c: p.ink),
            if (tmdb) line(kTmdbNotice, c: p.ink),
            line(
              'Playback: libmpv (LGPL-2.1+), FFmpeg (LGPL-3.0, built --disable-gpl '
              '--enable-version3) and libass (ISC), dynamically linked. Build scripts: '
              'github.com/media-kit/libmpv-android-video-build (default flavour) and '
              'github.com/media-kit/libmpv-win32-video-cmake. Licence texts ship in LICENSES/.',
            ),
            line(
              'Fonts: Big Shoulders Display, Geist, Geist Mono, Noto Sans (SIL OFL 1.1). '
              'Icons: Lucide (ISC).',
            ),
          ],
        ),
      ],
    );
  }
}
