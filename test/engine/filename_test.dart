import 'package:test/test.dart';
import 'package:marquee/engine/filename.dart';
import 'package:marquee/engine/models/subtitles.dart';

void main() {
  group('filename grammar', () {
    test('parses the house film', () {
      final p = parseName('The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv')!;
      expect(p.title, 'The Third Man');
      expect(p.year, 1949);
      expect(p.season, isNull);
      expect(p.episode, isNull);
      expect(p.resolution, '1080p');
      expect(p.source, 'BluRay');
      expect(p.videoCodecToken, 'x264');
      expect(p.group, 'AMIABLE');
      expect(p.kind, FeatureKind.movie);
      expect(p.confidence, NameConfidence.high);
    });

    test('flags a remastered release', () {
      final p = parseName('Chungking.Express.1994.REMASTERED.1080p.BluRay.x265-RARBG.mkv')!;
      expect(p.title, 'Chungking Express');
      expect(p.year, 1994);
      expect(p.resolution, '1080p');
      expect(p.source, 'BluRay');
      expect(p.videoCodecToken, 'x265');
      expect(p.group, 'RARBG');
      expect(p.remastered, isTrue);
    });

    test('keeps WEB-DL whole and H264 verbatim', () {
      final p = parseName('Paddington.2014.720p.WEB-DL.H264-NTb.mkv')!;
      expect(p.title, 'Paddington');
      expect(p.year, 2014);
      expect(p.resolution, '720p');
      expect(p.source, 'WEB-DL');
      expect(p.videoCodecToken, 'H264');
      expect(p.group, 'NTb');
    });

    test('reads season and episode', () {
      final p = parseName('Severance.S02E04.1080p.WEB.H264-NTb.mkv')!;
      expect(p.title, 'Severance');
      expect(p.year, isNull);
      expect(p.season, 2);
      expect(p.episode, 4);
      expect(p.resolution, '1080p');
      expect(p.source, 'WEB');
      expect(p.videoCodecToken, 'H264');
      expect(p.group, 'NTb');
      expect(p.kind, FeatureKind.episode);
    });

    test('handles spaces and a parenthesised year', () {
      final p = parseName('The Third Man (1949).mkv')!;
      expect(p.title, 'The Third Man');
      expect(p.year, 1949);
      expect(p.resolution, isNull);
      expect(p.source, isNull);
      expect(p.videoCodecToken, isNull);
      expect(p.group, isNull);
      expect(p.confidence, NameConfidence.high);
    });

    test('parses the anime bracket form and drops the CRC', () {
      final p = parseName('[SubsPlease] Frieren - 12 (1080p) [ABCD1234].mkv')!;
      expect(p.title, 'Frieren');
      expect(p.year, isNull);
      expect(p.season, isNull);
      expect(p.episode, 12);
      expect(p.resolution, '1080p');
      expect(p.source, isNull);
      expect(p.videoCodecToken, isNull);
      expect(p.group, 'SubsPlease');
      expect(p.kind, FeatureKind.episode);
    });

    test('gives a bare name low confidence so the raw filename is sent', () {
      final p = parseName('movie.mkv')!;
      expect(p.title, 'movie');
      expect(p.year, isNull);
      expect(p.group, isNull);
      expect(p.confidence, NameConfidence.low);
      expect(p.raw, 'movie.mkv');
    });

    test('rejects a subtitle file before parsing', () {
      expect(parseName('The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.en.srt'), isNull);
      expect(isSubtitleFile('x.ass'), isTrue);
      expect(isSubtitleFile('x.mkv'), isFalse);
    });

    test('does not steal a year that is part of the title', () {
      final p = parseName('Blade.Runner.2049.2017.2160p.UHD.BluRay.x265-TERMINAL.mkv')!;
      expect(p.title, 'Blade Runner 2049');
      expect(p.year, 2017);
      expect(p.group, 'TERMINAL');
    });

    test('never reads a trailing codec as the release group', () {
      final p = parseName('Some.Film.2010.1080p.BluRay-x265.mkv')!;
      expect(p.group, isNull);
      expect(p.videoCodecToken, 'x265');
    });

    test('parses a release name with no extension', () {
      final p = parseName('The.Third.Man.1949.BluRay-AMIABLE')!;
      expect(p.title, 'The Third Man');
      expect(p.source, 'BluRay');
      expect(p.resolution, isNull);
      expect(p.group, 'AMIABLE');
    });

    test('falls back to the parent directory when the basename is low confidence', () {
      final p = parsePath(r'D:\Films\The Third Man (1949)\video.mkv')!;
      expect(p.title, 'The Third Man');
      expect(p.year, 1949);
      expect(p.raw, 'video.mkv');
      expect(parsePath('/films/movie.mkv')!.confidence, NameConfidence.low);
    });
  });
}
