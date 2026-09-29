// Quota → ticket strip (§6.6). A pure function of the last /download or /login response.
// The total is NEVER a constant: print whatever `allowed_downloads` came back with.
import 'models/quota.dart';

const String kLowQuotaSentence =
    'Sign in at the ticket office (free, more tickets) or use the Subdl slot.';
const String kNoTicketsSentence =
    'No tickets left tonight — sign in for more, or use the Subdl slot.';

String _two(int n) => n.toString().padLeft(2, '0');

String _resets(DateTime? reset) {
  if (reset == null) return '';
  final u = reset.toUtc();
  return ' · RESETS ${_two(u.hour)}:${_two(u.minute)} UTC';
}

/// [pendingTear] is true while the ticket-tear animation runs: the view keeps showing the
/// PREVIOUS count until the tear completes (the widget test asserts that order).
TicketStrip ticketStrip(Quota q, {bool pendingTear = false}) {
  final r = q.remaining;
  final t = q.total;
  switch (q.state) {
    case TicketState.anonymous:
      return TicketStrip(
        text: 'ANONYMOUS · 5 PER DAY PER IP',
        sentence: null,
        ariaLabel: 'Anonymous: 5 downloads per day per network',
        state: TicketState.anonymous,
        pendingTear: pendingTear,
      );
    case TicketState.vip:
      final count = r == null ? 'VIP' : (t == null ? '$r LEFT · VIP' : '$r OF $t · VIP');
      return TicketStrip(
        text: count,
        sentence: null,
        ariaLabel: r == null ? 'VIP downloads' : '$r of ${t ?? r} downloads left, VIP',
        state: TicketState.vip,
        pendingTear: pendingTear,
      );
    case TicketState.unknown:
      return TicketStrip(
        text: 'SIGNED IN · TICKETS UNKNOWN',
        sentence: null,
        ariaLabel: 'Signed in; downloads left unknown',
        state: TicketState.unknown,
        pendingTear: pendingTear,
      );
    case TicketState.exhausted:
      return TicketStrip(
        text: 'NO TICKETS LEFT TONIGHT${_resets(q.resetUtc)}',
        sentence: kNoTicketsSentence,
        ariaLabel: 'No downloads left tonight',
        state: TicketState.exhausted,
        pendingTear: pendingTear,
      );
    case TicketState.twoLeft:
    case TicketState.nLeft:
      final left = r ?? 0;
      final of = t == null ? '$left LEFT TONIGHT' : '$left OF $t TONIGHT';
      return TicketStrip(
        text: '$of${_resets(q.resetUtc)}',
        sentence: q.state == TicketState.twoLeft ? kLowQuotaSentence : null,
        ariaLabel: t == null
            ? '$left downloads left tonight'
            : '$left of $t downloads left tonight',
        state: q.state,
        pendingTear: pendingTear,
      );
  }
}

/// Folds a /download response into the quota. `remaining` is always the server's number.
Quota quotaAfterDownload(Quota q, {required int remaining, DateTime? resetUtc}) =>
    q.copyWith(remaining: remaining, resetUtc: resetUtc);

/// Folds a /login response into the quota: `allowed_downloads` is the total — never 10.
Quota quotaAfterLogin({
  required int allowedDownloads,
  required bool vip,
  String? level,
  int? remaining,
}) => Quota(
  remaining: remaining ?? allowedDownloads,
  total: allowedDownloads,
  signedIn: true,
  vip: vip,
  level: level,
);
