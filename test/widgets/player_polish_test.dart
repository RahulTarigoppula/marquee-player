// The player's plain-words pieces: the subtitle timing rule with its Earlier / Later buttons,
// the menu's track names, the "Up next" card that only shows the session's countdown, and the
// picture of the touch gestures.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/theme/house.dart';
import 'package:marquee/theme/tokens.dart';
import 'package:marquee/ui/auditorium/controls/widgets.dart';
import 'package:marquee/ui/auditorium/menu_panel.dart'
    show attachedSubtitleLabel, delayLabel, trackName;
import 'package:marquee/ui/components/sync_rule.dart';

Widget room(Widget child) => MaterialApp(
  home: House(
    palette: Tokens.auditorium,
    matinee: false,
    house: const AlwaysStoppedAnimation(1),
    reducedMotion: true,
    child: Scaffold(body: Center(child: child)),
  ),
);

/// A sync rule that keeps its own value, as the session does for the real one.
class _Rule extends StatefulWidget {
  final int start;
  final ValueChanged<int> onValue;
  const _Rule({required this.start, required this.onValue});

  @override
  State<_Rule> createState() => _RuleState();
}

class _RuleState extends State<_Rule> {
  late int _ms = widget.start;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 400,
    child: SyncRule(
      delayMs: _ms,
      onChanged: (v) {
        setState(() => _ms = v);
        widget.onValue(v);
      },
    ),
  );
}

void main() {
  test('says the subtitle delay as a sentence', () {
    expect(syncSentence(0), 'Subtitles are in time with the video.');
    expect(syncSentence(350), 'Subtitles show 0.35 s later.');
    expect(syncSentence(-300), 'Subtitles show 0.30 s earlier.');
    expect(syncSentence(2000), 'Subtitles show 2.00 s later.');
  });

  testWidgets('Earlier and Later move the subtitles one step, Reset puts them back', (t) async {
    var value = 350;
    await t.pumpWidget(room(_Rule(start: 350, onValue: (v) => value = v)));
    expect(find.text('Subtitles show 0.35 s later.'), findsOneWidget);

    await t.tap(find.text('Later'));
    await t.pump();
    expect(value, 400);
    expect(find.text('Subtitles show 0.40 s later.'), findsOneWidget);

    await t.tap(find.text('Earlier'));
    await t.pump();
    await t.tap(find.text('Earlier'));
    await t.pump();
    expect(value, 300);

    await t.tap(find.text('Reset'));
    await t.pump();
    expect(value, 0);
    expect(find.text('Subtitles are in time with the video.'), findsOneWidget);
    // Nothing to reset once the subtitles are back in time.
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('a held Later keeps stepping, and letting go adds nothing', (t) async {
    var value = 0;
    await t.pumpWidget(room(_Rule(start: 0, onValue: (v) => value = v)));
    final finger = await t.startGesture(t.getCenter(find.text('Later')));
    await t.pump(const Duration(milliseconds: 450)); // past the wait before it repeats
    expect(value, 0);
    await t.pump(const Duration(milliseconds: 130));
    expect(value, 50);
    await t.pump(const Duration(milliseconds: 120));
    expect(value, 100);
    await finger.up();
    await t.pump();
    expect(value, 100);
    // An ordinary tap afterwards is one step again.
    await t.tap(find.text('Later'));
    await t.pump();
    expect(value, 150);
  });

  testWidgets('Later stops at the end of the range', (t) async {
    var value = 2000;
    await t.pumpWidget(room(_Rule(start: 2000, onValue: (v) => value = v)));
    await t.tap(find.text('Later'));
    await t.pump();
    expect(value, 2000);
    await t.tap(find.text('Earlier'));
    await t.pump();
    expect(value, 1950);
  });

  test('names a track by its language in words', () {
    expect(trackName('en', 'Forced', fallback: 'Track 1'), 'English · Forced');
    expect(trackName('ja', null, fallback: 'Track 2'), 'Japanese');
    // A title that only repeats the language is not said twice.
    expect(trackName('en', 'English', fallback: 'Track 3'), 'English');
    expect(trackName(null, 'Commentary', fallback: 'Track 4'), 'Commentary');
    // "Undetermined" is not a language to show; a track with nothing to say gets its number.
    expect(trackName('und', '', fallback: 'Track 5'), 'Track 5');
    expect(attachedSubtitleLabel('en', sidecar: false), 'English · downloaded');
    expect(attachedSubtitleLabel('hi', sidecar: true), 'Hindi · next to the video');
    expect(delayLabel(350), '+0.35 s');
  });

  testWidgets('the Up next card shows the time left and never starts the film itself', (t) async {
    final start = DateTime(2026, 10, 17, 21, 30);
    var now = start;
    var played = 0, cancelled = 0;
    await withClock(Clock(() => now), () async {
      await t.pumpWidget(
        room(
          UpNextCard(
            name: 'Severance S02E04',
            at: start.add(const Duration(seconds: 6)),
            onPlay: () => played++,
            onCancel: () => cancelled++,
          ),
        ),
      );
      expect(find.text('Up next in 6 s'), findsOneWidget);
      expect(find.text('Severance S02E04'), findsOneWidget);

      now = start.add(const Duration(milliseconds: 4200));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Up next in 2 s'), findsOneWidget);

      // Past the moment: the session starts the film, not the card.
      now = start.add(const Duration(seconds: 9));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Up next'), findsOneWidget);
      expect(played, 0);

      await t.tap(find.text('Cancel'));
      expect(cancelled, 1);
      await t.tap(find.text('Play now'));
      expect(played, 1);

      // Drop the card (and its display timer) before the test ends.
      await t.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('the gesture guide lists only what this phone does, and a tap sends it away', (
    t,
  ) async {
    var done = 0;
    await t.pumpWidget(room(GestureGuide(seekStep: 15, onDone: () => done++)));
    expect(find.text('Back 15 s'), findsOneWidget);
    expect(find.text('Forward 15 s'), findsOneWidget);
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Go back or forward'), findsOneWidget);

    await t.tap(find.text('Got it'));
    expect(done, 1);
    // Anywhere else on it does the same.
    await t.tapAt(const Offset(6, 6));
    expect(done, 2);

    await t.pumpWidget(room(GestureGuide(brightness: false, swipeToSeek: false, onDone: () {})));
    expect(find.text('Brightness'), findsNothing);
    expect(find.text('Go back or forward'), findsNothing);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('Back 10 s'), findsOneWidget);
  });
}
