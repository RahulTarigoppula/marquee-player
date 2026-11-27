// Settings (the "ticket office" in the code). Five plain sections — Subtitles, Playback, Appearance, Library,
// About — each a few cards with a heading and one line of explanation. Desktop: the sections
// down the left, one open on the right. Phone: a list of sections, each opening on its own.
//
// This file is the room itself (header, navigation, Back); each section lives in its own file
// beside it, built from parts.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/session.dart';
import '../../state/updates.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import '../components/room.dart';
import 'about_section.dart';
import 'appearance_section.dart';
import 'library_section.dart';
import 'playback_section.dart';
import 'subtitles_section.dart';

export 'about_section.dart' show kTmdbNotice;
export 'parts.dart' show kOfferedLanguages;

/// Settings switch to the two-pane layout at this width.
const double kSettingsWide = 840;

enum SettingsSection {
  subtitles('Subtitles', 'captions', 'Languages, size and colour, account'),
  playback('Playback', 'circle-play', 'Skipping, what plays next, sound'),
  appearance('Appearance', 'sun-moon', 'Theme, projector beam, sounds'),
  library('Library', 'library', 'Your video folders, backing up'),
  about('About', 'info', 'Version, updates, privacy, licences');

  final String title;
  final String icon;
  final String blurb;
  const SettingsSection(this.title, this.icon, this.blurb);
}

class TicketOfficeScreen extends ConsumerStatefulWidget {
  /// The section to open on (screenshots, deep links). Phone: null shows the section list.
  final SettingsSection? initialSection;
  const TicketOfficeScreen({super.key, this.initialSection});

  @override
  ConsumerState<TicketOfficeScreen> createState() => _TicketOfficeScreenState();
}

class _TicketOfficeScreenState extends ConsumerState<TicketOfficeScreen> {
  SettingsSection? _section;

  /// Holds the keyboard for the room, so Escape works before anything in it is focused.
  final _focus = FocusNode(debugLabel: 'ticket office');

  static SettingsSection? _named(String? name) => SettingsSection.values.asNameMap()[name];

  @override
  void initState() {
    super.initState();
    assert(_named(kSettingsAbout) == SettingsSection.about, 'lib/state spells the section name');
    // A notice ("Marquee 2.1.0 is available · What's new") asks for a section by name.
    _section = widget.initialSection ?? _named(ref.read(settingsJumpProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      ref.read(settingsJumpProvider.notifier).clear(); // taken: the next visit opens normally
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _leave() {
    final filmOpen = ref.read(sessionProvider) != null;
    // Reached mid-film from the threading "Sign in" row: go back to the film.
    ref.read(roomProvider.notifier).go(filmOpen ? Room.auditorium : Room.lobby);
  }

  /// Android Back and Escape: out of a section first (phone), then out of the room.
  void _back() {
    final wide = MediaQuery.sizeOf(context).width >= kSettingsWide;
    if (!wide && _section != null) {
      setState(() => _section = null);
    } else {
      _leave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final wide = MediaQuery.sizeOf(context).width >= kSettingsWide;
    // Already here when the notice is tapped: switch section in place.
    ref.listen(settingsJumpProvider, (_, name) {
      final section = _named(name);
      if (section == null) return;
      setState(() => _section = section);
      ref.read(settingsJumpProvider.notifier).clear();
    });
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
                : (filmOpen ? 'Back to the video' : 'Back to Home'),
            onTap: _back,
          ),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(inSection ? 'SETTINGS' : 'MARQUEE', style: Txt.label(p.inkFaint)),
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
              label: filmOpen ? 'Back to the video' : 'Done',
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

    // The shell's PopScope blocks Back outside the Lobby; this room answers it itself.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
        child: Focus(
          focusNode: _focus,
          child: Stack(
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
          ),
        ),
      ),
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

class _SectionBody extends StatelessWidget {
  final SettingsSection section;
  const _SectionBody({required this.section});

  @override
  Widget build(BuildContext context) => switch (section) {
    SettingsSection.subtitles => const SubtitlesSection(),
    SettingsSection.playback => const PlaybackSection(),
    SettingsSection.appearance => const AppearanceSection(),
    SettingsSection.library => const LibrarySection(),
    SettingsSection.about => const AboutSection(),
  };
}
