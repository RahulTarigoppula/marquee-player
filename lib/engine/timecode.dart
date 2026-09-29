// Folio timecodes (§6.7). Position FLOORS, remaining CEILS, so they always add up to the
// duration. HH is unbounded (12:30:00 never wraps), the minus is U+2212, never a hyphen.
const String kMinus = '−';
const int kTitleMax = 40;

String _two(int n) => n.toString().padLeft(2, '0');

/// HH:MM:SS with HH unbounded.
String fmtTimecode(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${_two(s ~/ 3600)}:${_two((s % 3600) ~/ 60)}:${_two(s % 60)}';
}

String folio(double position, double? duration) {
  final pos = position.isNaN || position < 0 ? 0 : position.floor();
  if (duration == null || duration.isNaN || duration <= 0) return '${fmtTimecode(pos)} · —';
  final remaining = duration.ceil() - pos;
  return '${fmtTimecode(pos)} · $kMinus${fmtTimecode(remaining < 0 ? 0 : remaining)}';
}

/// `SUB +0.35` style suffix; empty when no offset is set.
String subSuffix(int delayMs) {
  if (delayMs == 0) return '';
  final sign = delayMs > 0 ? '+' : kMinus;
  return 'SUB $sign${(delayMs.abs() / 1000).toStringAsFixed(2)}';
}

/// Title uppercased and condensed to 40 chars with an ellipsis.
String folioTitle(String title) {
  final t = title.toUpperCase().trim();
  return t.length <= kTitleMax ? t : '${t.substring(0, kTitleMax - 1).trimRight()}…';
}

/// `REEL 01 · THE THIRD MAN · 01:12:44 · −01:28:19` (+ suffixes, which append, never replace).
String auditoriumFolio({
  String? title,
  required double position,
  double? duration,
  List<String> suffixes = const [],
}) {
  final parts = <String>[
    'REEL 01',
    if (title != null && title.isNotEmpty) folioTitle(title),
    folio(position, duration),
    ...suffixes.where((s) => s.isNotEmpty),
  ];
  return parts.join(' · ');
}

const String kThreadingFolio = 'REEL 01 · THREADING';
