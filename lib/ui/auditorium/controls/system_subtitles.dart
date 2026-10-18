// Android subtitles in scripts the bundled font cannot draw.
//
// libass on Android sees exactly one font (the bundled Noto Sans: Latin, Greek, Cyrillic), so
// Arabic, Hindi, Chinese, Thai … came out as boxes. Pointing libass at /system/fonts is not an
// option: it loads every file in the folder into memory (hundreds of MB with CJK and emoji).
// Instead, when the subtitle's language or text needs another script, the engine hides mpv's
// own subtitle rendering and this widget draws mpv's `sub-text` with Flutter, whose text
// stack falls back to the phone's system fonts for every script. Bitmap subtitles (PGS,
// VobSub) never come here — mpv keeps drawing them. Styling follows Settings (size, look,
// placement); ASS positioning is lost for these tracks, which is the honest trade.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../engine/models/settings.dart';
import '../../../player/engine.dart';
import '../../../theme/tokens.dart';

class SystemFontSubtitles extends StatefulWidget {
  final PlayerEngine engine;
  final Settings settings;

  /// Lift the text while the transport bar is showing, so it never sits under the controls.
  final bool lifted;
  const SystemFontSubtitles({
    super.key,
    required this.engine,
    required this.settings,
    this.lifted = false,
  });

  @override
  State<SystemFontSubtitles> createState() => _SystemFontSubtitlesState();
}

class _SystemFontSubtitlesState extends State<SystemFontSubtitles> {
  final _subs = <StreamSubscription<Object?>>[];
  List<String> _lines = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.engine;
    _lines = e.player.state.subtitle;
    _subs
      ..add(e.player.stream.subtitle.listen((l) => setState(() => _lines = l)))
      ..add(e.systemFontSubtitles.changes.listen((_) => setState(() {})))
      ..add(e.player.stream.track.listen((_) => setState(() {})));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engine.drawsSubtitlesInFlutter) return const SizedBox.shrink();
    final text = [
      for (final l in _lines)
        if (l.trim().isNotEmpty) l.trim(),
    ].join('\n');
    if (text.isEmpty) return const SizedBox.shrink();
    final s = widget.settings;
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final size = (h * 0.052).clamp(14.0, 56.0) * s.subtitleScale;
        final box = s.subtitleLook == SubtitleLook.box;
        final style = TextStyle(
          fontFamily: Tokens.fontSubtitle,
          fontSize: size,
          height: 1.25,
          color: const Color(0xFFFFFFFF),
          fontWeight: FontWeight.w500,
          shadows: box
              ? null
              : const [
                  Shadow(color: Color(0xFF000000), blurRadius: 3),
                  Shadow(color: Color(0xFF000000), offset: Offset(1.5, 1.5), blurRadius: 1),
                  Shadow(color: Color(0xFF000000), offset: Offset(-1.5, -1.5), blurRadius: 1),
                  Shadow(color: Color(0xFF000000), offset: Offset(1.5, -1.5), blurRadius: 1),
                  Shadow(color: Color(0xFF000000), offset: Offset(-1.5, 1.5), blurRadius: 1),
                ],
        );
        Widget body = Text(text, textAlign: TextAlign.center, style: style);
        if (box) {
          body = DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xC0000000),
              borderRadius: BorderRadius.circular(Tokens.radiusSm),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size * 0.4, vertical: size * 0.12),
              child: body,
            ),
          );
        }
        final lift = widget.lifted ? 120.0 : 0.0;
        final (alignment, padding) = switch (s.subtitlePlacement) {
          SubtitlePlacement.top => (Alignment.topCenter, EdgeInsets.only(top: h * 0.06)),
          SubtitlePlacement.lowerThird => (
            Alignment.bottomCenter,
            EdgeInsets.only(bottom: h * 0.2 + lift * 0.5),
          ),
          SubtitlePlacement.bottom => (
            Alignment.bottomCenter,
            EdgeInsets.only(bottom: h * 0.05 + lift),
          ),
        };
        return IgnorePointer(
          child: AnimatedPadding(
            duration: Tokens.durBase,
            curve: Tokens.easeOut,
            padding: padding.add(const EdgeInsets.symmetric(horizontal: Tokens.space6)),
            child: Align(alignment: alignment, child: body),
          ),
        );
      },
    );
  }
}
