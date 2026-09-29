enum TicketState { anonymous, nLeft, twoLeft, exhausted, vip, unknown }

class Quota {
  final int? remaining; // from /download or /login
  final int? total; // login `allowed_downloads` — NEVER a constant
  final DateTime? resetUtc;
  final bool signedIn, vip;
  final String? level;

  const Quota({
    this.remaining,
    this.total,
    this.resetUtc,
    this.signedIn = false,
    this.vip = false,
    this.level,
  });

  static const anonymous = Quota();

  TicketState get state {
    if (!signedIn) return TicketState.anonymous;
    if (vip) return TicketState.vip;
    final r = remaining;
    if (r == null) return TicketState.unknown;
    if (r <= 0) return TicketState.exhausted;
    if (r <= 2) return TicketState.twoLeft;
    return TicketState.nLeft;
  }

  Quota copyWith({
    int? remaining,
    int? total,
    DateTime? resetUtc,
    bool? signedIn,
    bool? vip,
    String? level,
  }) => Quota(
    remaining: remaining ?? this.remaining,
    total: total ?? this.total,
    resetUtc: resetUtc ?? this.resetUtc,
    signedIn: signedIn ?? this.signedIn,
    vip: vip ?? this.vip,
    level: level ?? this.level,
  );
}

/// Pure view model produced by tickets.dart (§6.6).
class TicketStrip {
  final String text;
  final String? sentence;
  final String ariaLabel;
  final TicketState state;
  final bool pendingTear; // the count decrements AFTER ticket-tear completes

  const TicketStrip({
    required this.text,
    required this.sentence,
    required this.ariaLabel,
    required this.state,
    this.pendingTear = false,
  });
}
