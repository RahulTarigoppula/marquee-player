// Settings · Subtitles: the OpenSubtitles account and key, languages, where subtitles come from
// and how they are drawn (with a live preview).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/models.dart';
import '../../state/providers.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import '../components/ticket_strip.dart';
import 'parts.dart';

/// Where "Create a free account" and "Get a key" lead: the user's browser, on a tap.
const String kOpenSubtitlesSignUp = 'https://www.opensubtitles.com/en/users/sign_up';
const String kOpenSubtitlesConsumers = 'https://www.opensubtitles.com/en/consumers';
const String kSubdlKeyPage = 'https://subdl.com/panel/api';

class SubtitlesSection extends ConsumerStatefulWidget {
  const SubtitlesSection({super.key});

  @override
  ConsumerState<SubtitlesSection> createState() => _SubtitlesState();
}

class _SubtitlesState extends ConsumerState<SubtitlesSection> {
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
        SettingsGroup(
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
                  TextAction(
                    'Create a free account',
                    onTap: () => unawaited(openInBrowser(ref, kOpenSubtitlesSignUp)),
                  ),
                ],
              ),
            ],
          ],
        ),
        if (!buildHasApiKey)
          SettingsGroup(
            title: 'OpenSubtitles API key',
            helper:
                'This copy of Marquee was built without a key, so it needs yours (free). '
                'Sign in at opensubtitles.com, open "API consumers" in your profile, create a '
                'consumer and paste its key here.',
            children: [
              if (hasKey)
                StatusLine(
                  _osKeyJustSaved
                      ? 'Saved. Subtitle search is on.'
                      : 'A key is saved. Subtitle search is on.',
                )
              else
                const StatusLine('No key yet, so subtitles cannot be searched.', ok: false),
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
                    )
                  else
                    TextAction(
                      'Get a key',
                      onTap: () => unawaited(openInBrowser(ref, kOpenSubtitlesConsumers)),
                    ),
                ],
              ),
            ],
          ),
        SettingsGroup(
          title: 'Languages',
          helper:
              'Pick up to ${Settings.maxLanguages}, in the order you prefer. '
              'Tap a language again to remove it.',
          children: [
            LanguagePicker(
              selected: settings.languages,
              allowEmpty: false,
              semanticPrefix: 'Subtitle language',
              onChanged: (l) => editSettings(ref, (s) => s.copyWith(languages: l)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Finding subtitles',
          children: [
            ToggleBulb(
              label: 'Use subtitles inside the video first',
              hint:
                  'If the file already has subtitles in your language, use them instead of '
                  'searching online.',
              value: settings.preferEmbeddedSubtitles,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(preferEmbeddedSubtitles: v)),
            ),
            ToggleBulb(
              label: 'Prefer subtitles for the hard of hearing',
              hint: 'These also describe sounds, like [door slams].',
              value: settings.preferHearingImpaired,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(preferHearingImpaired: v)),
            ),
            ToggleBulb(
              label: 'Save subtitles next to the video',
              hint: 'Other players will find them too. Off: Marquee keeps them to itself.',
              value: settings.saveBesideFile,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(saveBesideFile: v)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'How subtitles look',
          helper: 'Changes show here, and on a film that is open, right away.',
          children: [
            _SubtitlePreview(
              scale: scale,
              look: settings.subtitleLook,
              placement: settings.subtitlePlacement,
              tint: settings.subtitleTint,
            ),
            const SizedBox(height: Tokens.space3),
            ControlBlock(
              label: 'Style',
              child: SegmentedChoice<SubtitleLook>(
                key: const ValueKey('subtitle-look'),
                groupLabel: 'Subtitle style',
                value: settings.subtitleLook,
                expand: true,
                // Short enough for two halves of a 360 px phone; the preview shows the rest.
                segments: const [
                  Segment(SubtitleLook.outline, 'Outlined'),
                  Segment(SubtitleLook.box, 'Dark box'),
                ],
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(subtitleLook: v)),
              ),
            ),
            ControlBlock(
              label: 'Colour',
              help: 'Subtitles that bring their own styling keep their own colours.',
              child: SegmentedChoice<SubtitleTint>(
                key: const ValueKey('subtitle-tint'),
                groupLabel: 'Subtitle colour',
                value: settings.subtitleTint,
                expand: true,
                segments: [for (final t in SubtitleTint.values) Segment(t, t.label)],
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(subtitleTint: v)),
              ),
            ),
            const SizedBox(height: Tokens.space2),
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
                editSettings(ref, (s) => s.copyWith(subtitleScale: v));
              },
            ),
            ControlBlock(
              label: 'Position',
              child: SegmentedChoice<SubtitlePlacement>(
                key: const ValueKey('subtitle-placement'),
                groupLabel: 'Subtitle position',
                value: settings.subtitlePlacement,
                expand: true,
                segments: const [
                  Segment(SubtitlePlacement.bottom, 'Bottom'),
                  Segment(SubtitlePlacement.lowerThird, 'Higher'),
                  Segment(SubtitlePlacement.top, 'Top'),
                ],
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(subtitlePlacement: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Backup source: Subdl',
          helper:
              'A second free subtitle site, searched when OpenSubtitles has nothing. '
              'It needs your own free key from subdl.com.',
          children: [
            ToggleBulb(
              label: 'Also search Subdl',
              value: settings.subdlEnabled,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(subdlEnabled: v)),
            ),
            if (settings.subdlEnabled) ...[
              const SizedBox(height: Tokens.space3),
              if (_subdlSaved)
                StatusLine(_subdlJustSaved ? 'Saved.' : 'A Subdl key is saved.')
              else
                const StatusLine('No Subdl key yet.', ok: false),
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
                    )
                  else
                    TextAction(
                      'Get a key',
                      onTap: () => unawaited(openInBrowser(ref, kSubdlKeyPage)),
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

/// A still "frame" with a line of dialogue drawn the way the player will draw it.
class _SubtitlePreview extends StatelessWidget {
  final double scale;
  final SubtitleLook look;
  final SubtitlePlacement placement;
  final SubtitleTint tint;
  const _SubtitlePreview({
    required this.scale,
    required this.look,
    required this.placement,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    // `#RRGGBB`, the same value mpv is given, so the preview cannot drift from the film.
    final ink = Color(
      0xFF000000 | (int.tryParse(tint.mpvColor.substring(1), radix: 16) ?? 0xFFFFFF),
    );
    return Semantics(
      label:
          'Preview of subtitles at ${(scale * 100).round()} percent, '
          '${tint.label.toLowerCase()}, '
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
                    color: ink,
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
                style: TextStyle(fontFamily: Tokens.fontSubtitle, fontSize: size, color: ink),
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
