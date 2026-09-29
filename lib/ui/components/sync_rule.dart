// The sync rule: a mono ruler from −2.00 to +2.00 sliding under a FIXED tungsten caret.
// The caret never moves — a screenshot with a moved caret is a bug.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/sync_rule.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';

const double kPxPerDetent = 12;

class SyncRule extends StatefulWidget {
  final int delayMs;
  final ValueChanged<int> onChanged;
  const SyncRule({super.key, required this.delayMs, required this.onChanged});

  @override
  State<SyncRule> createState() => _SyncRuleState();
}

class _SyncRuleState extends State<SyncRule> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final shownMs = _dragMs ?? widget.delayMs.toDouble();
    return Semantics(
      slider: true,
      label: 'Subtitle sync',
      value: spokenDelay(widget.delayMs),
      increasedValue: spokenDelay(stepMs(widget.delayMs, later: true)),
      decreasedValue: spokenDelay(stepMs(widget.delayMs, later: false)),
      onIncrease: () => widget.onChanged(stepMs(widget.delayMs, later: true)),
      onDecrease: () => widget.onChanged(stepMs(widget.delayMs, later: false)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          // Dragging the RULER left moves the value up (the ruler slides under the caret).
          final next = (shownMs - d.delta.dx / kPxPerDetent * kDetentMs).clamp(-2000.0, 2000.0);
          final before = snapMs(shownMs);
          final after = snapMs(next);
          if (before != after) HapticFeedback.selectionClick();
          setState(() => _dragMs = next);
        },
        onHorizontalDragEnd: (_) {
          final v = snapMs(_dragMs ?? widget.delayMs);
          setState(() => _dragMs = null);
          widget.onChanged(v);
        },
        onLongPress: () => widget.onChanged(resetMs),
        child: SizedBox(
          height: 52,
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _dragMs ?? widget.delayMs.toDouble()),
              duration: _dragMs == null ? Tokens.durFast : Duration.zero,
              curve: Tokens.easeOut,
              builder: (context, ms, _) => CustomPaint(
                size: Size.infinite,
                painter: _RulerPainter(ms: ms, palette: p),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double ms;
  final HousePalette palette;
  _RulerPainter({required this.ms, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final cx = size.width / 2;
    final offset = -ms / kDetentMs * kPxPerDetent; // the RULER moves
    final tick = Paint()..color = p.border;
    final major = Paint()..color = p.inkFaint;
    for (var d = -40; d <= 40; d++) {
      final x = cx + offset + d * kPxPerDetent;
      if (x < -20 || x > size.width + 20) continue;
      final isMajor = d % 10 == 0;
      canvas.drawRect(Rect.fromLTWH(x, 8, 1, isMajor ? 14 : 7), isMajor ? major : tick);
      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(
            text: formatDelay(d * kDetentMs),
            style: Txt.mono(Tokens.textXs, p.inkFaint),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 26));
      }
    }
    // The fixed caret: 1 px tungsten line with the bulb halo and a 7 px round cap.
    final caret = Paint()..color = p.accent;
    canvas.drawRect(Rect.fromLTWH(cx, 2, 1, 24), caret);
    canvas.drawCircle(Offset(cx + 0.5, 2), 3.5, caret);
    canvas.drawCircle(
      Offset(cx + 0.5, 2),
      6,
      Paint()
        ..color = p.accent.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_RulerPainter o) => o.ms != ms || o.palette != palette;
}
