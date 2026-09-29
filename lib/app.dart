// The app shell: one room at a time, and ONE AnimationController for the house lights.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'engine/models/settings.dart';
import 'platform/files.dart';
import 'platform/pip.dart';
import 'platform/window.dart';
import 'state/providers.dart';
import 'state/session.dart';
import 'theme/house.dart';
import 'theme/tokens.dart';
import 'ui/auditorium/auditorium_screen.dart';
import 'ui/components/room.dart';
import 'ui/lobby/lobby_screen.dart';
import 'ui/ticket_office/ticket_office_screen.dart';

class MarqueeApp extends ConsumerWidget {
  const MarqueeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsValueProvider);
    final room = ref.watch(roomProvider);
    final platformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final phase = skyPhaseAt(clock.now());
    final matinee =
        room != Room.auditorium &&
        switch (settings.lobbyTheme) {
          LobbyTheme.matinee => true,
          LobbyTheme.auditorium => false,
          LobbyTheme.auto => !platformDark && phase == SkyPhase.day,
        };
    final palette = matinee ? Tokens.matinee : Tokens.auditorium;
    return MaterialApp(
      title: 'Marquee',
      debugShowCheckedModeBanner: false,
      theme: marqueeTheme(palette, matinee: matinee),
      home: HouseLights(palette: palette, matinee: matinee),
    );
  }
}

class HouseLights extends ConsumerStatefulWidget {
  final HousePalette palette;
  final bool matinee;
  const HouseLights({super.key, required this.palette, required this.matinee});

  @override
  ConsumerState<HouseLights> createState() => _HouseLightsState();
}

class _HouseLightsState extends ConsumerState<HouseLights> with SingleTickerProviderStateMixin {
  // THE one tween: --house 1 → 0 over 900 ms on --ease-house. Everything lit reads it.
  late final AnimationController houseController = AnimationController(
    vsync: this,
    duration: Tokens.durHouse,
    value: 1,
  );
  late final Animation<double> _house = CurvedAnimation(
    parent: houseController,
    curve: Tokens.easeHouse,
  );
  bool _dragOver = false;

  @override
  void dispose() {
    houseController.dispose();
    super.dispose();
  }

  void _applyHouse(bool down, bool reduced) {
    houseController.duration = reduced ? const Duration(milliseconds: 240) : Tokens.durHouse;
    if (down) {
      unawaited(houseController.reverse());
    } else {
      unawaited(houseController.forward());
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final room = ref.watch(roomProvider);
    ref.listen(houseDownProvider, (_, down) {
      _applyHouse(down, reduced);
      unawaited(down ? WakelockPlus.enable() : WakelockPlus.disable()); // keep-awake: playback only
      if (Platform.isAndroid) {
        unawaited(
          SystemChrome.setEnabledSystemUIMode(
            down ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
          ),
        );
      }
      unawaited(setLobbyChrome(lobby: !down));
      unawaited(ref.read(pipProvider.notifier).setAutoEnter(enabled: down));
    });
    ref.listen(fullscreenProvider, (_, full) => unawaited(setFullscreen(full)));

    final inAuditorium = room == Room.auditorium;
    final palette = inAuditorium ? Tokens.auditorium : widget.palette;
    SystemChrome.setSystemUIOverlayStyle(
      (widget.matinee && !inAuditorium ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
          .copyWith(
            statusBarColor: const Color(0x00000000),
            systemNavigationBarColor: const Color(0x00000000),
          ),
    );

    return House(
      palette: palette,
      matinee: widget.matinee && !inAuditorium,
      house: _house,
      reducedMotion: reduced,
      // Every InkWell/InkResponse/TextField needs a Material ancestor; there is no Scaffold.
      child: Material(
        type: MaterialType.transparency,
        child: ColoredBox(
          color: palette.bg,
          child: Column(
            children: [
              if (Platform.isWindows && !ref.watch(fullscreenProvider)) const WindowBar(),
              Expanded(
                child: DropTarget(
                  enable: room != Room.auditorium,
                  onDragEntered: (_) => setState(() => _dragOver = true),
                  onDragExited: (_) => setState(() => _dragOver = false),
                  onDragDone: (d) async {
                    setState(() => _dragOver = false);
                    final path = d.files.firstOrNull?.path;
                    if (path == null) return;
                    final f = await fileFromPath(path);
                    if (f != null) await ref.read(sessionProvider.notifier).open(f);
                  },
                  child: AnimatedSwitcher(
                    duration: reduced ? const Duration(milliseconds: 240) : Tokens.durSlow,
                    switchInCurve: Tokens.easeOut,
                    child: switch (room) {
                      Room.lobby => LobbyScreen(key: const ValueKey('lobby'), dragOver: _dragOver),
                      Room.auditorium => const AuditoriumScreen(key: ValueKey('auditorium')),
                      Room.ticketOffice => const TicketOfficeScreen(key: ValueKey('office')),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
