// Subtitle options (the "Booth" in the code): everything about subtitles, and the sound's
// timing, in one sheet that never covers more than 70 % of the picture. The video keeps
// playing behind the glass. How subtitles look is a Setting: it persists and applies to
// every video, so this sheet shows the very controls Settings › Subtitles does.
//
// Once the video has started, the subtitle search lives HERE, not over the picture: what was
// found by name (pick one), why a search stalled and what to try next, and the progress of a
// search or download asked for from this sheet. It sits right under the list of subtitles,
// because it is what the sheet is opened for when a search needs an answer.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/models.dart';
import '../../engine/sentences.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import '../components/sync_rule.dart';
import '../components/ticket_strip.dart';
import '../threading/subtitle_choice.dart';
import '../ticket_office/subtitles_section.dart' show SubtitleLookControls;

const double kBoothMaxFraction = 0.7;

/// The sheet's name, the same words as the menu row that opens it.
const String kSubtitleOptions = 'Subtitle options';

class BoothSheet extends ConsumerStatefulWidget {
  const BoothSheet({super.key});

  @override
  ConsumerState<BoothSheet> createState() => _BoothSheetState();
}

class _BoothSheetState extends ConsumerState<BoothSheet> {
  final _search = TextEditingController();
  double _drag = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _close() => ref.read(boothOpenProvider.notifier).set(false);

  /// Through the session: it keeps Android from taking the picker for a trip Home (which
  /// would shrink the video into picture in picture behind it).
  Future<void> _loadFile() => ref.read(sessionProvider.notifier).pickAndLoadSubtitle();

  /// The search as it stands: a status line while it runs, the sentence it stalled on, the
  /// subtitles it found (a tap downloads that one: the only thing here that uses up a
  /// download) and the ways on from a stall.
  List<Widget> _searchRows(FilmSession s, HousePalette p) {
    final t = s.threading;
    final n = ref.read(sessionProvider.notifier);
    final stalled = t.event is Stalled ? t.event! as Stalled : null;
    final notice = t.event is Notice ? (t.event! as Notice).sentence : null;
    bool same(ScoredCandidate? a, ScoredCandidate b) =>
        a != null &&
        a.candidate.provider == b.candidate.provider &&
        a.candidate.id == b.candidate.id;
    return [
      if (s.subtitlesBusy)
        Padding(
          padding: const EdgeInsets.only(bottom: Tokens.space2),
          child: Semantics(
            liveRegion: true,
            child: Text(searchStatusLabel(t), style: Txt.label(p.accent)),
          ),
        ),
      if (stalled != null && stalled.sentence.isNotEmpty) ...[
        Sentence(stalled.sentence),
        const SizedBox(height: Tokens.space2),
      ],
      if (notice != null) ...[
        Sentence(notice, color: p.warning),
        const SizedBox(height: Tokens.space2),
      ],
      for (final c in t.candidates.take(8))
        SubtitleChoiceRow(
          scored: c,
          picked: same(t.picked, c),
          downloading: t.phase == LeaderPhase.downloading && !t.stalled && same(t.picked, c),
          onTap: () => unawaited(n.pick(c)),
        ),
      if (stalled != null)
        Wrap(
          children: [
            for (final a in stalled.next)
              ...switch (a) {
                FallbackAction.signIn => [
                  TextAction(
                    signInActionLabel(stalled.failure),
                    primary: true,
                    onTap: () {
                      _close();
                      ref.read(roomProvider.notifier).go(Room.ticketOffice);
                    },
                  ),
                ],
                FallbackAction.retry => [
                  TextAction(kTryAgain, onTap: () => unawaited(n.retrySubtitles())),
                ],
                FallbackAction.filenameSearch => [
                  TextAction(kSearchByFileName, onTap: () => unawaited(n.searchByFilename())),
                ],
                FallbackAction.subdl => [
                  TextAction(kTryBackupSite, onTap: () => unawaited(n.searchSubdl())),
                ],
                // The title field is just below; the video is already playing.
                FallbackAction.manualSearch || FallbackAction.skip => const <Widget>[],
              },
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox.shrink();
    final p = House.paletteOf(context);
    final pb = ref.watch(playbackProvider).value ?? s.engine.snapshot;
    final attached = s.threading.attached;
    final engine = s.engine;
    // Track choices go through the session, which remembers them for this video.
    final notifier = ref.read(sessionProvider.notifier);
    final attachedId = attached is ExternalSubtitle ? engine.externalIdFor(attached.path) : null;
    final h = MediaQuery.sizeOf(context).height;
    // The on-screen keyboard (Android) must never cover the search field.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _close,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, t, child) =>
                  FractionalTranslation(translation: Offset(0, t), child: child),
              child: Transform.translate(
                offset: Offset(0, _drag.clamp(0, h)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (h - keyboard) * kBoothMaxFraction,
                    maxWidth: 560,
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(Tokens.radiusLg),
                    ),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.bgElevated.withValues(alpha: 0.86),
                          border: Border(top: BorderSide(color: p.border)),
                          boxShadow: Tokens.shadow3,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Handle(
                              onDrag: (dy) => setState(() => _drag = (_drag + dy).clamp(0, h)),
                              onRelease: (v) {
                                if (v > 300 || _drag > 120) {
                                  _close();
                                } else {
                                  setState(() => _drag = 0);
                                }
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: Tokens.space5,
                                right: Tokens.space2,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Semantics(
                                      header: true,
                                      child: Text(
                                        kSubtitleOptions,
                                        style: Txt.body(
                                          Tokens.textLg,
                                          p.ink,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconMark(icon: 'x', label: 'Close', onTap: _close),
                                ],
                              ),
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  Tokens.space5,
                                  0,
                                  Tokens.space5,
                                  Tokens.space5,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _TrackRow(
                                      title: 'Off',
                                      selected: !pb.hasSubtitle,
                                      onTap: () => unawaited(notifier.subtitlesOff()),
                                    ),
                                    if (attached is ExternalSubtitle)
                                      _attachedRow(
                                        attached,
                                        p,
                                        selected: attachedId != null && pb.subtitleId == attachedId,
                                        onTap: () => unawaited(notifier.useAttachedSubtitle()),
                                      ),
                                    for (final t in pb.subtitleTracks.where(
                                      (t) => t.id != attachedId,
                                    ))
                                      _TrackRow(
                                        title: subtitleTrackTitle(
                                          id: t.id,
                                          language: t.language,
                                          title: t.title,
                                          external: engine.isExternal(t.id),
                                        ),
                                        selected: pb.subtitleId == t.id,
                                        onTap: () => unawaited(notifier.selectSubtitle(t.id)),
                                      ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextAction(
                                        'Load subtitle file…',
                                        onTap: () => unawaited(_loadFile()),
                                      ),
                                    ),
                                    const _Heading('Find different subtitles'),
                                    ..._searchRows(s, p),
                                    TextField(
                                      controller: _search,
                                      style: Txt.body(Tokens.textBase, p.ink),
                                      scrollPadding: const EdgeInsets.only(bottom: 120),
                                      textInputAction: TextInputAction.search,
                                      decoration: InputDecoration(
                                        // Short enough to show whole on a 360 px phone.
                                        hintText: 'Title, or leave empty for the file name',
                                        hintStyle: Txt.body(Tokens.textBase, p.inkFaint),
                                        enabledBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: p.borderStrong),
                                        ),
                                        focusedBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: p.accent),
                                        ),
                                      ),
                                      onSubmitted: (q) => unawaited(notifier.findAnother(q)),
                                    ),
                                    const SizedBox(height: Tokens.space3),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: HouseButton(
                                        label: 'Search',
                                        icon: 'search',
                                        onPressed: () =>
                                            unawaited(notifier.findAnother(_search.text)),
                                      ),
                                    ),
                                    const SizedBox(height: Tokens.space3),
                                    TicketStripView(
                                      strip: ref.watch(ticketStripProvider),
                                      count: ref.watch(quotaProvider).remaining,
                                    ),
                                    const _Heading('Subtitles too early or late?'),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: Tokens.space2),
                                      child: Text(
                                        'Make them show earlier if the words come after the '
                                        'voice, later if they come before it.',
                                        style: Txt.body(Tokens.textSm, p.inkMuted),
                                      ),
                                    ),
                                    SyncRule(
                                      delayMs: s.delayMs,
                                      onChanged: (v) => unawaited(notifier.setDelay(v)),
                                    ),
                                    const _Heading('How subtitles look'),
                                    const SubtitleLookControls(),
                                    const _Heading('Sound too early or late?'),
                                    _SoundTiming(
                                      ms: s.audioDelayMs,
                                      onChanged: (v) => unawaited(notifier.setAudioDelay(v)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The subtitle Marquee attached by itself: one it downloaded, or a file it found beside
  /// the video. Says in words whether its timing was checked against this exact file.
  Widget _attachedRow(
    ExternalSubtitle a,
    HousePalette p, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final language = languageLabel(a.language);
    final sidecar = a.provider == SubtitleProvider.sidecar;
    return _TrackRow(
      title: sidecar ? language : '$language — found by Marquee',
      status: a.syncedByHash
          ? 'In sync'
          : sidecar
          ? 'Next to the video'
          : 'Timing may be off',
      statusIcon: a.syncedByHash ? 'check' : null,
      statusColor: a.syncedByHash
          ? p.success
          : sidecar
          ? p.inkMuted
          : p.warning,
      // A file found beside the video already says where it is.
      detail: sidecar
          ? null
          : a.besideFile
          ? 'Saved next to the video'
          : 'Kept inside Marquee',
      selected: selected,
      onTap: onTap,
    );
  }
}

class _Handle extends StatelessWidget {
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onRelease;
  const _Handle({required this.onDrag, required this.onRelease});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    // A place to drag the sheet down by. The Close button under it is the one a screen
    // reader or a keyboard uses.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      onVerticalDragEnd: (d) => onRelease(d.primaryVelocity ?? 0),
      child: ExcludeSemantics(
        child: SizedBox(
          height: 24,
          width: double.infinity,
          child: Center(child: Container(width: 40, height: 3, color: p.borderStrong)),
        ),
      ),
    );
  }
}

/// A section's heading inside the sheet, written the way Settings writes a card's title: in
/// sentence case, often as the question the viewer has.
class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Tokens.space6, bottom: Tokens.space2),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Txt.body(Tokens.textBase, House.paletteOf(context).ink, weight: FontWeight.w600),
      ),
    ),
  );
}

/// The sound earlier or later in 50 ms steps, for a video whose sound is out of step with
/// the picture: the state in a sentence, two buttons that say which way, and a way back.
class _SoundTiming extends StatelessWidget {
  final int ms;
  final ValueChanged<int> onChanged;
  const _SoundTiming({required this.ms, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            soundTimingSentence(ms),
            style: Txt.body(Tokens.textBase, ms == 0 ? p.inkMuted : p.accent),
          ),
        ),
        const SizedBox(height: Tokens.space2),
        Wrap(
          spacing: Tokens.space2,
          runSpacing: Tokens.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            HouseButton(
              label: 'Earlier',
              icon: 'minus',
              semanticLabel: 'Sound 0.05 seconds earlier',
              onPressed: () => onChanged(ms - 50),
            ),
            HouseButton(
              label: 'Later',
              icon: 'plus',
              semanticLabel: 'Sound 0.05 seconds later',
              onPressed: () => onChanged(ms + 50),
            ),
            if (ms != 0) TextAction('Reset', onTap: () => onChanged(0)),
          ],
        ),
      ],
    );
  }
}

/// One subtitle that can be shown: its name, and under it what is known about it.
class _TrackRow extends StatelessWidget {
  final String title;
  final String? status;
  final String? statusIcon;
  final Color? statusColor;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;
  const _TrackRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.status,
    this.statusIcon,
    this.statusColor,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final under = [?status, ?detail];
    return Pressable(
      label: [title, ...under].join(', '),
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      radius: Tokens.radiusSm,
      builder: (context, s) => AnimatedContainer(
        duration: Tokens.durFast,
        constraints: const BoxConstraints(minHeight: Tokens.targetMin),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space2, vertical: Tokens.space1),
        color: pressWash(p, s),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Bulb(lit: selected, size: 7),
              const SizedBox(width: Tokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: Txt.body(Tokens.textBase, selected ? p.accent : p.ink)),
                    if (under.isNotEmpty)
                      Row(
                        children: [
                          if (statusIcon != null) ...[
                            LucideIcon(statusIcon!, size: 14, color: statusColor ?? p.inkMuted),
                            const SizedBox(width: Tokens.space1),
                          ],
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  if (status != null)
                                    TextSpan(
                                      text: status,
                                      style: TextStyle(color: statusColor ?? p.inkMuted),
                                    ),
                                  if (status != null && detail != null) const TextSpan(text: ' · '),
                                  if (detail != null) TextSpan(text: detail),
                                ],
                              ),
                              style: Txt.body(Tokens.textSm, p.inkMuted),
                            ),
                          ),
                        ],
                      ),
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
