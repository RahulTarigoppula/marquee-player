// What the subtitle search shows for itself, in one place: the row for a subtitle it found,
// the line that says what it is doing, and the names of the ways on from a stall. The opening
// screen (threading_overlay.dart) and the subtitle options sheet (booth_sheet.dart) both show a
// search, and must say the same thing in the same words.
import 'package:flutter/material.dart';

import '../../engine/models/models.dart';
import '../../engine/sentences.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/primitives.dart';

const String kTryAgain = 'Try again';
const String kSearchByFileName = 'Search by file name';
const String kTryBackupSite = 'Try the backup site (Subdl)';
const String kPlayWithoutSubtitles = 'Play without subtitles';

/// The way to Settings › Subtitles from a stall, named after what is missing there.
String signInActionLabel(ThreadingFailure failure) => switch (failure) {
  ThreadingFailure.noApiKey => 'Add your free API key…',
  ThreadingFailure.unauthorized => 'Sign in again…',
  _ => 'Sign in for more downloads (free)…',
};

/// A language name for a row; a subtitle that names none says so instead of showing a gap.
String languageLabel(String? code) =>
    code == null || code.trim().isEmpty ? kUnknownLanguage : languageName(code);

/// What the search is doing right now, as the small label above it.
String searchStatusLabel(ThreadingState t) => switch (t.phase) {
  LeaderPhase.hashing => 'READING THE FILE',
  LeaderPhase.searching => 'LOOKING FOR SUBTITLES',
  LeaderPhase.downloading =>
    'DOWNLOADING ${languageLabel(t.picked?.candidate.language ?? 'en').toUpperCase()} SUBTITLES',
  _ => 'GETTING READY',
};

/// One subtitle the search found. Tapping it downloads and attaches it. The green light is
/// the only thing that means "made for this exact file"; every other row carries the warning.
class SubtitleChoiceRow extends StatelessWidget {
  final ScoredCandidate scored;
  final bool picked;
  final bool downloading;
  final VoidCallback onTap;

  /// A card on its own surface (the opening screen) instead of a flat row (the sheet).
  final bool raised;

  const SubtitleChoiceRow({
    super.key,
    required this.scored,
    required this.picked,
    required this.downloading,
    required this.onTap,
    this.raised = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final c = scored.candidate;
    final exact = c.moviehashMatch;
    final language = languageLabel(c.language);
    final details = candidateDetails(c);
    // The plain facts first; the release name last, where a long one is cut off.
    final small = [
      if (details.isNotEmpty) details,
      if (c.release != null && c.release!.trim().isNotEmpty) c.release!.trim(),
    ].join(' · ');
    final radius = raised ? Tokens.radiusMd : Tokens.radiusSm;
    return Padding(
      padding: EdgeInsets.only(bottom: raised ? Tokens.space2 : 0),
      child: Pressable(
        label: [
          language,
          matchLine(exact: exact),
          if (details.isNotEmpty) details,
          if (downloading) 'downloading',
        ].join(', '),
        selected: picked,
        inMutuallyExclusiveGroup: true,
        onTap: onTap,
        radius: radius,
        builder: (context, s) => AnimatedContainer(
          duration: Tokens.durFast,
          constraints: const BoxConstraints(minHeight: Tokens.targetMin),
          padding: EdgeInsets.symmetric(
            horizontal: raised ? Tokens.space3 : Tokens.space2,
            vertical: Tokens.space2,
          ),
          decoration: BoxDecoration(
            color: raised
                ? Color.alphaBlend(pressWash(p, s), picked ? p.surface2 : p.surface)
                : pressWash(p, s, active: picked),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: raised ? Tokens.shadow1 : null,
          ),
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Level with the first line of text, not the middle of three.
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Bulb(lit: exact, color: p.success, size: 7),
                ),
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        language,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.body(
                          Tokens.textBase,
                          picked ? p.accent : p.ink,
                          weight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        matchLine(exact: exact),
                        style: Txt.body(Tokens.textSm, exact ? p.success : p.warning),
                      ),
                      if (small.isNotEmpty)
                        Text(
                          small,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.body(Tokens.textSm, p.inkMuted),
                        ),
                    ],
                  ),
                ),
                if (downloading) ...[
                  const SizedBox(width: Tokens.space2),
                  Padding(
                    padding: const EdgeInsets.only(top: Tokens.space1),
                    child: LucideIcon('download', size: 16, color: p.accent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
