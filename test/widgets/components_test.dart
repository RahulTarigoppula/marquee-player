import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/engine/models/quota.dart';
import 'package:marquee/engine/tickets.dart';
import 'package:marquee/theme/house.dart';
import 'package:marquee/theme/tokens.dart';
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
    expect(find.bySemanticsLabel('7 of 10 downloads left tonight'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('exposes a toggle bulb as a switch', (tester) async {
    var value = false;
    await tester.pumpWidget(
      room(
        StatefulBuilder(
          builder: (context, setState) => ToggleBulb(
            label: 'Haptics',
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    expect(find.text('OFF'), findsOneWidget);
    await tester.tap(find.text('Haptics'));
    await tester.pump();
    expect(value, isTrue);
    expect(find.text('ON'), findsOneWidget);
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
