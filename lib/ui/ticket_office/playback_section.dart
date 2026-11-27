// Settings · Playback: moving through a video, what happens when it ends, sound, audio
// language and the picture.
// Flutter's widgets library has a RepeatMode of its own (animations); ours is the setting.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/models/models.dart';
import '../../state/providers.dart';
import '../components/kit.dart';
import '../components/primitives.dart';
import 'parts.dart';

/// "When a video ends" is ONE question to the person watching. Underneath it is two settings
/// (`repeat` and `autoplayNext`); shown separately they contradict each other ("repeat this
/// video" and "play the next one" both on).
enum _AtEnd { stop, next, repeatOne, repeatAll }

_AtEnd _atEndOf(Settings s) => switch (s.repeat) {
  RepeatMode.one => _AtEnd.repeatOne,
  RepeatMode.all => _AtEnd.repeatAll,
  RepeatMode.off => s.autoplayNext ? _AtEnd.next : _AtEnd.stop,
};

Settings _withAtEnd(Settings s, _AtEnd v) => switch (v) {
  _AtEnd.stop => s.copyWith(repeat: RepeatMode.off, autoplayNext: false),
  _AtEnd.next => s.copyWith(repeat: RepeatMode.off, autoplayNext: true),
  // Repeating one video never reaches the next, so `autoplayNext` keeps its value.
  _AtEnd.repeatOne => s.copyWith(repeat: RepeatMode.one),
  // Going round a folder means moving on to the next file.
  _AtEnd.repeatAll => s.copyWith(repeat: RepeatMode.all, autoplayNext: true),
};

String _profileHelp(EqPreset preset) => switch (preset) {
  EqPreset.flat => 'The sound plays as it was recorded.',
  EqPreset.voiceBoost => 'Lifts speech so dialogue is easier to follow.',
  EqPreset.bassBoost => 'A fuller low end, good for small speakers.',
  EqPreset.trebleBoost => 'Brighter detail, for muffled or old recordings.',
  EqPreset.nightMode => 'Softer bass and clearer voices, for watching late.',
};

class PlaybackSection extends ConsumerWidget {
  const PlaybackSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsValueProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Moving through a video',
          children: [
            ControlBlock(
              label: 'Jump size',
              help: onAndroid
                  ? 'How many seconds the skip buttons and a double tap jump.'
                  : 'How many seconds the skip buttons jump.',
              child: SegmentedChoice<int>(
                key: const ValueKey('seek-step'),
                groupLabel: 'Jump size',
                value: settings.seekStepSeconds,
                expand: true,
                segments: [for (final s in Settings.seekSteps) Segment(s, '$s s')],
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(seekStepSeconds: v)),
              ),
            ),
            if (onDesktop)
              ToggleBulb(
                label: 'Preview while seeking',
                hint: 'Point at the seek bar to see a small picture of that moment.',
                value: settings.seekPreview,
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(seekPreview: v)),
              ),
            if (onAndroid)
              ToggleBulb(
                label: 'Swipe to seek',
                hint: 'Slide a finger sideways across the picture to move through the video.',
                value: settings.swipeToSeek,
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(swipeToSeek: v)),
              ),
            ToggleBulb(
              label: 'Show time remaining',
              hint: 'The clock shows how much is left instead of the full length.',
              value: settings.showRemaining,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(showRemaining: v)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'When a video ends',
          children: [
            ChoiceList<_AtEnd>(
              key: const ValueKey('at-end'),
              groupLabel: 'When a video ends',
              value: _atEndOf(settings),
              choices: [
                const Choice(_AtEnd.stop, 'Stop', hint: 'Nothing else plays until you choose it.'),
                const Choice(
                  _AtEnd.next,
                  'Play the next video in the folder',
                  hint: 'Handy for series: when an episode ends, the next file starts.',
                ),
                Choice(
                  _AtEnd.repeatOne,
                  RepeatMode.one.label,
                  hint: 'The same video starts again from the beginning.',
                ),
                Choice(
                  _AtEnd.repeatAll,
                  RepeatMode.all.label,
                  hint: 'Plays each video in the folder, then starts again at the first.',
                ),
              ],
              onChanged: (v) => editSettings(ref, (s) => _withAtEnd(s, v)),
            ),
          ],
        ),
        if (onAndroid)
          SettingsGroup(
            title: 'Away from the app',
            children: [
              ToggleBulb(
                label: 'Keep playing in the background',
                hint:
                    'The sound carries on when the screen is off or another app is open. '
                    'Play, pause and skip stay on the lock screen either way.',
                value: settings.backgroundPlay,
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(backgroundPlay: v)),
              ),
            ],
          ),
        SettingsGroup(
          title: 'Sound',
          children: [
            ControlBlock(
              label: 'Sound profile',
              help: _profileHelp(settings.eqPreset),
              child: OptionChips<EqPreset>(
                key: const ValueKey('eq-preset'),
                groupLabel: 'Sound profile',
                value: settings.eqPreset,
                choices: [for (final e in EqPreset.values) Choice(e, e.label)],
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(eqPreset: v)),
              ),
            ),
            ToggleBulb(
              label: 'Even out loud and quiet parts',
              hint: 'Whispers come up and explosions come down, so the volume can stay put.',
              value: settings.audioNormalize,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(audioNormalize: v)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Audio language',
          helper:
              'When a video has several audio tracks, play these first (best first). '
              'Choose none to keep each file\'s own default.',
          children: [
            LanguagePicker(
              selected: settings.audioLanguages,
              allowEmpty: true,
              semanticPrefix: 'Audio language',
              onChanged: (l) => editSettings(ref, (s) => s.copyWith(audioLanguages: l)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Picture',
          children: [
            ToggleBulb(
              label: 'Hardware decoding',
              hint:
                  'Smoother and cooler on most devices. Turn off if the picture flickers or '
                  'shows green blocks.',
              value: settings.hwdec != 'no',
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(hwdec: v ? 'auto-safe' : 'no')),
            ),
            ToggleBulb(
              label: 'Bias light',
              hint:
                  'Tints the walls around the picture with the video\'s colours. '
                  'Uses extra CPU and battery.',
              value: settings.biasLight,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(biasLight: v)),
            ),
          ],
        ),
      ],
    );
  }
}
