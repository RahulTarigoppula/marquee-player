// SRT parse / shift / emit (§6.11). A line state machine: no eval, anchored patterns, each cue
// capped at 10 000 characters so unbounded input cannot cause backtracking trouble.
const int kMaxCueChars = 10000;

final _timing = RegExp(
  r'^(\d{1,3}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,3}):(\d{2}):(\d{2})[,.](\d{1,3})(.*)$',
);
// Keep <i> <b> <u> (VTT supports them); strip every other tag, <font …> included, to its text.
final _foreignTag = RegExp(r'<(?!/?[ibu]>)[^>]{0,200}>', caseSensitive: false);
final _an8 = RegExp(r'^\{\\an8\}');
final _assOverride = RegExp(r'\{\\[^}]{0,200}\}');

class Cue {
  final int startMs;
  final int endMs;
  final String text;
  final String settings;
  const Cue(this.startMs, this.endMs, this.text, {this.settings = ''});
}

int _ms(String h, String m, String s, String frac) =>
    int.parse(h) * 3600000 +
    int.parse(m) * 60000 +
    int.parse(s) * 1000 +
    int.parse(frac.padRight(3, '0'));

/// Parses SRT text (BOM and CRLF tolerant) into cues sorted by start time.
List<Cue> parseSrt(String input) {
  var text = input.startsWith('﻿') ? input.substring(1) : input;
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final cues = <Cue>[];
  int? start, end;
  var settings = '';
  final body = <String>[];

  void flush() {
    if (start != null && end != null) {
      // Same order as srt2vtt.ts: trim, an8 → line:0, strip overrides and foreign tags, defuse
      // a literal "-->" (it would read as a cue timing), trim again, cap. Empty cues are dropped.
      var t = body.join('\n').trim();
      var cueSettings = settings;
      if (_an8.hasMatch(t)) cueSettings = '$cueSettings line:0'.trim();
      t = t.replaceAll(_assOverride, '').replaceAll(_foreignTag, '').replaceAll('-->', '→').trim();
      if (t.length > kMaxCueChars) t = t.substring(0, kMaxCueChars);
      if (t.isNotEmpty) cues.add(Cue(start!, end!, t, settings: cueSettings));
    }
    start = null;
    end = null;
    settings = '';
    body.clear();
  }

  for (final line in text.split('\n')) {
    final m = _timing.firstMatch(line.trim());
    if (m != null) {
      // A timing line always opens a new cue; a numeric line before it is just the index.
      if (body.isNotEmpty && RegExp(r'^\d+$').hasMatch(body.last.trim())) body.removeLast();
      flush();
      start = _ms(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!);
      end = _ms(m.group(5)!, m.group(6)!, m.group(7)!, m.group(8)!);
      continue;
    }
    if (line.trim().isEmpty) {
      if (start != null) flush();
      continue;
    }
    if (start != null) body.add(line);
  }
  flush();
  cues.sort((a, b) => a.startMs.compareTo(b.startMs));
  return cues;
}

/// Every start/end += ms, CLAMPED at zero; overlaps preserved (VTT allows them).
List<Cue> shiftCues(List<Cue> cues, int ms) => [
  for (final c in cues)
    Cue(
      (c.startMs + ms).clamp(0, 1 << 40),
      (c.endMs + ms).clamp(0, 1 << 40),
      c.text,
      settings: c.settings,
    ),
];

String _stamp(int ms, String sep) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  final f = ms % 1000;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)}$sep${f.toString().padLeft(3, '0')}';
}

String toVtt(List<Cue> cues) {
  final b = StringBuffer('WEBVTT\n');
  for (var i = 0; i < cues.length; i++) {
    final c = cues[i];
    final settings = c.settings.isEmpty ? '' : ' ${c.settings}';
    b.write(
      '\n${i + 1}\n${_stamp(c.startMs, '.')} --> ${_stamp(c.endMs, '.')}$settings\n${c.text}\n',
    );
  }
  return b.toString();
}

/// Renumbered SRT (used for "save beside file with the offset baked in").
String toSrt(List<Cue> cues) {
  final b = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final c = cues[i];
    if (i > 0) b.write('\n');
    b.write('${i + 1}\n${_stamp(c.startMs, ',')} --> ${_stamp(c.endMs, ',')}\n${c.text}\n');
  }
  return b.toString();
}

String srtToVtt(String srt, {int shiftMs = 0}) => toVtt(shiftCues(parseSrt(srt), shiftMs));
