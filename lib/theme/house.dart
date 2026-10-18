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

  /// Menus and dialogs are pushed on the app's Navigator, above every room's [House]: wrap
  /// their content with this so they keep the room's light.
  Widget carry(Widget child) => House(
    palette: palette,
    matinee: matinee,
    house: house,
    reducedMotion: reducedMotion,
    child: child,
  );

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
  // Light, not ripples: no splash, but a quiet lift on hover and a deeper one while pressed.
  splashFactory: NoSplash.splashFactory,
  highlightColor: p.ink.withValues(alpha: 0.08),
  focusColor: p.focus.withValues(alpha: 0.12),
  hoverColor: p.ink.withValues(alpha: 0.05),
  popupMenuTheme: PopupMenuThemeData(
    color: p.bgElevated,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shadowColor: const Color(0xCC000000),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Tokens.radiusMd),
      side: BorderSide(color: p.border),
    ),
    textStyle: Txt.body(Tokens.textBase, p.ink),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: p.bgElevated,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Tokens.radiusLg),
      side: BorderSide(color: p.border),
    ),
  ),
  tooltipTheme: TooltipThemeData(
    decoration: BoxDecoration(
      color: p.surface2,
      borderRadius: BorderRadius.circular(Tokens.radiusSm),
      border: Border.all(color: p.borderStrong),
    ),
    textStyle: Txt.body(Tokens.textSm, p.ink),
    waitDuration: const Duration(milliseconds: 500),
  ),
  scrollbarTheme: ScrollbarThemeData(
    thumbColor: WidgetStatePropertyAll(p.ink.withValues(alpha: 0.18)),
    radius: const Radius.circular(Tokens.radiusFull),
    thickness: const WidgetStatePropertyAll(6),
  ),
  sliderTheme: SliderThemeData(
    activeTrackColor: p.accent,
    inactiveTrackColor: p.surface2,
    thumbColor: p.accent,
    overlayColor: p.accent.withValues(alpha: 0.14),
    trackHeight: 4,
    showValueIndicator: ShowValueIndicator.never,
  ),
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
