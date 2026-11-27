// What the phone's lock screen, notification shade and headset buttons are told about the open
// film, and WHEN they are told. The system advances the clock by itself from the last position
// and speed it was given, so the film is described again only when something it could not have
// worked out changes: play or pause, a seek, another speed, another title.

/// The open film as the system shows it.
class NowPlayingInfo {
  final String title;

  /// A second line under the title (the file's name when the title was cleaned up).
  final String? subtitle;

  /// Zero when unknown (a live stream): the system then draws no seek bar.
  final Duration duration;
  final Duration position;
  final double speed;
  final bool playing;
  final bool buffering;
  final bool hasPrevious;
  final bool hasNext;

  /// The jump the rewind and forward buttons make, for their labels.
  final int stepSeconds;

  const NowPlayingInfo({
    required this.title,
    this.subtitle,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.speed = 1,
    this.playing = false,
    this.buffering = false,
    this.hasPrevious = false,
    this.hasNext = false,
    this.stepSeconds = 10,
  });

  /// The clock is running: playing, and not stalled on a slow source.
  bool get advancing => playing && !buffering;

  /// Everything but the position is the same.
  bool sameExceptPosition(NowPlayingInfo other) =>
      other.title == title &&
      other.subtitle == subtitle &&
      other.duration == duration &&
      other.speed == speed &&
      other.playing == playing &&
      other.buffering == buffering &&
      other.hasPrevious == hasPrevious &&
      other.hasNext == hasNext &&
      other.stepSeconds == stepSeconds;

  /// The `marquee/media` channel's `update` arguments.
  Map<String, Object?> toMap() => {
    'title': title,
    'subtitle': subtitle,
    'durationMs': duration.inMilliseconds,
    'positionMs': position.inMilliseconds,
    'speed': speed,
    'playing': playing,
    'buffering': buffering,
    'hasPrevious': hasPrevious,
    'hasNext': hasNext,
    'stepSeconds': stepSeconds,
  };
}

/// A clock this far from where the system expects it was moved by something (a seek, a stall):
/// say so. Smaller differences are the two clocks ticking apart, and correcting those would
/// redraw the lock screen for nothing.
const Duration kNowPlayingDrift = Duration(milliseconds: 1500);

/// Where the system believes the film is, [elapsed] after it was told [sent].
Duration expectedPosition(NowPlayingInfo sent, Duration elapsed) {
  if (!sent.advancing || elapsed <= Duration.zero) return sent.position;
  final at = sent.position + elapsed * sent.speed;
  return sent.duration > Duration.zero && at > sent.duration ? sent.duration : at;
}

/// Whether the system has to be told [now], having been told [sent] [elapsed] ago (null: never).
bool nowPlayingChanged(NowPlayingInfo? sent, Duration elapsed, NowPlayingInfo now) {
  if (sent == null || !sent.sameExceptPosition(now)) return true;
  final drift = now.position - expectedPosition(sent, elapsed);
  return drift.abs() > kNowPlayingDrift;
}

/// The second line: the file's own name, when the title shown is not simply that name.
String? nowPlayingSubtitle({required String title, required String fileName}) {
  final dot = fileName.lastIndexOf('.');
  final bare = dot > 0 ? fileName.substring(0, dot) : fileName;
  if (bare.isEmpty || bare == title || fileName == title) return null;
  return fileName;
}
