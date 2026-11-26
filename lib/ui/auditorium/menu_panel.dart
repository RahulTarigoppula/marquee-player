// The open menu's rows, built from the live session, the track lists and Settings. One panel,
// eleven menus: the five the bar opens and the lists those open in turn (chapters, sleep,
// second subtitle, sound, adjust picture, repeat).
//
// The 10 Hz rule: the panel watches the playback stream through ONE `select` (tracks, the
// selected ids, the rate, the current chapter), so a tick that only moves the clock rebuilds
// nothing here and a slider being dragged is never rebuilt from under the thumb.
import 'dart:async';
import 'dart:io' show Platform;

// Flutter has a RepeatMode of its own (animations); ours is the Settings one.
import 'package:flutter/widgets.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/models.dart';
import '../../engine/picture.dart';
import '../../engine/playback.dart';
import '../../platform/window.dart';
import '../../player/engine.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../components/kit.dart';
import 'controls/controls_bar.dart';
import 'controls/widgets.dart';

/// `EN  Director's commentary`, or [fallback] for a track that says nothing about itself.
String trackName(String? language, String? title, {required String fallback}) {
  final lang = language == null || language.isEmpty ? null : language.toUpperCase();
  final parts = [?lang, if (title != null && title.isNotEmpty) title];
  return parts.isEmpty ? fallback : parts.join('  ');
}

/// `+0.15 s`, `-0.05 s`, `0.00 s`.
String delayLabel(int ms) {
  final sign = ms > 0 ? '+' : (ms < 0 ? '-' : '');
  return '$sign${(ms.abs() / 1000).toStringAsFixed(2)} s';
}

/// `+12`, `-4`, `0`.
String _signed(int v) => v > 0 ? '+$v' : '$v';

bool _isTrack(String? id) => id != null && id.isNotEmpty && id != 'no' && id != 'auto';

int? _currentChapter(List<Chapter> chapters, Duration position) {
  int? current;
  final at = position.inMilliseconds / 1000;
  for (final c in chapters) {
    if (c.startSeconds <= at) current = c.index;
  }
  return current;
}

class MenuPanel extends ConsumerWidget {
  final AuditoriumMenu menu;
  final bool canGoBack, desktop;
  final double maxHeight;
  final VoidCallback onBack, onClose, onPickSubtitle, onBooth, onCueSheet, onDetails;
  final ValueChanged<AuditoriumMenu> onOpen;
  const MenuPanel({
    super.key,
    required this.menu,
    required this.canGoBack,
    required this.desktop,
    required this.maxHeight,
    required this.onBack,
    required this.onClose,
    required this.onOpen,
    required this.onPickSubtitle,
    required this.onBooth,
    required this.onCueSheet,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox.shrink();
    final e = s.engine;
    final n = ref.read(sessionProvider.notifier);
    // The track lists are the engine's own cached ones (identical between ticks), so this
    // record only differs when something a menu shows has changed.
    final pb = ref.watch(
      playbackProvider.select((v) {
        final pb = v.value ?? e.snapshot;
        return (
          audio: pb.audioTracks,
          subs: pb.subtitleTracks,
          aid: pb.audioId,
          sid: pb.subtitleId,
          sid2: pb.secondarySubtitleId,
          rate: pb.rate,
          chapter: menu == AuditoriumMenu.chapters
              ? _currentChapter(s.chapters, pb.position)
              : null,
        );
      }),
    );
    final st = ref.watch(settingsValueProvider.select((x) => (fx: x.audioFx, repeat: x.repeat)));
    final pic = s.picture;

    void then(Future<void> Function() f) {
      unawaited(f());
      onClose();
    }

    void edit(Settings Function(Settings) f) =>
        unawaited(ref.read(settingsProvider.notifier).edit(f));
    void picture(PictureAdjust next) => unawaited(n.setPicture(next));
    List<Widget> list(List<MenuEntry> entries) => [for (final x in entries) MenuRow(entry: x)];
    Widget slider(HouseSlider child) => Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.space1, Tokens.space2, Tokens.space1, 0),
      child: child,
    );

    final attached = s.threading.attached;
    final attachedId = attached is ExternalSubtitle ? e.externalIdFor(attached.path) : null;
    // A second subtitle is text drawn at the top: any text track but the one already showing.
    final seconds = [
      for (final t in pb.subs)
        if (t.id != pb.sid && !isBitmapSubtitle(t)) t,
    ];
    final second = pb.subs.where((t) => t.id == pb.sid2).firstOrNull;

    final (String title, List<Widget> rows) = switch (menu) {
      AuditoriumMenu.subtitles => (
        'Subtitles',
        list([
          MenuEntry('Off', selected: !_isTrack(pb.sid), onTap: () => then(n.subtitlesOff)),
          if (attached is ExternalSubtitle)
            MenuEntry(
              '${attached.language.toUpperCase()}  ${attached.provider == SubtitleProvider.sidecar ? 'beside the film' : 'downloaded'}',
              detail: attached.syncedByHash ? 'MATCH' : 'BY NAME',
              selected: attachedId != null && pb.sid == attachedId,
              onTap: () => then(n.useAttachedSubtitle),
            ),
          for (final t in pb.subs.where((t) => t.id != attachedId))
            MenuEntry(
              trackName(t.language, t.title, fallback: 'Track ${t.id}'),
              detail: isBitmapSubtitle(t)
                  ? 'IMAGE'
                  : e.isExternal(t.id)
                  ? 'FILE'
                  : null,
              selected: t.id == pb.sid,
              onTap: () => then(() => n.selectSubtitle(t.id)),
            ),
          if (seconds.isNotEmpty || _isTrack(pb.sid2))
            MenuEntry(
              'Second subtitle',
              icon: 'captions',
              detail: second == null
                  ? null
                  : trackName(second.language, null, fallback: 'Track ${second.id}'),
              opens: true,
              onTap: () => onOpen(AuditoriumMenu.secondSubtitle),
            ),
          MenuEntry('Load subtitle file…', icon: 'file-plus', onTap: onPickSubtitle),
          MenuEntry('Find, sync and style…', icon: 'search', onTap: onBooth),
        ]),
      ),
      AuditoriumMenu.secondSubtitle => (
        'Second subtitle',
        list([
          MenuEntry(
            'Off',
            selected: !_isTrack(pb.sid2),
            onTap: () => then(() => n.setSecondSubtitle(null)),
          ),
          for (final t in seconds)
            MenuEntry(
              trackName(t.language, t.title, fallback: 'Track ${t.id}'),
              detail: e.isExternal(t.id) ? 'FILE' : null,
              selected: t.id == pb.sid2,
              onTap: () => then(() => n.setSecondSubtitle(t.id)),
            ),
        ]),
      ),
      AuditoriumMenu.audio => (
        'Audio',
        [
          ...list([
            for (final t in pb.audio)
              MenuEntry(
                trackName(t.language, t.title, fallback: 'Track ${t.id}'),
                detail: [
                  if (t.channels != null) t.channels!,
                  if (t.codec != null) t.codec!.toUpperCase(),
                ].join(' · '),
                selected: t.id == pb.aid,
                onTap: () => then(() => n.selectAudio(t.id)),
              ),
            if (pb.audio.isEmpty) const MenuEntry('No audio tracks'),
          ]),
          const MenuDivider(),
          MenuRow(
            entry: MenuEntry(
              'Sound',
              icon: 'sliders-horizontal',
              detail: st.fx.preset.label,
              opens: true,
              onTap: () => onOpen(AuditoriumMenu.sound),
            ),
          ),
          MenuToggle(
            label: 'Even out loud and quiet parts',
            value: st.fx.normalize,
            onChanged: (v) => edit((x) => x.copyWith(audioNormalize: v)),
          ),
          // Sound out of step with the picture: 50 ms at a time, right here.
          MenuStepper(
            label: 'Audio delay',
            valueText: delayLabel(s.audioDelayMs),
            active: s.audioDelayMs != 0,
            minusLabel: 'Audio 50 ms earlier',
            plusLabel: 'Audio 50 ms later',
            onMinus: () => unawaited(n.setAudioDelay(s.audioDelayMs - 50)),
            onPlus: () => unawaited(n.setAudioDelay(s.audioDelayMs + 50)),
            onReset: s.audioDelayMs == 0 ? null : () => unawaited(n.setAudioDelay(0)),
          ),
        ],
      ),
      // Stays open: a profile is chosen by ear, one after another.
      AuditoriumMenu.sound => (
        'Sound',
        list([
          for (final preset in EqPreset.values)
            MenuEntry(
              preset.label,
              selected: st.fx.preset == preset,
              onTap: () => edit((x) => x.copyWith(eqPreset: preset)),
            ),
        ]),
      ),
      AuditoriumMenu.speed => (
        'Speed',
        [
          ...list([
            for (final r in kSpeeds)
              MenuEntry(
                r == 1 ? 'Normal' : speedLabel(r),
                detail: r == 1 ? '1×' : null,
                selected: (pb.rate - r).abs() < 0.01,
                onTap: () => then(() => e.setRate(r)),
              ),
          ]),
          const MenuDivider(),
          slider(
            HouseSlider(
              label: 'Fine speed',
              value: pb.rate,
              min: kMinSpeed,
              max: kMaxSpeed,
              divisions: ((kMaxSpeed - kMinSpeed) / kSpeedStep).round(),
              valueText: speedLabel(snapSpeed(pb.rate)),
              onChanged: (v) => unawaited(e.setRate(snapSpeed(v))),
            ),
          ),
        ],
      ),
      AuditoriumMenu.picture => (
        'Picture',
        [
          ...list([
            for (final f in PictureFit.values)
              MenuEntry(
                f.label,
                selected: s.fit == f,
                onTap: () {
                  n.setFit(f);
                  onClose();
                },
              ),
          ]),
          const MenuDivider(),
          MenuRow(
            entry: MenuEntry(
              'Rotate 90°',
              icon: 'rotate-cw',
              detail: pic.rotation == 0 ? null : '${pic.rotation}°',
              onTap: () => picture(pic.rotated),
            ),
          ),
          MenuStepper(
            label: 'Zoom',
            icon: 'zoom-in',
            valueText: '${pic.zoomPercent} %',
            active: pic.zoom != 0,
            minusLabel: 'Zoom out',
            plusLabel: 'Zoom in',
            onMinus: pic.zoom <= PictureAdjust.minZoom
                ? null
                : () => picture(pic.zoomedBy(-PictureAdjust.zoomStep)),
            onPlus: pic.zoom >= PictureAdjust.maxZoom
                ? null
                : () => picture(pic.zoomedBy(PictureAdjust.zoomStep)),
            onReset: pic.zoom == 0 ? null : () => picture(pic.copyWith(zoom: 0)),
          ),
          MenuToggle(
            label: 'Fix comb lines (deinterlace)',
            value: pic.deinterlace,
            onChanged: (v) => picture(pic.copyWith(deinterlace: v)),
          ),
          MenuRow(
            entry: MenuEntry(
              'Adjust picture',
              icon: 'sliders-horizontal',
              detail: pic.hasLevels ? 'ON' : null,
              opens: true,
              onTap: () => onOpen(AuditoriumMenu.adjust),
            ),
          ),
        ],
      ),
      AuditoriumMenu.adjust => (
        'Adjust picture',
        [
          for (final (label, value, set) in <(String, int, PictureAdjust Function(int))>[
            ('Brightness', pic.brightness, (v) => pic.copyWith(brightness: v)),
            ('Contrast', pic.contrast, (v) => pic.copyWith(contrast: v)),
            ('Saturation', pic.saturation, (v) => pic.copyWith(saturation: v)),
            ('Gamma', pic.gamma, (v) => pic.copyWith(gamma: v)),
          ])
            slider(
              HouseSlider(
                label: label,
                value: value.toDouble(),
                min: PictureAdjust.minLevel.toDouble(),
                max: PictureAdjust.maxLevel.toDouble(),
                divisions: PictureAdjust.maxLevel - PictureAdjust.minLevel,
                valueText: _signed(value),
                onChanged: (v) => picture(set(v.round())),
              ),
            ),
          MenuRow(
            entry: MenuEntry(
              'Reset',
              icon: 'rotate-ccw',
              onTap: pic.hasLevels ? () => picture(pic.levelsReset) : null,
            ),
          ),
        ],
      ),
      AuditoriumMenu.chapters => (
        'Chapters',
        list([
          for (final c in s.chapters)
            MenuEntry(
              c.title?.trim().isNotEmpty ?? false ? c.title! : 'Chapter ${c.index + 1}',
              detail: clockOf(c.startSeconds),
              selected: pb.chapter == c.index,
              onTap: () =>
                  then(() => e.seekTo(Duration(milliseconds: (c.startSeconds * 1000).round()))),
            ),
        ]),
      ),
      AuditoriumMenu.sleep => (
        'Sleep timer',
        list([
          for (final t in SleepTimer.values)
            MenuEntry(
              t.label,
              selected: s.sleep == t,
              onTap: () {
                n.setSleep(t);
                onClose();
              },
            ),
        ]),
      ),
      AuditoriumMenu.repeat => (
        'Repeat',
        list([
          for (final mode in RepeatMode.values)
            MenuEntry(
              mode.label,
              selected: st.repeat == mode,
              onTap: () {
                edit((x) => x.copyWith(repeat: mode));
                onClose();
              },
            ),
        ]),
      ),
      AuditoriumMenu.more => (
        'More',
        list([
          if (s.chapters.isNotEmpty)
            MenuEntry(
              'Chapters',
              icon: 'list',
              detail: '${s.chapters.length}',
              opens: true,
              onTap: () => onOpen(AuditoriumMenu.chapters),
            ),
          MenuEntry(
            s.looping
                ? 'Clear the A-B loop'
                : (s.loopA != null ? 'Set loop end (B)' : 'Set loop start (A)'),
            icon: 'repeat',
            detail: desktop ? 'L' : null,
            onTap: () => then(n.toggleLoop),
          ),
          MenuEntry(
            'Repeat',
            icon: 'repeat-1',
            detail: switch (st.repeat) {
              RepeatMode.off => null,
              RepeatMode.one => 'THIS VIDEO',
              RepeatMode.all => 'FOLDER',
            },
            opens: true,
            onTap: () => onOpen(AuditoriumMenu.repeat),
          ),
          MenuEntry('Screenshot', icon: 'camera', onTap: () => then(n.screenshot)),
          MenuEntry(
            'Sleep timer',
            icon: 'timer',
            detail: s.sleep == SleepTimer.off ? null : s.sleep.label,
            opens: true,
            onTap: () => onOpen(AuditoriumMenu.sleep),
          ),
          MenuEntry(
            'Picture',
            icon: 'scan',
            detail: s.fit.label,
            opens: true,
            onTap: () => onOpen(AuditoriumMenu.picture),
          ),
          MenuEntry('Video details', icon: 'info', detail: desktop ? 'I' : null, onTap: onDetails),
          // Windows only: a phone has picture in picture for this.
          if (Platform.isWindows)
            MenuEntry(
              'Keep on top',
              icon: 'pin',
              detail: ref.watch(pinnedProvider) ? 'ON' : 'T',
              selected: ref.watch(pinnedProvider),
              onTap: () {
                ref.read(pinnedProvider.notifier).toggle();
                onClose();
              },
            ),
          MenuEntry('Load subtitle file…', icon: 'file-plus', onTap: onPickSubtitle),
          MenuEntry(
            'Subtitle booth',
            icon: 'captions',
            detail: desktop ? 'S' : null,
            onTap: onBooth,
          ),
          if (desktop)
            MenuEntry('Keyboard shortcuts', icon: 'info', detail: '?', onTap: onCueSheet),
        ]),
      ),
    };
    return ControlMenu(
      title: title,
      rows: rows,
      onBack: canGoBack ? onBack : null,
      onClose: onClose,
      maxHeight: maxHeight,
    );
  }
}
