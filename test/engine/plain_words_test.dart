// The words people read about subtitles: language names, the lines under a found subtitle,
// the download allowance and the failure sentences. They are plain on purpose, and these
// tests keep the codes and the cinema ("print", "ticket", "lobby", "tonight") from coming back.
//
// A file of its own: the eight engine test files mirrored by the TypeScript suite must keep
// the same test names on both sides (scripts/check-parity.mjs).
import 'package:marquee/engine/models/models.dart';
import 'package:marquee/engine/sentences.dart';
import 'package:marquee/engine/tickets.dart';
import 'package:marquee/engine/timecode.dart';
import 'package:test/test.dart';

SubtitleCandidate _candidate({
  int downloads = 0,
  bool hearingImpaired = false,
  bool machine = false,
  bool ai = false,
  SubtitleProvider provider = SubtitleProvider.openSubtitles,
}) => SubtitleCandidate(
  provider: provider,
  id: '1',
  language: 'en',
  downloadCount: downloads,
  hearingImpaired: hearingImpaired,
  machineTranslated: machine,
  aiTranslated: ai,
);

void main() {
  group('language names', () {
    test('names a language from any code a file or a site uses for it', () {
      expect(languageName('en'), 'English');
      expect(languageName('EN'), 'English');
      expect(languageName('eng'), 'English');
      expect(languageName('fre'), 'French');
      expect(languageName('fra'), 'French');
      expect(languageName('jpn'), 'Japanese');
      expect(languageName('pt-BR'), 'Portuguese');
      expect(languageName('zh_TW'), 'Chinese');
    });

    test('has a name for every language the player can be asked to prefer', () {
      for (final code in ['he', 'fa', 'ur', 'th', 'vi', 'id', 'el', 'cs', 'ro', 'hu', 'uk']) {
        expect(languageName(code), isNot(code.toUpperCase()), reason: code);
      }
      expect(languageName('kan'), 'Kannada');
    });

    test('shows an unknown code as it is and says so when there is none', () {
      expect(languageName('xx'), 'XX');
      expect(languageName('tlh'), 'TLH');
      expect(languageName('und'), kUnknownLanguage);
    });
  });

  group('a found subtitle', () {
    test('says in words how it was matched', () {
      expect(matchLine(exact: true), 'Made for this exact file');
      expect(matchLine(exact: false), 'Matched by name — timing may be off');
    });

    test('counts downloads with separators and never as a code', () {
      expect(candidateDetails(_candidate(downloads: 12431)), '12,431 downloads');
      expect(candidateDetails(_candidate(downloads: 1)), '1 download');
      expect(candidateDetails(_candidate(downloads: 999)), '999 downloads');
    });

    test('leaves out a download count nobody knows', () {
      expect(candidateDetails(_candidate()), '');
      expect(candidateDetails(_candidate(provider: SubtitleProvider.subdl)), 'from Subdl');
    });

    test('spells out what the old tags meant', () {
      expect(
        candidateDetails(_candidate(downloads: 2000, hearingImpaired: true, machine: true)),
        '2,000 downloads · for the hard of hearing · machine-translated',
      );
      expect(candidateDetails(_candidate(ai: true)), 'machine-translated');
      final details = candidateDetails(
        _candidate(downloads: 5, hearingImpaired: true, provider: SubtitleProvider.subdl),
      );
      expect(details, '5 downloads · for the hard of hearing · from Subdl');
      expect(details, isNot(contains('HI')));
      expect(details, isNot(contains('fps')));
    });
  });

  group('counts', () {
    test('groups thousands', () {
      expect(thousands(0), '0');
      expect(thousands(999), '999');
      expect(thousands(1000), '1,000');
      expect(thousands(12431), '12,431');
      expect(thousands(1234567), '1,234,567');
      expect(thousands(-1200), '-1,200');
    });
  });

  group('the download allowance', () {
    test('is a sentence, with the right noun for one', () {
      expect(
        ticketStrip(const Quota(signedIn: true, remaining: 1)).text,
        '1 subtitle download left today',
      );
      expect(
        ticketStrip(const Quota(signedIn: true, remaining: 1, total: 10)).text,
        '1 of 10 subtitle downloads left today',
      );
      expect(
        ticketStrip(const Quota(signedIn: true, remaining: 1500, total: 2000)).text,
        '1,500 of 2,000 subtitle downloads left today',
      );
    });

    test('reads the same aloud as on screen', () {
      final s = ticketStrip(const Quota(signedIn: true, remaining: 4, total: 20));
      expect(s.ariaLabel, s.text);
    });

    test('names a VIP account without a count, and with one', () {
      final unknown = ticketStrip(const Quota(signedIn: true, vip: true));
      expect(unknown.text, 'VIP account');
      expect(unknown.ariaLabel, 'VIP account');
      final counted = ticketStrip(const Quota(signedIn: true, vip: true, remaining: 40));
      expect(counted.text, '40 subtitle downloads left today · VIP');
      expect(counted.ariaLabel, '40 subtitle downloads left today, VIP account');
    });

    test('says signed in when the count has not arrived', () {
      final s = ticketStrip(const Quota(signedIn: true));
      expect(s.text, 'Signed in · downloads left today not known yet');
      expect(s.ariaLabel, contains('not known yet'));
    });

    test('never says ticket, tonight, UTC or IP', () {
      final strips = [
        ticketStrip(Quota.anonymous),
        ticketStrip(const Quota(signedIn: true)),
        ticketStrip(const Quota(signedIn: true, vip: true, remaining: 3, total: 1000)),
        ticketStrip(Quota(signedIn: true, remaining: 0, total: 10, resetUtc: DateTime.utc(2026))),
        ticketStrip(Quota(signedIn: true, remaining: 2, total: 10, resetUtc: DateTime.utc(2026))),
        ticketStrip(Quota(signedIn: true, remaining: 7, total: 10, resetUtc: DateTime.utc(2026))),
      ];
      final cinema = RegExp(r'ticket|tonight|\bUTC\b|\bIP\b|slot|anonymous', caseSensitive: false);
      for (final s in strips) {
        for (final words in [s.text, s.ariaLabel, s.sentence ?? '']) {
          expect(words, isNot(matches(cinema)), reason: words);
        }
      }
    });

    test('offers the backup site, not a sign-in, to someone already signed in', () {
      final low = ticketStrip(const Quota(signedIn: true, remaining: 2, total: 10));
      expect(low.sentence, contains('Settings › Subtitles'));
      expect(low.sentence, contains('Subdl'));
      expect(low.sentence!.toLowerCase(), isNot(contains('sign in')));
    });
  });

  group('failure sentences', () {
    test('answer in plain words, never in cinema', () {
      final cinema = RegExp(r'\b(print|projected|ticket|lobby|reel|tonight|slot)\b');
      for (final f in ThreadingFailure.values) {
        expect(sentenceFor(f).toLowerCase(), isNot(matches(cinema)), reason: '$f');
      }
      expect(kPickASubtitle.toLowerCase(), isNot(matches(cinema)));
    });

    test('say exactly what the review asked for', () {
      expect(sentenceFor(ThreadingFailure.decodeFailed), "Marquee can't play this file.");
      expect(kCannotPlay, "Marquee can't play this file.");
      expect(sentenceFor(ThreadingFailure.noResults), 'No subtitles found for this video.');
      expect(
        sentenceFor(ThreadingFailure.unauthorized),
        'Your OpenSubtitles sign-in expired. Sign in again.',
      );
      expect(sentenceFor(ThreadingFailure.quotaExhausted), 'No subtitle downloads left today.');
      expect(sentenceFor(ThreadingFailure.noApiKey), contains('in Settings › Subtitles'));
    });

    test('say where the subtitles went when they could not be saved by the video', () {
      expect(
        sentenceFor(ThreadingFailure.writeFailed),
        "Couldn't save the subtitles next to the video, so Marquee keeps them itself.",
      );
    });
  });

  group('the opening screen', () {
    test('is headed with the title of the video', () {
      expect(threadingFolio('The Third Man'), 'The Third Man');
      expect(threadingFolio('  Severance S02E03 '), 'Severance S02E03');
    });

    test('falls back to plain words when there is no title', () {
      expect(threadingFolio(null), kThreadingFolio);
      expect(threadingFolio('   '), kThreadingFolio);
      expect(kThreadingFolio, isNot(contains('REEL')));
    });
  });

  group('subtitle options', () {
    test('names a track by its language and what it says about itself', () {
      expect(
        subtitleTrackTitle(id: '2', language: 'fre', title: 'Forced', external: false),
        'French · Forced',
      );
      expect(
        subtitleTrackTitle(id: '1', language: 'eng', external: false),
        'English · inside the video',
      );
      expect(
        subtitleTrackTitle(id: '5', language: 'hi', title: ' ', external: true),
        'Hindi · from a file',
      );
      expect(subtitleTrackTitle(id: '6', title: 'Signs', external: false), 'Signs');
    });

    test('numbers a track that says nothing, and names a loaded file', () {
      expect(subtitleTrackTitle(id: '3', external: false), 'Track 3');
      expect(subtitleTrackTitle(id: '3', language: '', external: false), 'Track 3');
      expect(subtitleTrackTitle(id: '4', external: true), 'Subtitle file');
    });

    test('says which way the sound is out, in seconds', () {
      expect(soundTimingSentence(0), 'Sound is in time with the picture.');
      expect(soundTimingSentence(150), 'Sound plays 0.15 s later.');
      expect(soundTimingSentence(-50), 'Sound plays 0.05 s earlier.');
      expect(soundTimingSentence(1200), 'Sound plays 1.20 s later.');
    });
  });
}
