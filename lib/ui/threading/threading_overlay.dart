// Threading: the loading indicator that never lies. Leader + hash line + candidates + strip.
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
    final lang = languageName(t.picked?.candidate.language ?? 'en');
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
    final wide = MediaQuery.sizeOf(context).width >= 900;
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
        Leader(state: t, size: wide ? 300 : 220),
        const SizedBox(height: Tokens.space3),
        Text(switch (t.phase) {
          LeaderPhase.hashing => 'READING THE PRINT',
          LeaderPhase.searching => 'SEARCHING SUBTITLES',
          LeaderPhase.downloading =>
            'DOWNLOADING ${languageName(t.picked?.candidate.language ?? 'en').toUpperCase()} SUBTITLES',
          _ => 'THREADING',
        }, style: Txt.label(p.accent)),
        const SizedBox(height: Tokens.space2),
        Text(
          [
            t.hash?.value ?? '················',
            if (t.sizeBytes != null) _size(t.sizeBytes!),
          ].join(' · '),
          style: Txt.mono(
            Tokens.textSm,
            p.inkMuted,
          ).copyWith(fontFeatures: const [FontFeature.slashedZero(), FontFeature.tabularFigures()]),
        ),
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
          _CandidateRow(
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

    return ColoredBox(
      color: p.bg.withValues(alpha: 0.92),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(kThreadingFolio, style: Txt.mono(Tokens.textSm, p.inkMuted)),
                  const Spacer(),
                  TextAction(
                    'Skip subtitles',
                    onTap: () => ref.read(sessionProvider.notifier).skipSubtitles(),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Tokens.space6),
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
            'Sign in at the ticket office (free, more tickets)',
            primary: true,
            onTap: () => ref.read(roomProvider.notifier).go(Room.ticketOffice),
          ),
          FallbackAction.retry => TextAction('Try again', onTap: () => unawaited(m?.retry())),
          FallbackAction.filenameSearch => TextAction(
            'Search by filename',
            onTap: () => unawaited(m?.filenameSearch()),
          ),
          FallbackAction.subdl => TextAction(
            'Use the Subdl slot',
            onTap: () => unawaited(m?.subdlSearch()),
          ),
          FallbackAction.manualSearch => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
            child: TextField(
              controller: _manual,
              style: Txt.body(Tokens.textBase, p.ink),
              decoration: InputDecoration(
                hintText: 'Type a title and press Enter',
                hintStyle: Txt.body(Tokens.textBase, p.inkFaint),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.borderStrong)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.accent)),
              ),
              onSubmitted: (q) => unawaited(n.findAnother(q)),
            ),
          ),
          FallbackAction.skip => TextAction(
            'Play without subtitles',
            primary: s.failure == ThreadingFailure.offline,
            onTap: n.skipSubtitles,
          ),
        },
    ];
  }

  static bool _same(ScoredCandidate? a, ScoredCandidate b) =>
      a != null && a.candidate.provider == b.candidate.provider && a.candidate.id == b.candidate.id;

  static String _size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _CandidateRow extends StatelessWidget {
  final ScoredCandidate scored;
  final bool picked;
  final bool downloading;
  final VoidCallback onTap;
  const _CandidateRow({
    required this.scored,
    required this.picked,
    required this.downloading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final c = scored.candidate;
    final meta = [
      '${_thousands(c.downloadCount)} dl',
      if (c.fps != null) '${c.fps!.toStringAsFixed(3)} fps',
      if (c.hearingImpaired) 'HI',
      if (c.machineTranslated || c.aiTranslated) 'MACHINE',
      if (c.provider == SubtitleProvider.subdl) 'SUBDL',
    ].join(' · ');
    return FocusRing(
      radius: Tokens.radiusMd,
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: picked,
        label:
            '${c.language}, ${c.release ?? 'untitled'}, ${c.moviehashMatch ? 'exact match' : 'by name, check sync'}',
        child: InkWell(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: Tokens.space2),
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space3, vertical: Tokens.space2),
            constraints: const BoxConstraints(minHeight: Tokens.targetMin),
            decoration: BoxDecoration(
              color: picked ? p.surface2 : p.surface,
              borderRadius: BorderRadius.circular(Tokens.radiusMd),
              boxShadow: Tokens.shadow1,
            ),
            child: Row(
              children: [
                Text(c.language.toUpperCase(), style: Txt.mono(Tokens.textSm, p.ink)),
                const SizedBox(width: Tokens.space2),
                Bulb(lit: c.moviehashMatch, color: p.success, size: 7),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.moviehashMatch
                            ? 'MATCH  ${c.release ?? ''}'
                            : c.release ?? 'Untitled release',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.body(Tokens.textSm, p.ink, weight: FontWeight.w500),
                      ),
                      Text(
                        c.moviehashMatch ? meta : 'BY NAME · CHECK SYNC · $meta',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.mono(Tokens.textXs, c.moviehashMatch ? p.inkMuted : p.warning),
                      ),
                    ],
                  ),
                ),
                if (downloading) Text('↓', style: Txt.mono(Tokens.textSm, p.accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _thousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
}
