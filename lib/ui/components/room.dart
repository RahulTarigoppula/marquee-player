// The room: sky band (time of day), the projector beam (shader with a never-throwing
// fallback), lobby grain and the bias-light walls. All of it is light, none of it is chrome.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show listEquals;
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
  /// The local time the sky shows; the Lobby passes its minute tick so the sky moves while the
  /// app stays open. Defaults to now.
  final DateTime? now;
  const SkyBand({super.key, this.now});

  @override
  Widget build(BuildContext context) {
    final h = House.of(context);
    final p = h.palette;
    final phase = skyPhaseAt(now ?? clock.now());
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
    // Its own layer: the 30 fps haze must not repaint the grain, the sky or the cards.
    return RepaintBoundary(
      child: IgnorePointer(
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
    // Its own layer, so nothing animating nearby (the beam, a hovered card) repaints it.
    return RepaintBoundary(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(
            opacity: h.matinee ? Tokens.grainMatinee : Tokens.grainAuditorium,
            child: const CustomPaint(size: Size.infinite, painter: _GrainPainter()),
          ),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  static const _tileSize = 256;
  static ui.Image? _tile;
  static bool _tileFailed = false;

  /// Scatters seeded 1 px specks (one per 90 px², as before) over [size].
  static void _speckle(Canvas canvas, Size size) {
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

  /// One 256 px tile, recorded once per process and repeated by an image shader: a single
  /// draw call instead of up to 40 000 rects per paint.
  static ui.Image? _grainTile() {
    if (_tile != null || _tileFailed) return _tile;
    try {
      final recorder = ui.PictureRecorder();
      _speckle(Canvas(recorder), const Size(_tileSize + 0.0, _tileSize + 0.0));
      final picture = recorder.endRecording();
      _tile = picture.toImageSync(_tileSize, _tileSize);
      picture.dispose();
    } on Object {
      _tileFailed = true;
    }
    return _tile;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tile = _grainTile();
    if (tile == null) {
      _speckle(canvas, size);
      return;
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        ),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}

/// Wall glow from the five bias-light stops: left, right and top radials around the picture.
///
/// The lerp restarts only when the colours really change (a new bias sample), never because the
/// parent rebuilt; at rest the three gradients sit in their own layer and are not repainted.
class Walls extends StatefulWidget {
  final List<Color>? stops;
  const Walls({super.key, this.stops});

  static const _alphas = [0.14, 0.08, 0.04, 0.02, 0.0];

  @override
  State<Walls> createState() => _WallsState();
}

class _WallsState extends State<Walls> with SingleTickerProviderStateMixin {
  late final AnimationController _lerp = AnimationController(vsync: this, value: 1);
  List<Color>? _from;
  List<Color>? _to;

  List<Color> _ramp() {
    final p = House.paletteOf(context);
    final stops = widget.stops;
    final base = stops != null && stops.length >= 5 ? stops : List.filled(5, p.focus);
    final boost = identical(base, stops) ? 1.0 : 6 / 14; // fallback: --focus at 6 %
    return [for (var i = 0; i < 5; i++) base[i].withValues(alpha: Walls._alphas[i] * boost)];
  }

  List<Color> get _current {
    final to = _to!;
    final from = _from ?? to;
    final t = _lerp.value;
    if (t >= 1) return to;
    return [for (var i = 0; i < to.length; i++) Color.lerp(from[i], to[i], t)!];
  }

  void _sync() {
    final target = _ramp();
    final to = _to;
    if (to == null) {
      _from = _to = target;
      return;
    }
    if (listEquals(to, target)) return;
    _from = _current;
    _to = target;
    _lerp.duration = House.of(context).reducedMotion
        ? const Duration(milliseconds: 1200)
        : const Duration(milliseconds: 600);
    _lerp.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Walls old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _lerp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: CustomPaint(size: Size.infinite, painter: _WallsPainter(this)),
      ),
    ),
  );
}

class _WallsPainter extends CustomPainter {
  final _WallsState state;
  _WallsPainter(this.state) : super(repaint: state._lerp);

  static const _stops = [0.0, 0.25, 0.5, 0.72, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final colors = state._current;
    void glow(Rect rect, Alignment at) => canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: at,
          radius: 1.1,
          colors: colors,
          stops: _stops,
        ).createShader(rect),
    );
    final w = size.width;
    final h = size.height;
    glow(Rect.fromLTWH(0, 0, w * 0.38, h), Alignment.centerRight);
    glow(Rect.fromLTWH(w * 0.62, 0, w * 0.38, h), Alignment.centerLeft);
    glow(Rect.fromLTWH(0, 0, w, h * 0.34), Alignment.bottomCenter);
  }

  @override
  bool shouldRepaint(_WallsPainter old) => old.state != state;
}
