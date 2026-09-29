// Film-gate detents (§6.9): chapters from mpv `chapter-list`, else every 5 minutes.
import 'models/media.dart';

const double kCaptureRadiusPx = 6; // at the gate's RENDERED width
const double kFallbackDetentSeconds = 300;
const double kFineGain = 1 / 8; // 80 px of finger = 10 px of gate

List<double> detentsFor(List<Chapter> chapters, double durationSeconds) {
  if (chapters.isNotEmpty) {
    return [for (final c in chapters) c.startSeconds]..sort();
  }
  if (durationSeconds <= 0) return const [0];
  return [for (var t = 0.0; t <= durationSeconds; t += kFallbackDetentSeconds) t];
}

class SnapResult {
  final double seconds;
  final bool snapped;
  const SnapResult(this.seconds, {required this.snapped});
}

/// Snaps the release point to the nearest detent within 6 px; otherwise seeks exactly there.
SnapResult snapTarget({
  required double releasePx,
  required double gateWidthPx,
  required double durationSeconds,
  required List<double> detents,
}) {
  if (gateWidthPx <= 0 || durationSeconds <= 0) return const SnapResult(0, snapped: false);
  final x = releasePx.clamp(0.0, gateWidthPx);
  final secondsPerPx = durationSeconds / gateWidthPx;
  double? best;
  var bestDist = double.infinity;
  for (final d in detents) {
    final dist = (d / secondsPerPx - x).abs();
    if (dist < bestDist) {
      bestDist = dist;
      best = d;
    }
  }
  if (best != null && bestDist <= kCaptureRadiusPx) return SnapResult(best, snapped: true);
  return SnapResult(x * secondsPerPx, snapped: false);
}

/// FINE mode: detents disabled, 1/8 gain.
double fineSeek({
  required double startSeconds,
  required double dragPx,
  required double gateWidthPx,
  required double durationSeconds,
}) {
  if (gateWidthPx <= 0) return startSeconds;
  final secondsPerPx = durationSeconds / gateWidthPx;
  return (startSeconds + dragPx * kFineGain * secondsPerPx).clamp(0.0, durationSeconds);
}

/// True when a drag from [fromSeconds] to [toSeconds] crosses a detent (selection tick).
bool crossesDetent(double fromSeconds, double toSeconds, List<double> detents) {
  final lo = fromSeconds < toSeconds ? fromSeconds : toSeconds;
  final hi = fromSeconds < toSeconds ? toSeconds : fromSeconds;
  return detents.any((d) => d > lo && d <= hi);
}
