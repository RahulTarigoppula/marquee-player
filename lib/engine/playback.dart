// Small, pure rules behind the Auditorium's transport: seek clamping, the folder's natural
// order, speed presets, picture fits, language codes for mpv and the Android subtitle-font
// test. No Flutter, no mpv: the player layer and the widgets call these.
import 'dart:convert';

import 'models/media.dart';

/// Never seek before the start, and never past one second before the end (a seek onto EOF
/// would end the film on a key press). An unknown duration only clamps at zero.
Duration clampSeek(Duration target, Duration duration) {
  if (target < Duration.zero) return Duration.zero;
  if (duration <= Duration.zero) return target;
  final last = duration - const Duration(seconds: 1);
  final ceiling = last < Duration.zero ? Duration.zero : last;
  return target > ceiling ? ceiling : target;
}

/// `0`–`9` jump to 0 %–90 % of the film.
Duration percentSeek(int digit, Duration duration) => duration * (digit.clamp(0, 9) / 10);

/// `h:mm:ss` (or `m:ss` under an hour) — the short clock used in notices and tooltips.
String shortClock(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

// ───────────────────────────── the folder's order ─────────────────────────────

final _chunk = RegExp(r'\d+|\D+');

/// "Episode 2" before "Episode 10": digit runs compare as numbers, the rest case-insensitively.
int naturalCompare(String a, String b) {
  final xs = _chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final ys = _chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final x = xs[i], y = ys[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null
        ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length))
        : x.compareTo(y);
    if (c != 0) return c;
  }
  final c = xs.length.compareTo(ys.length);
  return c != 0 ? c : a.compareTo(b);
}

/// The files either side of [current] in [names] (basenames), in natural order.
({String? previous, String? next}) neighboursOf(List<String> names, String current) {
  final sorted = [...names]..sort(naturalCompare);
  final i = sorted.indexOf(current);
  if (i < 0) return (previous: null, next: null);
  return (
    previous: i > 0 ? sorted[i - 1] : null,
    next: i < sorted.length - 1 ? sorted[i + 1] : null,
  );
}

// ───────────────────────────── speed, fit, sleep ─────────────────────────────

const List<double> kSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// `[` / `]`: the next preset below or above [current] (an off-preset rate snaps to one).
double stepSpeed(double current, {required bool faster}) {
  if (faster) {
    for (final s in kSpeeds) {
      if (s > current + 0.001) return s;
    }
    return kSpeeds.last;
  }
  for (final s in kSpeeds.reversed) {
    if (s < current - 0.001) return s;
  }
  return kSpeeds.first;
}

/// `1×`, `1.25×`, `0.5×`.
String speedLabel(double rate) {
  final s = rate
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return '$s×';
}

/// How the picture meets the screen. The widget maps these to a BoxFit / aspect ratio.
enum PictureFit {
  fit('Fit'),
  fill('Fill (crop)'),
  wide('16:9'),
  classic('4:3'),
  stretch('Stretch');

  final String label;
  const PictureFit(this.label);

  PictureFit get next => values[(index + 1) % values.length];

  /// A forced display aspect, or null to keep the film's own.
  double? get forcedAspect => switch (this) {
    PictureFit.wide => 16 / 9,
    PictureFit.classic => 4 / 3,
    _ => null,
  };
}

enum SleepTimer {
  off('Off'),
  endOfFilm('End of this film'),
  min30('30 minutes'),
  min60('60 minutes');

  final String label;
  const SleepTimer(this.label);

  Duration? get after => switch (this) {
    SleepTimer.min30 => const Duration(minutes: 30),
    SleepTimer.min60 => const Duration(minutes: 60),
    _ => null,
  };
}

// ───────────────────────────── resume keys ─────────────────────────────

/// A stream has no moviehash; its resume point (and sync offset) is keyed by a 64-bit FNV-1a
/// of the URL instead, in the same 16-hex shape.
MovieHash urlResumeKey(String url) {
  // Native ints are 64-bit and wrap on overflow, which is exactly FNV's modulo 2^64.
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(url)) {
    h ^= b;
    h *= 0x100000001b3;
  }
  return MovieHash(BigInt.from(h).toUnsigned(64).toRadixString(16).padLeft(16, '0'));
}

// ───────────────────────────── languages ─────────────────────────────

/// ISO 639-1 → the 639-2 codes containers use (bibliographic and terminology forms).
const Map<String, List<String>> kIso639_2 = {
  'en': ['eng'], 'hi': ['hin'], 'ta': ['tam'], 'te': ['tel'], 'ml': ['mal'], //
  'bn': ['ben'], 'mr': ['mar'], 'es': ['spa'], 'fr': ['fra', 'fre'], 'de': ['deu', 'ger'],
  'it': ['ita'], 'pt': ['por'], 'ru': ['rus'], 'ja': ['jpn'], 'ko': ['kor'],
  'zh': ['zho', 'chi'], 'ar': ['ara'], 'nl': ['nld', 'dut'], 'sv': ['swe'], 'pl': ['pol'],
  'tr': ['tur'], 'he': ['heb'], 'fa': ['fas', 'per'], 'ur': ['urd'], 'th': ['tha'],
  'vi': ['vie'], 'id': ['ind'], 'el': ['ell', 'gre'], 'cs': ['ces', 'cze'],
  'ro': ['ron', 'rum'], 'hu': ['hun'], 'uk': ['ukr'], 'da': ['dan'], 'fi': ['fin'],
  'no': ['nor', 'nob'], 'ms': ['msa', 'may'], 'kn': ['kan'], 'gu': ['guj'], 'pa': ['pan'],
};

/// Every spelling of [codes] mpv may meet in a container, best first — for `alang`.
List<String> mpvLanguageList(List<String> codes) => [
  for (final c in codes) ...[c.toLowerCase(), ...?kIso639_2[c.toLowerCase()]],
];

/// Whether a track tagged [trackLanguage] (`en`, `eng`, `en-US`, `English`) is [wanted].
bool languageMatches(String? trackLanguage, String wanted) {
  if (trackLanguage == null || trackLanguage.isEmpty) return false;
  final t = trackLanguage.toLowerCase().split(RegExp('[-_]')).first;
  final w = wanted.toLowerCase();
  return t == w || (kIso639_2[w]?.contains(t) ?? false);
}

/// The bundled subtitle font (Noto Sans) covers Latin, Greek and Cyrillic only.
const Set<String> _otherScripts = {
  'hi', 'ta', 'te', 'ml', 'bn', 'mr', 'kn', 'gu', 'pa', 'ne', 'si', 'zh', 'ja', 'ko', 'ar', //
  'fa', 'ur', 'he', 'yi', 'th', 'lo', 'km', 'my', 'ka', 'hy', 'am',
};

/// True when [code] is a language written outside Latin / Greek / Cyrillic.
bool isNonLatinLanguage(String? code) =>
    code != null && _otherScripts.any((l) => languageMatches(code, l));

/// True when [text] holds a character the bundled subtitle font cannot draw (Arabic,
/// Devanagari, CJK, Thai, …). Punctuation, symbols and the Latin extensions do not count.
bool needsSystemFonts(String text) {
  for (final r in text.runes) {
    if (r < 0x0530) continue; // Latin, IPA, combining marks, Greek, Cyrillic
    if (r >= 0x1D00 && r <= 0x2BFF) continue; // Latin/Greek ext., punctuation, symbols
    if (r >= 0x2DE0 && r <= 0x2DFF) continue; // Cyrillic Extended-A
    if (r >= 0xA640 && r <= 0xA69F) continue; // Cyrillic Extended-B
    if (r >= 0xA720 && r <= 0xA7FF) continue; // Latin Extended-D
    if (r >= 0xFB00 && r <= 0xFB06) continue; // Latin ligatures
    if (r >= 0xFE00 && r <= 0xFE2F) continue; // variation selectors, half marks
    if (r == 0xFEFF || r == 0xFFFD) continue;
    return true;
  }
  return false;
}
