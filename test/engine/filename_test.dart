import 'package:test/test.dart';
import 'package:marquee/engine/filename.dart';
import 'package:marquee/engine/models/subtitles.dart';

void main() {
  group('filename grammar', () {
    test('parses the house film with year, resolution, source, codec and group', () {
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

    test('flags a remastered release and keeps the title before the flag', () {
      final p = parseName('Chungking.Express.1994.REMASTERED.1080p.BluRay.x265-RARBG.mkv')!;
      expect(p.title, 'Chungking Express');
      expect(p.year, 1994);
      expect(p.resolution, '1080p');
      expect(p.source, 'BluRay');
      expect(p.videoCodecToken, 'x265');
      expect(p.group, 'RARBG');
      expect(p.remastered, isTrue);
    });

    test('keeps a WEB-DL source whole and the H264 codec token verbatim', () {
      final p = parseName('Paddington.2014.720p.WEB-DL.H264-NTb.mkv')!;
      expect(p.title, 'Paddington');
      expect(p.year, 2014);
      expect(p.resolution, '720p');
      expect(p.source, 'WEB-DL');
      expect(p.videoCodecToken, 'H264');
      expect(p.group, 'NTb');
    });

    test('parses season and episode as an episode', () {
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

    test('reads a year in parentheses from a name with spaces', () {
      final p = parseName('The Third Man (1949).mkv')!;
      expect(p.title, 'The Third Man');
      expect(p.year, 1949);
      expect(p.resolution, isNull);
      expect(p.source, isNull);
      expect(p.videoCodecToken, isNull);
      expect(p.group, isNull);
      expect(p.confidence, NameConfidence.high);
    });

    test('parses the anime bracket form and discards the trailing CRC', () {
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

    test('gives a bare name low confidence so the raw filename is searched', () {
      final p = parseName('movie.mkv')!;
      expect(p.title, 'movie');
      expect(p.year, isNull);
      expect(p.group, isNull);
      expect(p.confidence, NameConfidence.low);
      expect(p.raw, 'movie.mkv');
    });

    test('rejects a subtitle file as not a video', () {
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

    test('treats a trailing codec after the last dash as a codec, not a group', () {
      final p = parseName('Some.Film.2010.1080p.BluRay-x265.mkv')!;
      expect(p.group, isNull);
      expect(p.videoCodecToken, 'x265');
    });

    test('parses a release name with a group glued to the source', () {
      final p = parseName('The.Third.Man.1949.BluRay-AMIABLE')!;
      expect(p.title, 'The Third Man');
      expect(p.source, 'BluRay');
      expect(p.resolution, isNull);
      expect(p.group, 'AMIABLE');
    });

    test('parses the 1x03 and Season Episode forms', () {
      final a = parseName('Fargo 1x03 720p HDTV.mkv')!;
      expect(a.title, 'Fargo');
      expect(a.season, 1);
      expect(a.episode, 3);
      expect(a.source, 'HDTV');
      final b = parseName('Fargo Season 2 Episode 5.mkv')!;
      expect(b.title, 'Fargo');
      expect(b.season, 2);
      expect(b.episode, 5);
      expect(b.kind, FeatureKind.episode);
    });

    test('gives a multi-word title with quality tokens but no year medium confidence', () {
      final a = parseName('Some Great Film 1080p BluRay.mkv')!;
      expect(a.title, 'Some Great Film');
      expect(a.confidence, NameConfidence.medium);
      expect(a.proper, isFalse);
      final b = parseName('Film.PROPER.EXTENDED.720p.mkv')!;
      expect(b.proper, isTrue);
      expect(b.extended, isTrue);
    });

    test('falls back to the parent directory when the basename is low confidence', () {
      final p = parsePath(r'D:\Films\The Third Man (1949)\video.mkv')!;
      expect(p.title, 'The Third Man');
      expect(p.year, 1949);
      expect(p.raw, 'video.mkv');
      expect(parsePath('/films/movie.mkv')!.confidence, NameConfidence.low);
      final v = parsePath('/films/video.mkv')!;
      expect(v.title, 'video');
      expect(v.confidence, NameConfidence.low);
      expect(parsePath('The.Third.Man.1949.mkv')!.title, 'The Third Man');
    });
  });
}
