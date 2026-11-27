// The app shell: one room at a time, and ONE AnimationController for the house lights.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:clock/clock.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine/filename.dart';
import 'engine/models/settings.dart';
import 'platform/files.dart';
import 'platform/pip.dart';
import 'platform/window.dart';
import 'state/library.dart';
import 'state/notice.dart';
import 'state/now_playing.dart';
import 'state/providers.dart';
import 'state/session.dart';
import 'state/updates.dart';
import 'theme/house.dart';
import 'theme/tokens.dart';
import 'ui/auditorium/auditorium_screen.dart';
import 'ui/components/room.dart';
import 'ui/lobby/lobby_screen.dart';
import 'ui/ticket_office/ticket_office_screen.dart';

class MarqueeApp extends ConsumerWidget {
  const MarqueeApp({super.key});

  /// Two themes exist; each is built once, so a rebuild never hands MaterialApp a "new" one
  /// (which would animate every themed widget for 200 ms).
  static final _themes = <bool, ThemeData>{};
  static ThemeData _theme(bool matinee) => _themes[matinee] ??= marqueeTheme(
    matinee ? Tokens.matinee : Tokens.auditorium,
    matinee: matinee,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ONLY what decides the light: a volume save or a subtitle setting never rebuilds the app.
    final lobbyTheme = ref.watch(settingsValueProvider.select((s) => s.lobbyTheme));
    final inAuditorium = ref.watch(roomProvider.select((r) => r == Room.auditorium));
    final platformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final matinee =
        !inAuditorium &&
        switch (lobbyTheme) {
          LobbyTheme.matinee => true,
          LobbyTheme.auditorium => false,
          LobbyTheme.auto => !platformDark && skyPhaseAt(clock.now()) == SkyPhase.day,
        };
    return MaterialApp(
      title: 'Marquee',
      debugShowCheckedModeBanner: false,
      theme: _theme(matinee),
      home: HouseLights(palette: matinee ? Tokens.matinee : Tokens.auditorium, matinee: matinee),
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
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_globalKeys);
    // Backgrounded (Home, the app switcher, a call) or hidden: keep the resume point honest.
    // The device library notes when the app left, and looks for new videos after a while away.
    _lifecycle = AppLifecycleListener(
      onPause: _paused,
      onHide: () {
        _saveResume();
        _away();
      },
      onInactive: () {
        if (Platform.isAndroid) _saveResume();
        _away();
      },
      onResume: () => ref.read(deviceLibraryProvider.notifier).cameBack(),
    );
    onWindowClosing = () => ref.read(sessionProvider.notifier).close(toLobby: false);
    // The library's start-up scan begins once the Lobby's first frame is on screen, whichever
    // tab is open (the player asks it for the next episode too).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(deviceLibraryProvider);
    });
    // The once-a-day update check (opt-in, off by default) only exists once this is read.
    ref.read(autoUpdateCheckProvider);
    // Android: the lock screen, the notification shade and headset buttons follow the film.
    ref.read(nowPlayingProvider);
    // A PiP window that closes is followed at once by the app stopping: remember when, so
    // [_paused] can tell "the viewer closed the film" from "the screen went off".
    ref.listenManual(pipProvider, (was, now) {
      if (!(was ?? false) || now) return;
      _pipEndedAt = clock.now();
      // Android may stop the app BEFORE it says the window has gone: [_paused] then saw a PiP
      // window and left the film alone. A window that goes while the app is already unseen
      // was closed (going back to full screen makes the app visible first).
      final life = WidgetsBinding.instance.lifecycleState;
      if (life == AppLifecycleState.paused || life == AppLifecycleState.hidden) {
        ref.read(sessionProvider.notifier).pauseUnseen();
      }
    });
    // The Lobby's pictures are no use behind a film, and libmpv wants the memory.
    ref.listenManual(roomProvider, (_, room) {
      if (room == Room.auditorium) PaintingBinding.instance.imageCache.clear();
    });
  }

  DateTime? _pipEndedAt;

  void _away() => ref.read(deviceLibraryProvider.notifier).wentAway();

  /// Android: stopped (Home without PiP, the screen off, a closed PiP window) means unseen, so
  /// the film pauses, unless Settings says its sound carries on. A PiP window on screen only
  /// makes the app inactive, never paused; closing that window is always "stop", whatever the
  /// setting. This is the ONLY place a film is paused for being unseen: the Video widget's own
  /// pause-in-background is switched off (PictureLayer), or the setting could never work.
  void _paused() {
    _saveResume();
    _away();
    if (!Platform.isAndroid) return;
    final ended = _pipEndedAt;
    final pipClosed = ended != null && clock.now().difference(ended) < const Duration(seconds: 2);
    if (pipClosed || !ref.read(settingsValueProvider).backgroundPlay) {
      ref.read(sessionProvider.notifier).pauseUnseen();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeys);
    _lifecycle.dispose();
    onWindowClosing = null;
    houseController.dispose();
    super.dispose();
  }

  void _saveResume() => unawaited(ref.read(sessionProvider.notifier).saveResumeNow());

  /// Ctrl+O opens a film from any room (and replaces the one playing).
  bool _globalKeys(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyO) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    unawaited(() async {
      final f = await ref.read(pipProvider.notifier).withoutAutoEnter(pickVideo);
      if (f != null) await ref.read(sessionProvider.notifier).open(f);
    }());
    return true;
  }

  void _applyHouse(bool down, bool reduced) {
    houseController.duration = reduced ? const Duration(milliseconds: 240) : Tokens.durHouse;
    if (down) {
      unawaited(houseController.reverse());
    } else {
      unawaited(houseController.forward());
    }
  }

  Future<void> _drop(DropDoneDetails d) async {
    setState(() => _dragOver = false);
    final path = d.files.firstOrNull?.path;
    if (path == null) return;
    unawaited(focusWindow());
    final session = ref.read(sessionProvider.notifier);
    if (isSubtitleFile(path)) {
      // A subtitle dropped on the picture attaches to the film; anywhere else it is no film.
      if (ref.read(sessionProvider) != null) {
        await session.loadSubtitleFile(path);
      } else {
        ref.read(noticeProvider.notifier).show('Drop a video first, then its subtitles.');
      }
      return;
    }
    await session.openLocator(path);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final room = ref.watch(roomProvider);
    ref.listen(houseDownProvider, (_, down) {
      _applyHouse(down, reduced);
      // Keep-awake belongs to the Video widget: it holds the wakelock only WHILE PLAYING.
      if (Platform.isAndroid) {
        unawaited(
          SystemChrome.setEnabledSystemUIMode(
            down ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
          ),
        );
      }
      if (!down) unawaited(ref.read(pipProvider.notifier).setAutoEnter(enabled: false));
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

    // Android Back: the Lobby lets the app close, once it has stepped out of a library search
    // or folder; the Auditorium (overlays, then the film) and the Ticket Office (a section,
    // then the room) each handle their own.
    final lobbyStep = ref.watch(lobbyCanGoBackProvider);
    return PopScope(
      canPop: room == Room.lobby && !lobbyStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && ref.read(roomProvider) == Room.lobby) {
          ref.read(libraryBrowseProvider.notifier).back();
        }
      },
      child: House(
        palette: palette,
        matinee: widget.matinee && !inAuditorium,
        house: _house,
        reducedMotion: reduced,
        // Every InkWell/InkResponse/TextField needs a Material ancestor; there is no Scaffold.
        child: Material(
          type: MaterialType.transparency,
          child: ColoredBox(
            color: palette.bg,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    if (Platform.isWindows && !ref.watch(fullscreenProvider)) const WindowBar(),
                    Expanded(
                      child: DropTarget(
                        onDragEntered: (_) => setState(() => _dragOver = true),
                        onDragExited: (_) => setState(() => _dragOver = false),
                        onDragDone: (d) => unawaited(_drop(d)),
                        child: AnimatedSwitcher(
                          duration: reduced ? const Duration(milliseconds: 240) : Tokens.durSlow,
                          switchInCurve: Tokens.easeOut,
                          child: switch (room) {
                            Room.lobby => LobbyScreen(
                              key: const ValueKey('lobby'),
                              dragOver: _dragOver,
                            ),
                            Room.auditorium => const AuditoriumScreen(key: ValueKey('auditorium')),
                            Room.ticketOffice => const TicketOfficeScreen(key: ValueKey('office')),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                NoticePill(raised: inAuditorium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-line notice ("That file has moved or been deleted. · Remove"): a quiet pill near
/// the bottom, above every room, gone after its duration.
class NoticePill extends ConsumerStatefulWidget {
  /// In the Auditorium the pill sits above the transport bar, or under the top bar where the
  /// screen is too short for that to clear the middle of the picture.
  final bool raised;
  const NoticePill({super.key, this.raised = false});

  @override
  ConsumerState<NoticePill> createState() => _NoticePillState();
}

class _NoticePillState extends ConsumerState<NoticePill> {
  Timer? _timer;
  Notice? _shown;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm(Notice? n) {
    _timer?.cancel();
    if (n == null) return;
    _timer = Timer(n.duration, () {
      if (mounted) ref.read(noticeProvider.notifier).dismiss(n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(noticeProvider);
    if (!identical(notice, _shown)) {
      _shown = notice;
      _arm(notice);
    }
    final p = House.paletteOf(context);
    final pad = MediaQuery.paddingOf(context);
    // A phone held sideways is about 320 px tall: 128 px above the bottom is the middle of
    // the picture, right on the play and skip buttons, for as long as the notice stays.
    // There it sits just under the player's top bar instead (and drops in from above).
    final atTop = widget.raised && MediaQuery.sizeOf(context).height < 480;
    return Positioned(
      left: Tokens.space4,
      right: Tokens.space4,
      top: atTop ? pad.top + 56 : null,
      bottom: atTop ? null : pad.bottom + (widget.raised ? 128 : Tokens.space7),
      child: Center(
        child: AnimatedSwitcher(
          duration: Tokens.durBase,
          switchInCurve: Tokens.easeOut,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: Offset(0, atTop ? -0.3 : 0.3), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
          child: notice == null
              ? const SizedBox.shrink()
              : Semantics(
                  key: ValueKey(notice.serial),
                  liveRegion: true,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 560, minHeight: 44),
                    padding: const EdgeInsets.only(left: Tokens.space5, right: Tokens.space2),
                    decoration: BoxDecoration(
                      color: p.bgElevated.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(Tokens.radiusFull),
                      border: Border.all(color: p.borderStrong),
                      boxShadow: Tokens.shadow2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
                            child: Text(notice.text, style: Txt.body(Tokens.textSm, p.ink)),
                          ),
                        ),
                        if (notice.actionLabel != null)
                          TextButton(
                            onPressed: () {
                              ref.read(noticeProvider.notifier).dismiss(notice);
                              notice.onAction?.call();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: p.accent,
                              minimumSize: const Size(44, 44),
                            ),
                            child: Text(
                              notice.actionLabel!,
                              style: Txt.body(Tokens.textSm, p.accent, weight: FontWeight.w600),
                            ),
                          )
                        else
                          const SizedBox(width: Tokens.space3),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
