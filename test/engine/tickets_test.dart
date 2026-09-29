import 'package:marquee/engine/models/quota.dart';
import 'package:marquee/engine/tickets.dart';
import 'package:test/test.dart';

final reset = DateTime.utc(2026, 9, 7);

void main() {
  group('ticket strip', () {
    test('prints remaining of total and the UTC reset from the download response', () {
      final q = quotaAfterDownload(
        quotaAfterLogin(allowedDownloads: 10, vip: false),
        remaining: 7,
        resetUtc: reset,
      );
      final s = ticketStrip(q);
      expect(s.text, '7 OF 10 TONIGHT · RESETS 00:00 UTC');
      expect(s.state, TicketState.nLeft);
      expect(s.ariaLabel, '7 of 10 downloads left tonight');
      expect(s.sentence, isNull);
      expect(s.pendingTear, isFalse);
    });

    test('turns crimson with a sign-in or Subdl offer at two left', () {
      final s = ticketStrip(Quota(remaining: 2, total: 10, resetUtc: reset, signedIn: true));
      expect(s.state, TicketState.twoLeft);
      expect(s.text, '2 OF 10 TONIGHT · RESETS 00:00 UTC');
      expect(s.sentence, kLowQuotaSentence);
      expect(s.ariaLabel, '2 of 10 downloads left tonight');
    });

    test('reads no tickets left at zero remaining', () {
      final s = ticketStrip(Quota(remaining: 0, total: 10, resetUtc: reset, signedIn: true));
      expect(s.state, TicketState.exhausted);
      expect(s.text, 'NO TICKETS LEFT TONIGHT · RESETS 00:00 UTC');
      expect(s.sentence, kNoTicketsSentence);
      expect(s.ariaLabel, 'No downloads left tonight');
    });

    test('reads anonymous when signed out', () {
      final s = ticketStrip(Quota.anonymous);
      expect(s.text, 'ANONYMOUS · 5 PER DAY PER IP');
      expect(s.state, TicketState.anonymous);
      expect(s.ariaLabel, 'Anonymous: 5 downloads per day per network');
    });

    test('trusts allowed_downloads from the login response, never a constant', () {
      final q = quotaAfterLogin(allowedDownloads: 20, vip: false).copyWith(remaining: 7);
      expect(ticketStrip(q).text, '7 OF 20 TONIGHT');
      expect(ticketStrip(q).state, TicketState.nLeft);
    });

    test('marks a VIP account with its own total', () {
      final q = quotaAfterLogin(allowedDownloads: 1000, vip: true).copyWith(remaining: 7);
      expect(ticketStrip(q).text, '7 OF 1000 · VIP');
      expect(ticketStrip(q).state, TicketState.vip);
    });

    test('says so when the count is unknown', () {
      final s = ticketStrip(const Quota(signedIn: true));
      expect(s.state, TicketState.unknown);
      expect(ticketStrip(const Quota(signedIn: true, remaining: 4)).text, '4 LEFT TONIGHT');
    });

    test('carries the pending tear flag for the decrement-after-tear order', () {
      final s = ticketStrip(Quota(remaining: 7, total: 10, signedIn: true), pendingTear: true);
      expect(s.pendingTear, isTrue);
    });
  });
}
