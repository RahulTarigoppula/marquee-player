// Every failure has exactly one plain sentence (§7.5). Never a code, never a stack trace.
import 'models/leader.dart';
import 'tickets.dart';

/// The sign-in token stopped working (a 401).
const String kTicketExpired = 'Your ticket expired. Sign in again.';

String sentenceFor(ThreadingFailure f, {int? retryAfterSeconds}) => switch (f) {
  ThreadingFailure.fileTooSmall => '',
  ThreadingFailure.offline => "You're offline, so the film plays without new subtitles.",
  ThreadingFailure.timeout => 'OpenSubtitles is taking too long to answer.',
  ThreadingFailure.noResults => 'No subtitles found for this print.',
  ThreadingFailure.unauthorized => kTicketExpired,
  ThreadingFailure.quotaExhausted => kNoTicketsSentence,
  ThreadingFailure.rateLimited => 'OpenSubtitles asked us to wait ${retryAfterSeconds ?? 2} s.',
  ThreadingFailure.linkExpired => 'That download link expired. Fetching a fresh one.',
  ThreadingFailure.writeFailed => "Couldn't save beside the file, so it's in app storage instead.",
  ThreadingFailure.decodeFailed => "This print can't be projected.",
  ThreadingFailure.cancelled => 'Skipped subtitles.',
  ThreadingFailure.noApiKey =>
    'Add your free OpenSubtitles API key at the ticket office to search for subtitles.',
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
