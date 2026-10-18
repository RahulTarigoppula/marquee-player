// The film gate: a strip of 35 mm film as the seek bar. The playhead is the frame in the gate;
// release snaps to a chapter within 6 px; dragging UP switches to FINE (1/8 gain).
// Played, buffered and still-to-come read as three clearly different tones; hovering (or
// dragging) shows the time under the pointer above the strip.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/detents.dart';
import '../../engine/timecode.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';

class FilmGate extends StatefulWidget {
  final double position; // seconds
  final double duration;
  final double buffered;
  final List<double> detents;
  final bool buffering;
  final ValueChanged<double> onSeek;
  final ValueChanged<double>? onScrub; // live target while dragging (for the folio)

  /// Called with null when a drag ends — lets the parent drop its scrub readout.
  final VoidCallback? onScrubEnd;
  final double height;

  /// The A–B loop, in seconds (drawn as a band over the strip).
  final double? loopA, loopB;

  /// Chapter titles by start second, for the hover label.
  final Map<double, String> chapterTitles;

  const FilmGate({
    super.key,
    required this.position,
    required this.duration,
    required this.detents,
    required this.onSeek,
    this.onScrub,
    this.onScrubEnd,
    this.buffered = 0,
    this.buffering = false,
    this.height = Tokens.gateHeight,
    this.loopA,
    this.loopB,
    this.chapterTitles = const {},
  });

  @override
  State<FilmGate> createState() => _FilmGateState();
}

class _FilmGateState extends State<FilmGate> with SingleTickerProviderStateMixin {
  double? _dragSeconds;
  double _dragStartDy = 0;
  bool _fine = false;
  bool _detentFlash = false;
  double? _hoverDx;
  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void didUpdateWidget(FilmGate old) {
    super.didUpdateWidget(old);
    if (widget.buffering && !_flicker.isAnimating && !House.of(context).reducedMotion) {
      _flicker.repeat();
    } else if (!widget.buffering && _flicker.isAnimating) {
      _flicker.stop();
    }
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  double _secondsAt(double dx, double width) =>
      widget.duration <= 0 ? 0 : (dx / width).clamp(0.0, 1.0) * widget.duration;

  void _update(double target) {
    final prev = _dragSeconds ?? widget.position;
    final crossed = !_fine && crossesDetent(prev, target, widget.detents);
    if (crossed) HapticFeedback.selectionClick();
    setState(() {
      _dragSeconds = target;
      _detentFlash = crossed;
    });
    widget.onScrub?.call(target);
  }

  String? _chapterAt(double seconds) {
    String? title;
    for (final e in widget.chapterTitles.entries) {
      if (e.key <= seconds) title = e.value;
    }
    return title == null || title.trim().isEmpty ? null : title;
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final dur = widget.duration <= 0 ? 1.0 : widget.duration;
    final shown = _dragSeconds ?? widget.position;
    return Semantics(
      slider: true,
      label: 'Film gate',
      value: fmtTimecode(shown.floor()),
      increasedValue: fmtTimecode((shown + 5).floor()),
      decreasedValue: fmtTimecode((shown - 5).floor()),
      onIncrease: () => widget.onSeek((widget.position + 5).clamp(0, dur)),
      onDecrease: () => widget.onSeek((widget.position - 5).clamp(0, dur)),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          // The label follows the drag, else the hover.
          final labelSeconds = _dragSeconds ?? (_hoverDx == null ? null : _secondsAt(_hoverDx!, w));
          final chapter = labelSeconds == null ? null : _chapterAt(labelSeconds);
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (e) => setState(() => _hoverDx = e.localPosition.dx),
            onExit: (_) => setState(() => _hoverDx = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) {
                _dragStartDy = d.localPosition.dy;
                _fine = false;
                _update(_secondsAt(d.localPosition.dx, w));
              },
              onHorizontalDragUpdate: (d) {
                final wasFine = _fine;
                _fine = d.localPosition.dy < _dragStartDy - widget.height;
                if (_fine && wasFine) {
                  _update(
                    fineSeek(
                      startSeconds: _dragSeconds ?? widget.position,
                      dragPx: d.delta.dx,
                      gateWidthPx: w,
                      durationSeconds: dur,
                    ),
                  );
                } else {
                  _update(_secondsAt(d.localPosition.dx, w));
                }
              },
              onHorizontalDragEnd: (_) {
                final target = _dragSeconds ?? widget.position;
                final snap = _fine
                    ? SnapResult(target, snapped: false)
                    : snapTarget(
                        releasePx: target / dur * w,
                        gateWidthPx: w,
                        durationSeconds: dur,
                        detents: widget.detents,
                      );
                if (snap.snapped) HapticFeedback.lightImpact();
                widget.onSeek(snap.seconds);
                widget.onScrubEnd?.call();
                setState(() {
                  _dragSeconds = null;
                  _fine = false;
                  _detentFlash = false;
                });
              },
              onTapUp: (d) => widget.onSeek(_secondsAt(d.localPosition.dx, w)),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Full width: a childless CustomPaint in a loose parent is 0 px wide.
                  SizedBox(
                    width: w.isFinite ? w : null,
                    height: widget.height,
                    child: AnimatedBuilder(
                      animation: _flicker,
                      builder: (context, _) => CustomPaint(
                        painter: _GatePainter(
                          fraction: (shown / dur).clamp(0.0, 1.0),
                          buffered: (widget.buffered / dur).clamp(0.0, 1.0),
                          detents: [for (final d in widget.detents) d / dur],
                          loopA: widget.loopA == null ? null : widget.loopA! / dur,
                          loopB: widget.loopB == null ? null : widget.loopB! / dur,
                          palette: p,
                          edgeLit: _detentFlash,
                          frameVisible: !widget.buffering || _flicker.value < 0.5,
                        ),
                      ),
                    ),
                  ),
                  if (labelSeconds != null && w.isFinite && widget.duration > 0)
                    Positioned(
                      left: ((labelSeconds / dur) * w - 80).clamp(0.0, (w - 160).clamp(0.0, w)),
                      bottom: widget.height + Tokens.space2,
                      width: 160,
                      child: IgnorePointer(
                        child: Center(
                          child: _TimeLabel(
                            text: _fine
                                ? 'FINE ${fmtTimecode(labelSeconds.floor())}'
                                : fmtTimecode(labelSeconds.floor()),
                            chapter: chapter,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  final String text;
  final String? chapter;
  const _TimeLabel({required this.text, this.chapter});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space2, vertical: Tokens.space1),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        border: Border.all(color: p.borderStrong),
        boxShadow: Tokens.shadow1,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chapter != null)
            Text(
              chapter!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.body(Tokens.textXs, p.inkMuted),
            ),
          Text(text, style: Txt.mono(Tokens.textSm, p.ink)),
        ],
      ),
    );
  }
}

class _GatePainter extends CustomPainter {
  final double fraction, buffered;
  final double? loopA, loopB;
  final List<double> detents;
  final HousePalette palette;
  final bool edgeLit, frameVisible;
  _GatePainter({
    required this.fraction,
    required this.buffered,
    required this.detents,
    required this.palette,
    required this.edgeLit,
    required this.frameVisible,
    this.loopA,
    this.loopB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = p.bgElevated.withValues(alpha: 0.92));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = p.border
        ..style = PaintingStyle.stroke,
    );
    final inset = h * 0.25;
    final body = Rect.fromLTWH(0, inset, w, h - inset * 2);
    // Still to come: the dark base of the strip.
    canvas.drawRect(body, Paint()..color = p.surface);
    // Buffered: a lighter grey band ahead of the playhead.
    canvas.drawRect(
      Rect.fromLTWH(0, body.top, w * buffered, body.height),
      Paint()..color = p.ink.withValues(alpha: 0.2),
    );
    // Played: tungsten, unmistakable.
    canvas.drawRect(
      Rect.fromLTWH(0, body.top, w * fraction, body.height),
      Paint()..color = p.accent.withValues(alpha: 0.62),
    );
    // Sprocket perforations: 4 px strips 5 px from each edge.
    final hole = Paint()..color = p.surface2;
    for (var x = 7.0; x < w; x += 17) {
      canvas.drawRect(Rect.fromLTWH(x, 5, 3, 4), hole);
      canvas.drawRect(Rect.fromLTWH(x, h - 9, 3, 4), hole);
    }
    // Chapter ticks, full height of the body, visible over played and unplayed alike.
    final mark = Paint()..color = p.ink.withValues(alpha: 0.55);
    for (final d in detents) {
      if (d <= 0 || d >= 1) continue;
      canvas.drawRect(Rect.fromLTWH(d * w - 0.5, body.top, 2, body.height), mark);
    }
    final a = loopA;
    if (a != null) {
      final b = loopB ?? a;
      canvas.drawRect(
        Rect.fromLTRB(a * w, body.top - 3, (b * w).clamp(a * w + 2, w), body.top),
        Paint()..color = p.accent2Lit,
      );
    }
    if (!frameVisible) return;
    // The frame in the gate: a lit 16:9 window with a 1 px accent edge.
    final fh = body.height + 8;
    final fw = fh * 16 / 9;
    final fx = (fraction * w - fw / 2).clamp(0.0, (w - fw).clamp(0.0, w));
    final frame = Rect.fromLTWH(fx, body.top - 4, fw, fh);
    canvas.drawRect(frame, Paint()..color = p.accent.withValues(alpha: edgeLit ? 0.34 : 0.2));
    canvas.drawRect(
      frame,
      Paint()
        ..color = edgeLit ? const Color(0xFFFFFFFF) : p.accent
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_GatePainter o) =>
      o.fraction != fraction ||
      o.buffered != buffered ||
      o.edgeLit != edgeLit ||
      o.frameVisible != frameVisible ||
      o.palette != palette ||
      o.loopA != loopA ||
      o.loopB != loopB ||
      o.detents.length != detents.length;
}
