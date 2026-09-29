import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('structural laws', () {
    test('keeps lib/engine free of Flutter, Riverpod, drift and http', () {
      final banned = RegExp(
        r'''import\s+['"]package:(flutter|flutter_riverpod|riverpod|drift|http)[/:]''',
      );
      final offenders = [
        for (final f in Directory('lib/engine').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') && banned.hasMatch(f.readAsStringSync())) f.path,
      ];
      expect(offenders, isEmpty);
    });

    test('keeps widgets away from lib/api and lib/db', () {
      final banned = RegExp(r'''import\s+['"](package:marquee/|\.\./)+(api|db)/''');
      final ui = Directory('lib/ui');
      if (!ui.existsSync()) return;
      final offenders = [
        for (final f in ui.listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') && banned.hasMatch(f.readAsStringSync())) f.path,
      ];
      expect(offenders, isEmpty);
    });

    test('drives the house lights from a single tween', () {
      final ui = Directory('lib');
      final hits = [
        for (final f in ui.listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart'))
            ...RegExp(
              r'houseController\s*=\s*AnimationController',
            ).allMatches(f.readAsStringSync()),
      ];
      expect(hits.length, lessThanOrEqualTo(1));
    });
  });
}
