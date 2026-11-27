import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/models/quota.dart';
import 'package:marquee/engine/tickets.dart';
import 'package:marquee/theme/house.dart';
import 'package:marquee/theme/tokens.dart';
import 'package:marquee/ui/components/kit.dart';
import 'package:marquee/ui/components/primitives.dart';
import 'package:marquee/ui/components/sync_rule.dart';
import 'package:marquee/ui/components/ticket_strip.dart';

Widget room(Widget child) => MaterialApp(
  home: House(
    palette: Tokens.auditorium,
    matinee: false,
    house: const AlwaysStoppedAnimation(1),
    reducedMotion: true,
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('labels the ticket strip with the true count', (tester) async {
    final handle = tester.ensureSemantics();
    final strip = ticketStrip(const Quota(remaining: 7, total: 10, signedIn: true));
    await tester.pumpWidget(room(TicketStripView(strip: strip, count: 7)));
    expect(find.bySemanticsLabel('7 of 10 subtitle downloads left today'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('exposes a toggle bulb as a switch and flips it', (tester) async {
    final handle = tester.ensureSemantics();
    var value = false;
    await tester.pumpWidget(
      room(
        SizedBox(
          width: 400,
          child: StatefulBuilder(
            builder: (context, setState) => ToggleBulb(
              label: 'Haptics',
              hint: 'Small taps on phones',
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    final node = find.bySemanticsLabel('Haptics');
    expect(
      tester.getSemantics(node),
      isSemantics(hasToggledState: true, isToggled: false, hint: 'Small taps on phones'),
    );
    await tester.tap(find.text('Haptics'));
    await tester.pump();
    expect(value, isTrue);
    expect(tester.getSemantics(node), isSemantics(hasToggledState: true, isToggled: true));
    handle.dispose();
  });

  testWidgets('a toggle bulb flips from the keyboard', (tester) async {
    var value = false;
    await tester.pumpWidget(
      room(
        SizedBox(
          width: 400,
          child: StatefulBuilder(
            builder: (context, setState) => ToggleBulb(
              label: 'Beam',
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(value, isTrue);
  });

  testWidgets('a mark grows to fit its content instead of wrapping', (tester) async {
    await tester.pumpWidget(
      room(
        Mark(
          label: 'Subtitle sync plus 0.00 seconds',
          onTap: () {},
          child: const Text('SYNC +0.00', style: TextStyle(fontSize: 12)),
        ),
      ),
    );
    final size = tester.getSize(find.byType(Mark));
    expect(size.height, Tokens.targetMin);
    expect(size.width, greaterThan(Tokens.targetMin));
    // One line: the text is as tall as a single line of 12 px type.
    expect(tester.getSize(find.text('SYNC +0.00')).height, lessThan(20));
  });

  testWidgets('the Open disc is a focusable button', (tester) async {
    final handle = tester.ensureSemantics();
    var opened = 0;
    await tester.pumpWidget(room(OpenDisc(onTap: () => opened++)));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Open a video')),
      isSemantics(isButton: true, isFocusable: true, hasTapAction: true),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, 1);
    handle.dispose();
  });

  testWidgets('a segmented choice marks the chosen option selected', (tester) async {
    final handle = tester.ensureSemantics();
    var value = 'auto';
    await tester.pumpWidget(
      room(
        StatefulBuilder(
          builder: (context, setState) => SegmentedChoice<String>(
            groupLabel: 'Theme',
            value: value,
            segments: const [
              Segment('auto', 'Auto'),
              Segment('night', 'Night'),
              Segment('day', 'Day'),
            ],
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Theme: Auto')),
      isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true),
    );
    await tester.tap(find.text('Night'));
    await tester.pump();
    expect(value, 'night');
    expect(
      tester.getSemantics(find.bySemanticsLabel('Theme: Night')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Theme: Auto')),
      isSemantics(isSelected: false),
    );
    handle.dispose();
  });

  testWidgets('a disabled button does nothing', (tester) async {
    await tester.pumpWidget(room(const HouseButton(label: 'Sign in', onPressed: null)));
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a stretched segmented choice puts each label in the middle of its share', (
    tester,
  ) async {
    const key = ValueKey('choice');
    await tester.pumpWidget(
      room(
        SizedBox(
          width: 400,
          child: SegmentedChoice<String>(
            key: key,
            expand: true,
            value: 'a',
            segments: const [Segment('a', 'One'), Segment('b', 'Two')],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    // 400 px less the slot's 3 px padding and 1 px border on each side: two shares of 196.
    final left = tester.getTopLeft(find.byKey(key)).dx;
    expect(tester.getSize(find.byKey(key)).width, 400);
    expect(tester.getCenter(find.text('One')).dx - left, closeTo(4 + 98, 1));
    expect(tester.getCenter(find.text('Two')).dx - left, closeTo(4 + 196 + 98, 1));
  });

  testWidgets('a tall segmented choice gives a thumb 48 px options', (tester) async {
    const key = ValueKey('choice');
    var value = 'home';
    await tester.pumpWidget(
      room(
        SizedBox(
          width: 360,
          child: StatefulBuilder(
            builder: (context, setState) => SegmentedChoice<String>(
              key: key,
              expand: true,
              tall: true,
              value: value,
              segments: const [Segment('home', 'Home'), Segment('library', 'Library')],
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    // 48 px options inside the slot's padding and border.
    expect(tester.getSize(find.byKey(key)).height, 48 + 8);
    // The whole share takes the tap, not only the word: tap near the right end of the control.
    await tester.tapAt(tester.getTopRight(find.byKey(key)) + const Offset(-12, 28));
    await tester.pump();
    expect(value, 'library');
  });

  testWidgets('a tag is words with its tick as an icon, not a font glyph', (tester) async {
    await tester.pumpWidget(room(const Tag('English subtitles', icon: 'check')));
    expect(find.text('English subtitles'), findsOneWidget);
    expect(find.text('English subtitles ✓'), findsNothing);
    expect(find.byType(LucideIcon), findsOneWidget);
  });

  testWidgets('a tag shortens its words rather than spill out of a narrow card', (tester) async {
    await tester.pumpWidget(
      room(
        const SizedBox(
          width: 90,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Tag('Portuguese subtitles', icon: 'check'),
          ),
        ),
      ),
    );
    // No overflow error, and the tag is no wider than its card.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Tag)).width, lessThanOrEqualTo(90));
  });

  testWidgets('speaks the sync rule value in words', (tester) async {
    await tester.pumpWidget(
      room(SizedBox(width: 400, child: SyncRule(delayMs: 350, onChanged: (_) {}))),
    );
    final handle = tester.ensureSemantics();
    final data = tester.getSemantics(find.bySemanticsLabel('Subtitle sync')).getSemanticsData();
    expect(data.value, 'plus 0.35 seconds');
    expect(data.increasedValue, 'plus 0.40 seconds');
    handle.dispose();
  });
}
