// Riverpod providers (§5.4). Widgets watch these; only these touch lib/api and lib/db.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/opensubtitles.dart';
import '../db/database.dart';
import '../engine/models/models.dart';
import '../engine/tickets.dart';

const String appVersion = kMarqueeVersion;

/// Overridden in main() with the opened database (and in tests with an in-memory one).
final databaseProvider = Provider<MarqueeDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

final openSubtitlesProvider = Provider<OpenSubtitlesClient>((ref) {
  final c = OpenSubtitlesClient();
  ref.onDispose(c.client.close);
  return c;
});

// ───────────────────────────── settings ─────────────────────────────

class SettingsNotifier extends AsyncNotifier<Settings> {
  @override
  Future<Settings> build() => ref.read(databaseProvider).readSettings();

  Future<void> save(Settings s) async {
    state = AsyncData(s);
    await ref.read(databaseProvider).writeSettings(s);
  }

  Future<void> edit(Settings Function(Settings) f) async {
    final cur = state.value ?? const Settings();
    await save(f(cur));
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

/// Settings with defaults while loading — for widgets that must not flash.
final settingsValueProvider = Provider<Settings>(
  (ref) => ref.watch(settingsProvider).value ?? const Settings(),
);

// ───────────────────────────── quota + account ─────────────────────────────

const _jwtKey = 'os_jwt';
const _hostKey = 'os_host';
const _subdlKey = 'subdl_key';

enum AccountStatus { signedOut, signingIn, signedIn, expired, error }

class Account {
  final AccountStatus status;
  final String? username;
  final String? sentence;
  const Account({this.status = AccountStatus.signedOut, this.username, this.sentence});
}

class QuotaNotifier extends Notifier<Quota> {
  @override
  Quota build() => Quota.anonymous;

  void set(Quota q) => state = q;

  void afterDownload(int remaining, DateTime? reset) =>
      state = quotaAfterDownload(state, remaining: remaining, resetUtc: reset);
}

final quotaProvider = NotifierProvider<QuotaNotifier, Quota>(QuotaNotifier.new);

final ticketStripProvider = Provider((ref) => ticketStrip(ref.watch(quotaProvider)));

class AccountNotifier extends Notifier<Account> {
  @override
  Account build() {
    unawaited(_restore());
    return const Account();
  }

  FlutterSecureStorage get _store => ref.read(secureStorageProvider);
  OpenSubtitlesClient get _client => ref.read(openSubtitlesProvider);

  Future<void> _restore() async {
    try {
      final jwt = await _store.read(key: _jwtKey);
      if (jwt == null || jwt.isEmpty) return;
      _client.jwt = jwt;
      _client.host = await _store.read(key: _hostKey) ?? kDefaultHost;
      state = const Account(status: AccountStatus.signedIn);
      ref.read(quotaProvider.notifier).set(const Quota(signedIn: true));
      if (_client.hasKey) {
        ref.read(quotaProvider.notifier).set(await _client.userInfo());
      }
    } on ThreadingException catch (e) {
      if (e.failure == ThreadingFailure.unauthorized) {
        state = const Account(
          status: AccountStatus.expired,
          sentence: 'Ticket expired — sign in again.',
        );
      }
    } on Object {
      // Secure storage unavailable (e.g. a locked keyring): stay signed out, quietly.
    }
  }

  /// The JWT goes to secure storage; the password is never kept anywhere.
  Future<void> signIn(String username, String password) async {
    state = Account(status: AccountStatus.signingIn, username: username);
    try {
      final r = await _client.login(username, password);
      _client
        ..jwt = r.token
        ..host = r.baseUrl;
      await _store.write(key: _jwtKey, value: r.token);
      await _store.write(key: _hostKey, value: r.baseUrl);
      ref.read(quotaProvider.notifier).set(r.quota);
      state = Account(status: AccountStatus.signedIn, username: username);
    } on ThreadingException catch (e) {
      state = Account(
        status: AccountStatus.error,
        username: username,
        sentence: switch (e.failure) {
          ThreadingFailure.unauthorized => "That username and password didn't work.",
          ThreadingFailure.offline => "You're offline — try again when you're connected.",
          ThreadingFailure.rateLimited => 'OpenSubtitles asked us to wait a moment.',
          _ => "OpenSubtitles didn't answer — try again in a moment.",
        },
      );
    }
  }

  Future<void> signOut() async {
    await _client.logout();
    await _store.delete(key: _jwtKey);
    await _store.delete(key: _hostKey);
    _client.host = kDefaultHost;
    ref.read(quotaProvider.notifier).set(Quota.anonymous);
    state = const Account();
  }

  void markExpired() => state = const Account(
    status: AccountStatus.expired,
    sentence: 'Ticket expired — sign in again.',
  );

  Future<String?> subdlKey() => _store.read(key: _subdlKey);
  Future<void> setSubdlKey(String key) =>
      key.isEmpty ? _store.delete(key: _subdlKey) : _store.write(key: _subdlKey, value: key);
}

final accountProvider = NotifierProvider<AccountNotifier, Account>(AccountNotifier.new);

// ───────────────────────────── library ─────────────────────────────

final libraryProvider = StreamProvider<List<LobbyCard>>(
  (ref) => ref.watch(databaseProvider).watchLobby(),
);

// ───────────────────────────── rooms + house lights ─────────────────────────────

enum Room { lobby, auditorium, ticketOffice }

class RoomNotifier extends Notifier<Room> {
  @override
  Room build() => Room.lobby;
  void go(Room r) => state = r;
}

final roomProvider = NotifierProvider<RoomNotifier, Room>(RoomNotifier.new);

/// Target of the house lights: true = down (dark). ONE AnimationController in `HouseLights`
/// tweens `--house` toward it; every lit thing reads that single value.
class HouseNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(roomProvider) == Room.auditorium;
}

final houseDownProvider = NotifierProvider<HouseNotifier, bool>(HouseNotifier.new);

/// Whether the cue sheet overlay is shown.
class ToggleNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
  void toggle() => state = !state;
}

final cueSheetProvider = NotifierProvider<ToggleNotifier, bool>(ToggleNotifier.new);
final boothOpenProvider = NotifierProvider<ToggleNotifier, bool>(ToggleNotifier.new);

/// Library effects for widgets (they never touch lib/db themselves).
class LibraryActions {
  final Ref ref;
  const LibraryActions(this.ref);
  Future<void> remove(int id) => ref.read(databaseProvider).removeMedia(id);
  Future<Map<String, Object?>> export(String platform) =>
      ref.read(databaseProvider).exportLibrary(version: appVersion, platform: platform);
  Future<void> import(Map<String, Object?> json) async {
    await ref.read(databaseProvider).importLibrary(json);
    ref.invalidate(settingsProvider);
  }
}

final libraryActionsProvider = Provider<LibraryActions>(LibraryActions.new);
