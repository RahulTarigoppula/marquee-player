import 'dart:convert';
import 'dart:io';

import 'package:marquee/engine/srt.dart';
import 'package:test/test.dart';

String read(String name) => utf8.decode(File('test/fixtures/$name').readAsBytesSync());

void main() {
  group('srt to vtt', () {
    test('converts the BOM + CRLF + out-of-order sample byte for byte', () {
      expect(srtToVtt(read('sample-crlf-bom.srt')), read('sample-crlf-bom.expected.vtt'));
    });

    test('shifts every cue by the delay', () {
      final vtt = srtToVtt(read('sample-crlf-bom.srt'), shiftMs: 350);
      expect(vtt, contains('00:01:02.850 --> 00:01:04.350'));
      expect(vtt, contains('00:00:01.350 --> 00:00:02.850'));
    });

    test('never produces a negative start', () {
      final vtt = srtToVtt(read('sample-crlf-bom.srt'), shiftMs: -5000);
      expect(vtt, contains('00:00:00.000 --> 00:00:00.000'));
      expect(vtt, isNot(contains('-0')));
    });

    test('moves an an8 cue to the top line', () {
      final vtt = srtToVtt(read('sample.srt'));
      expect(vtt, contains('00:00:07.000 --> 00:00:09.000 line:0\nTop of the frame.'));
    });

    test('keeps italics and strips font tags', () {
      const srt = '1\n00:00:01,000 --> 00:00:02,000\n<font color="#fff">plain</font> <i>it</i>\n';
      expect(srtToVtt(srt), contains('plain <i>it</i>'));
    });

    test('caps a runaway cue at 10000 characters', () {
      final srt = '1\n00:00:01,000 --> 00:00:02,000\n${'x' * 20000}\n';
      expect(parseSrt(srt).single.text.length, kMaxCueChars);
    });

    test('emits renumbered SRT', () {
      final cues = parseSrt(read('sample-crlf-bom.srt'));
      expect(toSrt(cues), startsWith('1\n00:00:01,000 --> 00:00:02,500\nFirst line\n\n2\n'));
    });
  });
}
