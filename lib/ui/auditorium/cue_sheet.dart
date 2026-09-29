// The `?` cue sheet — generated from design/cue-sheet.json, the single source of truth.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/house.dart';
import '../../theme/tokens.dart';

class Cue {
  final String id;
  final List<String> keys;
  final String action;
  const Cue(this.id, this.keys, this.action);
}

List<Cue> parseCueSheet(String json) {
  final j = jsonDecode(json) as Map<String, Object?>;
  return [
    for (final c in (j['cues']! as List).cast<Map<String, Object?>>())
      Cue(c['id']! as String, (c['keys']! as List).cast<String>(), c['action']! as String),
  ];
}

final cueSheetDataProvider = FutureProvider<List<Cue>>(
  (ref) async => parseCueSheet(await rootBundle.loadString('design/cue-sheet.json')),
);

String prettyKey(String k) => k
    .replaceAll('ArrowLeft', '←')
    .replaceAll('ArrowRight', '→')
    .replaceAll('ArrowUp', '↑')
    .replaceAll('ArrowDown', '↓')
    .replaceAll('Escape', 'Esc');

class CueSheet extends ConsumerWidget {
  const CueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = House.paletteOf(context);
    final cues = ref.watch(cueSheetDataProvider).value ?? const [];
    return GestureDetector(
      onTap: () => ref.read(cueSheetProvider.notifier).set(false),
      child: ColoredBox(
        color: p.bg.withValues(alpha: 0.9),
        // Scrolls: 21 cues overflow a phone and the 720×480 minimum window.
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Tokens.space4),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 640),
              padding: const EdgeInsets.all(Tokens.space6),
              decoration: BoxDecoration(
                color: p.bgElevated,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
                boxShadow: Tokens.shadow3,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CUE SHEET',
                    style: Txt.display(Tokens.text2Xl, p.ink, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: Tokens.space4),
                  Wrap(
                    runSpacing: Tokens.space2,
                    children: [
                      for (final c in cues)
                        SizedBox(
                          width: 290,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(
                                  c.keys.map(prettyKey).join(' / '),
                                  style: Txt.mono(Tokens.textSm, p.accent),
                                ),
                              ),
                              Expanded(
                                child: Text(c.action, style: Txt.body(Tokens.textSm, p.ink)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
