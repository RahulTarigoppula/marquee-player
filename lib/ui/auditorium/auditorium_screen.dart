// The Auditorium: watch the film. The picture fills the window (or the phone); the controls
// float over it on soft gradients and fade away while the film plays. Keyboard map comes from
// design/cue-sheet.json.
//
// Layers, bottom to top: bias-light walls · the picture · Flutter subtitles (Android, other
// scripts) · the gesture surface · the controls · video details, "Skip intro" · menus,
// readouts, "Up next" · the Booth, the threading overlay and the cue sheet. Overlays are
// SIBLINGS of the gesture surface, never its children, so a tap on the threading overlay can
// never pause or seek the hidden film.
//
// This file holds the room's state, its keys and its gestures. The layers themselves live in
// layers.dart, the menus in menu_panel.dart, the pure widgets in controls/.
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:screen_brightness/screen_brightness.dart';

import '../../engine/bias_light.dart';
import '../../engine/playback.dart';
import '../../engine/sync_rule.dart';
import '../../platform/pip.dart';
import '../../platform/window.dart';
import '../../player/engine.dart';
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

enum _Drag { brightness, volume }

class AuditoriumScreen extends ConsumerStatefulWidget {
  const AuditoriumScreen({super.key});

  @override
  ConsumerState<AuditoriumScreen> createState() => _AuditoriumScreenState();
}

class _AuditoriumScreenState extends ConsumerState<AuditoriumScreen> {
  bool _controls = true;
  bool _syncOpen = false;
  bool _details = false;
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
  _Drag? _drag;
  double _dragVolume = 100;
  ({String icon, String text, double? level})? _readout;
  Offset? _doubleTapAt;
  bool _playing = false;
  bool _completed = false;
  bool _upNextCancelled = false;
  String? _pipKey;

  bool get _desktop => PlayerEngine.isDesktop;

  @override
  void initState() {
    super.initState();
    // Take the keyboard from whatever the Lobby had focused (autofocus alone loses to it).
    WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
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
    _idle?.cancel();
    _bias?.cancel();
    _readoutTimer?.cancel();
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
    _readoutTimer?.cancel();
    setState(() => _readout = (icon: icon, text: text, level: level));
    _readoutTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _readout = null);
    });
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
    if (_desktop && ref.read(fullscreenProvider)) {
      ref.read(fullscreenProvider.notifier).set(false);
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

  void _onTap() {
    if (_menu != null) {
      _closeMenu();
      return;
    }
    if (_desktop) {
      // Desktop: a click plays / pauses (a double click goes fullscreen).
      unawaited(_playPause());
      _poke();
    } else {
      _controls ? _hideControls() : _poke();
    }
  }

  void _onDoubleTap() {
    if (_desktop) {
      _toggleFullscreen();
      return;
    }
    final at = _doubleTapAt;
    final w = MediaQuery.sizeOf(context).width;
    if (at == null) return;
    final step = _seekStep;
    if (at.dx < w / 3) {
      unawaited(_seekBy(Duration(seconds: -step)));
      _showReadout('rotate-ccw', '$step s back');
    } else if (at.dx > w * 2 / 3) {
      unawaited(_seekBy(Duration(seconds: step)));
      _showReadout('rotate-cw', '$step s forward');
    } else {
      unawaited(_playPause());
    }
  }

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _menu != null) return;
    final s = _session;
    if (s == null || s.threadingVisible) return;
    _volumeBy(e.scrollDelta.dy < 0 ? 5 : -5);
    _poke();
  }

  /// Phone edge dimmers: a vertical swipe on the left 40 % sets brightness, on the right 40 %
  /// the volume. The system gesture insets (Android back swipes) and the status / nav bars
  /// are left alone.
  void _onDragStart(DragStartDetails d) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final pad = MediaQuery.paddingOf(context);
    final x = d.localPosition.dx;
    final y = d.localPosition.dy;
    _drag = null;
    if (y < pad.top + 24 || y > size.height - pad.bottom - insets.bottom - 24) return;
    if (x > insets.left + 8 && x < size.width * 0.4) {
      _drag = Platform.isAndroid ? _Drag.brightness : null;
    } else if (x > size.width * 0.6 && x < size.width - insets.right - 8) {
      _drag = _Drag.volume;
      _dragVolume = _session?.engine.player.state.volume ?? 100;
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final drag = _drag;
    if (drag == null) return;
    final h = MediaQuery.sizeOf(context).height;
    final delta = -d.delta.dy / (h * 0.6);
    switch (drag) {
      case _Drag.brightness:
        final next = ((_brightness ?? 0.5) + delta).clamp(0.02, 1.0);
        _brightness = next;
        _brightnessTouched = true;
        unawaited(ScreenBrightness.instance.setApplicationScreenBrightness(next));
        _showReadout('sun', 'Brightness ${(next * 100).round()} %', next);
      case _Drag.volume:
        _dragVolume = (_dragVolume + delta * 100).clamp(0.0, 150.0);
        unawaited(_notifier.setVolume(_dragVolume));
        _showReadout(
          VolumeControl.iconFor(_dragVolume, muted: false),
          'Volume ${_dragVolume.round()} %',
          _dragVolume / 150,
        );
    }
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
          if (!pb.completed) _upNextCancelled = false;
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
        }
      }
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
    // One rule decides the end of a film (repeat, "play the next one", the sleep timer): the
    // card shows only when that rule starts another film. A looping film never completes.
    final upNext = session.upNextFor(settings);
    final showUpNext =
        _completed && !_upNextCancelled && upNext != null && !session.threadingVisible;
    final pad = MediaQuery.paddingOf(context);
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
                  lifted: _controls && !session.threadingVisible,
                ),
              // The gesture surface: below the controls, beside (never around) the overlays.
              Listener(
                onPointerSignal: _onWheel,
                child: MouseRegion(
                  cursor: hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
                  onHover: (_) => _poke(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTap,
                    onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                    onDoubleTap: _onDoubleTap,
                    onSecondaryTap: _desktop ? () => _openMenu(AuditoriumMenu.more) : null,
                    onLongPressStart: _desktop
                        ? null
                        : (_) {
                            _holding = true;
                            _rateBeforeHold = engine.player.state.rate;
                            unawaited(engine.setRate(2));
                            _showReadout('gauge', '2× while held');
                          },
                    onLongPressEnd: _desktop
                        ? null
                        : (_) {
                            if (!_holding) return;
                            _holding = false;
                            unawaited(engine.setRate(_rateBeforeHold));
                          },
                    onVerticalDragStart: _desktop ? null : _onDragStart,
                    onVerticalDragUpdate: _desktop ? null : _onDragUpdate,
                    onVerticalDragEnd: _desktop ? null : (_) => _drag = null,
                  ),
                ),
              ),
              if (session.error != null)
                Undecodable(sentence: session.error!, onBack: () => unawaited(_back())),
              RepaintBoundary(
                child: IgnorePointer(
                  ignoring: !_controls,
                  child: AnimatedOpacity(
                    opacity: _controls ? 1 : 0,
                    duration: _controls ? Tokens.durFast : Tokens.durSlow,
                    curve: _controls ? Tokens.easeOut : Tokens.easeInOut,
                    child: MouseRegion(
                      onHover: (_) => _idle?.cancel(),
                      onExit: (_) => _poke(),
                      opaque: false,
                      child: ControlsLayer(
                        session: session,
                        desktop: _desktop,
                        fullscreen: fullscreen,
                        menu: _menu,
                        syncOpen: _syncOpen,
                        actions: actions,
                      ),
                    ),
                  ),
                ),
              ),
              // Under the title, clear of the bottom bar; it stays while the controls hide.
              if (_details && !session.threadingVisible)
                Positioned(
                  left: Tokens.space4,
                  right: Tokens.space4,
                  top: pad.top + 60,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: LiveVideoDetails(
                      key: ValueKey(engine),
                      engine: engine,
                      onClose: _toggleDetails,
                    ),
                  ),
                ),
              // "Skip intro": there even when the controls are not. A menu or the "Up next"
              // card takes the same corner, so it steps aside for them.
              if (_menu == null && !showUpNext && !booth)
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
                Positioned(
                  right: Tokens.space4,
                  bottom: pad.bottom + (_desktop ? 104 : 132),
                  left: _desktop ? null : Tokens.space4,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: MenuPanel(
                      menu: _menu!,
                      canGoBack: _menuTrail.isNotEmpty,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.6,
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
                      desktop: _desktop,
                    ),
                  ),
                ),
              ],
              if (_readout != null)
                Align(
                  alignment: const Alignment(0, -0.45),
                  child: IgnorePointer(
                    child: LevelReadout(
                      icon: _readout!.icon,
                      text: _readout!.text,
                      level: _readout!.level,
                    ),
                  ),
                ),
              if (showUpNext)
                Positioned(
                  right: Tokens.space5,
                  bottom: pad.bottom + 120,
                  child: UpNextCard(
                    key: ValueKey(upNext),
                    // A phone's library film is a content:// URI: it has no name to show.
                    name: upNext.startsWith('content://') ? 'The next video' : p.basename(upNext),
                    onPlay: () => unawaited(_notifier.playUpNext()),
                    onCancel: () => setState(() => _upNextCancelled = true),
                  ),
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
