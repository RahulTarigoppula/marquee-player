// The sync rule: a mono ruler from −2.00 to +2.00 sliding under a FIXED tungsten caret.
// The caret never moves — a screenshot with a moved caret is a bug.
//
// Around the ruler, for the person who thinks "the words come too late" and not "sync +0.35":
// one sentence that says where the subtitles are now, an Earlier and a Later button either
// side (one 50 ms step a tap, one after another while held), and Reset in plain sight once
// the value has moved. The ruler itself still drags, and a long press on it still resets.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/sync_rule.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';
import 'primitives.dart';

const double kPxPerDetent = 12;

/// A held Earlier / Later button starts repeating after this long, then steps this often.
const Duration _kHoldDelay = Duration(milliseconds: 400);
const Duration _kHoldEvery = Duration(milliseconds: 120);

/// Where the subtitles stand, as a person would say it.
String syncSentence(int ms) {
  if (ms == 0) return 'Subtitles are in time with the video.';
  final by = (ms.abs() / 1000).toStringAsFixed(2);
  return ms > 0 ? 'Subtitles show $by s later.' : 'Subtitles show $by s earlier.';
}

class SyncRule extends StatefulWidget {
  final int delayMs;
  final ValueChanged<int> onChanged;

  /// Draws a close button beside the sentence. The bar's own chip only shows while the rule
  /// is open or the delay is not 0, so the rule must be able to shut itself.
  final VoidCallback? onClose;
  const SyncRule({super.key, required this.delayMs, required this.onChanged, this.onClose});

  @override
  State<SyncRule> createState() => _SyncRuleState();
}

class _SyncRuleState extends State<SyncRule> {
  double? _dragMs;

  /// One detent earlier or later, or null at that end of the range. The step is worked out
  /// when it is taken, from the value of that moment (a held button takes many).
  VoidCallback? _step({required bool later}) {
    if (stepMs(widget.delayMs, later: later) == widget.delayMs) return null;
    return () {
      HapticFeedback.selectionClick();
      widget.onChanged(stepMs(widget.delayMs, later: later));
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final ms = widget.delayMs;
    final shownMs = _dragMs ?? ms.toDouble();
    final ruler = Semantics(
      slider: true,
      label: 'Subtitle sync',
      value: spokenDelay(ms),
      increasedValue: spokenDelay(stepMs(ms, later: true)),
      decreasedValue: spokenDelay(stepMs(ms, later: false)),
      onIncrease: () => widget.onChanged(stepMs(ms, later: true)),
      onDecrease: () => widget.onChanged(stepMs(ms, later: false)),
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
          final v = snapMs(_dragMs ?? ms);
          setState(() => _dragMs = null);
          widget.onChanged(v);
        },
        onLongPress: () => widget.onChanged(resetMs),
        child: SizedBox(
          height: 52,
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _dragMs ?? ms.toDouble()),
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
    // Its own dark backing: the sentence sits at the top of the bar, where the scrim over the
    // picture is thinnest. Never wider than a hand's reach between the two buttons, and
    // centred in a wide window.
    return Align(
      heightFactor: 1,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        padding: const EdgeInsets.fromLTRB(Tokens.space2, 0, Tokens.space2, Tokens.space2),
        decoration: BoxDecoration(
          color: p.bg.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          border: Border.all(color: p.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Tokens.targetMin),
              child: Row(
                children: [
                  const SizedBox(width: Tokens.space2),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        syncSentence(ms),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.body(Tokens.textSm, p.ink),
                      ),
                    ),
                  ),
                  if (ms != resetMs)
                    TextAction('Reset', primary: true, onTap: () => widget.onChanged(resetMs)),
                  if (widget.onClose != null)
                    IconMark(icon: 'x', label: 'Close subtitle timing', onTap: widget.onClose),
                ],
              ),
            ),
            Row(
              children: [
                _StepButton(
                  text: 'Earlier',
                  label: 'Subtitles 0.05 seconds earlier',
                  onStep: _step(later: false),
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(child: ruler),
                const SizedBox(width: Tokens.space2),
                _StepButton(
                  text: 'Later',
                  label: 'Subtitles 0.05 seconds later',
                  onStep: _step(later: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Earlier" / "Later": one step a tap, and one after another while it is held down.
class _StepButton extends StatefulWidget {
  final String text, label;

  /// Null at the end of the range.
  final VoidCallback? onStep;
  const _StepButton({required this.text, required this.label, required this.onStep});

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _wait, _repeat;

  /// The hold in progress has already stepped: the tap that ends it must not add one more.
  bool _held = false;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _wait?.cancel();
    _repeat?.cancel();
    _wait = null;
    _repeat = null;
  }

  void _down(PointerDownEvent e) {
    _stop();
    _held = false;
    if (widget.onStep == null) return;
    _wait = Timer(_kHoldDelay, () {
      _repeat = Timer.periodic(_kHoldEvery, (_) {
        // Asked afresh each time: the owner hands over a new step as the value moves, and
        // none at the end of the range.
        final step = widget.onStep;
        if (step == null) {
          _stop();
          return;
        }
        _held = true;
        step();
      });
    });
  }

  void _up() {
    _stop();
    // After this event has been through the tap recogniser (it hears the lift last), the
    // button is an ordinary one again: the keyboard's Enter must not find it "held".
    scheduleMicrotask(() => _held = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final step = widget.onStep;
    return Listener(
      onPointerDown: _down,
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: Pressable(
        label: widget.label,
        // No tooltip: on a touch screen it opens on a long press, which is this button's own
        // gesture.
        radius: Tokens.radiusFull,
        onTap: step == null
            ? null
            : () {
                if (!_held) step();
              },
        builder: (context, s) => AnimatedContainer(
          duration: Tokens.durFast,
          constraints: const BoxConstraints(minWidth: 64, minHeight: Tokens.targetMin),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
          decoration: BoxDecoration(
            color: Color.alphaBlend(pressWash(p, s), p.ink.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(Tokens.radiusFull),
            border: Border.all(color: s.lit ? p.inkFaint : p.borderStrong),
          ),
          child: Center(
            widthFactor: 1,
            child: ExcludeSemantics(
              child: Text(
                widget.text,
                softWrap: false,
                style: Txt.body(
                  Tokens.textSm,
                  step == null ? p.inkFaint : p.ink,
                  weight: FontWeight.w600,
                ),
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
