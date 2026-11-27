// The download allowance: a row of perforated stubs and one plain line ("7 of 10 subtitle
// downloads left today"). Its text is the server's truth; the count decrements only AFTER the
// tear animation completes. The stubs are the charm; the words are set as a sentence, not a code.
import 'package:flutter/material.dart';

import '../../engine/models/quota.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';

class TicketStripView extends StatefulWidget {
  final TicketStrip strip;
  final int? count; // number of stubs to draw
  const TicketStripView({super.key, required this.strip, this.count});

  @override
  State<TicketStripView> createState() => _TicketStripViewState();
}

class _TicketStripViewState extends State<TicketStripView> with SingleTickerProviderStateMixin {
  late final AnimationController _tear = AnimationController(vsync: this, duration: Tokens.durBase);
  late TicketStrip _shown = widget.strip;
  late int? _shownCount = widget.count;

  @override
  void didUpdateWidget(TicketStripView old) {
    super.didUpdateWidget(old);
    final fewer = (widget.count ?? 0) < (_shownCount ?? 0);
    if (fewer && !House.of(context).reducedMotion) {
      _tear.forward(from: 0).whenComplete(() {
        if (mounted) {
          setState(() {
            _shown = widget.strip;
            _shownCount = widget.count;
          });
        }
      });
    } else {
      _shown = widget.strip;
      _shownCount = widget.count;
    }
  }

  @override
  void dispose() {
    _tear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final low = _shown.state == TicketState.twoLeft || _shown.state == TicketState.exhausted;
    final textColor = switch (_shown.state) {
      TicketState.anonymous || TicketState.unknown => p.inkMuted,
      TicketState.twoLeft || TicketState.exhausted => p.accent2Lit,
      _ => p.ink,
    };
    final stubs = (_shownCount ?? 0).clamp(0, 10);
    return Semantics(
      label: _shown.ariaLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The line drops under the stubs where the two do not fit side by side (a phone).
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Tokens.space2,
            runSpacing: Tokens.space1,
            children: [
              if (stubs > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < stubs; i++)
                      AnimatedBuilder(
                        animation: _tear,
                        builder: (context, child) {
                          final last = i == stubs - 1 && _tear.isAnimating;
                          return Opacity(
                            opacity: last ? 1 - _tear.value : 1,
                            child: Transform.translate(
                              offset: Offset(0, last ? -12 * _tear.value : 0),
                              child: Transform.rotate(
                                angle: last ? -0.1 * _tear.value : 0,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: 8,
                          height: 18,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: low ? p.accent2 : p.surface2,
                            borderRadius: BorderRadius.circular(1),
                            border: Border.all(color: low ? p.accent2 : p.borderStrong),
                          ),
                        ),
                      ),
                  ],
                ),
              Text(_shown.text, style: Txt.body(Tokens.textSm, textColor)),
            ],
          ),
          // Advice, not an alarm: the count above carries the colour.
          if (_shown.sentence != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.space1),
              child: Text(_shown.sentence!, style: Txt.body(Tokens.textSm, p.inkMuted)),
            ),
        ],
      ),
    );
  }
}
