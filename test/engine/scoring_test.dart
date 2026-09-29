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
const fps = 23.976;
String r2(double v) => v.toStringAsFixed(2);

// The four golden rows of §6.4, by file id.
final third = fixture('candidates-third-man.json');
SubtitleCandidate byId(String id) => third.firstWhere((c) => c.id == id);
final a = byId('1234567'); // hash-matched house release
final d = byId('1234570'); // same release, no hash
final c = byId('1234569'); // group match, fps mismatch, HI
final b = byId('1234568'); // H264 not x264, HI

double s(SubtitleCandidate x, {bool preferHI = false}) =>
    scoreCandidate(x, file, fps, preferHI).score;

List<ScoredCandidate> rank(
  Iterable<SubtitleCandidate> xs, {
  bool preferHI = false,
  List<String>? languages = const ['en'],
}) => rankCandidates(xs, parsed: file, containerFps: fps, preferHI: preferHI, languages: languages);

const machineE = SubtitleCandidate(
  provider: SubtitleProvider.openSubtitles,
  id: 'e',
  language: 'en',
  release: 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE',
  downloadCount: 99999,
  moviehashMatch: true,
  machineTranslated: true,
  fps: fps,
);

void main() {
  group('scoring', () {
    test('scores the hash-matched house release at 1414.09', () {
      expect(r2(s(a)), '1414.09');
      expect(scoreCandidate(a, file, fps, false).reasons, [
        'hash +1000',
        'group +200',
        'source +100',
        'res +50',
        'codec +20',
        'fps +40',
        'downloads +4.09',
      ]);
    });

    test('scores the same release without a hash match at 414.71', () {
      expect(r2(s(d)), '414.71');
    });

    test('lets a release-group match beat an fps mismatch at 232.96', () {
      expect(r2(s(c)), '232.96');
    });

    test('treats H264 and x264 as different codecs at 63.61', () {
      expect(r2(s(b)), '63.61');
      expect(scoreCandidate(b, file, fps, false).reasons, isNot(contains('codec +20')));
    });

    test('ranks A, D, C, B and auto-picks A', () {
      final ranked = rank([b, c, d, a]);
      expect(ranked.map((x) => x.candidate.id), ['1234567', '1234570', '1234569', '1234568']);
      expect(ranked.map((x) => r2(x.score)), ['1414.09', '414.71', '232.96', '63.61']);
      expect(autoPickOf(ranked)!.candidate.id, '1234567');
    });

    test('lists a machine-translated candidate below A but never auto-picks it', () {
      expect(s(machineE), lessThan(1414));
      final ranked = rank([machineE, a, d]);
      expect(ranked.first.candidate.id, '1234567');
      expect(ranked.firstWhere((x) => x.candidate.id == 'e').autoPick, isFalse);
      expect(scoreCandidate(machineE, file, fps, false).reasons, contains('machine -500'));
      const ai = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'ai',
        language: 'en',
        downloadCount: 10,
        aiTranslated: true,
      );
      expect(rank([ai]).first.autoPick, isFalse);
    });

    test('auto-picks the best human translation when rank 1 is machine-translated', () {
      final ranked = rank([machineE, d]);
      expect(ranked.first.candidate.id, 'e');
      expect(autoPickOf(ranked)!.candidate.id, '1234570');
      expect(autoPickOf(rank([machineE])), isNull);
      expect(autoPickOf(const []), isNull);
    });

    test('breaks ties on download count', () {
      const few = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'few',
        language: 'en',
        downloadCount: 0,
      );
      const more = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'more',
        language: 'en',
        downloadCount: 1,
      );
      // log10(max(0,1)) == log10(1) == 0: equal scores, so download count decides.
      final ranked = rankCandidates([few, more], parsed: null, containerFps: null, preferHI: false);
      expect(ranked.map((x) => x.score), [0, 0]);
      expect(ranked.map((x) => x.candidate.id), ['more', 'few']);
    });

    test('keeps every candidate in the ranked list', () {
      expect(rank([a, b, c, d, machineE]), hasLength(5));
    });

    test('applies the language filter before scoring', () {
      const hi = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'hi',
        language: 'hi',
        downloadCount: 999999,
        moviehashMatch: true,
      );
      expect(rank([hi, b]).map((x) => x.candidate.id), ['1234568']);
      expect(rank([hi, b], languages: const []), hasLength(2));
      expect(rank([hi], languages: const ['HI']), hasLength(1));
      expect(
        rank([hi, ...third], languages: const ['EN']).map((x) => x.candidate.language).toSet(),
        {'en'},
      );
    });

    test('adds 60 to hearing-impaired candidates when HI is preferred without moving A', () {
      expect(s(c, preferHI: true) - s(c), closeTo(60, 1e-6));
      expect(s(b, preferHI: true) - s(b), closeTo(60, 1e-6));
      expect(scoreCandidate(c, file, fps, true).reasons, contains('HI +30'));
      expect(scoreCandidate(c, file, fps, false).reasons, contains('HI -30'));
      expect(s(a, preferHI: true), closeTo(s(a), 1e-6));
      final ranked = rank([b, c, d, a], preferHI: true);
      expect(ranked.map((x) => r2(x.score)), ['1414.09', '414.71', '292.96', '123.61']);
      expect(ranked.first.candidate.id, '1234567');
      expect(ranked.first.autoPick, isTrue);
    });

    test('never lights the match bulb for a Subdl candidate', () {
      const sd = SubtitleCandidate(
        provider: SubtitleProvider.subdl,
        id: '/subtitle/1234-5678.zip',
        language: 'en',
        release: 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE',
      );
      expect(sd.moviehashMatch, isFalse);
      expect(scoreCandidate(sd, file, fps, false).reasons, isNot(contains('hash +1000')));
    });

    test('compares tokens case-insensitively and never matches null', () {
      expect(eqi('BluRay', 'bluray'), isTrue);
      expect(eqi('x264', 'X264'), isTrue);
      expect(eqi('x264', 'H264'), isFalse);
      expect(eqi(null, null), isFalse);
      expect(eqi(null, 'x264'), isFalse);
      expect(eqi('x264', null), isFalse);
    });

    test('skips release comparisons when either name is unknown', () {
      expect(scoreCandidate(a, null, null, false).reasons, ['hash +1000', 'downloads +4.09']);
      const n = SubtitleCandidate(
        provider: SubtitleProvider.openSubtitles,
        id: 'n',
        language: 'en',
      );
      expect(scoreCandidate(n, file, null, false).score, 0);
    });

    test('parses every OpenSubtitles search fixture', () {
      for (final f in ['search-hash-hit.json', 'search-by-name.json', 'search-miss.json']) {
        expect(() => fixture(f), returnsNormally);
      }
      expect(fixture('search-hash-hit.json').first.feature!.imdbId, 41959);
      expect(fixture('search-by-name.json').any((x) => x.machineTranslated), isTrue);
    });
  });
}
