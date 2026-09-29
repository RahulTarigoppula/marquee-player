import 'dart:convert';
import 'dart:io';

import 'package:marquee/engine/srt.dart';
import 'package:test/test.dart';

String read(String name) => utf8.decode(File('test/fixtures/$name').readAsBytesSync());

void main() {
  group('srt to vtt', () {
    test('converts the BOM + CRLF fixture byte for byte', () {
      expect(srtToVtt(read('sample-crlf-bom.srt')), read('sample-crlf-bom.expected.vtt'));
    });

    test('sorts cues by start and renumbers them', () {
      final cues = parseSrt(read('sample-crlf-bom.srt'));
      expect(cues.map((c) => c.startMs), [1000, 62500]);
      expect(toVtt(cues).split('\n')[2], '1');
    });

    test('shifts every cue by the delay', () {
      final vtt = srtToVtt(read('sample-crlf-bom.srt'), shiftMs: 350);
      expect(vtt, contains('00:00:01.350 --> 00:00:02.850'));
      expect(vtt, contains('00:01:02.850 --> 00:01:04.350'));
    });

    test('clamps a negative shift at zero and keeps overlaps', () {
      final cues = parseSrt(
        '1\n00:00:00,200 --> 00:00:01,000\nA\n\n2\n00:00:00,500 --> 00:00:02,000\nB\n',
      );
      final shifted = shiftCues(cues, -350);
      expect(shifted.map((c) => [c.startMs, c.endMs]), [
        [0, 650],
        [150, 1650],
      ]);
      final vtt = srtToVtt(read('sample-crlf-bom.srt'), shiftMs: -5000);
      expect(vtt, contains('00:00:00.000 --> 00:00:00.000'));
      expect(vtt, isNot(contains('-0')));
    });

    test('keeps italic, bold and underline tags and strips font tags to their text', () {
      final cues = parseSrt(
        '1\n00:00:01,000 --> 00:00:02,000\n'
        '<font color="#ff0000"><b>Red</b></font> <u>u</u> <i>i</i>\n',
      );
      expect(cues.first.text, '<b>Red</b> <u>u</u> <i>i</i>');
    });

    test('strips unknown tags, defuses a literal arrow and trims the cue', () {
      final cues = parseSrt(
        '1\n00:00:01,000 --> 00:00:02,000\n'
        '  <span class="x">left</span> --> <I>right</I>  \n\n'
        '2\n00:00:03,000 --> 00:00:04,000\n<font color="red"> </font>\n',
      );
      expect(cues, hasLength(1));
      expect(cues.single.text, 'left → <I>right</I>');
    });

    test('turns a leading an8 override into line 0', () {
      final vtt = srtToVtt(read('sample.srt'));
      expect(vtt, contains('00:00:07.000 --> 00:00:09.000 line:0\nTop of the frame.'));
      expect(vtt, isNot(contains(r'{\an8}')));
    });

    test('caps a cue at 10000 characters', () {
      final srt = '1\n00:00:01,000 --> 00:00:02,000\n${'x' * 20000}\n';
      expect(parseSrt(srt).single.text.length, kMaxCueChars);
      expect(kMaxCueChars, 10000);
    });

    test('ignores stray text outside a cue and a timing with no text', () {
      final cues = parseSrt(
        'garbage\n\n1\n00:00:01,000 --> 00:00:02,000\n\n2\n00:00:03.5 --> 00:00:04,000\nok',
      );
      expect(cues, hasLength(1));
      expect(cues.first.startMs, 3500);
    });

    test('formats VTT timestamps with milliseconds and unbounded hours', () {
      final vtt = toVtt(const [Cue(0, 45000123, 'x')]);
      expect(vtt, contains('00:00:00.000 --> 12:30:00.123'));
      expect(toVtt(shiftCues(const [Cue(0, 10, 'x')], -1)), contains('00:00:00.000 --> '));
    });

    test('emits renumbered SRT', () {
      final cues = parseSrt(read('sample-crlf-bom.srt'));
      expect(toSrt(cues), startsWith('1\n00:00:01,000 --> 00:00:02,500\nFirst line\n\n2\n'));
    });
  });
}
