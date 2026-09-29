// Every failure has exactly one plain sentence (§7.5). Never a code, never a stack trace.
import 'models/leader.dart';

String sentenceFor(ThreadingFailure f, {int? retryAfterSeconds}) => switch (f) {
  ThreadingFailure.fileTooSmall => '',
  ThreadingFailure.offline => "You're offline — playing without new subtitles.",
  ThreadingFailure.timeout => 'OpenSubtitles is taking too long to answer.',
  ThreadingFailure.noResults => 'No subtitles found for this print.',
  ThreadingFailure.unauthorized => 'Ticket expired — sign in again.',
  ThreadingFailure.quotaExhausted =>
    'No tickets left tonight — sign in for more, or use the Subdl slot.',
  ThreadingFailure.rateLimited => 'OpenSubtitles asked us to wait ${retryAfterSeconds ?? 2} s.',
  ThreadingFailure.linkExpired => 'That print expired — fetching a fresh link.',
  ThreadingFailure.writeFailed => "Couldn't write beside the file — saved in app storage instead.",
  ThreadingFailure.decodeFailed => "This print can't be projected.",
  ThreadingFailure.cancelled => 'Skipped subtitles.',
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
};

String languageName(String code) => kLanguageNames[code.toLowerCase()] ?? code.toUpperCase();
