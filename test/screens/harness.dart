// Screenshot harness: real fonts, fixed clock, faked providers. Used by screenshots_test.dart
// (tag `screenshot`), which CI renders with `--update-goldens` and publishes to the
// `screenshots` branch — the only way to look at the Flutter UI from a machine that cannot run it.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
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
import 'package:marquee/state/thumbnails.dart';
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
      subtitleLanguage: 'hi',
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
    LobbyCard(
      id: 5,
      locator: '/films/Chungking.Express.1994.720p.mkv',
      displayName: 'Chungking.Express.1994.720p.mkv',
      title: 'Chungking Express',
      year: 1994,
      container: 'matroska,webm',
      durationMs: 102 * 60000,
      resumeFraction: 0.12,
      subtitleLanguage: 'en',
      delayMs: -300,
      lastPlayedAt: now.subtract(const Duration(days: 12)),
    ),
  ];
}

// ───────────────────────────── fake film frames ─────────────────────────────

/// Writes stand-in "frames" for media ids 1, 2, 3 and 5 (4 keeps its title card) into a temp
/// folder, as the Auditorium would. Pure Dart PNGs (named .jpg like the real ones — decoders
/// sniff the bytes), so no engine call is needed to make them.
Directory fakeThumbnails() {
  final dir = Directory.systemTemp.createTempSync('marquee-thumbs');
  const scenes = {
    // id: (top colour, bottom colour, light colour, light x, light y)
    1: (0xFF1C2230, 0xFF0B0B0F, 0xFFE8C88A, 0.72, 0.30), // night street, one lamp
    2: (0xFF7FB2D8, 0xFF3F6B3A, 0xFFFFF1C9, 0.25, 0.22), // sky over a green valley
    3: (0xFFE9EEF0, 0xFF5E8C86, 0xFFFFFFFF, 0.50, 0.15), // white office, teal floor
    5: (0xFF1E3A2F, 0xFF120E15, 0xFFFF7A59, 0.35, 0.55), // neon-lit corridor
  };
  for (final MapEntry(key: id, value: s) in scenes.entries) {
    final (top, bottom, light, lx, ly) = s;
    File(thumbnailPath(dir, id)).writeAsBytesSync(_scene(320, 180, top, bottom, light, lx, ly));
  }
  return dir;
}

Uint8List _scene(int w, int h, int top, int bottom, int light, double lx, double ly) {
  int ch(int c, int shift) => (c >> shift) & 0xFF;
  double mix(int a, int b, double t) => a + (b - a) * t;
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0); // filter: none
    final t = y / (h - 1);
    for (var x = 0; x < w; x++) {
      final dx = x / w - lx;
      final dy = (y / h - ly) * h / w;
      final glow = math.exp(-(dx * dx + dy * dy) * 40);
      for (final shift in const [16, 8, 0]) {
        final base = mix(ch(top, shift), ch(bottom, shift), t);
        raw.addByte(mix(base.round(), ch(light, shift), glow * 0.85).round().clamp(0, 255));
      }
    }
  }
  return _png(w, h, raw.toBytes());
}

Uint8List _png(int w, int h, Uint8List scanlines) {
  final out = BytesBuilder()..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = Uint8List.fromList([...type.codeUnits, ...data]);
    out
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc32(body)));
  }

  chunk('IHDR', [..._u32(w), ..._u32(h), 8, 2, 0, 0, 0]); // 8-bit RGB
  chunk('IDAT', ZLibCodec().encode(scanlines));
  chunk('IEND', const []);
  return out.toBytes();
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// Decodes every frame in [dir] into the image cache with real async, BEFORE the room is
/// pumped: inside the fake-async test zone a file read never completes, so a card would show
/// its title card forever.
Future<void> _precacheFrames(WidgetTester tester, Directory dir) async {
  await tester.runAsync(() async {
    for (final f in dir.listSync().whereType<File>()) {
      final done = Completer<void>();
      final stream = FileImage(f).resolve(ImageConfiguration.empty);
      void finish() {
        if (!done.isCompleted) done.complete();
      }

      final listener = ImageStreamListener((_, _) => finish(), onError: (_, _) => finish());
      stream.addListener(listener);
      await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
      stream.removeListener(listener);
    }
  });
}

// ───────────────────────────── the room ─────────────────────────────

/// Overrides that keep every plugin and the database out of a screenshot. [thumbnails] is the
/// frame folder (see [fakeThumbnails]); an empty temp folder by default.
List<Override> screenOverrides({
  List<LobbyCard> library = const [],
  Settings settings = const Settings(),
  Directory? thumbnails,
  List<Override> extra = const [],
}) {
  FlutterSecureStorage.setMockInitialValues({});
  final db = MarqueeDatabase(NativeDatabase.memory());
  final thumbs = thumbnails ?? Directory.systemTemp.createTempSync('marquee-thumbs');
  return [
    databaseProvider.overrideWithValue(db),
    libraryProvider.overrideWith((ref) => Stream.value(library)),
    settingsProvider.overrideWith(() => FakeSettings(settings)),
    thumbnailDirProvider.overrideWith((ref) async => thumbs),
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
/// `goldens/<name>.png`. [platform] makes the room believe it runs there (desktop-only hints
/// such as "drag a file here"); [thumbnails] is decoded up front so frames show.
Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget child, {
  Size size = kDesktop,
  DateTime? at,
  List<Override> overrides = const [],
  bool matinee = false,
  TargetPlatform? platform,
  Directory? thumbnails,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  await loadAppFonts();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (thumbnails != null) await _precacheFrames(tester, thumbnails);
  debugDefaultTargetPlatformOverride = platform;
  try {
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
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
