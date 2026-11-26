// The Auditorium's layers that are not the gesture surface: the picture, the controls (the
// only part the 10 Hz playback stream rebuilds), the "Skip intro" pill, the video details
// overlay and the "can't be projected" card. Each one watches exactly what it draws, so the
// screen itself (auditorium_screen.dart: state, keys, gestures) never rebuilds on a clock tick.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../engine/detents.dart';
import '../../engine/models/models.dart';
import '../../engine/playback.dart';
import '../../platform/window.dart';
import '../../player/engine.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/primitives.dart';
import '../components/sync_rule.dart';
import 'controls/controls_bar.dart';
import 'controls/widgets.dart';

/// The picture alone. Rebuilt when the fit, the room's size or the film's own size changes,
/// never by a clock tick. Rotation, zoom and the levels are mpv's work (see
/// `PlayerEngine.applyPicture`): the texture arrives already turned.
///
/// libass draws the subtitle line INTO that texture, so "Fill (crop)" would cut it off with
/// the bottom of the picture: this layer knows how much is cropped and tells the engine to
/// move the line in by as much.
class PictureLayer extends ConsumerStatefulWidget {
  final PlayerEngine engine;
  final PictureFit fit;
  final bool transparent;
  const PictureLayer({
    super.key,
    required this.engine,
    required this.fit,
    required this.transparent,
  });

  @override
  ConsumerState<PictureLayer> createState() => _PictureLayerState();
}

class _PictureLayerState extends ConsumerState<PictureLayer> {
  double _crop = 0;

  @override
  void didUpdateWidget(PictureLayer old) {
    super.didUpdateWidget(old);
    if (old.engine != widget.engine) _crop = 0; // a new player starts uncropped
  }

  void _syncCrop(double crop) {
    if ((crop - _crop).abs() < 0.5) return;
    _crop = crop;
    final engine = widget.engine;
    // After the build: this talks to the player, it draws nothing.
    scheduleMicrotask(() => unawaited(engine.setSubtitleCrop(crop)));
  }

  @override
  Widget build(BuildContext context) {
    final fit = widget.fit;
    final film = ref.watch(
      playbackProvider.select((v) => (w: v.value?.width ?? 0, h: v.value?.height ?? 0)),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final known = film.w > 0 && film.h > 0 && box.maxHeight > 0 && box.maxHeight.isFinite;
        _syncCrop(
          fit == PictureFit.fill && known
              ? fillCropPercent(
                  videoAspect: film.w / film.h,
                  viewAspect: box.maxWidth / box.maxHeight,
                )
              : 0,
        );
        return RepaintBoundary(
          child: Video(
            controller: widget.engine.controller,
            controls: NoVideoControls,
            fill: widget.transparent ? const Color(0x00000000) : Tokens.pictureBg,
            fit: switch (fit) {
              PictureFit.fill => BoxFit.cover,
              PictureFit.stretch => BoxFit.fill,
              _ => BoxFit.contain,
            },
            aspectRatio: fit.forcedAspect,
            // Keep-awake only while the film actually plays (released on pause).
            wakelock: true,
          ),
        );
      },
    );
  }
}

/// The controls at 10 Hz: the only part of the room the playback stream rebuilds.
class ControlsLayer extends ConsumerStatefulWidget {
  final FilmSession session;
  final bool desktop, fullscreen, syncOpen;
  final AuditoriumMenu? menu;
  final ControlsActions actions;
  const ControlsLayer({
    super.key,
    required this.session,
    required this.desktop,
    required this.fullscreen,
    required this.syncOpen,
    required this.menu,
    required this.actions,
  });

  @override
  ConsumerState<ControlsLayer> createState() => _ControlsLayerState();
}

class _ControlsLayerState extends ConsumerState<ControlsLayer> {
  double? _scrub;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pb = ref.watch(playbackProvider).value ?? const PlaybackState();
    final prefs = ref.watch(
      settingsValueProvider.select((x) => (step: x.seekStepSeconds, remaining: x.showRemaining)),
    );
    final dur = pb.duration.inMilliseconds / 1000;
    final a = widget.actions;
    final attached = s.threading.attached;
    return AuditoriumControls(
      data: ControlsData(
        title: s.displayTitle,
        position: _scrub ?? pb.position.inMilliseconds / 1000,
        duration: dur,
        buffered: pb.buffer.inMilliseconds / 1000,
        buffering: pb.buffering,
        playing: pb.playing,
        volume: pb.volume,
        muted: pb.muted,
        rate: pb.rate,
        delayMs: s.delayMs,
        hasSubtitle: pb.hasSubtitle,
        matched: attached is ExternalSubtitle && attached.syncedByHash,
        detents: detentsFor(s.chapters, dur),
        chapterTitles: {
          for (final c in s.chapters)
            if (c.title != null) c.startSeconds: c.title!,
        },
        loopA: s.loopA == null ? null : s.loopA!.inMilliseconds / 1000,
        loopB: s.loopB == null ? null : s.loopB!.inMilliseconds / 1000,
        hasPrevious: s.previousPath != null,
        hasNext: s.nextPath != null,
        fullscreen: widget.fullscreen,
        desktop: widget.desktop,
        showPip: Platform.isAndroid,
        sleeping: s.sleep != SleepTimer.off,
        fit: s.fit,
        pictureAdjusted: !s.picture.isNeutral,
        pinned: ref.watch(pinnedProvider),
        seekStep: prefs.step,
        showRemaining: prefs.remaining,
        openMenu: widget.menu,
        syncOpen: widget.syncOpen,
      ),
      actions: ControlsActions(
        onBack: a.onBack,
        onPlayPause: a.onPlayPause,
        onMute: a.onMute,
        onFullscreen: a.onFullscreen,
        onToggleSync: a.onToggleSync,
        onSeekBy: a.onSeekBy,
        onSeek: (v) {
          setState(() => _scrub = null);
          a.onSeek(v);
        },
        onScrub: (v) {
          setState(() => _scrub = v);
          a.onScrub(v);
        },
        onScrubEnd: () {
          setState(() => _scrub = null);
          a.onScrubEnd();
        },
        onVolume: a.onVolume,
        onMenu: a.onMenu,
        onPrevious: a.onPrevious,
        onNext: a.onNext,
        onPip: a.onPip,
        onCueSheet: a.onCueSheet,
        onToggleClock: a.onToggleClock,
      ),
      syncRule: widget.syncOpen
          ? Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space2),
              child: SyncRule(
                delayMs: s.delayMs,
                onChanged: (v) => unawaited(ref.read(sessionProvider.notifier).setDelay(v)),
              ),
            )
          : null,
    );
  }
}

/// "Skip intro" / "Skip recap" / "Skip credits" / "Next episode", while the film is inside
/// such a chapter. It watches the playback stream through a `select` on the answer itself, so
/// it rebuilds when the button appears, changes or goes, not ten times a second.
class SkipChapterButton extends ConsumerWidget {
  final bool desktop;

  /// Told what was skipped (for the screen's readout).
  final ValueChanged<String>? onSkipped;
  const SkipChapterButton({super.key, required this.desktop, this.onSkipped});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final film = ref.watch(
      sessionProvider.select(
        (s) => s == null || s.threadingVisible || s.error != null
            ? null
            : (chapters: s.chapters, hasNext: s.nextPath != null),
      ),
    );
    if (film == null || film.chapters.isEmpty) return const SizedBox.shrink();
    final skip = ref.watch(
      playbackProvider.select((v) {
        final pb = v.value;
        if (pb == null || pb.completed) return null;
        return skippableChapter(
          film.chapters,
          pb.position.inMilliseconds / 1000,
          pb.duration.inMilliseconds / 1000,
          hasNext: film.hasNext,
        );
      }),
    );
    if (skip == null) return const SizedBox.shrink();
    return SkipPill(
      label: skip.label,
      keyHint: desktop ? 'Enter' : null,
      onTap: () => unawaited(_skip(ref)),
    );
  }

  Future<void> _skip(WidgetRef ref) async {
    final done = await ref.read(sessionProvider.notifier).skipChapter();
    if (done != null) onSkipped?.call(done);
  }
}

/// The video details overlay, live: asks mpv once a second, and only while it is on screen
/// (the widget is built only then). Its own state: nothing else rebuilds.
class LiveVideoDetails extends StatefulWidget {
  final PlayerEngine engine;
  final VoidCallback onClose;
  const LiveVideoDetails({super.key, required this.engine, required this.onClose});

  @override
  State<LiveVideoDetails> createState() => _LiveVideoDetailsState();
}

class _LiveVideoDetailsState extends State<LiveVideoDetails> {
  Timer? _tick;
  bool _busy = false;
  List<({String label, String value})> _lines = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_read()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (_busy) return; // a slow answer is not asked for twice
    _busy = true;
    try {
      final lines = videoDetailLines(await widget.engine.stats());
      if (mounted) setState(() => _lines = lines);
    } on Object {
      // The film closed mid-question: the last answer stays until the overlay goes too.
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => VideoDetailsPanel(lines: _lines, onClose: widget.onClose);
}

/// A film libmpv could not open: one sentence and the way out.
class Undecodable extends StatelessWidget {
  final String sentence;
  final VoidCallback onBack;
  const Undecodable({super.key, required this.sentence, required this.onBack});

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
