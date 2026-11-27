// Quota → the download allowance line (§6.6). A pure function of the last /download or /login
// response. The total is NEVER a constant: print whatever `allowed_downloads` came back with.
//
// The words are plain on purpose: "7 of 10 subtitle downloads left today". The reset time is
// left out: the server gives it in UTC, which is tomorrow for some viewers and tonight for
// others, and "today" is close enough to act on.
import 'models/quota.dart';

/// Under the line when the day's downloads are nearly gone or gone. Only a signed-in count
/// gets that far (see [Quota.state]), so it never says "sign in".
const String kLowQuotaSentence =
    'Need more? Turn on the backup site (Subdl) in Settings › Subtitles.';

/// A search or download the server refused for the day. The ways on (sign in, the backup
/// site) are the buttons under it.
const String kNoTicketsSentence = 'No subtitle downloads left today.';

/// 12431 → `12,431`: every count a person reads (downloads left, downloads so far).
String thousands(int n) {
  final digits = n.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return n < 0 ? '-$digits' : digits;
}

/// `7 of 10 subtitle downloads left today`, `1 subtitle download left today`.
String _left(int left, int? total) {
  final noun = left == 1 && total == null ? 'subtitle download' : 'subtitle downloads';
  return total == null
      ? '${thousands(left)} $noun left today'
      : '${thousands(left)} of ${thousands(total)} $noun left today';
}

/// [pendingTear] is true while the ticket-tear animation runs: the view keeps showing the
/// PREVIOUS count until the tear completes (the widget test asserts that order).
TicketStrip ticketStrip(Quota q, {bool pendingTear = false}) {
  final r = q.remaining;
  final t = q.total;
  switch (q.state) {
    case TicketState.anonymous:
      return TicketStrip(
        text: 'Not signed in · 5 subtitle downloads a day',
        sentence: null,
        ariaLabel: 'Not signed in: 5 subtitle downloads a day',
        state: TicketState.anonymous,
        pendingTear: pendingTear,
      );
    case TicketState.vip:
      final count = r == null ? 'VIP account' : '${_left(r, t)} · VIP';
      return TicketStrip(
        text: count,
        sentence: null,
        ariaLabel: r == null ? 'VIP account' : '${_left(r, t)}, VIP account',
        state: TicketState.vip,
        pendingTear: pendingTear,
      );
    case TicketState.unknown:
      return TicketStrip(
        text: 'Signed in · downloads left today not known yet',
        sentence: null,
        ariaLabel: 'Signed in. Subtitle downloads left today: not known yet',
        state: TicketState.unknown,
        pendingTear: pendingTear,
      );
    case TicketState.exhausted:
      return TicketStrip(
        text: 'No subtitle downloads left today',
        sentence: kLowQuotaSentence,
        ariaLabel: 'No subtitle downloads left today',
        state: TicketState.exhausted,
        pendingTear: pendingTear,
      );
    case TicketState.twoLeft:
    case TicketState.nLeft:
      final left = _left(r ?? 0, t);
      return TicketStrip(
        text: left,
        sentence: q.state == TicketState.twoLeft ? kLowQuotaSentence : null,
        ariaLabel: left,
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
