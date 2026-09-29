import 'dart:convert';
import 'dart:io';

import 'package:marquee/engine/filename.dart';
import 'package:marquee/engine/models/subtitles.dart';
import 'package:marquee/engine/scoring.dart';
import 'package:test/test.dart';

List<SubtitleCandidate> fixture(String name) {
  final j = jsonDecode(File('test/fixtures/os/$name').readAsStringSync()) as Map<String, Object?>;
  return (j['data']! as List)
      .cast<Map<String, Object?>>()
      .map(SubtitleCandidate.fromOpenSubtitles)
      .whereType<SubtitleCandidate>()
      .toList();
}

final file = parseName('The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv');
String r2(double v) => v.toStringAsFixed(2);

void main() {
  group('scoring', () {
    test('ranks the Third Man candidates A, D, C, B with the frozen scores', () {
      final ranked = rankCandidates(
        fixture('candidates-third-man.json'),
        parsed: file,
        containerFps: 23.976,
        preferHI: false,
      );
      expect(ranked.map((s) => r2(s.score)), ['1414.09', '414.71', '232.96', '63.61']);
      expect(ranked.map((s) => s.candidate.id), ['1234567', '1234570', '1234569', '1234568']);
      expect(autoPickOf(ranked)!.candidate.id, '1234567');
    });

    test('explains a score with its reasons', () {
      final a = fixture('candidates-third-man.json').firstWhere((c) => c.moviehashMatch);
      final s = scoreCandidate(a, file, 23.976, false);
      expect(s.reasons, [
        'hash +1000',
        'group +200',
        'source +100',
        'res +50',
        'codec +20',
        'fps +40',
        'downloads +4.09',
      ]);
    });

    test('treats x264 and H264 as different codec tokens', () {
      expect(eqi('x264', 'H264'), isFalse);
      expect(eqi('x264', 'X264'), isTrue);
      expect(eqi(null, null), isFalse);
    });

    test('lists a machine-translated hash match but never auto-picks it', () {
      const e = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'e',
        language: 'en',
        release: 'Some.Other.Release',
        downloadCount: 99999,
        moviehashMatch: true,
        machineTranslated: true,
        fps: 23.976,
      );
      final ranked = rankCandidates(
        [e, ...fixture('candidates-third-man.json')],
        parsed: file,
        containerFps: 23.976,
        preferHI: false,
      );
      final scoredE = ranked.firstWhere((s) => s.candidate.id == 'e');
      expect(scoredE.autoPick, isFalse);
      expect(scoredE.score, lessThan(1414));
      expect(ranked.first.candidate.id, '1234567');
      expect(ranked, hasLength(5));
    });

    test('never auto-picks when rank 1 is machine translated', () {
      const e = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'e',
        language: 'en',
        downloadCount: 10,
        moviehashMatch: true,
        aiTranslated: true,
      );
      final ranked = rankCandidates([e], parsed: file, containerFps: null, preferHI: false);
      expect(autoPickOf(ranked), isNull);
      expect(autoPickOf(const []), isNull);
    });

    test('gives hearing-impaired rows +60 relative when HI is preferred', () {
      final ranked = rankCandidates(
        fixture('candidates-third-man.json'),
        parsed: file,
        containerFps: 23.976,
        preferHI: true,
      );
      expect(ranked.map((s) => r2(s.score)), ['1414.09', '414.71', '292.96', '123.61']);
    });

    test('breaks ties on download count', () {
      const a = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'few',
        language: 'en',
        downloadCount: 0,
      );
      const b = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'more',
        language: 'en',
        downloadCount: 1,
      );
      // log10(max(0,1)) == log10(1) == 0: equal scores, so download count decides.
      final ranked = rankCandidates([a, b], parsed: null, containerFps: null, preferHI: false);
      expect(ranked.map((s) => s.candidate.id), ['more', 'few']);
    });

    test('applies the language filter before scoring and keeps every other row', () {
      const hi = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'hi',
        language: 'hi',
        moviehashMatch: true,
      );
      final ranked = rankCandidates(
        [hi, ...fixture('candidates-third-man.json')],
        parsed: file,
        containerFps: 23.976,
        preferHI: false,
        languages: ['EN'],
      );
      expect(ranked.map((s) => s.candidate.language).toSet(), {'en'});
      expect(ranked, hasLength(4));
    });

    test('never lights MATCH for a Subdl candidate', () {
      const s = SubtitleCandidate(provider: SubtitleProvider.subdl, id: '/x.zip', language: 'en');
      expect(scoreCandidate(s, file, null, false).reasons, isNot(contains('hash +1000')));
    });

    test('parses every OpenSubtitles search fixture', () {
      for (final f in ['search-hash-hit.json', 'search-by-name.json', 'search-miss.json']) {
        expect(() => fixture(f), returnsNormally);
      }
      expect(fixture('search-hash-hit.json').first.feature!.imdbId, 41959);
      expect(fixture('search-by-name.json').any((c) => c.machineTranslated), isTrue);
    });
  });
}
