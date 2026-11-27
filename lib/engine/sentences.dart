// Every failure has exactly one plain sentence (§7.5). Never a code, never a stack trace, and
// never the cinema: an error is read by someone who is already confused, so it says "video",
// "subtitles" and "Settings", the words on the screens it points to.
import 'models/leader.dart';
import 'models/subtitles.dart';
import 'playback.dart' show kIso639_2;
import 'tickets.dart';

/// The sign-in token stopped working (a 401).
const String kTicketExpired = 'Your OpenSubtitles sign-in expired. Sign in again.';

/// Subtitles were found by name, not by the file's fingerprint: the viewer chooses.
const String kPickASubtitle = 'No exact match for this file. Pick the subtitles that fit.';

/// libmpv could not open or decode the file. The card that shows it adds the file's name.
const String kCannotPlay = "Marquee can't play this file.";

String sentenceFor(ThreadingFailure f, {int? retryAfterSeconds}) => switch (f) {
  ThreadingFailure.fileTooSmall => '',
  ThreadingFailure.offline => "You're offline, so the video plays without new subtitles.",
  ThreadingFailure.timeout => 'OpenSubtitles is taking too long to answer.',
  ThreadingFailure.noResults => 'No subtitles found for this video.',
  ThreadingFailure.unauthorized => kTicketExpired,
  ThreadingFailure.quotaExhausted => kNoTicketsSentence,
  ThreadingFailure.rateLimited => 'OpenSubtitles asked us to wait ${retryAfterSeconds ?? 2} s.',
  ThreadingFailure.linkExpired => 'That download link expired. Getting a fresh one.',
  ThreadingFailure.writeFailed =>
    "Couldn't save the subtitles next to the video, so Marquee keeps them itself.",
  ThreadingFailure.decodeFailed => kCannotPlay,
  ThreadingFailure.cancelled => 'Skipped subtitles.',
  ThreadingFailure.noApiKey =>
    'Add your free OpenSubtitles API key in Settings › Subtitles to search for subtitles.',
};

/// The phase announcement, once per phase — never per sweep frame.
String announceFor(LeaderPhase p, {String language = 'English', bool synced = false}) =>
    switch (p) {
      LeaderPhase.idle => '',
      LeaderPhase.hashing => 'Reading file',
      LeaderPhase.searching => 'Searching subtitles',
      LeaderPhase.downloading => 'Downloading $language subtitles',
      LeaderPhase.flash ||
      LeaderPhase.done => synced ? 'Subtitles attached, in sync' : 'Subtitles attached',
    };

const Map<String, String> kLanguageNames = {
  'en': 'English',
  'hi': 'Hindi',
  'ta': 'Tamil',
  'te': 'Telugu',
  'ml': 'Malayalam',
  'bn': 'Bengali',
  'mr': 'Marathi',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'ar': 'Arabic',
  'nl': 'Dutch',
  'sv': 'Swedish',
  'pl': 'Polish',
  'tr': 'Turkish',
  'he': 'Hebrew',
  'fa': 'Persian',
  'ur': 'Urdu',
  'th': 'Thai',
  'vi': 'Vietnamese',
  'id': 'Indonesian',
  'el': 'Greek',
  'cs': 'Czech',
  'ro': 'Romanian',
  'hu': 'Hungarian',
  'uk': 'Ukrainian',
  'da': 'Danish',
  'fi': 'Finnish',
  'no': 'Norwegian',
  'ms': 'Malay',
  'kn': 'Kannada',
  'gu': 'Gujarati',
  'pa': 'Punjabi',
};

/// What a container writes when it does not know a track's language.
const String kUnknownLanguage = 'Unknown language';

/// The three-letter codes containers use (`eng`, `fre`, `jpn`), back to the two-letter ones.
final Map<String, String> _fromIso639_2 = {
  for (final MapEntry(key: two, value: threes) in kIso639_2.entries)
    for (final three in threes) three: two,
};

/// A language as a person says it: `en`, `eng` and `en-US` are all "English". A code nobody
/// here knows is shown as it is, in capitals, rather than guessed at.
String languageName(String code) {
  final c = code.toLowerCase();
  if (c == 'und') return kUnknownLanguage;
  final base = c.split(RegExp('[-_]')).first;
  return kLanguageNames[c] ??
      kLanguageNames[base] ??
      kLanguageNames[_fromIso639_2[base]] ??
      code.toUpperCase();
}

/// How a found subtitle was matched to the video, as its row says it: the green light, or the
/// warning that its timing was never checked against this file.
const String kMadeForThisFile = 'Made for this exact file';
const String kMatchedByName = 'Matched by name — timing may be off';

String matchLine({required bool exact}) => exact ? kMadeForThisFile : kMatchedByName;

/// The small print under a found subtitle: what helps someone choose between two of them.
/// Frame rates stay out (Video details has them); a count of zero is "not known", so unsaid.
String candidateDetails(SubtitleCandidate c) => [
  if (c.downloadCount == 1) '1 download',
  if (c.downloadCount > 1) '${thousands(c.downloadCount)} downloads',
  if (c.hearingImpaired) 'for the hard of hearing',
  if (c.machineTranslated || c.aiTranslated) 'machine-translated',
  if (c.provider == SubtitleProvider.subdl) 'from Subdl',
].join(' · ');

/// The sound's timing in a sentence, the way the subtitle timing ruler says its own
/// ("Subtitles show 0.35 s later."): `Sound plays 0.15 s later.`
String soundTimingSentence(int ms) {
  if (ms == 0) return 'Sound is in time with the picture.';
  final by = (ms.abs() / 1000).toStringAsFixed(2);
  return ms > 0 ? 'Sound plays $by s later.' : 'Sound plays $by s earlier.';
}

/// A subtitle that came with the video or from a file, as a row names it: `French · Forced`,
/// `English · inside the video`, or `Track 3` for one that says nothing about itself.
String subtitleTrackTitle({
  required String id,
  String? language,
  String? title,
  required bool external,
}) {
  final lang = language == null || language.trim().isEmpty ? null : languageName(language);
  final name = title == null || title.trim().isEmpty ? null : title.trim();
  if (lang == null && name == null) return external ? 'Subtitle file' : 'Track $id';
  return [?lang, name ?? (external ? 'from a file' : 'inside the video')].join(' · ');
}
