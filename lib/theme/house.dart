// HOUSE LIGHTS runtime theme: the palette for the current room and the single `--house`
// value (1 = house up, 0 = dark) that drives every lighting change.
import 'package:flutter/material.dart';

import 'tokens.dart';

class House extends InheritedWidget {
  final HousePalette palette;
  final bool matinee;
  final Animation<double> house; // THE one value
  final bool reducedMotion;

  const House({
    super.key,
    required this.palette,
    required this.matinee,
    required this.house,
    required this.reducedMotion,
    required super.child,
  });

  static House of(BuildContext context) {
    final h = context.dependOnInheritedWidgetOfExactType<House>();
    assert(h != null, 'No House above this context');
    return h!;
  }

  static HousePalette paletteOf(BuildContext context) => of(context).palette;

  @override
  bool updateShouldNotify(House old) =>
      palette != old.palette ||
      matinee != old.matinee ||
      house != old.house ||
      reducedMotion != old.reducedMotion;
}

abstract final class Txt {
  static TextStyle display(double size, Color color, {FontWeight weight = FontWeight.w900}) =>
      TextStyle(
        fontFamily: Tokens.fontDisplay,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: Tokens.leadingTight,
        letterSpacing:
            size * (size >= Tokens.text3Xl ? Tokens.trackingDisplayLg : Tokens.trackingDisplay),
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle body(double size, Color color, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: Tokens.fontBody,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: Tokens.leadingBody,
      );

  static TextStyle mono(double size, Color color, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: Tokens.fontMono,
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures(), FontFeature.liningFigures()],
      );

  /// Small uppercase labels: xs, +0.08 em, weight 500, --ink-faint.
  static TextStyle label(Color color) => TextStyle(
    fontFamily: Tokens.fontBody,
    fontSize: Tokens.textXs,
    fontWeight: FontWeight.w500,
    letterSpacing: Tokens.textXs * Tokens.trackingLabel,
    color: color,
  );
}

ThemeData marqueeTheme(HousePalette p, {required bool matinee}) => ThemeData(
  useMaterial3: true,
  brightness: matinee ? Brightness.light : Brightness.dark,
  scaffoldBackgroundColor: p.bg,
  canvasColor: p.bg,
  fontFamily: Tokens.fontBody,
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
  focusColor: p.focus.withValues(alpha: 0.12),
  hoverColor: p.surface2,
  colorScheme: ColorScheme(
    brightness: matinee ? Brightness.light : Brightness.dark,
    primary: p.accent,
    onPrimary: p.accentInk,
    secondary: p.accent2,
    onSecondary: p.ink,
    error: p.danger,
    onError: p.accentInk,
    surface: p.bgElevated,
    onSurface: p.ink,
  ),
  textSelectionTheme: TextSelectionThemeData(
    cursorColor: p.accent,
    selectionColor: p.accent.withValues(alpha: 0.3),
  ),
);
