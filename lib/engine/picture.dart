// What the viewer may do to ONE film's picture: the four levels, a quarter-turn rotation, a
// zoom and deinterlacing. A value type; the player layer turns it into mpv properties
// ([PictureAdjust.mpvProperties]) and the session remembers it per film.
import 'dart:math' as math;

class PictureAdjust {
  /// mpv's own range for brightness, contrast, saturation and gamma.
  static const minLevel = -100;
  static const maxLevel = 100;

  /// mpv `video-zoom` is log2: -1 is half size, 2 is four times.
  static const minZoom = -1.0;
  static const maxZoom = 2.0;

  /// One press of Zoom in / Zoom out.
  static const zoomStep = 0.25;

  final int brightness, contrast, saturation, gamma;

  /// Clockwise, one of 0 / 90 / 180 / 270.
  final int rotation;
  final double zoom;
  final bool deinterlace;

  const PictureAdjust._({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.gamma = 0,
    this.rotation = 0,
    this.zoom = 0,
    this.deinterlace = false,
  });

  /// The film as it is.
  static const neutral = PictureAdjust._();

  /// Every value is brought into range, so no caller can hand mpv a number it refuses.
  factory PictureAdjust({
    int brightness = 0,
    int contrast = 0,
    int saturation = 0,
    int gamma = 0,
    int rotation = 0,
    double zoom = 0,
    bool deinterlace = false,
  }) => PictureAdjust._(
    brightness: _level(brightness),
    contrast: _level(contrast),
    saturation: _level(saturation),
    gamma: _level(gamma),
    rotation: _quarterTurn(rotation),
    zoom: _zoom(zoom),
    deinterlace: deinterlace,
  );

  static int _level(int v) => v.clamp(minLevel, maxLevel).toInt();

  /// Anything that is not a quarter turn is no turn at all.
  static int _quarterTurn(int degrees) {
    final d = degrees % 360;
    return d % 90 == 0 ? d : 0;
  }

  static double _zoom(double v) {
    if (v.isNaN) return 0;
    // Two decimals: what mpv is sent, so equal values stay equal after a round trip.
    return (v.clamp(minZoom, maxZoom) * 100).round() / 100;
  }

  bool get isNeutral => this == neutral;

  /// Any of the four sliders is off its centre.
  bool get hasLevels => brightness != 0 || contrast != 0 || saturation != 0 || gamma != 0;

  /// The zoom as people say it: 100 % is the film's own size.
  int get zoomPercent => (math.pow(2, zoom) * 100).round();

  PictureAdjust copyWith({
    int? brightness,
    int? contrast,
    int? saturation,
    int? gamma,
    int? rotation,
    double? zoom,
    bool? deinterlace,
  }) => PictureAdjust(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    gamma: gamma ?? this.gamma,
    rotation: rotation ?? this.rotation,
    zoom: zoom ?? this.zoom,
    deinterlace: deinterlace ?? this.deinterlace,
  );

  /// A quarter turn clockwise.
  PictureAdjust get rotated => copyWith(rotation: rotation + 90);

  PictureAdjust zoomedBy(double delta) => copyWith(zoom: zoom + delta);

  /// The sliders back at their centres; rotation, zoom and deinterlacing stay.
  PictureAdjust get levelsReset => copyWith(brightness: 0, contrast: 0, saturation: 0, gamma: 0);

  /// The mpv properties that draw this adjustment, by name.
  Map<String, String> get mpvProperties => {
    'brightness': '$brightness',
    'contrast': '$contrast',
    'saturation': '$saturation',
    'gamma': '$gamma',
    'video-rotate': '$rotation',
    'video-zoom': zoom.toStringAsFixed(2),
    'deinterlace': deinterlace ? 'yes' : 'no',
  };

  Map<String, Object?> toJson() => {
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'gamma': gamma,
    'rotation': rotation,
    'zoom': zoom,
    'deinterlace': deinterlace,
  };

  /// Tolerant: anything missing, mistyped or out of range falls back to neutral for that field.
  factory PictureAdjust.fromJson(Object? json) {
    if (json is! Map) return neutral;
    int whole(String k) => json[k] is num ? (json[k] as num).round() : 0;
    final z = json['zoom'];
    return PictureAdjust(
      brightness: whole('brightness'),
      contrast: whole('contrast'),
      saturation: whole('saturation'),
      gamma: whole('gamma'),
      rotation: whole('rotation'),
      zoom: z is num ? z.toDouble() : 0,
      deinterlace: json['deinterlace'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PictureAdjust &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.gamma == gamma &&
      other.rotation == rotation &&
      other.zoom == zoom &&
      other.deinterlace == deinterlace;

  @override
  int get hashCode =>
      Object.hash(brightness, contrast, saturation, gamma, rotation, zoom, deinterlace);
}
