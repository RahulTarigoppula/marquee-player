// The Auditorium's layers that are not the gesture surface: the picture, the controls (the
// only part the 10 Hz playback stream rebuilds), the seek bar's preview picture, the "Skip
// intro" pill, the video details overlay and the "can't play this file" card. Each one watches
// exactly what it draws, so the screen itself (auditorium_screen.dart: state, keys, gestures)
// never rebuilds on a clock tick.
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
import '../../player/preview.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
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
            // media_kit would pause the film itself every time the app leaves the front,
            // which silently undid "Keep playing in the background". Whether leaving pauses
            // is the app shell's decision alone (lib/app.dart).
            pauseUponEnteringBackgroundMode: false,
          ),
        );
      },
    );
  }
}

/// The controls at 10 Hz: the only part of the room the playback stream rebuilds, and only
/// while they can be seen. Faded out they stay mounted (so they can fade back in), but
/// [visible] false stops them listening to the clock: a film playing with its controls hidden
/// rebuilds nothing here.
class ControlsLayer extends ConsumerStatefulWidget {
  final FilmSession session;
  final bool desktop, fullscreen, syncOpen, visible;
  final AuditoriumMenu? menu;
  final FilmOrientation orientation;
  final ControlsActions actions;
  const ControlsLayer({
    super.key,
    required this.session,
    required this.desktop,
    required this.fullscreen,
    required this.syncOpen,
    required this.menu,
    required this.actions,
    this.visible = true,
    this.orientation = FilmOrientation.auto,
  });

  @override
  ConsumerState<ControlsLayer> createState() => _ControlsLayerState();
}

class _ControlsLayerState extends ConsumerState<ControlsLayer> {
  double? _scrub;

  // The seek bar's preview frames (see lib/player/preview.dart): asked of the session on the
  // first hover, and only ever rebuilt here when a frame becomes (or stops being) available.
  SeekPreview? _preview;
  StreamSubscription<bool>? _previewReady;

  @override
  void didUpdateWidget(ControlsLayer old) {
    super.didUpdateWidget(old);
    if (old.session.engine != widget.session.engine) _dropPreview(); // it went with its film
  }

  @override
  void dispose() {
    _dropPreview();
    super.dispose();
  }

  void _dropPreview() {
    unawaited(_previewReady?.cancel());
    _previewReady = null;
    _preview = null;
  }

  /// The pointer is over the seek bar at [seconds]: aim the preview there. Nothing is
  /// rebuilt: the frame arrives on the preview's own texture.
  void _aimPreview(double seconds) {
    // Asked every time: the session knows when this film has none (a stream, a phone, a
    // preview that failed, the setting switched off a moment ago).
    final preview = ref.read(sessionProvider.notifier).seekPreview();
    if (!identical(preview, _preview)) {
      final shown = _preview?.ready.value ?? false;
      _dropPreview();
      _preview = preview;
      _previewReady = preview?.ready.changes.listen((_) {
        if (mounted) setState(() {});
      });
      if (shown && mounted) setState(() {}); // the frame that was showing is gone
    }
    preview?.show(Duration(milliseconds: (seconds * 1000).round()));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    // Hidden: one look, no subscription. The screen rebuilds this layer the moment the
    // controls are wanted again, and that build watches the stream's CURRENT value, so the
    // first frame that can be seen already shows the right time.
    final playback = widget.visible ? ref.watch(playbackProvider) : ref.read(playbackProvider);
    final pb = playback.value ?? const PlaybackState();
    final prefs = ref.watch(
      settingsValueProvider.select((x) => (step: x.seekStepSeconds, remaining: x.showRemaining)),
    );
    final dur = pb.duration.inMilliseconds / 1000;
    final a = widget.actions;
    final attached = s.threading.attached;
    final preview = _preview;
    final frames = preview != null && preview.usable && preview.ready.value
        ? preview.controller
        : null;
    return AuditoriumControls(
      seekPreview: frames == null ? null : PreviewPicture(controller: frames),
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
        orientation: widget.orientation,
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
        onLock: a.onLock,
        onRotate: a.onRotate,
        onSeekHover: _aimPreview,
      ),
      syncRule: widget.syncOpen
          ? Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space2),
              child: SyncRule(
                delayMs: s.delayMs,
                onChanged: (v) => unawaited(ref.read(sessionProvider.notifier).setDelay(v)),
                onClose: a.onToggleSync,
              ),
            )
          : null,
    );
  }
}

/// The preview player's picture, for the bubble above the seek bar. It never holds the
/// screen awake and never follows the app to the background: it is a still, not a film.
class PreviewPicture extends StatelessWidget {
  final VideoController controller;
  const PreviewPicture({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Video(
      controller: controller,
      controls: NoVideoControls,
      fill: Tokens.pictureBg,
      wakelock: false,
      pauseUponEnteringBackgroundMode: false,
      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
    ),
  );
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

  /// Two columns in [maxWidth] (see [VideoDetailsPanel.wide]).
  final bool wide;
  final double maxWidth;
  const LiveVideoDetails({
    super.key,
    required this.engine,
    required this.onClose,
    this.wide = false,
    this.maxWidth = 400,
  });

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
  Widget build(BuildContext context) => VideoDetailsPanel(
    lines: _lines,
    onClose: widget.onClose,
    wide: widget.wide,
    maxWidth: widget.maxWidth,
  );
}

/// A file libmpv could not open. The card covers the whole room, controls included (there
/// is nothing to control): the one [sentence] it is handed, whatever it says, the file's own
/// name so a person with ten downloads knows which one it was, and the two things there are
/// to do about it.
class Undecodable extends StatelessWidget {
  final String sentence;
  final String fileName;
  final VoidCallback onRetry, onBack;
  const Undecodable({
    super.key,
    required this.sentence,
    required this.fileName,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final p = Tokens.auditorium;
    return ColoredBox(
      color: p.bg,
      child: SafeArea(
        child: Center(
          // Scrolls: a long sentence and a long name on a phone held sideways.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Tokens.space5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LucideIcon('film', size: 32, color: p.inkFaint),
                  const SizedBox(height: Tokens.space4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      sentence,
                      textAlign: TextAlign.center,
                      style: Txt.body(Tokens.textLg, p.ink, weight: FontWeight.w500),
                    ),
                  ),
                  if (fileName.isNotEmpty) ...[
                    const SizedBox(height: Tokens.space2),
                    Text(
                      fileName,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.mono(Tokens.textSm, p.inkMuted),
                    ),
                  ],
                  const SizedBox(height: Tokens.space6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: Tokens.space3,
                    runSpacing: Tokens.space2,
                    children: [
                      HouseButton(
                        label: 'Try again',
                        icon: 'refresh-cw',
                        kind: ButtonKind.primary,
                        onPressed: onRetry,
                      ),
                      HouseButton(label: 'Back to Home', onPressed: onBack),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
