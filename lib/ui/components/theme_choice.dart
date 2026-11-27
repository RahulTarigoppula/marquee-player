// Auto · Night · Day — the one theme control: in Settings › Appearance everywhere, and in the
// Lobby bar too where there is room for it (a desktop window, never a phone).
import 'package:flutter/widgets.dart';

import '../../engine/models/settings.dart';
import 'kit.dart';

const kThemeSegments = [
  Segment(LobbyTheme.auto, 'Auto', icon: 'sun-moon'),
  Segment(LobbyTheme.auditorium, 'Night', icon: 'moon'),
  Segment(LobbyTheme.matinee, 'Day', icon: 'sun'),
];

class ThemeChoice extends StatelessWidget {
  final LobbyTheme value;
  final ValueChanged<LobbyTheme> onChanged;

  /// Icons only (the desktop Lobby bar); labels stay in tooltips and for screen readers.
  final bool compact;
  final bool expand;
  const ThemeChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) => SegmentedChoice<LobbyTheme>(
    segments: kThemeSegments,
    value: value,
    onChanged: onChanged,
    compact: compact,
    expand: expand,
    groupLabel: 'Theme',
  );
}
