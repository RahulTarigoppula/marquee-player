// Windows chrome: a frameless window whose drag region is the marquee strip, three bulb
// window controls, and geometry that persists between runs (app_state.window_bounds).
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../db/database.dart';
import '../theme/house.dart';
import '../theme/tokens.dart';
import '../ui/components/primitives.dart';

bool get _desktop => Platform.isWindows;

Future<void> initWindow(MarqueeDatabase db) async {
  if (!_desktop) return;
  await windowManager.ensureInitialized();
  final b = await db.readState('window_bounds');
  const opts = WindowOptions(
    title: 'Marquee',
    minimumSize: Size(720, 480),
    size: Size(1280, 800),
    center: true,
    backgroundColor: Tokens.bg,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(opts, () async {
    if (b is Map) {
      final x = (b['x'] as num?)?.toDouble();
      final y = (b['y'] as num?)?.toDouble();
      final w = (b['w'] as num?)?.toDouble();
      final h = (b['h'] as num?)?.toDouble();
      if (x != null && y != null && w != null && h != null && w >= 720 && h >= 480) {
        await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
      }
      if (b['maximized'] == true) await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
  });
  windowManager.addListener(_BoundsSaver(db));
}

class _BoundsSaver with WindowListener {
  final MarqueeDatabase db;
  Timer? _debounce;
  _BoundsSaver(this.db);

  void _save() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final r = await windowManager.getBounds();
      await db.writeState('window_bounds', {
        'x': r.left,
        'y': r.top,
        'w': r.width,
        'h': r.height,
        'maximized': await windowManager.isMaximized(),
      });
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

/// The Lobby is opaque on purpose: the picture is never composited over a translucent surface,
/// and a flat --bg Lobby is the documented fallback for Mica (decoration, not a feature).
Future<void> setLobbyChrome({required bool lobby}) async {}

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
