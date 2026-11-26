import 'package:marquee/engine/filename.dart';
import 'package:marquee/engine/models/media.dart';
import 'package:marquee/engine/models/settings.dart';
import 'package:marquee/engine/picture.dart';
import 'package:marquee/engine/playback.dart';
import 'package:test/test.dart';

void main() {
  group('seek clamping', () {
    const dur = Duration(minutes: 100);

    test('never seeks before the start', () {
      expect(clampSeek(const Duration(seconds: -12), dur), Duration.zero);
    });

    test('stops one second short of the end', () {
      expect(clampSeek(dur + const Duration(seconds: 30), dur), dur - const Duration(seconds: 1));
      expect(clampSeek(dur, dur), dur - const Duration(seconds: 1));
    });

    test('passes an in-range target through', () {
      expect(clampSeek(const Duration(minutes: 3), dur), const Duration(minutes: 3));
    });

    test('only clamps at zero while the duration is unknown', () {
      expect(clampSeek(const Duration(hours: 9), Duration.zero), const Duration(hours: 9));
    });

    test('holds a sub-second film at zero', () {
      const tiny = Duration(milliseconds: 400);
      expect(clampSeek(const Duration(milliseconds: 300), tiny), Duration.zero);
    });

    test('maps the digit keys to tenths of the film', () {
      expect(percentSeek(0, dur), Duration.zero);
      expect(percentSeek(5, dur), const Duration(minutes: 50));
      expect(percentSeek(9, dur), const Duration(minutes: 90));
      expect(percentSeek(12, dur), const Duration(minutes: 90));
    });

    test('ticks the controls once a second for a feature, finer for a short clip', () {
      expect(clockStep(const Duration(hours: 2)), const Duration(seconds: 1));
      expect(clockStep(const Duration(seconds: 30)), const Duration(milliseconds: 100));
      expect(clockStep(Duration.zero), const Duration(milliseconds: 100));
      expect(clockStep(const Duration(minutes: 15)), const Duration(milliseconds: 600));
    });

    test('rounds the position down to the tick, so equal ticks compare equal', () {
      const film = Duration(hours: 2);
      final a = clockTick(const Duration(milliseconds: 61100), film);
      final b = clockTick(const Duration(milliseconds: 61900), film);
      expect(a, const Duration(seconds: 61));
      expect(a, b);
      expect(
        clockTick(const Duration(milliseconds: 1250), const Duration(seconds: 20)),
        const Duration(milliseconds: 1200),
      );
    });

    test('prints a short clock', () {
      expect(shortClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(shortClock(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(shortClock(const Duration(seconds: -3)), '0:00');
    });
  });

  group('natural order', () {
    test('compares digit runs as numbers', () {
      final files = ['Ep 10.mkv', 'Ep 2.mkv', 'ep 1.mkv', 'Ep 2b.mkv'];
      files.sort(naturalCompare);
      expect(files, ['ep 1.mkv', 'Ep 2.mkv', 'Ep 2b.mkv', 'Ep 10.mkv']);
    });

    test('orders zero-padded twins deterministically', () {
      expect(naturalCompare('S01E02', 'S01E002'), lessThan(0));
      expect(naturalCompare('a', 'a'), 0);
      expect(naturalCompare('a1', 'a1x'), lessThan(0));
    });

    test('finds the neighbours of the playing file', () {
      final names = ['Show S01E03.mkv', 'Show S01E01.mkv', 'Show S01E02.mkv'];
      final n = neighboursOf(names, 'Show S01E02.mkv');
      expect(n.previous, 'Show S01E01.mkv');
      expect(n.next, 'Show S01E03.mkv');
      final first = neighboursOf(names, 'Show S01E01.mkv');
      expect(first.previous, isNull);
      final last = neighboursOf(names, 'Show S01E03.mkv');
      expect(last.next, isNull);
      expect(neighboursOf(names, 'other.mkv').next, isNull);
    });

    test('lists only video containers', () {
      expect(isVideoFile('a.MKV'), isTrue);
      expect(isVideoFile('a.srt'), isFalse);
      expect(isVideoFile('README'), isFalse);
    });
  });

  group('speed and picture', () {
    test('steps through the presets', () {
      expect(stepSpeed(1, faster: true), 1.25);
      expect(stepSpeed(1, faster: false), 0.75);
      expect(stepSpeed(2, faster: true), 2);
      expect(stepSpeed(0.25, faster: false), 0.25);
      expect(stepSpeed(1.1, faster: false), 1);
    });

    test('labels a rate without trailing zeros', () {
      expect(speedLabel(1), '1×');
      expect(speedLabel(1.25), '1.25×');
      expect(speedLabel(0.5), '0.5×');
    });

    test('cycles the picture fits', () {
      expect(PictureFit.fit.next, PictureFit.fill);
      expect(PictureFit.stretch.next, PictureFit.fit);
      expect(PictureFit.wide.forcedAspect, closeTo(1.778, 0.001));
      expect(PictureFit.classic.forcedAspect, closeTo(1.333, 0.001));
      expect(PictureFit.fill.forcedAspect, isNull);
      expect(PictureFit.fill.label, 'Fill (crop)');
    });

    test('knows how long each sleep timer runs', () {
      expect(SleepTimer.min30.after, const Duration(minutes: 30));
      expect(SleepTimer.min60.after, const Duration(minutes: 60));
      expect(SleepTimer.endOfFilm.after, isNull);
      expect(SleepTimer.off.label, 'Off');
    });
  });

  group('touch gestures', () {
    test('a full-width swipe covers 90 s of an episode and up to 5 min of a long film', () {
      expect(swipeSeekSpan(24 * 60), 90);
      expect(swipeSeekSpan(60 * 60), 180);
      expect(swipeSeekSpan(100 * 60), 300);
      expect(swipeSeekSpan(4 * 3600), 300);
    });

    test('never covers more than the film itself, and guesses for a live stream', () {
      expect(swipeSeekSpan(20), 20);
      expect(swipeSeekSpan(0), 90);
      expect(swipeSeekSpan(-1), 90);
      expect(swipeSeekSpan(double.nan), 90);
    });

    test('turns a swipe into a target time', () {
      // An episode: half the width is 45 s.
      expect(
        swipeSeekTarget(startSeconds: 600, dragPx: 180, widthPx: 360, durationSeconds: 1440),
        closeTo(645, 0.001),
      );
      expect(
        swipeSeekTarget(startSeconds: 600, dragPx: -360, widthPx: 360, durationSeconds: 1440),
        closeTo(510, 0.001),
      );
    });

    test('stops a swipe at the start and one second short of the end', () {
      expect(
        swipeSeekTarget(startSeconds: 20, dragPx: -900, widthPx: 360, durationSeconds: 1440),
        0,
      );
      expect(
        swipeSeekTarget(startSeconds: 1400, dragPx: 900, widthPx: 360, durationSeconds: 1440),
        1439,
      );
      expect(swipeSeekTarget(startSeconds: 0.2, dragPx: 50, widthPx: 100, durationSeconds: 0.8), 0);
    });

    test('lets a swipe run on while the length is unknown, and ignores a room with no width', () {
      expect(
        swipeSeekTarget(startSeconds: 50, dragPx: 360, widthPx: 360, durationSeconds: 0),
        closeTo(140, 0.001),
      );
      expect(swipeSeekTarget(startSeconds: 50, dragPx: 99, widthPx: 0, durationSeconds: 600), 50);
      expect(
        swipeSeekTarget(startSeconds: 50, dragPx: double.nan, widthPx: 360, durationSeconds: 600),
        50,
      );
    });

    test('prints how far a swipe has moved the film', () {
      expect(signedClock(42), '+0:42');
      expect(signedClock(-65.4), '-1:05');
      expect(signedClock(0), '+0:00');
      expect(signedClock(-0.2), '+0:00');
      expect(signedClock(3725), '+1:02:05');
      expect(signedClock(double.nan), '+0:00');
    });

    test('reads no direction into a drag until it has gone far enough', () {
      expect(swipeAxis(10, 5), isNull);
      expect(swipeAxis(0, -23), isNull);
    });

    test('needs clear intent for a sideways swipe', () {
      expect(swipeAxis(40, 6), SwipeAxis.horizontal);
      expect(swipeAxis(-40, -20), SwipeAxis.horizontal);
      expect(swipeAxis(6, 40), SwipeAxis.vertical);
      expect(swipeAxis(-20, -30), SwipeAxis.vertical);
      // A diagonal is nobody's: it must not seek and must not change the volume.
      expect(swipeAxis(30, 24), SwipeAxis.neither);
      expect(swipeAxis(-28, 26), SwipeAxis.neither);
    });

    test('splits the picture into thirds for taps', () {
      expect(tapZone(10, 360), -1);
      expect(tapZone(180, 360), 0);
      expect(tapZone(350, 360), 1);
      expect(tapZone(120, 360), 0);
      expect(tapZone(240, 360), 0);
      expect(tapZone(5, 0), 0);
    });

    test('a pinch out fills the screen, a pinch in fits the picture', () {
      expect(pinchFit(PictureFit.fit, 1.3), PictureFit.fill);
      expect(pinchFit(PictureFit.fill, 0.7), PictureFit.fit);
      expect(pinchFit(PictureFit.stretch, 1.25), PictureFit.fill);
      expect(pinchFit(PictureFit.wide, 0.8), PictureFit.fit);
    });

    test('a pinch that has not gone far, or has nowhere to go, changes nothing', () {
      expect(pinchFit(PictureFit.fit, 1.1), isNull);
      expect(pinchFit(PictureFit.fill, 0.9), isNull);
      expect(pinchFit(PictureFit.fill, 1.6), isNull);
      expect(pinchFit(PictureFit.fit, 0.5), isNull);
      expect(pinchFit(PictureFit.fit, double.nan), isNull);
      expect(pinchFit(PictureFit.fit, 0), isNull);
    });
  });

  group('which way up', () {
    test('a wide picture lies down, a tall one stands up', () {
      expect(
        orientationFor(FilmOrientation.auto, width: 1920, height: 1080),
        FilmOrientation.landscape,
      );
      expect(
        orientationFor(FilmOrientation.auto, width: 1080, height: 1920),
        FilmOrientation.portrait,
      );
      expect(
        orientationFor(FilmOrientation.auto, width: 1440, height: 1080),
        FilmOrientation.landscape,
      );
    });

    test('leaves a square picture to the system, and waits for an unknown size', () {
      expect(orientationFor(FilmOrientation.auto, width: 1080, height: 1080), FilmOrientation.auto);
      expect(orientationFor(FilmOrientation.auto, width: 0, height: 0), isNull);
      expect(orientationFor(FilmOrientation.auto, width: 1920, height: 0), isNull);
    });

    test('a choice made with the rotate button wins, size known or not', () {
      expect(
        orientationFor(FilmOrientation.portrait, width: 1920, height: 1080),
        FilmOrientation.portrait,
      );
      expect(
        orientationFor(FilmOrientation.landscape, width: 0, height: 0),
        FilmOrientation.landscape,
      );
    });

    test('the rotate button cycles auto, landscape, portrait', () {
      expect(FilmOrientation.auto.next, FilmOrientation.landscape);
      expect(FilmOrientation.landscape.next, FilmOrientation.portrait);
      expect(FilmOrientation.portrait.next, FilmOrientation.auto);
      expect(FilmOrientation.landscape.label, 'Landscape');
    });
  });

  group('seek preview', () {
    test('is for a file on disk, on desktop, when Settings allow it', () {
      bool allowed({
        bool enabled = true,
        bool desktop = true,
        bool remote = false,
        bool contentUri = false,
      }) => seekPreviewAllowed(
        enabled: enabled,
        desktop: desktop,
        remote: remote,
        contentUri: contentUri,
      );
      expect(allowed(), isTrue);
      expect(allowed(enabled: false), isFalse);
      expect(allowed(desktop: false), isFalse);
      expect(allowed(remote: true), isFalse);
      expect(allowed(contentUri: true), isFalse);
    });
  });

  group('fill and the subtitle line', () {
    test('knows how much "Fill" cuts off the top and bottom', () {
      expect(fillCropPercent(videoAspect: 16 / 9, viewAspect: 20 / 9), closeTo(10, 0.001));
      expect(fillCropPercent(videoAspect: 4 / 3, viewAspect: 16 / 9), closeTo(12.5, 0.001));
      // A scope film on a 16:9 screen loses its sides, not its subtitle line.
      expect(fillCropPercent(videoAspect: 2.39, viewAspect: 16 / 9), 0);
      expect(fillCropPercent(videoAspect: 16 / 9, viewAspect: 16 / 9), 0);
      expect(fillCropPercent(videoAspect: 0, viewAspect: 2), 0);
      expect(fillCropPercent(videoAspect: 2, viewAspect: 0), 0);
    });

    test('keeps mpv\'s own positions while nothing is cropped', () {
      expect(subtitleOffsets(SubtitlePlacement.bottom, 0), (subPos: 100, marginY: kSubMarginY));
      expect(subtitleOffsets(SubtitlePlacement.lowerThird, 0), (subPos: 82, marginY: kSubMarginY));
      expect(subtitleOffsets(SubtitlePlacement.top, 0), (subPos: 100, marginY: kSubMarginY));
    });

    test('moves the line in by what the crop takes', () {
      expect(subtitleOffsets(SubtitlePlacement.bottom, 10), (subPos: 90, marginY: kSubMarginY));
      expect(subtitleOffsets(SubtitlePlacement.lowerThird, 10), (subPos: 72, marginY: kSubMarginY));
      expect(subtitleOffsets(SubtitlePlacement.top, 10), (subPos: 100, marginY: kSubMarginY + 72));
    });

    test('never moves it past the middle of the picture', () {
      expect(subtitleOffsets(SubtitlePlacement.bottom, 90).subPos, 60);
      expect(subtitleOffsets(SubtitlePlacement.bottom, -5).subPos, 100);
      expect(subtitleOffsets(SubtitlePlacement.bottom, double.nan).subPos, 100);
    });
  });

  group('the folder, for repeat', () {
    const names = ['Show E10.mkv', 'Show E2.mkv', 'Show E1.mkv'];

    test('knows the first file from anywhere but the first', () {
      expect(folderOrder(names, 'Show E10.mkv'), (
        previous: 'Show E2.mkv',
        next: null,
        first: 'Show E1.mkv',
      ));
      expect(folderOrder(names, 'Show E2.mkv'), (
        previous: 'Show E1.mkv',
        next: 'Show E10.mkv',
        first: 'Show E1.mkv',
      ));
    });

    test('has nothing to wrap to from the first or only file', () {
      expect(folderOrder(names, 'Show E1.mkv'), (previous: null, next: 'Show E2.mkv', first: null));
      expect(folderOrder(['solo.mkv'], 'solo.mkv'), (previous: null, next: null, first: null));
      expect(folderOrder(names, 'elsewhere.mkv'), (previous: null, next: null, first: null));
    });
  });

  group('fine speed', () {
    test('snaps to the 0.05 grid inside mpv\'s range', () {
      expect(snapSpeed(1.1500000001), 1.15);
      expect(snapSpeed(1.02), 1.0);
      expect(snapSpeed(1.03), 1.05);
      expect(snapSpeed(0.1), kMinSpeed);
      expect(snapSpeed(9), kMaxSpeed);
      expect(speedLabel(snapSpeed(2.349)), '2.35×');
    });
  });

  group('when a film ends', () {
    EndAction act(
      RepeatMode repeat, {
      bool autoplay = true,
      bool next = false,
      bool first = false,
      bool sleep = false,
    }) => endAction(
      repeat: repeat,
      autoplayNext: autoplay,
      hasNext: next,
      hasFirst: first,
      sleepAtEnd: sleep,
    );

    test('stops as it always did with repeat off', () {
      expect(act(RepeatMode.off), EndAction.stop);
      expect(act(RepeatMode.off, next: true), EndAction.next);
      expect(act(RepeatMode.off, next: true, autoplay: false), EndAction.stop);
      expect(act(RepeatMode.off, first: true), EndAction.stop);
    });

    test('loops one film, whatever is next', () {
      expect(act(RepeatMode.one), EndAction.loop);
      expect(act(RepeatMode.one, next: true, first: true), EndAction.loop);
    });

    test('plays through the folder and wraps at its end', () {
      expect(act(RepeatMode.all, next: true), EndAction.next);
      expect(act(RepeatMode.all, next: true, autoplay: false), EndAction.next);
      expect(act(RepeatMode.all, first: true), EndAction.wrap);
      expect(act(RepeatMode.all, first: true, autoplay: false), EndAction.wrap);
    });

    test('loops a folder of one', () {
      expect(act(RepeatMode.all), EndAction.loop);
    });

    test('lets "end of this film" on the sleep timer end the night', () {
      for (final r in RepeatMode.values) {
        expect(act(r, next: true, first: true, sleep: true), EndAction.stop, reason: r.name);
      }
    });
  });

  group('skip intro, recap and credits', () {
    List<Chapter> chapters(List<(double, String?)> c) => [
      for (final (i, (start, title)) in c.indexed)
        Chapter(index: i, startSeconds: start, title: title),
    ];
    const dur = 1440.0;
    final episode = chapters([
      (0, 'Recap'),
      (45, 'Opening'),
      (135, 'Part A'),
      (700, 'Part B'),
      (1290, 'Ending'),
      (1380, 'Next Episode Preview'),
    ]);

    test('offers the skip only inside the chapter, to the start of the next', () {
      expect(skippableChapter(episode, 10, dur), (label: 'Skip recap', toSeconds: 45.0));
      expect(skippableChapter(episode, 45, dur), (label: 'Skip intro', toSeconds: 135.0));
      expect(skippableChapter(episode, 400, dur), isNull);
      expect(skippableChapter(episode, 1300, dur), (label: 'Skip credits', toSeconds: 1380.0));
    });

    test('hides in the last second of the chapter', () {
      expect(skippableChapter(episode, 134.5, dur), isNull);
      expect(skippableChapter(episode, 133.9, dur), isNotNull);
    });

    test('turns a closing chapter into "Next episode" only when there is one', () {
      expect(skippableChapter(episode, 1400, dur), isNull);
      expect(skippableChapter(episode, 1400, dur, hasNext: true), (
        label: 'Next episode',
        toSeconds: dur,
      ));
      final film = chapters([(0, 'Film'), (5000, 'End Credits')]);
      expect(skippableChapter(film, 5100, 5400), isNull);
      expect(skippableChapter(film, 5100, 5400, hasNext: true)?.label, 'Next episode');
    });

    test('never skips an intro that is the whole rest of the file', () {
      final odd = chapters([(0, 'Film'), (100, 'Intro')]);
      expect(skippableChapter(odd, 120, 200, hasNext: true), isNull);
    });

    test('reads the usual spellings, whole words, any case', () {
      String? label(String title) =>
          skippableChapter(chapters([(0, title), (90, 'Episode')]), 5, 1000)?.label;
      for (final t in ['Intro', 'INTRO', 'intro (clean)', 'Opening', 'OP', 'op', 'OP1', 'OP 2']) {
        expect(label(t), 'Skip intro', reason: t);
      }
      for (final t in ['Opening Credits', 'Opening Theme', 'Main Title Opening', 'オープニング']) {
        expect(label(t), 'Skip intro', reason: t);
      }
      for (final t in ['Recap', 'Previously on Lost', 'PREVIOUSLY']) {
        expect(label(t), 'Skip recap', reason: t);
      }
      for (final t in ['Credits', 'End Credits', 'Closing credits', 'Ending', 'ED', 'ED2']) {
        expect(label(t), 'Skip credits', reason: t);
      }
      for (final t in ['Outro', 'Ending Theme', 'エンディング']) {
        expect(label(t), 'Skip credits', reason: t);
      }
      for (final t in ['Preview', 'Next Episode Preview', '予告']) {
        expect(label(t), 'Skip preview', reason: t);
      }
    });

    test('leaves ordinary scenes alone', () {
      String? label(String? title) =>
          skippableChapter(chapters([(0, title), (90, 'Episode')]), 5, 1000)?.label;
      for (final t in [
        'Opera',
        'Introduction to the case',
        'Opening Night',
        'Ed arrives',
        'The Ending of the World',
        'Post-credits scene',
        'Chapter 1',
        'Part A',
        'Edge of town',
        'Operation Dawn',
        'Reopening',
        '',
        null,
      ]) {
        expect(label(t), isNull, reason: '$t');
      }
    });

    test('needs chapters, a position inside them and a known length', () {
      expect(skippableChapter(const [], 10, dur), isNull);
      expect(skippableChapter(episode, 10, 0), isNull);
      expect(skippableChapter(chapters([(30, 'Intro'), (90, 'Film')]), 10, dur), isNull);
    });
  });

  group('per-film memory', () {
    test('stores nothing for an untouched film', () {
      expect(const FilmPrefs().isEmpty, isTrue);
      expect(const FilmPrefs().toJson(), isEmpty);
    });

    test('stores only what was chosen', () {
      final p = FilmPrefs(audioId: '2', subtitle: FilmPrefs.off, picture: PictureAdjust(zoom: 0.5));
      expect(p.isEmpty, isFalse);
      expect(p.toJson().keys, ['audio', 'subtitle', 'picture']);
      expect(FilmPrefs.fromJson(p.toJson()), p);
      expect(FilmPrefs.fromJson(p.toJson()).hashCode, p.hashCode);
    });

    test('forgets a choice on request and keeps the rest', () {
      const p = FilmPrefs(audioId: '2', subtitle: '3', secondSubtitleId: '4');
      final q = p.copyWith(clearSubtitle: true, clearSecondSubtitle: true);
      expect(q.subtitle, isNull);
      expect(q.secondSubtitleId, isNull);
      expect(q.audioId, '2');
      expect(p.copyWith(subtitle: FilmPrefs.off).subtitle, 'off');
      expect(p.copyWith(picture: PictureAdjust(rotation: 90)).picture.rotation, 90);
      expect(p == q, isFalse);
    });

    test('reads damaged JSON as far as it can', () {
      expect(FilmPrefs.fromJson(null), const FilmPrefs());
      final p = FilmPrefs.fromJson(const {
        'audio': 2,
        'subtitle': '',
        'secondSubtitle': '5',
        'picture': 'tilted',
        'other': 1,
      });
      expect(p.audioId, isNull);
      expect(p.subtitle, isNull);
      expect(p.secondSubtitleId, '5');
      expect(p.picture, PictureAdjust.neutral);
    });
  });

  group('video details', () {
    test('formats bit rates and sizes the way people read them', () {
      expect(formatBitrate(4200000), '4.2 Mbps');
      expect(formatBitrate(640000), '640 kbps');
      expect(formatBytes(4692251771), '4.37 GB');
      expect(formatBytes(851443712), '812 MB');
      expect(formatBytes(98304), '96 KB');
    });

    test('lists every property the overlay reads once', () {
      expect(kDetailProperties.toSet(), hasLength(kDetailProperties.length));
    });

    test('draws a full film', () {
      final rows = videoDetailLines(const {
        'video-format': 'hevc',
        'video-codec': 'HEVC (High Efficiency Video Coding)',
        'video-params/w': '3840',
        'video-params/h': '2160',
        'video-params/pixelformat': 'yuv420p10',
        'container-fps': '23.976024',
        'estimated-vf-fps': '23.976',
        'video-bitrate': '18400000',
        'hwdec-current': 'd3d11va',
        'frame-drop-count': '3',
        'decoder-frame-drop-count': '0',
        'video-params/primaries': 'bt.2020',
        'video-params/gamma': 'pq',
        'audio-codec-name': 'eac3',
        'audio-params/channel-count': '6',
        'audio-params/samplerate': '48000',
        'audio-bitrate': '640000',
        'file-format': 'matroska,webm',
        'file-size': '4692251771',
        'demuxer-cache-duration': '12.44',
      });
      expect(rows, [
        (label: 'Video', value: 'hevc · 3840×2160 · yuv420p10'),
        (label: 'Frame rate', value: '23.976 fps'),
        (label: 'Video bitrate', value: '18.4 Mbps'),
        (label: 'Decoder', value: 'Hardware (d3d11va)'),
        (label: 'Dropped frames', value: '3 display · 0 decoder'),
        (label: 'Colour', value: 'bt.2020 · pq (HDR)'),
        (label: 'Audio', value: 'eac3 · 6 ch · 48 kHz'),
        (label: 'Audio bitrate', value: '640 kbps'),
        (label: 'File', value: 'matroska,webm · 4.37 GB'),
        (label: 'Buffered ahead', value: '12.4 s'),
      ]);
    });

    test('leaves out what mpv did not say', () {
      expect(videoDetailLines(const {}), isEmpty);
      final rows = videoDetailLines(const {
        'video-codec': 'H.264 / AVC',
        'video-params/w': '1280',
        'container-fps': '25.000',
        'estimated-vf-fps': '12.4',
        'hwdec-current': 'no',
        'video-bitrate': '0',
        'video-params/gamma': 'bt.1886',
        'audio-params/samplerate': '44100',
        'file-size': 'nan',
        'file-format': ' ',
      });
      expect(rows, [
        (label: 'Video', value: 'H.264 / AVC'),
        (label: 'Frame rate', value: '25 fps · 12.4 shown'),
        (label: 'Decoder', value: 'Software'),
        (label: 'Colour', value: 'bt.1886'),
        (label: 'Audio', value: '44.1 kHz'),
      ]);
    });

    test('still names the frame rate actually shown without a container rate', () {
      expect(videoDetailLines(const {'estimated-vf-fps': '29.97'}), [
        (label: 'Frame rate', value: '30.0 shown'),
      ]);
    });
  });

  group('resume keys for streams', () {
    test('is stable and 16 hex characters', () {
      final a = urlResumeKey('https://example.com/film.m3u8');
      expect(a.isValid, isTrue);
      expect(urlResumeKey('https://example.com/film.m3u8'), a);
      expect(urlResumeKey('https://example.com/other.m3u8'), isNot(a));
    });

    test('matches the FNV-1a reference vector', () {
      expect(urlResumeKey('a').value, 'af63dc4c8601ec8c');
      expect(urlResumeKey('').value, 'cbf29ce484222325');
    });
  });

  group('languages', () {
    test('lists every container spelling for alang', () {
      expect(mpvLanguageList(['fr', 'xx']), ['fr', 'fra', 'fre', 'xx']);
    });

    test('matches 639-1, 639-2 and region tags', () {
      expect(languageMatches('eng', 'en'), isTrue);
      expect(languageMatches('en-US', 'en'), isTrue);
      expect(languageMatches('ger', 'de'), isTrue);
      expect(languageMatches('fra', 'de'), isFalse);
      expect(languageMatches(null, 'en'), isFalse);
      expect(languageMatches('', 'en'), isFalse);
    });

    test('knows which languages the bundled font cannot draw', () {
      expect(isNonLatinLanguage('ara'), isTrue);
      expect(isNonLatinLanguage('hi'), isTrue);
      expect(isNonLatinLanguage('ru'), isFalse);
      expect(isNonLatinLanguage('en'), isFalse);
      expect(isNonLatinLanguage(null), isFalse);
    });

    test('spots text outside Latin, Greek and Cyrillic', () {
      expect(needsSystemFonts('Héllo — “Ωμέγα” Привет …'), isFalse);
      expect(needsSystemFonts('﻿ok�'), isFalse);
      expect(needsSystemFonts('مرحبا'), isTrue);
      expect(needsSystemFonts('こんにちは'), isTrue);
      expect(needsSystemFonts('नमस्ते'), isTrue);
    });
  });
}
