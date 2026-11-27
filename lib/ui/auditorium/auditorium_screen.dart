// The Auditorium: watch the film. The picture fills the window (or the phone); the controls
// float over it on soft gradients and fade away while the film plays. Keyboard map comes from
// design/cue-sheet.json.
//
// Layers, bottom to top: bias-light walls · the picture · Flutter subtitles (Android, other
// scripts) · the gesture surface · the controls · video details, "Skip intro" · menus,
// readouts, "Up next", the "Unlock" pill · the "can't play this file" card · the picture of
// the touch gestures · the Booth, the threading overlay and the cue sheet. Overlays are
// SIBLINGS of the gesture surface, never its children, so a tap on the threading overlay can
// never pause or seek the hidden film.
//
// This file holds the room's state, its keys and its gestures. The layers themselves live in
// layers.dart, the menus in menu_panel.dart, the pure widgets in controls/.
//
// Touch (phones), all on ONE gesture detector, so the arena has one answer for every touch:
//   tap            controls on / off (after the double-tap window, so a double tap is not both)
//   tap tap (tap)  left third back, right third forward, one step per tap after the first;
//                  the middle plays / pauses
//   hold           2x while held
//   one finger     up / down on the left 40 %: brightness; on the right 40 %: volume;
//                  sideways anywhere but the screen edges: scrub, ONE seek when it lifts
//   two fingers    spread: Fill (crop); pinch: Fit
// Drags and pinches share Flutter's scale recogniser (a detector cannot have both a pan and a
// scale): a one-finger "scale" is the drag. A finger added or lifted mid-gesture ends it and
// the rest of that touch does nothing, so a pinch never turns into a seek.
//
// None of that can be seen, so the first film on a phone opens with a picture of it
// (`GestureGuide`, remembered by the `gestureHintSeen` setting) and More › Touch gestures
// shows it again. Keep the guide's words in step with the table above.
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:screen_brightness/screen_brightness.dart';

import '../../engine/bias_light.dart';
import '../../engine/models/settings.dart';
import '../../engine/playback.dart';
import '../../engine/sync_rule.dart';
import '../../platform/pip.dart';
import '../../platform/window.dart';
import '../../player/engine.dart';
import '../../state/library.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../booth/booth_sheet.dart';
import '../components/room.dart';
import '../threading/threading_overlay.dart';
import 'controls/controls_bar.dart';
import 'controls/system_subtitles.dart';
import 'controls/widgets.dart';
import 'cue_sheet.dart';
import 'layers.dart';
import 'menu_panel.dart';

/// What the touch in progress has turned out to be (see the table at the top of the file).
enum _Gesture { none, undecided, brightness, volume, seek, pinch, dead }

/// After a double tap, further taps keep adding steps while they come this fast.
const _kTapStreak = Duration(milliseconds: 600);

/// The "Unlock" pill stays this long after a tap on a locked screen.
const _kUnlockShown = Duration(seconds: 3);

class AuditoriumScreen extends ConsumerStatefulWidget {
  const AuditoriumScreen({super.key});

  @override
  ConsumerState<AuditoriumScreen> createState() => _AuditoriumScreenState();
}

class _AuditoriumScreenState extends ConsumerState<AuditoriumScreen> {
  bool _controls = true;
  bool _syncOpen = false;
  bool _details = false;

  /// The picture of the touch gestures, asked for from the More menu. (The first film shows
  /// it unasked: see [_firstHintDue].)
  bool _hints = false;
  AuditoriumMenu? _menu;
  final _menuTrail = <AuditoriumMenu>[];
  Timer? _idle;
  Timer? _bias;
  Timer? _readoutTimer;
  List<Color>? _stops;
  bool _biasBusy = false;
  final _focus = FocusNode(debugLabel: 'auditorium');
  double _rateBeforeHold = 1;
  bool _holding = false;
  double? _brightness;
  bool _brightnessTouched = false;
  double _dragVolume = 100;

  // Readouts follow the finger, so they are their own small rebuilds, never the screen's.
  final _readout = ValueNotifier<({String icon, String text, double? level})?>(null);
  final _swipe = ValueNotifier<({double target, double delta})?>(null);

  // One touch, from the first finger down to the last one up.
  int _touches = 0;
  Offset? _downAt;
  bool _touchCancelled = false;
  _Gesture _gesture = _Gesture.none;
  double _seekFrom = 0;
  double _seekOriginX = 0;
  double _pinchBase = 1;

  // A run of taps in one place: the first waits on [_tapTimer] for a second.
  ({int zone, int count, Offset at})? _taps;
  Timer? _tapTimer;

  // Android: the screen locked against touches, and the way this film is held.
  bool _locked = false;
  bool _unlockShown = false;
  Timer? _unlockTimer;
  FilmOrientation _orient = FilmOrientation.auto;
  FilmOrientation? _orientSent;
  bool _playing = false;
  bool _completed = false;
  String? _pipKey;

  bool get _desktop => PlayerEngine.isDesktop;

  @override
  void initState() {
    super.initState();
    // Take the keyboard from whatever the Lobby had focused (autofocus alone loses to it).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refocus();
      _applyOrientation(); // back from the Ticket Office: the film's size is already known
    });
    // A film that already ended (or is playing) before this screen was rebuilt, e.g. on the
    // way back from Settings: the stream only reports CHANGES, so start from what is true.
    final now = ref.read(sessionProvider)?.engine;
    if (now != null && !now.isDisposed) {
      _playing = now.player.state.playing;
      _completed = now.player.state.completed;
    }
    _poke();
    _startBias();
    if (Platform.isAndroid) {
      unawaited(() async {
        try {
          final v = await ScreenBrightness.instance.application;
          if (mounted && !_brightnessTouched) _brightness = v;
        } on Object {
          // No reading: the first swipe starts from the middle.
        }
      }());
    }
  }

  @override
  void dispose() {
    if (_brightnessTouched) {
      unawaited(ScreenBrightness.instance.resetApplicationScreenBrightness());
    }
    // The rooms outside turn as the phone does again. All four ways is Android's "full user",
    // which is what the manifest asks for (an empty list would be "unspecified" instead).
    if (_orientSent != null) {
      unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    }
    _idle?.cancel();
    _bias?.cancel();
    _readoutTimer?.cancel();
    _tapTimer?.cancel();
    _unlockTimer?.cancel();
    _readout.dispose();
    _swipe.dispose();
    _focus.dispose();
    super.dispose();
  }

  FilmSession? get _session => ref.read(sessionProvider);
  SessionNotifier get _notifier => ref.read(sessionProvider.notifier);

  void _refocus() {
    if (!mounted) return;
    final f = FocusManager.instance.primaryFocus;
    final inField = f?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (!inField) _focus.requestFocus();
  }

  /// Shows the controls and re-arms the auto-hide (only while playing, with nothing open).
  void _poke() {
    _idle?.cancel();
    if (FocusManager.instance.primaryFocus == null ||
        FocusManager.instance.primaryFocus is FocusScopeNode) {
      _focus.requestFocus();
    }
    if (!_controls && mounted) setState(() => _controls = true);
    _idle = Timer(Tokens.controlsIdle, () {
      if (!mounted || !_playing) return;
      if (ref.read(boothOpenProvider) || _syncOpen || _menu != null) return;
      setState(() => _controls = false);
    });
  }

  void _hideControls() {
    _idle?.cancel();
    if (_playing && _menu == null) setState(() => _controls = false);
  }

  void _showReadout(String icon, String text, [double? level]) {
    if (!mounted) return; // a skip or a seek that finished after the room was left
    _readoutTimer?.cancel();
    _readout.value = (icon: icon, text: text, level: level);
    _readoutTimer = Timer(const Duration(milliseconds: 900), () => _readout.value = null);
  }

  // ───────────────────────── which way up, and the lock (Android) ─────────────────────────

  /// Asks Android to hold the screen the way this film wants. With the phone's rotation lock
  /// on, nothing else would turn it: a film opened in portrait stayed there. Each pair below
  /// is Android's "user" kind: that way up, either way round by the sensor where the phone
  /// allows it. A picture whose size is not known yet changes nothing.
  /// Never while the film is in picture in picture: the little window has no way up, and
  /// asking for one there fights the system. It is asked again when the window grows back.
  void _applyOrientation({int? width, int? height}) {
    if (!Platform.isAndroid || !mounted || ref.read(pipProvider)) return;
    final s = _session;
    if (s == null) return;
    final pb = width == null || height == null ? s.engine.snapshot : null;
    final want = orientationFor(
      _orient,
      width: width ?? pb?.width ?? 0,
      height: height ?? pb?.height ?? 0,
    );
    if (want == null || want == _orientSent) return;
    _orientSent = want;
    unawaited(
      SystemChrome.setPreferredOrientations(switch (want) {
        FilmOrientation.landscape => const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        FilmOrientation.portrait => const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],
        FilmOrientation.auto => DeviceOrientation.values, // a square picture: as the phone turns
      }),
    );
  }

  /// The rotate button: follow the video, landscape, portrait, for this film.
  void _cycleOrientation() {
    setState(() => _orient = _orient.next);
    _applyOrientation();
    _showReadout('rotate-ccw-square', _orient.label);
    _poke();
  }

  /// Everything goes inert and out of sight; the pill shows once, to say where the way out is.
  void _lock() {
    _idle?.cancel();
    _tapTimer?.cancel();
    _taps = null;
    // The recognisers go with the lock: a swipe another finger still holds will never end.
    _gesture = _Gesture.dead;
    _swipe.value = null;
    setState(() {
      _locked = true;
      _menu = null;
      _menuTrail.clear();
      _syncOpen = false;
    });
    _showUnlock();
  }

  void _unlock() {
    _unlockTimer?.cancel();
    setState(() {
      _locked = false;
      _unlockShown = false;
    });
    _poke();
    _showReadout('lock-open', 'Unlocked');
  }

  /// A tap (or Back) on a locked screen: the way out, for a moment.
  void _showUnlock() {
    _unlockTimer?.cancel();
    if (!_unlockShown) setState(() => _unlockShown = true);
    _unlockTimer = Timer(_kUnlockShown, () {
      if (mounted) setState(() => _unlockShown = false);
    });
  }

  /// A new film (or none): the lock, the chosen rotation and any touch in progress were the
  /// last film's.
  void _resetForFilm() {
    _tapTimer?.cancel();
    _unlockTimer?.cancel();
    _taps = null;
    _touches = 0;
    _gesture = _Gesture.none;
    _holding = false;
    _swipe.value = null;
    _pipKey = null; // the next tick sends this film's shape (and its way up) afresh
    if (_locked || _unlockShown || _orient != FilmOrientation.auto) {
      setState(() {
        _locked = false;
        _unlockShown = false;
        _orient = FilmOrientation.auto;
      });
    }
  }

  // ───────────────────────────── bias light ─────────────────────────────

  /// Off by default. When on, ONE small frame every three seconds, taken without the player's
  /// lock — a locked JPEG every 500 ms is what made the controls lag.
  void _startBias() {
    _bias?.cancel();
    _bias = null;
    if (!ref.read(settingsValueProvider).biasLight) {
      if (_stops != null) setState(() => _stops = null);
      return;
    }
    _bias = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_biasBusy || !mounted) return;
      final s = _session;
      if (s == null || !_playing) return; // paused ⇒ the glow freezes
      // Playing unseen (the screen is off, or another app is in front): there is no picture
      // to sample and nobody to glow for.
      final life = WidgetsBinding.instance.lifecycleState;
      if (life == AppLifecycleState.paused || life == AppLifecycleState.hidden) return;
      _biasBusy = true;
      try {
        final bytes = await s.engine.biasFrame();
        if (bytes == null || !mounted) return;
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64, targetHeight: 36);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        frame.image.dispose();
        if (data == null) return;
        final rgba = data.buffer.asUint8List(0, 64 * 29 * 4); // top 80 %: subtitles live below
        final stops = await extractStops(rgba, 64, 29);
        if (!mounted) return;
        setState(() => _stops = stops?.argb.map(Color.new).toList());
      } on Object {
        // A bad frame (or a film closed mid-screenshot) is not worth a word.
      } finally {
        _biasBusy = false;
      }
    });
  }

  // ───────────────────────────── actions ─────────────────────────────

  Future<void> _playPause() async {
    final s = _session;
    if (s == null || s.threadingVisible) return;
    await s.engine.playOrPause();
  }

  Future<void> _seekBy(Duration d) async {
    final s = _session;
    if (s == null || s.threadingVisible) return;
    await s.engine.seekBy(d);
  }

  Future<void> _seekTo(Duration d) async {
    final s = _session;
    if (s == null || s.threadingVisible) return;
    await s.engine.seekTo(d);
  }

  void _volumeBy(double delta) {
    final s = _session;
    if (s == null) return;
    final v = (s.engine.player.state.volume + delta).clamp(0.0, 150.0);
    unawaited(_notifier.setVolume(v));
    _showReadout(VolumeControl.iconFor(v, muted: false), 'Volume ${v.round()} %', v / 150);
  }

  void _toggleFullscreen() => ref.read(fullscreenProvider.notifier).toggle();

  void _openMenu(AuditoriumMenu m, {bool sub = false}) {
    setState(() {
      if (sub && _menu != null) {
        _menuTrail.add(_menu!);
      } else {
        _menuTrail.clear();
      }
      _menu = _menu == m && !sub ? null : m;
      _controls = true;
    });
    _idle?.cancel();
    if (_menu == null) _poke();
  }

  void _closeMenu() {
    setState(() {
      _menu = null;
      _menuTrail.clear();
    });
    _poke();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
  }

  /// Through the session: it keeps Android from taking the picker for a trip Home (which
  /// would shrink the film into picture in picture behind it).
  Future<void> _pickSubtitle() async {
    _closeMenu();
    await _notifier.pickAndLoadSubtitle();
  }

  void _openBooth() {
    _closeMenu();
    ref.read(boothOpenProvider.notifier).set(true);
  }

  void _toggleDetails() => setState(() => _details = !_details);

  /// The first film on a phone shows the touch gestures once, as soon as the picture is up
  /// (never over the leader or the "can't play" card). The film is NOT paused for it: it goes
  /// with one tap, and nothing that watches the film from outside sees it stop.
  bool _firstHintDue(FilmSession s, Settings settings) =>
      !_desktop &&
      !_locked &&
      s.started &&
      !s.threadingVisible &&
      s.error == null &&
      !settings.gestureHintSeen;

  bool get _hintsUp {
    final s = _session;
    return s != null && (_hints || _firstHintDue(s, ref.read(settingsValueProvider)));
  }

  /// "Got it", a tap anywhere on the guide, or Back. The controls come up as they would for
  /// any first tap, so the next thing seen is where everything is.
  void _closeHints() {
    if (_hints) setState(() => _hints = false);
    if (!ref.read(settingsValueProvider).gestureHintSeen) {
      unawaited(ref.read(settingsProvider.notifier).edit((s) => s.copyWith(gestureHintSeen: true)));
    }
    _poke();
  }

  /// Windows: the film stays above the other windows.
  void _togglePinned() {
    ref.read(pinnedProvider.notifier).toggle();
    _showReadout('pin', ref.read(pinnedProvider) ? 'Kept on top' : 'No longer on top');
  }

  int get _seekStep => ref.read(settingsValueProvider).seekStepSeconds;

  Future<void> _enterPip() async {
    final pb = _session?.engine.snapshot;
    await ref
        .read(pipProvider.notifier)
        .enter(w: pb?.width ?? 16, h: pb?.height ?? 9, playing: pb?.playing ?? true);
  }

  /// Esc / Back, one lighting state at a time: fullscreen, then a menu or overlay, then the
  /// threading overlay ("Play without subtitles"), then the film itself.
  Future<void> _back() async {
    if (_locked) {
      _showUnlock(); // Back is swallowed: it only shows the way out
      return;
    }
    if (_desktop && ref.read(fullscreenProvider)) {
      ref.read(fullscreenProvider.notifier).set(false);
      return;
    }
    if (_hintsUp) {
      _closeHints();
      return;
    }
    if (_menu != null) {
      _closeMenu();
      return;
    }
    if (ref.read(cueSheetProvider)) {
      ref.read(cueSheetProvider.notifier).set(false);
      return;
    }
    if (ref.read(boothOpenProvider)) {
      ref.read(boothOpenProvider.notifier).set(false);
      return;
    }
    if (_syncOpen) {
      setState(() => _syncOpen = false);
      return;
    }
    if (_details) {
      setState(() => _details = false);
      return;
    }
    final s = _session;
    if (s != null && s.threadingVisible) {
      _notifier.skipSubtitles();
      return;
    }
    await _notifier.close();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (_locked) {
      // Nothing acts on the film. The keys are not swallowed either: the phone's own volume
      // buttons arrive here too, and they must keep working.
      if (k != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
      _showUnlock();
      return KeyEventResult.handled;
    }
    final focused = FocusManager.instance.primaryFocus;
    final inField = focused?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (k == LogicalKeyboardKey.escape) {
      // Esc in a search field leaves the field (and the Booth) instead of being swallowed.
      if (inField) {
        focused?.unfocus();
        ref.read(boothOpenProvider.notifier).set(false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
      } else {
        unawaited(_back());
      }
      return KeyEventResult.handled;
    }
    // Keys typed into the booth/threading search fields are text, not transport controls.
    if (inField) return KeyEventResult.ignored;
    final s = _session;
    if (s == null) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (k == LogicalKeyboardKey.slash && shift || e.character == '?') {
      ref.read(cueSheetProvider.notifier).toggle();
      return KeyEventResult.handled;
    }
    // While the leader counts, the film is hidden and paused: no key may act on it.
    if (s.threadingVisible) return KeyEventResult.ignored;
    final engine = s.engine;
    final player = engine.player;
    final repeat = e is KeyRepeatEvent;
    _poke();
    void delay(bool later) {
      final cur = _session?.delayMs ?? 0;
      unawaited(_notifier.setDelay(stepMs(cur, later: later, shift: shift)));
      setState(() => _syncOpen = true);
    }

    final digit = _digitOf(k);
    if (digit != null) {
      if (repeat) return KeyEventResult.handled;
      unawaited(_seekTo(percentSeek(digit, player.state.duration)));
      _showReadout('rotate-cw', '${digit * 10} %');
    } else if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      if (repeat) return KeyEventResult.handled;
      if (k == LogicalKeyboardKey.mediaPlay) {
        unawaited(engine.play());
      } else if (k == LogicalKeyboardKey.mediaPause) {
        unawaited(engine.pause());
      } else {
        unawaited(_playPause());
      }
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekBy(Duration(seconds: shift ? -30 : -5)));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekBy(Duration(seconds: shift ? 30 : 5)));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _volumeBy(5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _volumeBy(-5);
    } else if (k == LogicalKeyboardKey.keyM) {
      if (repeat) return KeyEventResult.handled;
      unawaited(engine.toggleMute());
      _showReadout(engine.muted ? 'volume-2' : 'volume-x', engine.muted ? 'Sound on' : 'Muted');
    } else if (k == LogicalKeyboardKey.keyN || k == LogicalKeyboardKey.mediaTrackNext) {
      if (!repeat) unawaited(_notifier.playNeighbour(next: true));
    } else if (k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.mediaTrackPrevious) {
      if (!repeat) unawaited(_notifier.playNeighbour(next: false));
    } else if (k == LogicalKeyboardKey.keyJ) {
      delay(false);
    } else if (k == LogicalKeyboardKey.keyK) {
      delay(true);
    } else if (k == LogicalKeyboardKey.comma) {
      unawaited(engine.frameStep(forward: false));
    } else if (k == LogicalKeyboardKey.period) {
      unawaited(engine.frameStep(forward: true));
    } else if (k == LogicalKeyboardKey.keyL) {
      if (!repeat) unawaited(_notifier.toggleLoop());
    } else if (k == LogicalKeyboardKey.bracketLeft || k == LogicalKeyboardKey.bracketRight) {
      final next = stepSpeed(player.state.rate, faster: k == LogicalKeyboardKey.bracketRight);
      unawaited(engine.setRate(next));
      _showReadout('gauge', speedLabel(next));
    } else if (k == LogicalKeyboardKey.keyF) {
      if (!repeat) _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyS) {
      if (!repeat) ref.read(boothOpenProvider.notifier).toggle();
    } else if (k == LogicalKeyboardKey.keyA) {
      if (repeat) return KeyEventResult.handled;
      final pb = engine.snapshot;
      final tracks = pb.audioTracks;
      if (tracks.isNotEmpty) {
        final i = tracks.indexWhere((t) => t.id == pb.audioId);
        final t = tracks[(i + 1) % tracks.length];
        unawaited(_notifier.selectAudio(t.id));
        _showReadout('audio-lines', trackName(t.language, t.title, fallback: 'Track ${t.id}'));
      }
    } else if (k == LogicalKeyboardKey.keyI) {
      if (!repeat) _toggleDetails();
    } else if (k == LogicalKeyboardKey.keyT) {
      // The cue sheet is the Windows keyboard map; elsewhere T is not a key the app knows.
      if (!Platform.isWindows) return KeyEventResult.ignored;
      if (!repeat) _togglePinned();
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      // Only while "Skip intro" is offered; otherwise Enter is not ours to swallow.
      final skip = _notifier.skippable;
      if (skip == null) return KeyEventResult.ignored;
      if (!repeat) {
        unawaited(_notifier.skipChapter());
        _showReadout('skip-forward', skip.label);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static int? _digitOf(LogicalKeyboardKey k) {
    const digits = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    final i = digits.indexOf(k);
    if (i >= 0) return i;
    final j = numpad.indexOf(k);
    return j >= 0 ? j : null;
  }

  // ───────────────────────────── gestures ─────────────────────────────

  /// A tap that lands. The first of a run waits for the double-tap window before it counts
  /// as a single tap: so a double click goes fullscreen without also pausing and resuming
  /// the film, and a double tap seeks without flashing the controls.
  void _onTapUp(TapUpDetails d) {
    if (_menu != null) {
      _closeMenu();
      return;
    }
    final at = d.localPosition;
    final run = _taps;
    if (run != null && (at - run.at).distance <= kDoubleTapSlop) {
      _tapTimer?.cancel();
      final count = run.count + 1;
      _taps = (zone: run.zone, count: count, at: at);
      _tapTimer = Timer(_kTapStreak, () => _taps = null);
      _onTapAgain(run.zone, count);
      return;
    }
    _tapTimer?.cancel();
    // A tap somewhere else while the first still waited: that first one was a single tap.
    if (run != null && run.count == 1) _onSingleTap();
    _taps = (
      zone: _desktop ? 0 : tapZone(at.dx, MediaQuery.sizeOf(context).width),
      count: 1,
      at: at,
    );
    _tapTimer = Timer(kDoubleTapTimeout, () {
      _taps = null;
      if (mounted) _onSingleTap();
    });
  }

  void _onSingleTap() {
    if (_menu != null) {
      _closeMenu();
    } else if (_desktop) {
      // Desktop: a click plays / pauses (a double click goes fullscreen).
      unawaited(_playPause());
      _poke();
    } else {
      _controls ? _hideControls() : _poke();
    }
  }

  /// The second tap of a run, or one more ([count] taps so far, all in [zone]).
  void _onTapAgain(int zone, int count) {
    if (_desktop) {
      if (count.isEven) _toggleFullscreen();
      return;
    }
    if (zone == 0) {
      if (count.isEven) unawaited(_playPause());
      return;
    }
    // One step per tap after the first; mpv adds queued relative seeks up, and the readout
    // shows the running total.
    final step = _seekStep;
    unawaited(_seekBy(Duration(seconds: zone * step)));
    final total = (count - 1) * step;
    _showReadout(
      zone < 0 ? 'rotate-ccw' : 'rotate-cw',
      zone < 0 ? '$total s back' : '$total s forward',
    );
  }

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _menu != null) return;
    final s = _session;
    if (s == null || s.threadingVisible) return;
    _volumeBy(e.scrollDelta.dy < 0 ? 5 : -5);
    _poke();
  }

  // Fingers are counted by a Listener around the detector: it hears every pointer BEFORE the
  // recognisers do (they are fed last, by the gesture binding), so the handlers below can
  // trust the count, the place the first finger landed and whether the system took the touch.

  void _onPointerDown(PointerDownEvent e) {
    _touches++;
    if (_touches != 1) return;
    _downAt = e.localPosition;
    _gesture = _Gesture.none;
    _touchCancelled = false;
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_touches > 0) _touches--;
  }

  /// Android took the touch for itself (a back swipe, the notification shade).
  void _onPointerCancel(PointerCancelEvent e) {
    _touchCancelled = true;
    if (_touches > 0) _touches--;
    _releaseHold();
  }

  /// A hold that was cancelled (the system took the touch, or the film went into the little
  /// window with the finger still down) gets no "end" from Flutter: without this the film
  /// would stay at 2x and every later swipe would be refused as "still holding".
  void _releaseHold() {
    if (!_holding) return;
    _holding = false;
    unawaited(_session?.engine.setRate(_rateBeforeHold));
  }

  void _onHoldStart(LongPressStartDetails d) {
    final s = _session;
    // Two fingers resting on the glass are the start of a pinch, not a hold.
    if (s == null || s.threadingVisible || _touches > 1) return;
    _holding = true;
    _rateBeforeHold = s.engine.player.state.rate;
    unawaited(s.engine.setRate(2));
    _showReadout('gauge', '2× while held');
  }

  void _onHoldEnd(LongPressEndDetails d) => _releaseHold();

  /// A drag (one finger) or a pinch (two) has begun. Flutter ends the gesture and starts a
  /// new one whenever a finger is added or lifted; only the first of a touch may act, except
  /// that a drag which had not yet shown its direction may still become a pinch.
  void _onScaleStart(ScaleStartDetails d) {
    final s = _session;
    final free = _gesture == _Gesture.none && !_holding && _menu == null && !_touchCancelled;
    if (!free || s == null || s.threadingVisible || s.error != null) {
      _gesture = _Gesture.dead;
      return;
    }
    if (d.pointerCount > 1) {
      _gesture = _Gesture.pinch;
      _pinchBase = 1;
      return;
    }
    // The status bar's pull-down and the home swipe own the top and bottom edges.
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final pad = MediaQuery.paddingOf(context);
    final y = (_downAt ?? d.localFocalPoint).dy;
    if (y < pad.top + 24 || y > size.height - pad.bottom - insets.bottom - 24) {
      _gesture = _Gesture.dead;
      return;
    }
    _gesture = _Gesture.undecided;
    _decide(s, d.localFocalPoint);
  }

  /// Reads the drag's direction once the finger has travelled far enough from where it
  /// landed. Up / down on the left 40 % is brightness, on the right 40 % volume; sideways is
  /// a scrub, unless it began at a screen edge (Android's back swipe lives there).
  void _decide(FilmSession s, Offset now) {
    final from = _downAt ?? now;
    final axis = swipeAxis(now.dx - from.dx, now.dy - from.dy);
    if (axis == null) return;
    final width = MediaQuery.sizeOf(context).width;
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final x = from.dx;
    switch (axis) {
      case SwipeAxis.neither:
        _gesture = _Gesture.dead;
      case SwipeAxis.vertical:
        if (x > insets.left + 8 && x < width * 0.4) {
          _gesture = Platform.isAndroid ? _Gesture.brightness : _Gesture.dead;
        } else if (x > width * 0.6 && x < width - insets.right - 8) {
          _gesture = _Gesture.volume;
          _dragVolume = s.engine.player.state.volume;
        } else {
          _gesture = _Gesture.dead;
        }
      case SwipeAxis.horizontal:
        final edge =
            x < math.max(insets.left, 16.0) + 8 || x > width - math.max(insets.right, 16.0) - 8;
        if (edge || !ref.read(settingsValueProvider).swipeToSeek) {
          _gesture = _Gesture.dead;
        } else {
          _gesture = _Gesture.seek;
          _seekFrom = s.engine.player.state.position.inMilliseconds / 1000;
          // Measured from here, not from where the finger landed: the readout opens at +0:00.
          _seekOriginX = now.dx;
        }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final s = _session;
    if (s == null) return;
    if (_gesture == _Gesture.undecided) _decide(s, d.localFocalPoint);
    switch (_gesture) {
      case _Gesture.brightness:
        final next = ((_brightness ?? 0.5) + _levelDelta(d)).clamp(0.02, 1.0);
        _brightness = next;
        _brightnessTouched = true;
        unawaited(ScreenBrightness.instance.setApplicationScreenBrightness(next));
        _showReadout('sun', 'Brightness ${(next * 100).round()} %', next);
      case _Gesture.volume:
        _dragVolume = (_dragVolume + _levelDelta(d) * 100).clamp(0.0, 150.0);
        unawaited(_notifier.setVolume(_dragVolume));
        _showReadout(
          VolumeControl.iconFor(_dragVolume, muted: false),
          'Volume ${_dragVolume.round()} %',
          _dragVolume / 150,
        );
      case _Gesture.seek:
        // Only the readout moves: the film is sought once, when the finger lifts.
        final target = swipeSeekTarget(
          startSeconds: _seekFrom,
          dragPx: d.localFocalPoint.dx - _seekOriginX,
          widthPx: MediaQuery.sizeOf(context).width,
          durationSeconds: s.engine.player.state.duration.inMilliseconds / 1000,
        );
        _swipe.value = (target: target, delta: target - _seekFrom);
      case _Gesture.pinch:
        if (d.pointerCount < 2) return;
        // Measured from the last switch, so the same pinch can go out and come back in.
        final fit = pinchFit(s.fit, d.scale / _pinchBase);
        if (fit == null) return;
        _pinchBase = d.scale;
        _notifier.setFit(fit);
        _showReadout('scan', fit.label);
      case _Gesture.none || _Gesture.undecided || _Gesture.dead:
        break;
    }
  }

  /// A full swipe up or down the middle 60 % of the screen is the whole range.
  double _levelDelta(ScaleUpdateDetails d) =>
      -d.focalPointDelta.dy / (MediaQuery.sizeOf(context).height * 0.6);

  void _onScaleEnd(ScaleEndDetails d) {
    final was = _gesture;
    // A second finger landing on a drag that had not shown its direction starts a pinch;
    // anything else spends the touch.
    _gesture = was == _Gesture.undecided && d.pointerCount > 1 ? _Gesture.none : _Gesture.dead;
    if (was != _Gesture.seek) return;
    final swipe = _swipe.value;
    _swipe.value = null;
    // Lifted is a seek. Taken by the system, or joined by a second finger, is a change of mind.
    if (swipe == null || _touchCancelled || d.pointerCount > 0 || swipe.delta.abs() < 1) return;
    final known = (_session?.engine.player.state.duration ?? Duration.zero) > Duration.zero;
    if (known) {
      unawaited(_seekTo(Duration(milliseconds: (swipe.target * 1000).round())));
    } else {
      unawaited(_seekBy(Duration(milliseconds: (swipe.delta * 1000).round())));
    }
    _showReadout(swipe.delta < 0 ? 'rotate-ccw' : 'rotate-cw', signedClock(swipe.delta));
  }

  /// "Up next" says the next film's title the way the Library does ("Severance S02E04"),
  /// not its raw file name. A phone's library film is a content:// URI: its name is the
  /// device library's to give.
  String _upNextName(String locator) {
    if (!locator.startsWith('content://')) return libraryTitle(p.basename(locator));
    final items = ref.read(deviceLibraryProvider).value?.items ?? const <LibraryItem>[];
    for (final item in items) {
      if (item.locator == locator) return libraryTitle(item.name);
    }
    return 'The next video';
  }

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final booth = ref.watch(boothOpenProvider);
    final cue = ref.watch(cueSheetProvider);
    final settings = ref.watch(settingsValueProvider);
    final fullscreen = ref.watch(fullscreenProvider);
    ref.listen(playbackProvider, (_, next) {
      final pb = next.value;
      if (pb == null) return;
      if (pb.playing != _playing || pb.completed != _completed) {
        setState(() {
          _playing = pb.playing;
          _completed = pb.completed;
        });
        if (!pb.playing) {
          _idle?.cancel();
          if (!_controls) setState(() => _controls = true);
        } else {
          _poke();
        }
      }
      if (Platform.isAndroid && pb.width > 0 && pb.height > 0) {
        final key = '${pb.width}x${pb.height}:${pb.playing}';
        if (key != _pipKey) {
          _pipKey = key;
          unawaited(
            ref
                .read(pipProvider.notifier)
                .setAutoEnter(enabled: true, w: pb.width, h: pb.height, playing: pb.playing),
          );
          _applyOrientation(width: pb.width, height: pb.height);
        }
      }
    });
    ref.listen(sessionProvider.select((s) => s?.engine), (_, _) => _resetForFilm());
    // Back from picture in picture: the way up asked for while it was small was not sent.
    ref.listen(pipProvider, (_, inPip) {
      // The gesture surface is not built in the little window: no touch survives the trip.
      _touches = 0;
      _gesture = _Gesture.none;
      _swipe.value = null;
      _releaseHold();
      if (!inPip) _applyOrientation();
    });
    // Overlays that took the keyboard give it back when they go.
    ref.listen(boothOpenProvider, (_, open) {
      if (!open) WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
    });
    ref.listen(cueSheetProvider, (_, open) {
      if (!open) WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
    });
    ref.listen(sessionProvider.select((s) => s?.threadingVisible ?? false), (_, visible) {
      if (!visible) WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
    });
    ref.listen(settingsProvider.select((s) => s.value?.biasLight ?? false), (_, _) {
      _startBias();
    });

    if (session == null) return const SizedBox.shrink();
    final engine = session.engine;
    if (ref.watch(pipProvider)) {
      return PictureLayer(engine: engine, fit: session.fit, transparent: false);
    }
    // One rule decides the end of a film (repeat, "play the next one", the sleep timer), and
    // the session runs the countdown to the next one (it must also run in picture in picture
    // and with the screen off, where this screen is not built). The card shows that countdown
    // while there is one; it starts nothing itself.
    final upNext = session.upNextFor(settings);
    final upNextAt = session.upNextAt;
    final showUpNext = upNextAt != null && upNext != null && !session.threadingVisible;
    final pad = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final shown = _controls && !_locked;
    final hints = _hints || _firstHintDue(session, settings);
    final touch = !_desktop && !_locked;
    // Video details sit under the title. Where the play button is in the middle of the
    // picture (phones, narrow windows) they must end above it: a room too short for the
    // column gets the two-column panel, and whatever still does not fit is scaled down.
    final detailsTop = pad.top + 56;
    final detailsRoom = !_desktop || size.width < 720
        ? math.max(size.height / 2 - 34 - Tokens.space2 - detailsTop, 48.0)
        : null;
    final detailsWide =
        detailsRoom != null && detailsRoom < VideoDetailsPanel.tallHeight && size.width >= 560;
    final hideCursor = _desktop && !_controls && _playing && _menu == null;
    final actions = ControlsActions(
      onBack: () => unawaited(_back()),
      onPlayPause: () => unawaited(_playPause()),
      onMute: () => unawaited(engine.toggleMute()),
      onFullscreen: _toggleFullscreen,
      onToggleSync: () => setState(() => _syncOpen = !_syncOpen),
      onSeekBy: (d) => unawaited(_seekBy(d)),
      onSeek: (v) => unawaited(_seekTo(Duration(milliseconds: (v * 1000).round()))),
      onScrub: (_) => _idle?.cancel(),
      onScrubEnd: _poke,
      onVolume: (v) => unawaited(_notifier.setVolume(v)),
      onMenu: _openMenu,
      // Phones too: the buttons only draw when the folder or the device library has a neighbour.
      onPrevious: () => unawaited(_notifier.playNeighbour(next: false)),
      onNext: () => unawaited(_notifier.playNeighbour(next: true)),
      onPip: Platform.isAndroid ? () => unawaited(_enterPip()) : null,
      onCueSheet: () => ref.read(cueSheetProvider.notifier).toggle(),
      onToggleClock: () => unawaited(
        ref
            .read(settingsProvider.notifier)
            .edit((s) => s.copyWith(showRemaining: !s.showRemaining)),
      ),
      onLock: Platform.isAndroid ? _lock : null,
      onRotate: Platform.isAndroid ? _cycleOrientation : null,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: ColoredBox(
          color: Tokens.pictureBg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (settings.biasLight) Walls(stops: _stops),
              PictureLayer(
                engine: engine,
                fit: session.fit,
                transparent: settings.biasLight && _stops != null,
              ),
              if (Platform.isAndroid)
                SystemFontSubtitles(
                  engine: engine,
                  settings: settings,
                  lifted: shown && !session.threadingVisible,
                ),
              // The gesture surface: below the controls, beside (never around) the overlays.
              // Locked, it hears one thing: a tap, which shows the way out.
              Listener(
                onPointerSignal: _onWheel,
                onPointerDown: _desktop ? null : _onPointerDown,
                onPointerUp: _desktop ? null : _onPointerUp,
                onPointerCancel: _desktop ? null : _onPointerCancel,
                child: MouseRegion(
                  cursor: hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
                  onHover: (_) => _poke(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _locked ? (_) => _showUnlock() : _onTapUp,
                    onSecondaryTap: _desktop ? () => _openMenu(AuditoriumMenu.more) : null,
                    onLongPressStart: touch ? _onHoldStart : null,
                    onLongPressEnd: touch ? _onHoldEnd : null,
                    onScaleStart: touch ? _onScaleStart : null,
                    onScaleUpdate: touch ? _onScaleUpdate : null,
                    onScaleEnd: touch ? _onScaleEnd : null,
                  ),
                ),
              ),
              RepaintBoundary(
                child: IgnorePointer(
                  ignoring: !shown,
                  child: AnimatedOpacity(
                    opacity: shown ? 1 : 0,
                    duration: shown ? Tokens.durFast : Tokens.durSlow,
                    curve: shown ? Tokens.easeOut : Tokens.easeInOut,
                    child: MouseRegion(
                      onHover: (_) => _idle?.cancel(),
                      onExit: (_) => _poke(),
                      // A control takes its own touches; the empty picture between the bars
                      // still reaches the gesture surface below. (`opaque: false` let EVERY
                      // touch through as well: a thumb resting on the seek bar became a
                      // long-press 2x, and a swipe from the bar changed the volume.)
                      hitTestBehavior: HitTestBehavior.deferToChild,
                      child: ControlsLayer(
                        session: session,
                        visible: shown,
                        desktop: _desktop,
                        fullscreen: fullscreen,
                        menu: _menu,
                        syncOpen: _syncOpen,
                        orientation: _orient,
                        actions: actions,
                      ),
                    ),
                  ),
                ),
              ),
              // Under the title, clear of the bottom bar and of the play button in the middle;
              // it stays while the controls hide.
              if (_details && !session.threadingVisible)
                Positioned(
                  left: Tokens.space4,
                  right: Tokens.space4,
                  top: detailsTop,
                  height: detailsRoom,
                  child: IgnorePointer(
                    ignoring: _locked,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: LiveVideoDetails(
                          key: ValueKey(engine),
                          engine: engine,
                          onClose: _toggleDetails,
                          wide: detailsWide,
                          // Unconstrained inside the FittedBox: the room's width is told.
                          maxWidth: detailsWide
                              ? size.width - Tokens.space4 * 2
                              : math.min(400.0, size.width - Tokens.space4 * 2),
                        ),
                      ),
                    ),
                  ),
                ),
              // "Skip intro": there even when the controls are not. A menu or the "Up next"
              // card takes the same corner, so it steps aside for them.
              if (_menu == null && !showUpNext && !booth && !_locked)
                Positioned(
                  right: Tokens.space4,
                  bottom: pad.bottom + (_desktop ? 104 : 132),
                  child: SkipChapterButton(
                    desktop: _desktop,
                    onSkipped: (label) => _showReadout('skip-forward', label),
                  ),
                ),
              if (_menu != null) ...[
                Positioned.fill(
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _closeMenu),
                ),
                MenuSlot(
                  desktop: _desktop,
                  builder: (maxHeight, sheet) => MenuPanel(
                    menu: _menu!,
                    canGoBack: _menuTrail.isNotEmpty,
                    maxHeight: maxHeight,
                    fill: sheet,
                    onBack: () => setState(() => _menu = _menuTrail.removeLast()),
                    onClose: _closeMenu,
                    onOpen: (m) => _openMenu(m, sub: true),
                    onPickSubtitle: () => unawaited(_pickSubtitle()),
                    onBooth: _openBooth,
                    onCueSheet: () {
                      _closeMenu();
                      ref.read(cueSheetProvider.notifier).set(true);
                    },
                    onDetails: () {
                      _closeMenu();
                      _toggleDetails();
                    },
                    onSync: () {
                      _closeMenu();
                      setState(() => _syncOpen = true);
                    },
                    onGestures: _desktop
                        ? null
                        : () {
                            _closeMenu();
                            setState(() => _hints = true);
                          },
                    onRotate: Platform.isAndroid ? _cycleOrientation : null,
                    orientation: _orient,
                    desktop: _desktop,
                  ),
                ),
              ],
              // The readouts rebuild alone: a swipe moves them sixty times a second.
              IgnorePointer(
                child: ValueListenableBuilder(
                  valueListenable: _readout,
                  builder: (context, readout, _) => readout == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: const Alignment(0, -0.45),
                          child: LevelReadout(
                            icon: readout.icon,
                            text: readout.text,
                            level: readout.level,
                          ),
                        ),
                ),
              ),
              IgnorePointer(
                child: ValueListenableBuilder(
                  valueListenable: _swipe,
                  builder: (context, swipe, _) => swipe == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: const Alignment(0, -0.45),
                          child: SeekReadout(
                            time: clockOf(swipe.target),
                            delta: signedClock(swipe.delta),
                          ),
                        ),
                ),
              ),
              if (showUpNext)
                Positioned(
                  right: Tokens.space5,
                  // A phone held sideways: just clear of the bar, so the card ends under the
                  // top one.
                  bottom: pad.bottom + (size.height < kShortRoom ? 108 : 120),
                  child: IgnorePointer(
                    ignoring: _locked,
                    child: UpNextCard(
                      key: ValueKey(upNext),
                      name: _upNextName(upNext),
                      at: upNextAt,
                      onPlay: () => unawaited(_notifier.playUpNext()),
                      onCancel: _notifier.cancelUpNext,
                    ),
                  ),
                ),
              if (_locked)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: pad.bottom + Tokens.space9,
                  child: Center(
                    child: IgnorePointer(
                      ignoring: !_unlockShown,
                      child: AnimatedOpacity(
                        opacity: _unlockShown ? 1 : 0,
                        duration: _unlockShown ? Tokens.durFast : Tokens.durSlow,
                        child: UnlockPill(onUnlock: _unlock),
                      ),
                    ),
                  ),
                ),
              // Over the controls too: a file that cannot play has nothing to control, and
              // the play button in the middle of a phone must not sit on the sentence.
              if (session.error != null)
                Undecodable(
                  sentence: session.error!,
                  fileName: session.file.displayName,
                  // The same file again, through the one way in: it closes what is here first.
                  onRetry: () => unawaited(_notifier.open(session.file)),
                  onBack: () => unawaited(_notifier.close()),
                ),
              if (hints)
                GestureGuide(
                  seekStep: settings.seekStepSeconds,
                  brightness: Platform.isAndroid,
                  swipeToSeek: settings.swipeToSeek,
                  onDone: _closeHints,
                ),
              if (booth) const BoothSheet(),
              if (session.threadingVisible) const ThreadingOverlay(),
              if (cue) const CueSheet(),
            ],
          ),
        ),
      ),
    );
  }
}
