// Candidate ranking with the FROZEN weights (§6.4). If a weight changes, the golden table in
// docs/IMPLEMENTATION-PROMPT.md §6.4 changes in the same commit.
import 'dart:math' as math;

import 'filename.dart';
import 'models/subtitles.dart';

const double kHashWeight = 1000;
const double kGroupWeight = 200;
const double kSourceWeight = 100;
const double kResolutionWeight = 50;
const double kCodecWeight = 20;
const double kFpsWeight = 40; // ± — a release-group match still beats an fps mismatch
const double kHearingImpairedWeight = 30; // ± by preference
const double kMachinePenalty = 500;
const double kFpsTolerance = 0.01;

/// Case-insensitive EXACT token equality (R4): `x264` and `H264` are different provenance.
/// Two unknowns are not a match.
bool eqi(String? a, String? b) => a != null && b != null && a.toLowerCase() == b.toLowerCase();

String _fmt(double v) => v.toStringAsFixed(2);

ScoredCandidate scoreCandidate(
  SubtitleCandidate c,
  ParsedName? n,
  double? containerFps,
  bool preferHI,
) {
  var s = 0.0;
  final why = <String>[];
  if (c.moviehashMatch) {
    s += kHashWeight;
    why.add('hash +1000');
  }
  final release = c.release;
  final r = release == null ? null : parseName(release);
  if (n != null && r != null) {
    if (eqi(r.group, n.group)) {
      s += kGroupWeight;
      why.add('group +200');
    }
    if (eqi(r.source, n.source)) {
      s += kSourceWeight;
      why.add('source +100');
    }
    if (eqi(r.resolution, n.resolution)) {
      s += kResolutionWeight;
      why.add('res +50');
    }
    if (eqi(r.videoCodecToken, n.videoCodecToken)) {
      s += kCodecWeight;
      why.add('codec +20');
    }
  }
  final fps = c.fps;
  if (containerFps != null && fps != null) {
    final same = (fps - containerFps).abs() <= kFpsTolerance;
    s += same ? kFpsWeight : -kFpsWeight;
    why.add(same ? 'fps +40' : 'fps -40');
  }
  if (c.hearingImpaired) {
    s += preferHI ? kHearingImpairedWeight : -kHearingImpairedWeight;
    why.add(preferHI ? 'HI +30' : 'HI -30');
  }
  final machine = c.machineTranslated || c.aiTranslated;
  if (machine) {
    s -= kMachinePenalty;
    why.add('machine -500');
  }
  final dl = math.log(math.max(c.downloadCount, 1)) / math.ln10; // log10 — the tie-breaker
  s += dl;
  why.add('downloads +${_fmt(dl)}');
  return ScoredCandidate(candidate: c, score: s, reasons: why, autoPick: !machine);
}

/// Ordered, NEVER filtered — except by language, which is applied before scoring.
/// Ties break on download_count.
List<ScoredCandidate> rankCandidates(
  Iterable<SubtitleCandidate> candidates, {
  required ParsedName? parsed,
  required double? containerFps,
  required bool preferHI,
  List<String>? languages,
}) {
  final langs = languages?.map((l) => l.toLowerCase()).toSet();
  final scored = [
    for (final c in candidates)
      if (langs == null || langs.isEmpty || langs.contains(c.language.toLowerCase()))
        scoreCandidate(c, parsed, containerFps, preferHI),
  ];
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return b.candidate.downloadCount.compareTo(a.candidate.downloadCount);
  });
  return scored;
}

/// The auto-pick is the highest-ranked row that may be auto-picked: machine/AI-translated rows
/// are listed but skipped, so a human translation below a machine-translated rank 1 is picked.
/// None when every row is machine/AI translated.
ScoredCandidate? autoPickOf(List<ScoredCandidate> ranked) {
  for (final s in ranked) {
    if (s.autoPick) return s;
  }
  return null;
}
