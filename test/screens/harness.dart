// Screenshot harness: real fonts, fixed clock, faked providers. Used by screenshots_test.dart
// (tag `screenshot`), which CI renders with `--update-goldens` and publishes to the
// `screenshots` branch — the only way to look at the Flutter UI from a machine that cannot run it.
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/db/database.dart';
import 'package:marquee/engine/models/media.dart';
import 'package:marquee/engine/models/settings.dart';
import 'package:marquee/state/providers.dart';
import 'package:marquee/theme/house.dart';
import 'package:marquee/theme/tokens.dart';

const kDesktop = Size(1280, 800);
const kPhone = Size(412, 915);
const kPhoneLandscape = Size(915, 412);

/// 21:30 on a Saturday: night sky, deterministic copy.
final kNight = DateTime(2026, 10, 17, 21, 30);
final kDay = DateTime(2026, 10, 17, 13, 10);

bool _fontsLoaded = false;

Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  const families = {
    'Big Shoulders Display': ['assets/fonts/BigShouldersDisplay-Variable.ttf'],
    'Geist': ['assets/fonts/Geist-Variable.ttf'],
    'Geist Mono': ['assets/fonts/GeistMono-Variable.ttf'],
    'Noto Sans': ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf'],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load(f));
    }
    await loader.load();
  }
}

class FakeSettings extends SettingsNotifier {
  final Settings initial;
  FakeSettings([this.initial = const Settings()]);
  @override
  Future<Settings> build() async => initial;
  @override
  Future<void> save(Settings s) async => state = AsyncData(s);
}

/// A small, believable library for the Lobby.
List<LobbyCard> sampleLibrary() {
  final now = DateTime(2026, 10, 17, 21);
  return [
    LobbyCard(
      id: 1,
      locator: '/films/The.Third.Man.1949.1080p.BluRay.x264.mkv',
      displayName: 'The.Third.Man.1949.1080p.BluRay.x264.mkv',
      title: 'The Third Man',
      year: 1949,
      container: 'matroska,webm',
      durationMs: 104 * 60000,
      resumeFraction: 0.42,
      subtitleLanguage: 'en',
      delayMs: 150,
      lastPlayedAt: now,
    ),
    LobbyCard(
      id: 2,
      locator: '/films/Spirited.Away.2001.1080p.mkv',
      displayName: 'Spirited.Away.2001.1080p.mkv',
      title: 'Spirited Away',
      year: 2001,
      container: 'matroska,webm',
      durationMs: 125 * 60000,
      resumeFraction: 0,
      finished: true,
      subtitleLanguage: 'en',
      lastPlayedAt: now.subtract(const Duration(days: 1)),
    ),
    LobbyCard(
      id: 3,
      locator: '/shows/Severance.S02E03.1080p.WEB.h264.mkv',
      displayName: 'Severance.S02E03.1080p.WEB.h264.mkv',
      title: 'Severance',
      container: 'matroska,webm',
      durationMs: 48 * 60000,
      resumeFraction: 0.81,
      lastPlayedAt: now.subtract(const Duration(days: 2)),
    ),
    LobbyCard(
      id: 4,
      locator: '/films/holiday_2024_beach.mp4',
      displayName: 'holiday_2024_beach.mp4',
      container: 'mov,mp4,m4a,3gp,3g2,mj2',
      durationMs: 6 * 60000,
      resumeFraction: 0,
      lastPlayedAt: now.subtract(const Duration(days: 9)),
    ),
  ];
}

/// Overrides that keep every plugin and the database out of a screenshot.
List<Override> screenOverrides({
  List<LobbyCard> library = const [],
  Settings settings = const Settings(),
  List<Override> extra = const [],
}) {
  FlutterSecureStorage.setMockInitialValues({});
  final db = MarqueeDatabase(NativeDatabase.memory());
  return [
    databaseProvider.overrideWithValue(db),
    libraryProvider.overrideWith((ref) => Stream.value(library)),
    settingsProvider.overrideWith(() => FakeSettings(settings)),
    ...extra,
  ];
}

/// Wraps [child] the way `HouseLights` does, without the window bar and plugins.
Widget roomFor(Widget child, {bool matinee = false}) {
  final palette = matinee ? Tokens.matinee : Tokens.auditorium;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: marqueeTheme(palette, matinee: matinee),
    home: House(
      palette: palette,
      matinee: matinee,
      house: const AlwaysStoppedAnimation(1),
      reducedMotion: true,
      child: Material(
        type: MaterialType.transparency,
        child: ColoredBox(color: palette.bg, child: child),
      ),
    ),
  );
}

/// Renders [child] at [size] and compares it with (or, with --update-goldens, writes)
/// `goldens/<name>.png`.
Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget child, {
  Size size = kDesktop,
  DateTime? at,
  List<Override> overrides = const [],
  bool matinee = false,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  await loadAppFonts();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await withClock(Clock.fixed(at ?? kNight), () async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: roomFor(child, matinee: matinee),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));
    if (act != null) await act(tester);
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('goldens/$name.png'));
  });
  // Drop the tree (and any repeating animation timers) before the test ends.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}
