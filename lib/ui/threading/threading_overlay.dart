// The opening screen ("threading" in the code): the loading indicator that never lies. The
// countdown and what it is doing, the subtitles it found, and how many downloads are left.
// Everything on it is said in plain words: the video's own title, not a reel number; no file
// fingerprint (Video details has it).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/models.dart';
import '../../engine/sentences.dart';
import '../../engine/timecode.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/leader.dart';
import '../components/primitives.dart';
import '../components/ticket_strip.dart';
import 'subtitle_choice.dart';

class ThreadingOverlay extends ConsumerStatefulWidget {
  const ThreadingOverlay({super.key});

  @override
  ConsumerState<ThreadingOverlay> createState() => _ThreadingOverlayState();
}

class _ThreadingOverlayState extends ConsumerState<ThreadingOverlay> {
  LeaderPhase? _announced;
  bool _matchPopped = false;
  final _manual = TextEditingController();

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _announce(ThreadingState t, BuildContext context) {
    if (t.phase == _announced) return;
    _announced = t.phase;
    final lang = languageLabel(t.picked?.candidate.language ?? 'en');
    final synced = t.attached is ExternalSubtitle && (t.attached as ExternalSubtitle).syncedByHash;
    final text = announceFor(t.phase, language: lang, synced: synced);
    if (text.isNotEmpty) {
      unawaited(SemanticsService.sendAnnouncement(View.of(context), text, TextDirection.ltr));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final t = session.threading;
    final p = House.paletteOf(context);
    final room = MediaQuery.sizeOf(context);
    final wide = room.width >= 900;
    // A phone held sideways: the countdown shrinks so it, and the words under it, fit the
    // height instead of being cut off at the bottom edge.
    final short = room.height < 520;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announce(t, context);
    });
    final matched = t.candidates.isNotEmpty && t.candidates.first.candidate.moviehashMatch;
    if (matched && !_matchPopped) {
      _matchPopped = true;
      if (ref.read(settingsValueProvider).haptics) unawaited(HapticFeedback.mediumImpact());
    }
    final stalled = t.event is Stalled ? t.event! as Stalled : null;
    final notice = t.event is Notice ? (t.event! as Notice).sentence : null;

    final leaderCol = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Leader(state: t, size: short ? 160 : (wide ? 300 : 220)),
        const SizedBox(height: Tokens.space3),
        // What is being opened, in the words Home used for it. Here, under the countdown, it
        // has the width for a whole title; beside the buttons above it would be cut to a stub.
        Semantics(
          header: true,
          child: Text(
            threadingFolio(session.displayTitle),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: Tokens.space1),
        Text(searchStatusLabel(t), style: Txt.label(p.accent)),
      ],
    );

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stalled != null) ...[
          Sentence(stalled.sentence, color: p.ink),
          const SizedBox(height: Tokens.space3),
        ],
        if (notice != null) ...[
          Sentence(notice, color: p.warning),
          const SizedBox(height: Tokens.space3),
        ],
        for (final c in t.candidates.take(8))
          SubtitleChoiceRow(
            raised: true,
            scored: c,
            picked: _same(t.picked, c),
            downloading: t.phase == LeaderPhase.downloading && _same(t.picked, c),
            onTap: () => unawaited(ref.read(sessionProvider.notifier).pick(c)),
          ),
        if (stalled != null) ..._fallbacks(stalled, p),
        const SizedBox(height: Tokens.space4),
        TicketStripView(
          strip: ref.watch(ticketStripProvider),
          count: ref.watch(quotaProvider).remaining,
        ),
      ],
    );

    // The video waits, paused, behind this overlay. There is ALWAYS a way to just watch it.
    return ColoredBox(
      color: p.bg.withValues(alpha: 0.94),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Tokens.space5,
            Tokens.space5,
            Tokens.space5,
            Tokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconMark(
                    icon: 'arrow-left',
                    label: 'Back to Home',
                    onTap: () => unawaited(ref.read(sessionProvider.notifier).close()),
                  ),
                  const Spacer(),
                  TextAction(
                    kPlayWithoutSubtitles,
                    primary: stalled != null,
                    onTap: () => ref.read(sessionProvider.notifier).skipSubtitles(),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(top: short ? Tokens.space3 : Tokens.space6),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 360, child: Center(child: leaderCol)),
                              const SizedBox(width: Tokens.space7),
                              Expanded(child: list),
                            ],
                          )
                        : Column(
                            children: [
                              leaderCol,
                              const SizedBox(height: Tokens.space6),
                              list,
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _fallbacks(Stalled s, HousePalette p) {
    final n = ref.read(sessionProvider.notifier);
    final m = n.machine;
    return [
      const SizedBox(height: Tokens.space3),
      for (final a in s.next)
        switch (a) {
          FallbackAction.signIn => TextAction(
            signInActionLabel(s.failure),
            primary: true,
            onTap: () => ref.read(roomProvider.notifier).go(Room.ticketOffice),
          ),
          FallbackAction.retry => TextAction(kTryAgain, onTap: () => unawaited(m?.retry())),
          FallbackAction.filenameSearch => TextAction(
            kSearchByFileName,
            onTap: () => unawaited(m?.filenameSearch()),
          ),
          FallbackAction.subdl => TextAction(
            kTryBackupSite,
            onTap: () => unawaited(m?.subdlSearch()),
          ),
          FallbackAction.manualSearch => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
            child: TextField(
              controller: _manual,
              style: Txt.body(Tokens.textBase, p.ink),
              scrollPadding: const EdgeInsets.only(bottom: 120),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Or type the title and press Enter',
                hintStyle: Txt.body(Tokens.textBase, p.inkFaint),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.borderStrong)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.accent)),
              ),
              onSubmitted: (q) => unawaited(n.findAnother(q)),
            ),
          ),
          // Always at the top of the overlay already — never twice.
          FallbackAction.skip => const SizedBox.shrink(),
        },
    ];
  }

  static bool _same(ScoredCandidate? a, ScoredCandidate b) =>
      a != null && a.candidate.provider == b.candidate.provider && a.candidate.id == b.candidate.id;
}
