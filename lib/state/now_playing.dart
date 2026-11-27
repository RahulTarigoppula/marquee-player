// Keeps the phone's lock screen, notification shade and headset buttons in step with the open
// film, and does what they ask. Android only: Windows has its own media keys (the Auditorium
// handles them) and plays on when minimised without help.
//
// The film is shown from the moment it starts until it closes. Between two films of a folder
// (the end of an episode, or "next" pressed on the lock screen) the controls STAY, reading
// "loading": dropping them would end the playback service, and Android does not let an app in
// the background start it again.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/now_playing.dart';
import '../platform/now_playing.dart';
import '../player/engine.dart';
import 'providers.dart';
import 'session.dart';

/// How long an empty session may still be "the next film is opening" before it is checked again.
const Duration kNowPlayingHold = Duration(seconds: 3);

/// The channel to the system: replaced in tests.
final nowPlayingChannelProvider = Provider<NowPlayingChannel>((ref) => NowPlayingChannel());

/// Read once from the app shell at start-up; it then follows the session for the app's life.
final nowPlayingProvider = Provider<void>((ref) {
  if (!NowPlayingChannel.supported) return;
  final bridge = _NowPlayingBridge(ref, ref.read(nowPlayingChannelProvider));
  ref.onDispose(bridge.dispose);
  bridge.start();
});

class _NowPlayingBridge {
  final Ref ref;
  final NowPlayingChannel channel;

  _NowPlayingBridge(this.ref, this.channel);

  PlayerEngine? _engine;
  StreamSubscription<PlaybackState>? _states;
  Timer? _hold;

  /// What the system was last told, and how long ago: it has been advancing the clock itself
  /// since (see [nowPlayingChanged]).
  NowPlayingInfo? _sent;
  final _sinceSent = Stopwatch();

  SessionNotifier get _notifier => ref.read(sessionProvider.notifier);

  void start() {
    channel.listen(
      NowPlayingCommands(
        play: () => unawaited(_engine?.play()),
        pause: () {
          unawaited(_engine?.pause());
          unawaited(_notifier.saveResumeNow());
        },
        rewind: () => _jump(forward: false),
        forward: () => _jump(forward: true),
        previous: () => unawaited(_notifier.playNeighbour(next: false)),
        next: () => unawaited(_notifier.playNeighbour(next: true)),
        seekTo: (at) => unawaited(_engine?.seekTo(at)),
      ),
    );
    ref.listen(sessionProvider, (_, s) => _onSession(s), fireImmediately: true);
    // The jump size is on the buttons' labels.
    ref.listen(settingsValueProvider.select((s) => s.seekStepSeconds), (_, _) => _push());
  }

  void dispose() {
    _hold?.cancel();
    unawaited(_states?.cancel());
    channel.stopListening();
    unawaited(channel.clear());
  }

  void _jump({required bool forward}) {
    final step = Duration(seconds: ref.read(settingsValueProvider).seekStepSeconds);
    unawaited(_engine?.seekBy(forward ? step : -step));
  }

  void _onSession(FilmSession? s) {
    _hold?.cancel();
    final showable = s != null && s.error == null;
    final engine = showable && s.started ? s.engine : null;
    if (!identical(engine, _engine)) {
      unawaited(_states?.cancel());
      _engine = engine;
      // 10 Hz while the film moves, silent while it is paused: every tick is weighed by
      // [nowPlayingChanged], and almost none is sent on.
      _states = engine?.states.listen((_) => _push());
    }
    if (showable) {
      _push();
    } else if (s == null && _sent != null && _notifier.isOpening) {
      // The previous film has closed and the next is on its way: keep the controls. An open
      // that fails leaves the session empty with no further event, hence the second look.
      _hold = Timer(kNowPlayingHold, () => _onSession(ref.read(sessionProvider)));
    } else {
      _clear();
    }
  }

  void _clear() {
    if (_sent == null) return;
    _sent = null;
    _sinceSent.stop();
    unawaited(channel.clear());
  }

  void _push() {
    final s = ref.read(sessionProvider);
    if (s == null || s.error != null) return;
    final info = s.started ? _playing(s) : _loading(s);
    if (info == null || !nowPlayingChanged(_sent, _sinceSent.elapsed, info)) return;
    _sent = info;
    _sinceSent
      ..reset()
      ..start();
    unawaited(channel.show(info));
  }

  NowPlayingInfo? _playing(FilmSession s) {
    final engine = s.engine;
    if (engine.isDisposed) return null;
    final st = engine.player.state;
    final title = s.displayTitle;
    return NowPlayingInfo(
      title: title,
      subtitle: nowPlayingSubtitle(title: title, fileName: s.file.displayName),
      duration: st.duration,
      position: st.position,
      speed: st.rate,
      playing: st.playing,
      buffering: st.buffering,
      hasPrevious: s.previousPath != null,
      hasNext: s.nextPath != null,
      stepSeconds: ref.read(settingsValueProvider).seekStepSeconds,
    );
  }

  /// A film that has not started yet is shown only when it follows another: the controls then
  /// carry over, as "loading", so the service behind them never stops.
  NowPlayingInfo? _loading(FilmSession s) {
    if (_sent == null) return null;
    final title = s.displayTitle;
    return NowPlayingInfo(
      title: title,
      subtitle: nowPlayingSubtitle(title: title, fileName: s.file.displayName),
      playing: true,
      buffering: true,
      stepSeconds: ref.read(settingsValueProvider).seekStepSeconds,
    );
  }
}
