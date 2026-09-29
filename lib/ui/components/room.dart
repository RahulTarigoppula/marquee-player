// The room: sky band (time of day), the projector beam (shader with a never-throwing
// fallback), lobby grain and the bias-light walls. All of it is light, none of it is chrome.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/house.dart';
import '../../theme/tokens.dart';

enum SkyPhase { dawn, day, dusk, night }

/// Local-clock sky: dawn 05–08, day 08–17, dusk 17–20, night otherwise.
SkyPhase skyPhaseAt(DateTime local) {
  final h = local.hour;
  if (h >= 5 && h < 8) return SkyPhase.dawn;
  if (h >= 8 && h < 17) return SkyPhase.day;
  if (h >= 17 && h < 20) return SkyPhase.dusk;
  return SkyPhase.night;
}

Color skyColor(HousePalette p, SkyPhase s) => switch (s) {
  SkyPhase.dawn => p.skyDawn,
  SkyPhase.day => p.skyDay,
  SkyPhase.dusk => p.skyDusk,
  SkyPhase.night => p.skyNight,
};

class SkyBand extends StatelessWidget {
  const SkyBand({super.key});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final phase = skyPhaseAt(clock.now());
    final next = SkyPhase.values[(phase.index + 1) % SkyPhase.values.length];
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: h.house,
        builder: (context, _) => Opacity(
          opacity: (0.14 + 0.86 * h.house.value).clamp(0.0, 1.0),
          child: FractionallySizedBox(
            alignment: Alignment.topCenter,
            heightFactor: 0.46,
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    skyColor(p, phase),
                    skyColor(p, next).withValues(alpha: 0.6),
                    p.bg.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.52, 1],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The projector beam. Tries beam.frag; any failure (missing asset, no GPU support, reduced
/// motion) falls back to a static radial gradient. Never throws.
class Beam extends StatefulWidget {
  final double width; // cone half-width at the floor, 0..1
  final Color? tint;
  final bool animate;
  const Beam({super.key, this.width = 0.16, this.tint, this.animate = true});

  @override
  State<Beam> createState() => _BeamState();
}

// TickerProviderStateMixin, not Single…: the ticker is disposed and re-created whenever reduced
// motion or TickerMode flips, and the single-ticker mixin asserts on the second createTicker.
class _BeamState extends State<Beam> with TickerProviderStateMixin {
  static Future<ui.FragmentProgram?>? _program;
  ui.FragmentShader? _shader;
  Ticker? _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _program ??= ui.FragmentProgram.fromAsset(
      'assets/shaders/beam.frag',
    ).then<ui.FragmentProgram?>((p) => p, onError: (Object _) => null);
    _program!.then((p) {
      if (!mounted || p == null) return;
      try {
        setState(() => _shader = p.fragmentShader());
      } on Object {
        _shader = null;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(Beam old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    final run =
        widget.animate && !House.of(context).reducedMotion && TickerMode.valuesOf(context).enabled;
    if (run && _ticker == null) {
      var last = Duration.zero;
      _ticker = createTicker((e) {
        if ((e - last).inMilliseconds < 33) return; // 30 fps is plenty for haze
        last = e;
        setState(() => _t = e.inMilliseconds / 1000);
      })..start();
    } else if (!run && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    if (h.matinee) return const SizedBox.shrink(); // daylight: no beam, no dust
    final tint = widget.tint ?? h.palette.accent;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: h.house,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _BeamPainter(
              shader: _shader,
              time: _t,
              width: widget.width + (1 - h.house.value) * 0.46,
              house: h.house.value,
              tint: tint,
              dust: !h.reducedMotion && widget.animate,
              dprCap: Theme.of(context).platform == TargetPlatform.android ? 1.0 : 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  final ui.FragmentShader? shader;
  final double time, width, house, dprCap;
  final Color tint;
  final bool dust;
  _BeamPainter({
    required this.shader,
    required this.time,
    required this.width,
    required this.house,
    required this.tint,
    required this.dust,
    required this.dprCap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = shader;
    if (s != null) {
      try {
        s
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, time)
          ..setFloat(3, width)
          ..setFloat(4, math.sin(time * 2 * math.pi / 9) * 1.5 * math.pi / 180)
          ..setFloat(5, house)
          ..setFloat(6, tint.r)
          ..setFloat(7, tint.g)
          ..setFloat(8, tint.b)
          ..setFloat(9, 1)
          ..setFloat(10, dust ? 1 : 0);
        canvas.drawRect(Offset.zero & size, Paint()..shader = s);
        return;
      } on Object {
        // fall through to the static beam
      }
    }
    final rect = Offset.zero & size;
    final path = Path()
      ..moveTo(size.width * 0.46, -size.height * 0.06)
      ..lineTo(size.width * 0.54, -size.height * 0.06)
      ..lineTo(size.width * (0.5 + width), size.height * 1.08)
      ..lineTo(size.width * (0.5 - width), size.height * 1.08)
      ..close();
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -1.28),
          radius: 1.3,
          colors: [
            tint.withValues(alpha: 0.15),
            tint.withValues(alpha: 0.06),
            tint.withValues(alpha: 0),
          ],
          stops: const [0, 0.34, 0.66],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.time != time ||
      old.width != width ||
      old.house != house ||
      old.tint != tint ||
      old.shader != shader;
}

/// Lobby grain at 4 % (Matinee 3 %). Never in the Auditorium, never over the picture.
class Grain extends StatelessWidget {
  const Grain({super.key});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    if (h.reducedMotion) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Opacity(
          opacity: h.matinee ? Tokens.grainMatinee : Tokens.grainAuditorium,
          child: const CustomPaint(size: Size.infinite, painter: _GrainPainter()),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(8); // seeded: goldens stay stable
    final light = Paint()..color = const Color(0xFFFFFFFF);
    final dark = Paint()..color = const Color(0xFF000000);
    final n = (size.width * size.height / 90).clamp(0, 40000).toInt();
    for (var i = 0; i < n; i++) {
      canvas.drawRect(
        Rect.fromLTWH(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height, 1, 1),
        rnd.nextBool() ? light : dark,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}

/// Wall glow from the five bias-light stops: left, right and top radials around the picture.
class Walls extends StatelessWidget {
  final List<Color>? stops;
  const Walls({super.key, this.stops});

  static const _alphas = [0.14, 0.08, 0.04, 0.02, 0.0];

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    final base = stops ?? List.filled(5, p.focus);
    final boost = stops == null ? 6 / 14 : 1.0; // fallback: --focus at 6 %
    List<Color> ramp() => [
      for (var i = 0; i < 5; i++) base[i].withValues(alpha: _alphas[i] * boost),
    ];
    Widget glow(Alignment at, AlignmentGeometry align, double wf, double hf) => Align(
      alignment: align,
      child: FractionallySizedBox(
        widthFactor: wf,
        heightFactor: hf,
        child: TweenAnimationBuilder<List<Color>>(
          tween: _StopsTween(end: ramp()),
          duration: House.of(context).reducedMotion
              ? const Duration(milliseconds: 1200)
              : const Duration(milliseconds: 600),
          builder: (context, colors, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: at,
                radius: 1.1,
                colors: colors,
                stops: const [0, 0.25, 0.5, 0.72, 1],
              ),
            ),
          ),
        ),
      ),
    );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            glow(Alignment.centerRight, Alignment.centerLeft, 0.38, 1),
            glow(Alignment.centerLeft, Alignment.centerRight, 0.38, 1),
            glow(Alignment.bottomCenter, Alignment.topCenter, 1, 0.34),
          ],
        ),
      ),
    );
  }
}

class _StopsTween extends Tween<List<Color>> {
  _StopsTween({required super.end}) : super(begin: end);

  @override
  List<Color> lerp(double t) {
    final a = begin ?? end!;
    final b = end!;
    return [for (var i = 0; i < b.length; i++) Color.lerp(a[i], b[i], t)!];
  }
}
