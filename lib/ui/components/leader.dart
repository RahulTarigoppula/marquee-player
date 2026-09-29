// The academy leader: rings, crosshair, conic sweep, hand, numeral. The sweep is driven by
// the real phase clock (engine/threading.dart leaderSweep) and FREEZES on a stall.
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/models/leader.dart';
import '../../engine/threading.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';

class Leader extends StatefulWidget {
  final ThreadingState state;
  final double size;
  const Leader({super.key, required this.state, this.size = 280});

  @override
  State<Leader> createState() => _LeaderState();
}

class _LeaderState extends State<Leader> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  bool get _running => !widget.state.stalled && widget.state.numeral != null;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Leader old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_running && !_ticker.isActive) _ticker.start();
    if (!_running && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final s = widget.state;
    final ev = s.event;
    final start = s.phaseStartedAt ?? clock.now();
    final sweep = h.reducedMotion
        ? (ev is Stalled ? 0.5 : 1.0)
        : leaderSweep(start, clock.now(), frozenAt: ev is Stalled ? ev.stalledAt : null);
    final numeral = s.numeral ?? (s.phase == LeaderPhase.flash ? null : 1);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _LeaderPainter(
            sweep: sweep,
            stalled: s.stalled,
            flash: s.phase == LeaderPhase.flash,
            accent: p.accent,
            border: p.border,
            ground: p.bgElevated,
          ),
          child: Center(
            child: Transform.translate(
              offset: Offset(0, -widget.size * 0.02), // optically 2 % above centre
              child: AnimatedSwitcher(
                duration: Tokens.durBase,
                child: numeral == null
                    ? const SizedBox.shrink()
                    : Text(
                        '$numeral',
                        key: ValueKey(numeral),
                        style: Txt.display(widget.size * 0.42, s.stalled ? p.warning : p.ink),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaderPainter extends CustomPainter {
  final double sweep;
  final bool stalled, flash;
  final Color accent, border, ground;
  _LeaderPainter({
    required this.sweep,
    required this.stalled,
    required this.flash,
    required this.accent,
    required this.border,
    required this.ground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (flash) {
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFF000000)); // the 66 ms black flash
      return;
    }
    canvas.drawCircle(c, r * 0.96, Paint()..color = ground);
    final line = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(c, r * 0.96, line);
    canvas.drawCircle(c, r * 0.96 * 0.92, line);
    canvas.drawCircle(c, r * 0.96 * 0.78, line);
    canvas.drawLine(Offset(c.dx - r * 1.06, c.dy), Offset(c.dx + r * 1.06, c.dy), line);
    canvas.drawLine(Offset(c.dx, c.dy - r * 1.06), Offset(c.dx, c.dy + r * 1.06), line);

    final angle = sweep * 2 * math.pi;
    if (angle > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.96),
        -math.pi / 2,
        angle,
        true,
        Paint()..color = accent.withValues(alpha: 0.15),
      );
    }
    final hand = Offset(c.dx + r * 0.96 * math.sin(angle), c.dy - r * 0.96 * math.cos(angle));
    canvas.drawLine(
      c,
      hand,
      Paint()
        ..shader = LinearGradient(
          colors: [accent.withValues(alpha: 0), accent],
        ).createShader(Rect.fromPoints(c, hand))
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: stalled ? 0.3 : 1),
    );
  }

  @override
  bool shouldRepaint(_LeaderPainter old) =>
      old.sweep != sweep || old.stalled != stalled || old.flash != flash || old.accent != accent;
}
