// Small, pure rules behind the Auditorium's transport: seek clamping, the folder's natural
// order, speed presets, picture fits, what happens when a film ends, skippable chapters, the
// per-film memory, the video details readout, language codes for mpv and the Android
// subtitle-font test. No Flutter, no mpv: the player layer and the widgets call these.
import 'dart:convert';

import 'models/media.dart';
import 'models/settings.dart';
import 'picture.dart';

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

/// How finely the transport needs the clock for a film of [duration]: about one step per
/// pixel of a 1500 px seek bar, never finer than the 100 ms playback stream and never coarser
/// than the one-second time readout. A two-hour film redraws its controls once a second, not
/// ten times.
Duration clockStep(Duration duration) =>
    Duration(milliseconds: (duration.inMilliseconds ~/ 1500).clamp(100, 1000));

/// [position] rounded down to [clockStep] of [duration]: what the controls actually draw.
Duration clockTick(Duration position, Duration duration) {
  final step = clockStep(duration).inMilliseconds;
  return Duration(milliseconds: position.inMilliseconds ~/ step * step);
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

/// [neighboursOf], plus the folder's first file for "Repeat the folder" (null when [current]
/// is that file, or the only one: there is nothing to wrap to).
({String? previous, String? next, String? first}) folderOrder(List<String> names, String current) {
  final sorted = [...names]..sort(naturalCompare);
  final i = sorted.indexOf(current);
  if (i < 0) return (previous: null, next: null, first: null);
  return (
    previous: i > 0 ? sorted[i - 1] : null,
    next: i < sorted.length - 1 ? sorted[i + 1] : null,
    first: i > 0 ? sorted.first : null,
  );
}

// ───────────────────────────── speed, fit, sleep ─────────────────────────────

const List<double> kSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// The fine speed slider: mpv's own range, in steps small enough to match a dub to a sub.
const double kMinSpeed = 0.25;
const double kMaxSpeed = 4.0;
const double kSpeedStep = 0.05;

/// [rate] on the slider's grid (binary floats drift: 1.1500000001 must read 1.15).
double snapSpeed(double rate) {
  final steps = (rate.clamp(kMinSpeed, kMaxSpeed) / kSpeedStep).round();
  return (steps * kSpeedStep * 100).round() / 100;
}

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

/// How much of the picture "Fill (crop)" cuts off at the top and again at the bottom, in
/// percent of its height. Zero when the picture is the wider of the two (the sides are cut
/// instead).
double fillCropPercent({required double videoAspect, required double viewAspect}) {
  if (videoAspect <= 0 || viewAspect <= 0 || viewAspect <= videoAspect) return 0;
  return (1 - videoAspect / viewAspect) / 2 * 100;
}

/// mpv's default `sub-margin-y`, in 720ths of the picture's height.
const int kSubMarginY = 22;

/// Where text subtitles sit, as mpv's `sub-pos` and `sub-margin-y`. libass draws into the
/// film's own frame, so when "Fill (crop)" cuts [cropPercent] off the top and bottom the line
/// must move in by as much or it is cut off with them. `sub-pos` only moves bottom-aligned
/// lines; a line at the top moves by its margin.
({int subPos, int marginY}) subtitleOffsets(SubtitlePlacement placement, double cropPercent) {
  final crop = cropPercent.isNaN ? 0 : cropPercent.clamp(0, 40).round();
  return switch (placement) {
    SubtitlePlacement.bottom => (subPos: 100 - crop, marginY: kSubMarginY),
    SubtitlePlacement.lowerThird => (subPos: 82 - crop, marginY: kSubMarginY),
    SubtitlePlacement.top => (subPos: 100, marginY: kSubMarginY + (crop * 7.2).round()),
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

// ───────────────────────────── swipes, taps, pinches ─────────────────────────────

/// Seconds one full-width swipe covers: a twentieth of the film, never under a minute and a
/// half (an episode still moves usefully), never over five minutes (a long film stays
/// steerable), and never more than the film itself. An unknown length (a live stream) gets
/// the minimum.
double swipeSeekSpan(double durationSeconds) {
  if (durationSeconds.isNaN || durationSeconds <= 0) return 90;
  final span = (durationSeconds * 0.05).clamp(90.0, 300.0);
  return span < durationSeconds ? span : durationSeconds;
}

/// Where a horizontal swipe of [dragPx] (right is forward) across a picture [widthPx] wide
/// lands, starting from [startSeconds]: never before the start, never in the film's last
/// second (see [clampSeek]).
double swipeSeekTarget({
  required double startSeconds,
  required double dragPx,
  required double widthPx,
  required double durationSeconds,
}) {
  if (widthPx <= 0 || dragPx.isNaN) return startSeconds;
  final target = startSeconds + dragPx / widthPx * swipeSeekSpan(durationSeconds);
  if (target <= 0) return 0;
  if (durationSeconds <= 0) return target;
  final last = durationSeconds > 1 ? durationSeconds - 1 : 0.0;
  return target > last ? last : target;
}

/// `+0:42`, `-1:05`, `+0:00`: how far a swipe has moved the film.
String signedClock(double deltaSeconds) {
  final s = deltaSeconds.isNaN ? 0 : deltaSeconds.round();
  return '${s < 0 ? '-' : '+'}${shortClock(Duration(seconds: s.abs()))}';
}

enum SwipeAxis { horizontal, vertical, neither }

/// A finger must travel this far (logical pixels) before its drag is read at all.
const double kSwipeDecideAt = 24;

/// Which way a one-finger drag is going, once it has gone far enough to tell (null until
/// then). Sideways needs CLEAR intent, within about 30° of level, so a seek never starts from
/// a sloppy brightness or volume swipe; a diagonal is neither and does nothing.
SwipeAxis? swipeAxis(double dx, double dy) {
  final x = dx.abs(), y = dy.abs();
  if (x * x + y * y < kSwipeDecideAt * kSwipeDecideAt) return null;
  if (x >= y * 1.7) return SwipeAxis.horizontal;
  if (y >= x * 1.2) return SwipeAxis.vertical;
  return SwipeAxis.neither;
}

/// The third of the picture a tap landed in: -1 (seek back), 0 (play / pause), 1 (forward).
int tapZone(double x, double width) {
  if (width <= 0) return 0;
  if (x < width / 3) return -1;
  return x > width * 2 / 3 ? 1 : 0;
}

/// Two fingers must move this far apart (as a ratio of where they started) to switch the fit.
const double kPinchOut = 1.2;

/// What a pinch at [scale] (1 = where the fingers started) switches the picture to: spread
/// out for "Fill (crop)", pinched in for "Fit". Null while it has not gone far enough, or
/// the picture is already there.
PictureFit? pinchFit(PictureFit current, double scale) {
  if (scale.isNaN || scale <= 0) return null;
  if (scale >= kPinchOut) return current == PictureFit.fill ? null : PictureFit.fill;
  if (scale <= 1 / kPinchOut) return current == PictureFit.fit ? null : PictureFit.fit;
  return null;
}

// ───────────────────────────── which way up (phones) ─────────────────────────────

/// How the screen is turned while ONE film plays. The rotate button cycles these.
enum FilmOrientation {
  auto('Rotation follows the video'),
  landscape('Landscape'),
  portrait('Portrait');

  final String label;
  const FilmOrientation(this.label);

  FilmOrientation get next => values[(index + 1) % values.length];
}

/// The way the screen should be held for a [width] × [height] picture under [mode]: a wide
/// picture lies down, a tall one (shot on a phone) stands up. [FilmOrientation.auto] back
/// means "as the system likes" (a square picture); null means the size is not known yet, so
/// nothing should change.
FilmOrientation? orientationFor(FilmOrientation mode, {required int width, required int height}) {
  if (mode != FilmOrientation.auto) return mode;
  if (width <= 0 || height <= 0) return null;
  if (width * 10 >= height * 11) return FilmOrientation.landscape;
  if (height * 10 >= width * 11) return FilmOrientation.portrait;
  return FilmOrientation.auto;
}

// ───────────────────────────── seek preview ─────────────────────────────

/// Whether the seek bar may show frames of the film under the pointer. They come from a
/// second, tiny player reading the same file, so: only a file on disk (a stream would be
/// fetched twice, and a content:// grant is not ours to open twice), and only on desktop. On
/// a phone that second decoder has to be a software one (a second hardware session is not
/// something every chipset gives) and a 4K HEVC keyframe in software costs the heat, battery
/// and memory the film itself needs: Android shows the time alone.
bool seekPreviewAllowed({
  required bool enabled,
  required bool desktop,
  required bool remote,
  required bool contentUri,
}) => enabled && desktop && !remote && !contentUri;

// ───────────────────────────── when a film ends ─────────────────────────────

enum EndAction {
  /// The last frame stays; nothing starts.
  stop,

  /// The same film again (mpv `loop-file`: it never reports an end, so no card shows).
  loop,

  /// The folder's next film, after the "Up next" countdown.
  next,

  /// Back to the folder's first film, after the same countdown.
  wrap,
}

/// The ONE rule for the end of a film, shared by the session (which arms mpv's loop) and the
/// Auditorium (which shows "Up next"), so the two can never both start something.
/// "End of this film" on the sleep timer beats everything: the night is over.
EndAction endAction({
  required RepeatMode repeat,
  required bool autoplayNext,
  required bool hasNext,
  required bool hasFirst,
  bool sleepAtEnd = false,
}) {
  if (sleepAtEnd) return EndAction.stop;
  if (repeat == RepeatMode.one) return EndAction.loop;
  // Repeating the folder means playing through it, whatever "play the next one" says.
  if (hasNext) {
    return autoplayNext || repeat == RepeatMode.all ? EndAction.next : EndAction.stop;
  }
  if (repeat == RepeatMode.all) return hasFirst ? EndAction.wrap : EndAction.loop;
  return EndAction.stop;
}

// ───────────────────────────── skip intro / recap / credits ─────────────────────────────

enum _Skippable { intro, recap, credits, preview }

/// Words that say what a chapter is all by themselves.
const Map<String, _Skippable> _strongWords = {
  'intro': _Skippable.intro,
  'recap': _Skippable.recap,
  'previously': _Skippable.recap,
  'outro': _Skippable.credits,
};

/// Words that only count when nothing else in the title disagrees: "Opening" is an intro,
/// "Opening Night" is a scene; "ED" is an ending, "Ed arrives" is a person.
const Map<String, _Skippable> _weakWords = {
  'opening': _Skippable.intro,
  'op': _Skippable.intro,
  'ending': _Skippable.credits,
  'ed': _Skippable.credits,
  'credits': _Skippable.credits,
  'credit': _Skippable.credits,
  'preview': _Skippable.preview,
};

/// Words that may sit beside a weak word without changing its meaning ("End Credits",
/// "Opening Theme", "Next Episode Preview", "OP 2").
const Set<String> _fillerWords = {
  'the', 'a', 'of', 'and', 'main', 'title', 'titles', 'theme', 'song', 'sequence', 'part', //
  'tv', 'size', 'ver', 'version', 'clean', 'creditless', 'next', 'episode', 'end', 'closing',
};

/// What anime discs call them, for titles with no Latin word at all.
const Map<String, _Skippable> _kana = {
  'オープニング': _Skippable.intro,
  'エンディング': _Skippable.credits,
  '予告': _Skippable.preview,
};

final _titleWords = RegExp(r'[a-z]+|\d+');

_Skippable? _skippableKind(String? title) {
  if (title == null) return null;
  for (final e in _kana.entries) {
    if (title.contains(e.key)) return e.value;
  }
  // Whole words only, digits split off: "OP1" is OP + 1, "Opera" is just "opera".
  final words = [for (final m in _titleWords.allMatches(title.toLowerCase())) m[0]!];
  for (final w in words) {
    final strong = _strongWords[w];
    if (strong != null) return strong;
  }
  final telling = [
    for (final w in words)
      if (!_fillerWords.contains(w) && int.tryParse(w) == null) w,
  ];
  if (telling.isEmpty || !telling.every(_weakWords.containsKey)) return null;
  // "Opening Credits" is an opening; "Credits and Preview" is a preview.
  final kinds = {for (final w in telling) _weakWords[w]!};
  if (kinds.contains(_Skippable.intro)) return _Skippable.intro;
  if (kinds.contains(_Skippable.preview)) return _Skippable.preview;
  return _Skippable.credits;
}

/// The "Skip intro" button: set while [positionSeconds] is inside a chapter whose title names
/// an intro, a recap, the credits or a preview, with where the skip lands (the next chapter).
/// Credits or a preview as the LAST chapter skip to the end of the film, which is only worth a
/// button when a next file exists ([hasNext]): then it reads "Next episode" and [toSeconds] is
/// [durationSeconds]. Null means no button.
({String label, double toSeconds})? skippableChapter(
  List<Chapter> chapters,
  double positionSeconds,
  double durationSeconds, {
  bool hasNext = false,
}) {
  if (durationSeconds <= 0) return null;
  var at = -1;
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].startSeconds <= positionSeconds) at = i;
  }
  if (at < 0) return null;
  final kind = _skippableKind(chapters[at].title);
  if (kind == null) return null;
  final to = at < chapters.length - 1 ? chapters[at + 1].startSeconds : durationSeconds;
  if (to >= durationSeconds) {
    final ends = kind == _Skippable.credits || kind == _Skippable.preview;
    return ends && hasNext ? (label: 'Next episode', toSeconds: durationSeconds) : null;
  }
  // A second from the end of the chapter the button would only flash.
  if (to - positionSeconds < 1) return null;
  return (
    label: switch (kind) {
      _Skippable.intro => 'Skip intro',
      _Skippable.recap => 'Skip recap',
      _Skippable.credits => 'Skip credits',
      _Skippable.preview => 'Skip preview',
    },
    toSeconds: to,
  );
}

// ───────────────────────────── per-film memory ─────────────────────────────

/// What the viewer chose for ONE film, remembered by its hash: the audio track, an explicit
/// subtitle choice, the second subtitle and the picture adjustments. Everything else follows
/// Settings. Track ids are mpv's (`aid` / `sid`); the session only applies one that still exists.
class FilmPrefs {
  /// [subtitle] when the viewer turned subtitles off for this film.
  static const off = 'off';

  final String? audioId;

  /// A track id, [off], or null to let the automatic pick stand.
  final String? subtitle;
  final String? secondSubtitleId;
  final PictureAdjust picture;

  const FilmPrefs({
    this.audioId,
    this.subtitle,
    this.secondSubtitleId,
    this.picture = PictureAdjust.neutral,
  });

  bool get isEmpty =>
      audioId == null && subtitle == null && secondSubtitleId == null && picture.isNeutral;

  FilmPrefs copyWith({
    String? audioId,
    String? subtitle,
    bool clearSubtitle = false,
    String? secondSubtitleId,
    bool clearSecondSubtitle = false,
    PictureAdjust? picture,
  }) => FilmPrefs(
    audioId: audioId ?? this.audioId,
    subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
    secondSubtitleId: clearSecondSubtitle ? null : (secondSubtitleId ?? this.secondSubtitleId),
    picture: picture ?? this.picture,
  );

  /// Only what was chosen: an untouched film stores nothing (an empty map deletes the row).
  Map<String, Object?> toJson() => {
    'audio': ?audioId,
    'subtitle': ?subtitle,
    'secondSubtitle': ?secondSubtitleId,
    if (!picture.isNeutral) 'picture': picture.toJson(),
  };

  /// Tolerant, like every stored value: unknown fields are ignored, bad ones dropped.
  factory FilmPrefs.fromJson(Map<String, Object?>? j) {
    if (j == null) return const FilmPrefs();
    String? id(String k) {
      final v = j[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    return FilmPrefs(
      audioId: id('audio'),
      subtitle: id('subtitle'),
      secondSubtitleId: id('secondSubtitle'),
      picture: PictureAdjust.fromJson(j['picture']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FilmPrefs &&
      other.audioId == audioId &&
      other.subtitle == subtitle &&
      other.secondSubtitleId == secondSubtitleId &&
      other.picture == picture;

  @override
  int get hashCode => Object.hash(audioId, subtitle, secondSubtitleId, picture);
}

// ───────────────────────────── video details ─────────────────────────────

/// The mpv properties behind the video details overlay, in reading order.
const List<String> kDetailProperties = [
  'video-format',
  'video-codec',
  'video-params/w',
  'video-params/h',
  'video-params/pixelformat',
  'container-fps',
  'estimated-vf-fps',
  'video-bitrate',
  'hwdec-current',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'video-params/primaries',
  'video-params/gamma',
  'audio-codec-name',
  'audio-params/channel-count',
  'audio-params/samplerate',
  'audio-bitrate',
  'file-format',
  'file-size',
  'demuxer-cache-duration',
];

/// `4.2 Mbps`, `640 kbps`.
String formatBitrate(double bitsPerSecond) => bitsPerSecond >= 1000000
    ? '${(bitsPerSecond / 1000000).toStringAsFixed(1)} Mbps'
    : '${(bitsPerSecond / 1000).round()} kbps';

/// `4.37 GB`, `812 MB`, `96 KB` (binary units, as file managers show them).
String formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024, mb = 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).round()} KB';
}

/// `23.976`, `25`, `59.94`.
String _fps(double v) =>
    v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

/// The overlay's rows from raw mpv property values ([kDetailProperties] by name). A value mpv
/// did not give (no audio, a stream with no size, an older libmpv) simply leaves its part, or
/// its whole row, out.
List<({String label, String value})> videoDetailLines(Map<String, String> raw) {
  String? text(String k) {
    final v = raw[k]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  double? number(String k) {
    final v = double.tryParse(text(k) ?? '');
    return v == null || v.isNaN || v.isInfinite ? null : v;
  }

  final rows = <({String label, String value})>[];
  void row(String label, List<String?> parts) {
    final shown = parts.whereType<String>().toList();
    if (shown.isNotEmpty) rows.add((label: label, value: shown.join(' · ')));
  }

  final w = number('video-params/w'), h = number('video-params/h');
  row('Video', [
    text('video-format') ?? text('video-codec'),
    if (w != null && h != null) '${w.round()}×${h.round()}',
    text('video-params/pixelformat'),
  ]);
  final fps = number('container-fps'), shown = number('estimated-vf-fps');
  row('Frame rate', [
    if (fps != null && fps > 0) '${_fps(fps)} fps',
    if (shown != null && shown > 0 && (fps == null || (shown - fps).abs() >= 0.1))
      '${shown.toStringAsFixed(1)} shown',
  ]);
  final vbr = number('video-bitrate');
  row('Video bitrate', [if (vbr != null && vbr > 0) formatBitrate(vbr)]);
  final hw = text('hwdec-current');
  if (text('video-format') != null || hw != null) {
    row('Decoder', [hw == null || hw == 'no' ? 'Software' : 'Hardware ($hw)']);
  }
  final late = number('frame-drop-count'), skipped = number('decoder-frame-drop-count');
  row('Dropped frames', [
    if (late != null) '${late.round()} display',
    if (skipped != null) '${skipped.round()} decoder',
  ]);
  final gamma = text('video-params/gamma');
  final hdr = gamma == 'pq' || gamma == 'hlg';
  row('Colour', [text('video-params/primaries'), if (gamma != null) hdr ? '$gamma (HDR)' : gamma]);
  final channels = number('audio-params/channel-count');
  final rate = number('audio-params/samplerate');
  row('Audio', [
    text('audio-codec-name'),
    if (channels != null && channels > 0) '${channels.round()} ch',
    if (rate != null && rate > 0) '${_fps(rate / 1000)} kHz',
  ]);
  final abr = number('audio-bitrate');
  row('Audio bitrate', [if (abr != null && abr > 0) formatBitrate(abr)]);
  final size = number('file-size');
  row('File', [text('file-format'), if (size != null && size > 0) formatBytes(size.round())]);
  final cache = number('demuxer-cache-duration');
  row('Buffered ahead', [if (cache != null && cache >= 0) '${cache.toStringAsFixed(1)} s']);
  return rows;
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
