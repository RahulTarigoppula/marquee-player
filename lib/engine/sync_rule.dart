// The sync rule (§6.8). Positive means the subtitles appear LATER. Values are in whole
// milliseconds so 50 ms detents never accumulate floating-point drift.
import 'timecode.dart' show kMinus;

const int kDetentMs = 50;
const int kBigStepMs = 500;
const int kRangeMs = 2000;

/// ROUND to the nearest 50 ms detent (not floor), clamped to ±2.00 s.
int snapMs(num ms) {
  final snapped = (ms / kDetentMs).round() * kDetentMs;
  return snapped.clamp(-kRangeMs, kRangeMs);
}

/// Seconds in, milliseconds out — what a ruler drag produces.
int snapSeconds(double seconds) => snapMs(seconds * 1000);

/// `J` = earlier (−), `K` = later (+); Shift makes it 500 ms.
int stepMs(int current, {required bool later, bool shift = false}) =>
    snapMs(current + (shift ? kBigStepMs : kDetentMs) * (later ? 1 : -1));

const int resetMs = 0;

/// `+0.35` / `−0.30` / `+0.00` — for the readout (`SYNC +0.35`) and the Lobby chip.
String formatDelay(int ms) {
  final sign = ms < 0 ? kMinus : '+';
  return '$sign${(ms.abs() / 1000).toStringAsFixed(2)}';
}

/// What mpv's `sub-delay` property receives.
String mpvSubDelay(int ms) => (ms / 1000).toStringAsFixed(2);

/// `plus 0.35 seconds` — the slider's aria-valuetext / semantics value.
String spokenDelay(int ms) =>
    '${ms < 0 ? 'minus' : 'plus'} ${(ms.abs() / 1000).toStringAsFixed(2)} seconds';
