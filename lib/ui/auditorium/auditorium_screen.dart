// The Auditorium: watch the film. Chrome exists only while you need it; controls sit on the
// wall (--bg), never on the picture. Keyboard map comes from design/cue-sheet.json.
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../engine/bias_light.dart';
import '../../engine/detents.dart';
import '../../engine/models/models.dart';
import '../../engine/sync_rule.dart';
import '../../engine/timecode.dart';
import '../../platform/pip.dart';
import '../../player/engine.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../booth/booth_sheet.dart';
import '../components/film_gate.dart';
import '../components/primitives.dart';
import '../components/room.dart';
import '../components/sync_rule.dart';
import '../threading/threading_overlay.dart';
import 'cue_sheet.dart';

class AuditoriumScreen extends ConsumerStatefulWidget {
  const AuditoriumScreen({super.key});

  @override
  ConsumerState<AuditoriumScreen> createState() => _AuditoriumScreenState();
}

class _AuditoriumScreenState extends ConsumerState<AuditoriumScreen> {
  bool _controls = true;
  bool _syncOpen = false;
  Timer? _idle;
  Timer? _bias;
  List<Color>? _stops;
  double? _scrub;
  final _focus = FocusNode(debugLabel: 'auditorium');
  double _rateBeforeHold = 1;
  double? _brightness;

  /// Edge dimmers (48 px wide): left = brightness (restored on dispose), right = volume.
  void _edgeDimmer(DragUpdateDetails d, FilmSession session) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final delta = -d.delta.dy / (h * 0.6);
    if (d.localPosition.dx <= 48 && Platform.isAndroid) {
      final next = ((_brightness ?? 0.5) + delta).clamp(0.02, 1.0);
      _brightness = next;
      unawaited(ScreenBrightness.instance.setApplicationScreenBrightness(next));
    } else if (d.localPosition.dx >= w - 48) {
      final player = session.engine.player;
      unawaited(player.setVolume((player.state.volume + delta * 100).clamp(0, 100)));
    }
  }

  @override
  void initState() {
    super.initState();
    _poke();
    _startBias();
  }

  @override
  void dispose() {
    if (_brightness != null) {
      unawaited(ScreenBrightness.instance.resetApplicationScreenBrightness());
    }
    _idle?.cancel();
    _bias?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _poke() {
    _idle?.cancel();
    if (!_controls) setState(() => _controls = true);
    _idle = Timer(Tokens.controlsIdle, () {
      if (mounted && !ref.read(boothOpenProvider) && !_syncOpen) setState(() => _controls = false);
    });
  }

  /// Bias light: screenshot → decoder downscale to 64×36 → top 80 % → five stops.
  void _startBias() {
    final settings = ref.read(settingsValueProvider);
    if (!settings.biasLight) return;
    final every = Duration(milliseconds: Platform.isAndroid ? 1000 : 500);
    _bias = Timer.periodic(every, (_) async {
      final s = ref.read(sessionProvider);
      if (s == null || !s.engine.player.state.playing) return; // paused ⇒ the glow freezes
      final bytes = await s.engine.screenshot();
      if (bytes == null || !mounted) return;
      try {
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
        // A bad frame is not worth a word.
      }
    });
  }

  Future<void> _back() async {
    if (ref.read(cueSheetProvider)) {
      ref.read(cueSheetProvider.notifier).set(false);
      return;
    }
    if (ref.read(boothOpenProvider)) {
      ref.read(boothOpenProvider.notifier).set(false);
      return;
    }
    final s = ref.read(sessionProvider);
    if (s != null && s.threadingVisible) {
      ref.read(sessionProvider.notifier).skipSubtitles();
      return;
    }
    await ref.read(sessionProvider.notifier).close();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final s = ref.read(sessionProvider);
    if (s == null) return KeyEventResult.ignored;
    final player = s.engine.player;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final k = e.logicalKey;
    final pos = player.state.position;
    final dur = player.state.duration;
    Duration clampD(Duration d) =>
        d < Duration.zero ? Duration.zero : (d > dur && dur > Duration.zero ? dur : d);
    _poke();
    void delay(bool later) {
      final cur = ref.read(sessionProvider)?.delayMs ?? 0;
      unawaited(
        ref.read(sessionProvider.notifier).setDelay(stepMs(cur, later: later, shift: shift)),
      );
      setState(() => _syncOpen = true);
    }

    if (k == LogicalKeyboardKey.space) {
      unawaited(player.playOrPause());
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      unawaited(player.seek(clampD(pos - Duration(seconds: shift ? 30 : 5))));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      unawaited(player.seek(clampD(pos + Duration(seconds: shift ? 30 : 5))));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      unawaited(player.setVolume((player.state.volume + 5).clamp(0, 100)));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      unawaited(player.setVolume((player.state.volume - 5).clamp(0, 100)));
    } else if (k == LogicalKeyboardKey.keyJ) {
      delay(false);
    } else if (k == LogicalKeyboardKey.keyK) {
      delay(true);
    } else if (k == LogicalKeyboardKey.comma) {
      unawaited(s.engine.frameStep(forward: false));
    } else if (k == LogicalKeyboardKey.period) {
      unawaited(s.engine.frameStep(forward: true));
    } else if (k == LogicalKeyboardKey.keyL) {
      unawaited(s.engine.abLoop());
    } else if (k == LogicalKeyboardKey.bracketLeft) {
      unawaited(player.setRate((player.state.rate - 0.1).clamp(0.25, 4)));
    } else if (k == LogicalKeyboardKey.bracketRight) {
      unawaited(player.setRate((player.state.rate + 0.1).clamp(0.25, 4)));
    } else if (k == LogicalKeyboardKey.keyF) {
      ref.read(fullscreenProvider.notifier).toggle();
    } else if (k == LogicalKeyboardKey.keyS) {
      ref.read(boothOpenProvider.notifier).toggle();
    } else if (k == LogicalKeyboardKey.keyA) {
      final tracks = player.state.tracks.audio
          .where((t) => t.id != 'auto' && t.id != 'no')
          .toList();
      if (tracks.isNotEmpty) {
        final i = tracks.indexWhere((t) => t.id == player.state.track.audio.id);
        unawaited(player.setAudioTrack(tracks[(i + 1) % tracks.length]));
      }
    } else if (k == LogicalKeyboardKey.slash && shift || e.character == '?') {
      ref.read(cueSheetProvider.notifier).toggle();
    } else if (k == LogicalKeyboardKey.escape) {
      unawaited(_back());
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final pb = ref.watch(playbackProvider).value ?? const PlaybackState();
    final booth = ref.watch(boothOpenProvider);
    final cue = ref.watch(cueSheetProvider);
    if (session == null) return const SizedBox.shrink();
    if (ref.watch(pipProvider)) {
      return Video(
        controller: session.engine.controller,
        controls: NoVideoControls,
        fill: Tokens.pictureBg,
      );
    }
    final p = Tokens.auditorium; // playback is ALWAYS the Auditorium
    final pos = (_scrub ?? pb.position.inMilliseconds / 1000);
    final dur = pb.duration.inMilliseconds / 1000;
    final detents = detentsFor(session.chapters, dur);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final suffixes = [
      if (pb.rate != 1) '${pb.rate.toStringAsFixed(1)}×',
      subSuffix(session.delayMs),
    ];
    final folioText = auditoriumFolio(
      title: wide ? session.displayTitle : null,
      position: pos,
      duration: dur > 0 ? dur : null,
      suffixes: suffixes,
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
        child: MouseRegion(
          onHover: (_) => _poke(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _controls ? setState(() => _controls = false) : _poke(),
            onDoubleTapDown: (d) {
              final w = MediaQuery.sizeOf(context).width;
              final player = session.engine.player;
              final delta = Duration(
                seconds: d.localPosition.dx < w / 3
                    ? -10
                    : (d.localPosition.dx > w * 2 / 3 ? 10 : 0),
              );
              if (delta != Duration.zero) unawaited(player.seek(player.state.position + delta));
            },
            onDoubleTap: () {},
            onLongPressStart: (_) {
              _rateBeforeHold = session.engine.player.state.rate;
              unawaited(session.engine.player.setRate(2));
            },
            onLongPressEnd: (_) => unawaited(session.engine.player.setRate(_rateBeforeHold)),
            onVerticalDragUpdate: (d) => _edgeDimmer(d, session),
            child: ColoredBox(
              color: p.bg,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Walls(stops: _stops),
                  Column(
                    children: [
                      _Folio(text: folioText, dim: !_controls, matched: _matched(session)),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: wide ? Tokens.space10 : 0),
                          child: session.error != null
                              ? _Undecodable(
                                  sentence: session.error!,
                                  onBack: () => unawaited(_back()),
                                )
                              : Video(
                                  controller: session.engine.controller,
                                  controls: NoVideoControls,
                                  fill: Tokens.pictureBg,
                                ),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _controls ? 1 : 0,
                        duration: _controls ? Tokens.durFast : Tokens.durSlow,
                        curve: _controls ? Tokens.easeOut : Tokens.easeInOut,
                        child: IgnorePointer(
                          ignoring: !_controls,
                          child: _Controls(
                            session: session,
                            pb: pb,
                            position: pos,
                            duration: dur,
                            detents: detents,
                            syncOpen: _syncOpen,
                            wide: wide,
                            onScrub: (v) => setState(() => _scrub = v),
                            onSeek: (v) {
                              setState(() => _scrub = null);
                              unawaited(
                                session.engine.player.seek(
                                  Duration(milliseconds: (v * 1000).round()),
                                ),
                              );
                            },
                            onToggleSync: () => setState(() => _syncOpen = !_syncOpen),
                            onBack: () => unawaited(_back()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (booth) const BoothSheet(),
                  if (session.threadingVisible) const ThreadingOverlay(),
                  if (cue) const CueSheet(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool _matched(FilmSession s) {
    final a = s.threading.attached;
    return a is ExternalSubtitle && a.syncedByHash;
  }
}

class _Folio extends StatelessWidget {
  final String text;
  final bool dim;
  final bool matched;
  const _Folio({required this.text, required this.dim, required this.matched});

  @override
  Widget build(BuildContext context) {
    final p = Tokens.auditorium;
    return SafeArea(
      bottom: false,
      child: AnimatedOpacity(
        opacity: dim ? 0.4 : 1, // the folio survives auto-hide at 40 %
        duration: Tokens.durSlow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space5, vertical: Tokens.space3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.mono(Tokens.textSm, p.ink),
                ),
              ),
              if (matched) ...[
                Bulb(color: p.success, size: 7),
                const SizedBox(width: Tokens.space2),
                Text('MATCH', style: Txt.mono(Tokens.textXs, p.success)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  final FilmSession session;
  final PlaybackState pb;
  final double position, duration;
  final List<double> detents;
  final bool syncOpen, wide;
  final ValueChanged<double> onSeek, onScrub;
  final VoidCallback onToggleSync, onBack;
  const _Controls({
    required this.session,
    required this.pb,
    required this.position,
    required this.duration,
    required this.detents,
    required this.syncOpen,
    required this.wide,
    required this.onSeek,
    required this.onScrub,
    required this.onToggleSync,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Tokens.auditorium;
    final player = session.engine.player;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.space4,
          Tokens.space2,
          Tokens.space4,
          Tokens.space3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AisleLights(),
            const SizedBox(height: Tokens.space2),
            if (syncOpen)
              SyncRule(
                delayMs: session.delayMs,
                onChanged: (v) => unawaited(ref.read(sessionProvider.notifier).setDelay(v)),
              ),
            FilmGate(
              position: position,
              duration: duration,
              buffered: pb.buffer.inMilliseconds / 1000,
              buffering: pb.buffering,
              detents: detents,
              height: wide ? Tokens.gateHeightDesktop : Tokens.gateHeight,
              onSeek: onSeek,
              onScrub: onScrub,
            ),
            const SizedBox(height: Tokens.space2),
            // Two groups that wrap onto a second line on a narrow phone instead of overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconMark(icon: 'arrow-left', label: 'Back to the lobby', onTap: onBack),
                    TextMark(
                      text: '◀10',
                      label: 'Back 10 seconds',
                      onTap: () => unawaited(
                        player.seek(player.state.position - const Duration(seconds: 10)),
                      ),
                    ),
                    _PlayMark(playing: pb.playing, onTap: () => unawaited(player.playOrPause())),
                    TextMark(
                      text: '10▶',
                      label: 'Forward 10 seconds',
                      onTap: () => unawaited(
                        player.seek(player.state.position + const Duration(seconds: 10)),
                      ),
                    ),
                    const SizedBox(width: Tokens.space2),
                    Mark(
                      label: 'Subtitle sync ${spokenDelay(session.delayMs)}',
                      onTap: onToggleSync,
                      child: Text(
                        'SYNC ${formatDelay(session.delayMs)}',
                        style: Txt.mono(Tokens.textXs, syncOpen ? p.accent : p.ink),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconMark(
                      icon: 'captions',
                      label: 'Subtitle booth',
                      active: pb.hasSubtitle,
                      onTap: () => ref.read(boothOpenProvider.notifier).toggle(),
                    ),
                    if (wide)
                      Mark(
                        label: 'Speed',
                        onTap: () => unawaited(player.setRate(pb.rate >= 2 ? 1 : pb.rate + 0.25)),
                        child: Text(
                          '${pb.rate.toStringAsFixed(2)}×',
                          style: Txt.mono(Tokens.textXs, p.inkMuted),
                        ),
                      ),
                    IconMark(
                      icon: ref.watch(fullscreenProvider) ? 'minimize-2' : 'maximize-2',
                      label: 'Fullscreen',
                      onTap: () => ref.read(fullscreenProvider.notifier).toggle(),
                    ),
                    if (wide)
                      TextMark(
                        text: '?',
                        label: 'Cue sheet',
                        onTap: () => ref.read(cueSheetProvider.notifier).toggle(),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayMark extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayMark({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Tokens.auditorium;
    return Mark(
      label: playing ? 'Pause' : 'Play',
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
        child: Center(child: LucideIcon(playing ? 'pause' : 'play', color: p.accentInk, size: 18)),
      ),
    );
  }
}

class _AisleLights extends StatelessWidget {
  const _AisleLights();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LayoutBuilder(
      builder: (context, c) {
        final n = (c.maxWidth / 28).floor().clamp(4, 60);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (var i = 0; i < n; i++) const Bulb(size: 4, intensity: 0.6)],
        );
      },
    ),
  );
}

class _Undecodable extends StatelessWidget {
  final String sentence;
  final VoidCallback onBack;
  const _Undecodable({required this.sentence, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final p = Tokens.auditorium;
    return ColoredBox(
      color: p.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sentence, style: Txt.body(Tokens.textLg, p.ink)),
            const SizedBox(height: Tokens.space3),
            TextAction('Open another file', primary: true, onTap: onBack),
          ],
        ),
      ),
    );
  }
}

class FullscreenNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final fullscreenProvider = NotifierProvider<FullscreenNotifier, bool>(FullscreenNotifier.new);
