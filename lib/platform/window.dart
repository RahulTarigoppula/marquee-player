// Windows chrome: a frameless window whose drag region is the marquee strip, three bulb
// window controls, and geometry that persists between runs (app_state.window_bounds).
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../db/database.dart';
import '../theme/house.dart';
import '../theme/tokens.dart';
import '../ui/components/primitives.dart';

bool get _desktop => Platform.isWindows;

/// Restores the saved bounds and shows the window. The database opens (on its own isolate)
/// while the window manager starts up: the two waits overlap instead of adding up.
Future<void> initWindow(MarqueeDatabase db) async {
  if (!_desktop) return;
  final bounds = db.readState('window_bounds').then<Object?>((b) => b, onError: (Object _) => null);
  await windowManager.ensureInitialized();
  final b = await bounds;
  const opts = WindowOptions(
    title: 'Marquee',
    minimumSize: Size(720, 480),
    size: Size(1280, 800),
    center: true,
    backgroundColor: Tokens.bg,
    titleBarStyle: TitleBarStyle.hidden,
  );
  // waitUntilReadyToShow calls its callback without waiting for it: the Completer is what
  // makes "the first frame is held until the window is in place" true.
  final placed = Completer<void>();
  var maximized = false;
  await windowManager.waitUntilReadyToShow(opts, () async {
    try {
      if (b is Map) {
        final x = (b['x'] as num?)?.toDouble();
        final y = (b['y'] as num?)?.toDouble();
        final w = (b['w'] as num?)?.toDouble();
        final h = (b['h'] as num?)?.toDouble();
        if (x != null && y != null && w != null && h != null && w >= 720 && h >= 480) {
          final saved = Rect.fromLTWH(x, y, w, h);
          // A window last used on a monitor that is gone stays at the centred default.
          if (boundsReachable(saved, _displaySizes())) {
            await windowManager.setBounds(saved);
          } else {
            await windowManager.setSize(saved.size);
            await windowManager.center();
          }
        }
        maximized = b['maximized'] == true;
        if (maximized) await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    } on Object {
      // A window at its default size is better than no window.
    } finally {
      placed.complete();
    }
  });
  await placed.future;
  if (maximized) {
    // The runner shows the window again on the first frame (SW_SHOWNORMAL), which undoes a
    // maximise made before it. Put it back once that frame is out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(milliseconds: 200), () async {
        try {
          if (!await windowManager.isMaximized()) await windowManager.maximize();
        } on Object {
          // It stays a normal window.
        }
      });
    });
  }
  windowManager.addListener(_BoundsSaver(db));
  // Closing the window saves the resume point first (see [onWindowClosing]).
  await windowManager.setPreventClose(true);
  windowManager.addListener(_CloseGuard());
}

/// The connected displays, in logical pixels. Flutter knows their sizes, not where they sit.
List<Size> _displaySizes() => [
  for (final d in PlatformDispatcher.instance.displays)
    if (d.devicePixelRatio > 0) d.size / d.devicePixelRatio,
];

/// Whether a window at [bounds] could be reached with the mouse: enough of its title strip
/// must lie on a display. With ONE display that is exact (it sits at the origin). With
/// several, their arrangement is unknown here, so only bounds no arrangement of them could
/// contain are refused. No display list at all (an embedder that sends none) refuses nothing.
bool boundsReachable(Rect bounds, List<Size> displays) {
  if (displays.isEmpty) return true;
  const grip = Size(160, 40); // this much of the title strip must be on screen
  final Rect desk;
  if (displays.length == 1) {
    desk = Offset.zero & displays.single;
  } else {
    var w = 0.0, h = 0.0;
    for (final d in displays) {
      w += d.width;
      h += d.height;
    }
    desk = Rect.fromLTRB(-w, -h, w, h);
  }
  final strip = Rect.fromLTWH(bounds.left, bounds.top, bounds.width, grip.height);
  final seen = strip.intersect(desk);
  // Half the strip's height is enough: a window snapped to the top edge sits a few pixels
  // above it.
  return seen.width >= grip.width && seen.height >= grip.height / 2;
}

/// Runs before the window closes (the resume point, the session); the window is destroyed
/// when it completes, or after two seconds whatever happens.
Future<void> Function()? onWindowClosing;

class _CloseGuard with WindowListener {
  bool _closing = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await onWindowClosing?.call().timeout(const Duration(seconds: 2));
    } on Object {
      // Never keep a window the user closed.
    }
    await windowManager.destroy();
  }
}

/// Brings the window forward (after a drop, or a file forwarded by a second launch).
Future<void> focusWindow() async {
  if (!_desktop) return;
  try {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  } on Object {
    // Not worth a word.
  }
}

class _BoundsSaver with WindowListener {
  final MarqueeDatabase db;
  Timer? _debounce;
  _BoundsSaver(this.db);

  void _save() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        // Fullscreen bounds are the monitor's: restoring them would trap the next launch.
        if (await windowManager.isFullScreen()) return;
        if (await windowManager.isMaximized()) {
          // Only the flag: the saved rectangle stays the NORMAL window's, so un-maximising
          // after the next launch goes back to a window, not to a screen-sized one.
          final old = await db.readState('window_bounds');
          await db.writeState('window_bounds', {
            if (old is Map) ...old.cast<String, Object?>(),
            'maximized': true,
          });
          return;
        }
        // A minimised window reports a parking position far off screen.
        if (await windowManager.isMinimized()) return;
        final r = await windowManager.getBounds();
        await db.writeState('window_bounds', {
          'x': r.left,
          'y': r.top,
          'w': r.width,
          'h': r.height,
          'maximized': false,
        });
      } on Object {
        // The window is closing: the last saved place stands.
      }
    });
  }

  @override
  void onWindowMoved() => _save();
  @override
  void onWindowResized() => _save();
  @override
  void onWindowMaximize() => _save();
  @override
  void onWindowUnmaximize() => _save();
}

Future<void> setFullscreen(bool full) async {
  if (_desktop) {
    await windowManager.setFullScreen(full);
  } else if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(
      full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}

/// Windows: the film stays above every other window (a film in the corner while you work).
/// Nothing to do elsewhere: Android has picture in picture for that.
Future<void> setAlwaysOnTop(bool on) async {
  if (!_desktop) return;
  try {
    await windowManager.setAlwaysOnTop(on);
  } on Object {
    // The window is going away, or the plugin is missing: it simply stays as it was.
  }
}

/// "Keep on top". The session turns it off when the film closes, so the Lobby never floats.
class PinnedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool on) {
    if (on == state) return;
    state = on;
    unawaited(setAlwaysOnTop(on));
  }

  void toggle() => set(!state);
}

final pinnedProvider = NotifierProvider<PinnedNotifier, bool>(PinnedNotifier.new);

/// The title bar: a thin strip that drags the window, with minimise / maximise / close bulbs.
class WindowBar extends StatelessWidget {
  const WindowBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = House.paletteOf(context);
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: Tokens.space4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'MARQUEE',
                    style: Txt.display(Tokens.textSm, p.inkMuted, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          _WindowBulb(label: 'Minimise', onTap: () => unawaited(windowManager.minimize())),
          _WindowBulb(
            label: 'Maximise',
            onTap: () async => await windowManager.isMaximized()
                ? windowManager.unmaximize()
                : windowManager.maximize(),
          ),
          _WindowBulb(label: 'Close', onTap: () => unawaited(windowManager.close())),
          const SizedBox(width: Tokens.space2),
        ],
      ),
    );
  }
}

class _WindowBulb extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _WindowBulb({required this.label, required this.onTap});

  @override
  State<_WindowBulb> createState() => _WindowBulbState();
}

class _WindowBulbState extends State<_WindowBulb> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        label: widget.label,
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(child: Bulb(lit: _hover, size: 9)),
          ),
        ),
      ),
    ),
  );
}
