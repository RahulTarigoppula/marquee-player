// The marquee: title spelled bulb by bulb (60 ms stagger, capped at 24 letters), a crimson
// 1 px trim, bulbs lit at night with a seeded 0.5 % flicker, painted (off) in Matinee.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/house.dart';
import '../../theme/tokens.dart';
import 'primitives.dart';

const int kWarmupCap = 24;
const Duration kWarmupStagger = Duration(milliseconds: 60);
const Duration kWarmupLetter = Duration(milliseconds: 320);

class MarqueeSign extends StatefulWidget {
  final String title;
  final String? meta; // '1949 · NOW SHOWING'
  final bool identified; // unknown file ⇒ one bulb stays dark
  final bool night;
  final double fontSize;
  const MarqueeSign({
    super.key,
    required this.title,
    this.meta,
    this.identified = true,
    this.night = true,
    this.fontSize = Tokens.text4Xl,
  });

  @override
  State<MarqueeSign> createState() => _MarqueeSignState();
}

class _MarqueeSignState extends State<MarqueeSign> with SingleTickerProviderStateMixin {
  late final AnimationController _warm = AnimationController(vsync: this);
  final _rnd = math.Random(8);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(MarqueeSign old) {
    super.didUpdateWidget(old);
    if (old.title != widget.title) _start();
  }

  void _start() {
    final n = math.min(widget.title.length, kWarmupCap);
    _warm.duration = kWarmupStagger * n + kWarmupLetter;
    _warm.forward(from: 0);
  }

  @override
  void dispose() {
    _warm.dispose();
    super.dispose();
  }

  double _letterOpacity(int i, double t, bool reduced) {
    if (reduced) return t;
    final total = _warm.duration!.inMilliseconds;
    final start = math.min(i, kWarmupCap) * kWarmupStagger.inMilliseconds / total;
    final len = kWarmupLetter.inMilliseconds / total;
    final x = ((t - start) / len).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(x) * (x < 0.94 ? 1.1 : 1.0); // 2-frame overshoot
  }

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final lit = widget.night && !h.matinee;
    final title = widget.title.toUpperCase();
    return Semantics(
      header: true,
      label: '${widget.title}${widget.meta == null ? '' : ', ${widget.meta}'}',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([_warm, h.house]),
        builder: (context, _) {
          final house = h.house.value;
          final bulbIntensity = 0.08 + 0.92 * house;
          return Container(
            constraints: const BoxConstraints(maxWidth: 760),
            decoration: BoxDecoration(
              color: h.matinee ? p.surface2 : p.bgElevated.withValues(alpha: 0.7),
              border: Border.all(color: p.border),
              borderRadius: BorderRadius.circular(Tokens.radiusSm),
              boxShadow: h.matinee ? null : Tokens.shadow2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: Tokens.space3),
                _BulbRow(
                  lit: lit,
                  intensity: bulbIntensity,
                  dark: widget.identified ? null : 3,
                  rnd: _rnd,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.space5,
                    vertical: Tokens.space2,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < title.length; i++)
                          Opacity(
                            opacity: _letterOpacity(
                              i,
                              _warm.value,
                              h.reducedMotion,
                            ).clamp(0.0, 1.0),
                            child: Text(
                              title[i],
                              style: Txt.display(widget.fontSize, p.ink).copyWith(
                                shadows: lit
                                    ? [
                                        Shadow(
                                          color: p.accent.withValues(alpha: 0.45 * house),
                                          blurRadius: 12,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.meta != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.space2),
                    child: Text(widget.meta!, style: Txt.label(p.inkMuted)),
                  ),
                _BulbRow(lit: lit, intensity: bulbIntensity, rnd: _rnd),
                const SizedBox(height: Tokens.space3),
                Container(
                  height: 1,
                  color: p.accent2.withValues(alpha: 0.3 + 0.7 * house),
                ), // crimson trim
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BulbRow extends StatelessWidget {
  final bool lit;
  final double intensity;
  final int? dark;
  final math.Random rnd;
  const _BulbRow({required this.lit, required this.intensity, required this.rnd, this.dark});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 7; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
          child: Bulb(
            lit: lit && i != dark,
            intensity: intensity * (rnd.nextDouble() < 0.005 ? 0.6 : 1), // 0.5 % night flicker
          ),
        ),
    ],
  );
}
