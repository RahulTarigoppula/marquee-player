// The film gate: a strip of 35 mm film as the seek bar. The playhead is the frame in the gate;
// release snaps to a chapter within 6 px; dragging UP switches to FINE (1/8 gain).
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
  final double height;
  const FilmGate({
    super.key,
    required this.position,
    required this.duration,
    required this.detents,
    required this.onSeek,
    this.onScrub,
    this.buffered = 0,
    this.buffering = false,
    this.height = Tokens.gateHeight,
  });

  @override
  State<FilmGate> createState() => _FilmGateState();
}

class _FilmGateState extends State<FilmGate> with SingleTickerProviderStateMixin {
  double? _dragSeconds;
  double _dragStartDy = 0;
  bool _fine = false;
  bool _detentFlash = false;
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
      child: Focus(
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onSeek((widget.position + 5).clamp(0, dur));
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onSeek((widget.position - 5).clamp(0, dur));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return GestureDetector(
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
                setState(() {
                  _dragSeconds = null;
                  _fine = false;
                  _detentFlash = false;
                });
              },
              onTapUp: (d) => widget.onSeek(_secondsAt(d.localPosition.dx, w)),
              // Full width: a childless CustomPaint in a loose (cross-centred) parent is 0 px wide.
              child: SizedBox(
                width: w.isFinite ? w : null,
                height: widget.height,
                child: AnimatedBuilder(
                  animation: _flicker,
                  builder: (context, _) => CustomPaint(
                    painter: _GatePainter(
                      fraction: (shown / dur).clamp(0.0, 1.0),
                      buffered: (widget.buffered / dur).clamp(0.0, 1.0),
                      detents: [for (final d in widget.detents) d / dur],
                      palette: p,
                      edgeLit: _detentFlash,
                      frameVisible: !widget.buffering || _flicker.value < 0.5,
                    ),
                    child: _dragSeconds == null
                        ? null
                        : Align(
                            alignment: Alignment(((shown / dur) * 2 - 1).clamp(-0.92, 0.92), 0),
                            child: Text(
                              _fine
                                  ? 'FINE ${fmtTimecode(shown.floor())}'
                                  : fmtTimecode(shown.floor()),
                              style: Txt.mono(10, p.ink),
                            ),
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GatePainter extends CustomPainter {
  final double fraction, buffered;
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = p.bgElevated);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = p.border
        ..style = PaintingStyle.stroke,
    );
    final inset = h * 0.25;
    final body = Rect.fromLTWH(0, inset, w, h - inset * 2);
    canvas.drawRect(body, Paint()..color = p.surface);
    canvas.drawRect(
      Rect.fromLTWH(0, body.top, w * buffered, body.height),
      Paint()..color = p.surface2,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, body.top, w * fraction, body.height),
      Paint()..color = Color.lerp(p.surface2, p.accent, 0.2)!,
    );
    // Sprocket perforations: 4 px strips 5 px from each edge.
    final hole = Paint()..color = p.surface2;
    for (var x = 7.0; x < w; x += 17) {
      canvas.drawRect(Rect.fromLTWH(x, 5, 3, 4), hole);
      canvas.drawRect(Rect.fromLTWH(x, h - 9, 3, 4), hole);
    }
    final mark = Paint()..color = p.borderStrong;
    for (final d in detents) {
      canvas.drawRect(Rect.fromLTWH(d * w, body.top, 1, body.height), mark);
    }
    if (!frameVisible) return;
    // The frame in the gate: a lit 16:9 window with a 1 px accent edge.
    final fh = body.height + 8;
    final fw = fh * 16 / 9;
    final fx = (fraction * w - fw / 2).clamp(0.0, w - fw);
    final frame = Rect.fromLTWH(fx, body.top - 4, fw, fh);
    canvas.drawRect(frame, Paint()..color = p.accent.withValues(alpha: edgeLit ? 0.26 : 0.14));
    canvas.drawRect(
      frame,
      Paint()
        ..color = edgeLit ? const Color(0xFFFFFFFF) : p.accent
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
      o.detents.length != detents.length;
}
