// Settings · Appearance: the theme and the small pleasures of the room.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../components/primitives.dart';
import '../components/theme_choice.dart';
import 'parts.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsValueProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Theme',
          helper:
              'Auto is light by day and dark at night (and follows your device). '
              'Videos always play in the dark.',
          children: [
            ThemeChoice(
              value: settings.lobbyTheme,
              expand: true,
              onChanged: (t) => editSettings(ref, (s) => s.copyWith(lobbyTheme: t)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'The room',
          children: [
            ToggleBulb(
              label: 'Projector beam',
              hint: 'The soft cone of light on the Home screen at night.',
              value: settings.beam,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(beam: v)),
            ),
            ToggleBulb(
              label: 'Sounds',
              hint: 'Quiet cues when a video opens and its subtitles arrive.',
              value: settings.sounds,
              onChanged: (v) => editSettings(ref, (s) => s.copyWith(sounds: v)),
            ),
            // A PC has nothing to buzz: the switch would only raise a question.
            if (onAndroid)
              ToggleBulb(
                label: 'Vibration',
                hint: 'Small taps when you seek or change the subtitle timing.',
                value: settings.haptics,
                onChanged: (v) => editSettings(ref, (s) => s.copyWith(haptics: v)),
              ),
          ],
        ),
      ],
    );
  }
}
