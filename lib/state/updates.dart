// Updates, privately. Nothing here touches the network unless the user tapped "Check for
// updates" or turned "Check for updates automatically" on; then it is one GET to GitHub
// (lib/api/updates.dart), at most once a day, a few seconds after start-up, off the UI's path.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/updates.dart';
import '../engine/version.dart';
import 'notice.dart';
import 'providers.dart';

export '../api/updates.dart' show Release, kIssuesPage, kProjectPage;

sealed class UpdateState {
  const UpdateState();
}

/// Nobody has asked yet (or a silent check found nothing worth saying).
class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateAvailable extends UpdateState {
  final Release release;

  /// False when this build's version cannot be compared (a test build): [release] is the
  /// latest one, offered as a page to look at, not announced as newer.
  final bool newer;
  const UpdateAvailable(this.release, {this.newer = true});
}

class UpdateFailed extends UpdateState {
  /// One plain sentence with the next step.
  final String sentence;
  const UpdateFailed(this.sentence);
}

/// The version this build compares releases with. Overridden in tests and screenshots.
final currentVersionProvider = Provider<String>((ref) => appVersion);

final updatesClientProvider = Provider<UpdatesClient>((ref) {
  final c = UpdatesClient();
  ref.onDispose(c.client.close);
  return c;
});

/// The Settings section the Ticket Office should open on next ([kSettingsAbout]). The screen
/// takes the request and clears it.
class SettingsJumpNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void to(String section) => state = section;
  void clear() => state = null;
}

final settingsJumpProvider = NotifierProvider<SettingsJumpNotifier, String?>(
  SettingsJumpNotifier.new,
);

/// `SettingsSection.about.name`, spelled here because lib/state never imports lib/ui.
const String kSettingsAbout = 'about';

/// Start-up settles first (the window, the library, an "Open with" film); then the check.
const Duration kAutoCheckDelay = Duration(seconds: 6);

const _stateKey = 'update_check';

class UpdatesNotifier extends Notifier<UpdateState> {
  bool _busy = false;

  /// Whether the check in flight was started by the app, not the user: it says nothing unless
  /// it finds a newer version. A tap on "Check for updates" meanwhile makes it speak.
  bool _silent = false;
  void Function()? _stopWaitingForLobby;

  @override
  UpdateState build() {
    ref.onDispose(() => _stopWaitingForLobby?.call());
    return const UpdateIdle();
  }

  /// "Check for updates": always asks, and says what it found or why it could not.
  Future<void> check() async {
    _silent = false;
    state = const UpdateChecking();
    await _run();
  }

  /// The automatic check: only with the user's consent (the setting), only for a build that
  /// can be compared, and only when the last check was a day or more ago.
  Future<void> checkIfDue() async {
    if (_busy || !ref.read(settingsValueProvider).autoCheckUpdates) return;
    // A test build learns nothing from the answer, so it does not ask.
    if (!canCompare(ref.read(currentVersionProvider))) return;
    try {
      final record = await ref.read(databaseProvider).readState(_stateKey);
      if (!updateCheckDue(_lastCheck(record), clock.now())) return;
    } on Object {
      return; // no record to trust: rather skip a day than ask twice
    }
    if (!ref.mounted || _busy) return;
    _silent = true;
    await _run();
  }

  Future<void> _run() async {
    if (_busy) return; // the check in flight answers for this one too
    _busy = true;
    try {
      final release = await ref.read(updatesClientProvider).latest(UpdateTarget.current);
      if (!ref.mounted) return;
      final verdict = compareRelease(ref.read(currentVersionProvider), release.tag);
      final announce = _silent && verdict == UpdateVerdict.newer;
      switch (verdict) {
        case UpdateVerdict.newer:
          state = UpdateAvailable(release);
        case UpdateVerdict.upToDate:
          if (!_silent) state = const UpdateUpToDate();
        case UpdateVerdict.unknown:
          if (!_silent) state = UpdateAvailable(release, newer: false);
      }
      final told = await _stamp(notified: announce ? release.tag : null);
      // One notice per version: the next day's check finds the same release and stays quiet.
      if (announce && told != release.tag && ref.mounted) _announce(release);
    } on UpdateException catch (e) {
      // Offline, nothing reached GitHub: that does not use up today's check.
      if (e.failure != UpdateFailure.offline) await _stamp();
      if (!_silent && ref.mounted) state = UpdateFailed(e.sentence);
    } on Object {
      if (!_silent && ref.mounted) {
        state = UpdateFailed(const UpdateException(UpdateFailure.unexpected).sentence);
      }
    } finally {
      _busy = false;
    }
  }

  static DateTime? _lastCheck(Object? record) {
    final at = record is Map ? record['at'] : null;
    return at is String ? DateTime.tryParse(at) : null;
  }

  /// Records this check (a manual one counts as today's). Returns the version the user had
  /// already been told about before this call, if any.
  Future<String?> _stamp({String? notified}) async {
    try {
      final db = ref.read(databaseProvider);
      final old = await db.readState(_stateKey);
      final told = old is Map && old['notified'] is String ? old['notified'] as String : null;
      await db.writeState(_stateKey, {
        'at': clock.now().toUtc().toIso8601String(),
        'notified': ?(notified ?? told),
      });
      return told;
    } on Object {
      return null; // a read-only or closing database: the check itself still stands
    }
  }

  void _announce(Release release) {
    void show() => ref
        .read(noticeProvider.notifier)
        .show(
          'Marquee ${release.version} is available.',
          actionLabel: "What's new",
          duration: const Duration(seconds: 8),
          onAction: () {
            ref.read(settingsJumpProvider.notifier).to(kSettingsAbout);
            ref.read(roomProvider.notifier).go(Room.ticketOffice);
          },
        );
    if (ref.read(roomProvider) != Room.auditorium) return show();
    // Never over a film: it waits for the Lobby.
    _stopWaitingForLobby?.call();
    final sub = ref.listen(roomProvider, (_, room) {
      if (room != Room.lobby) return;
      _stopWaitingForLobby?.call();
      _stopWaitingForLobby = null;
      show();
    });
    _stopWaitingForLobby = sub.close;
  }
}

final updatesProvider = NotifierProvider<UpdatesNotifier, UpdateState>(UpdatesNotifier.new);

/// Keeps the automatic check alive: read it once from the app shell at start-up. It waits for
/// the setting (so it also wakes when the user turns it on), then [kAutoCheckDelay], then asks
/// [UpdatesNotifier.checkIfDue]. With the setting off it does nothing at all.
final autoUpdateCheckProvider = Provider<void>((ref) {
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.listen(settingsValueProvider.select((s) => s.autoCheckUpdates), (_, on) {
    timer?.cancel();
    timer = on
        ? Timer(kAutoCheckDelay, () => unawaited(ref.read(updatesProvider.notifier).checkIfDue()))
        : null;
  }, fireImmediately: true);
});
