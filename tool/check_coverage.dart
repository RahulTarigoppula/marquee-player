// Coverage gates for the pure-Dart engine (IMPLEMENTATION-PROMPT §10).
//
//   dart run tool/check_coverage.dart coverage/lcov.info
//
// * lib/engine/{hash,scoring,timecode,sync_rule,tickets}.dart must be 100 % line-covered.
// * The rest of lib/engine/ must be >= 90 % line-covered in aggregate.
// A strict file that no test loads fails. Other engine files that no test loads (declaration-only
// models have no executable lines) are listed as "not loaded" and do not count toward the 90 %.
// Only dart: libraries are imported, so this runs without `pub get`.
import 'dart:io';

const strictFiles = <String>{
  'lib/engine/hash.dart',
  'lib/engine/scoring.dart',
  'lib/engine/timecode.dart',
  'lib/engine/sync_rule.dart',
  'lib/engine/tickets.dart',
};
const restThreshold = 90.0;

class FileCov {
  FileCov(this.path, {this.absent = false});
  final String path;

  /// On disk under lib/engine/ but never loaded by any test (so not in lcov.info).
  final bool absent;
  final Map<int, int> lines = {};
  int get found => lines.length;
  int get hit => lines.values.where((h) => h > 0).length;
  double get pct => found == 0 ? 100 : hit * 100 / found;
}

void usage() {
  stderr.writeln('usage: dart run tool/check_coverage.dart <path/to/lcov.info>');
  stderr.writeln('');
  stderr.writeln('  100 % lines required: ${strictFiles.join(', ')}');
  stderr.writeln(
    '  >= ${restThreshold.toStringAsFixed(0)} % lines required: the rest of lib/engine/ (aggregate)',
  );
}

/// Maps an SF: path (absolute, relative, Windows or POSIX) to `lib/...` when it is inside lib/.
String? toRepoPath(String sf) {
  final p = sf.replaceAll('\\', '/');
  final i = p.lastIndexOf('/lib/');
  if (p.startsWith('lib/')) return p;
  if (i >= 0) return p.substring(i + 1);
  return null;
}

Map<String, FileCov> parseLcov(String text) {
  final out = <String, FileCov>{};
  FileCov? cur;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      final path = toRepoPath(line.substring(3));
      cur = path == null ? null : out.putIfAbsent(path, () => FileCov(path));
    } else if (line.startsWith('DA:') && cur != null) {
      final parts = line.substring(3).split(',');
      if (parts.length < 2) continue;
      final ln = int.tryParse(parts[0]);
      final hits = int.tryParse(parts[1]);
      if (ln == null || hits == null) continue;
      cur.lines[ln] = (cur.lines[ln] ?? 0) + hits;
    } else if (line == 'end_of_record') {
      cur = null;
    }
  }
  return out;
}

String fmt(double v) => '${v.toStringAsFixed(1)} %';

void main(List<String> args) {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    usage();
    exit(args.isEmpty ? 64 : 0);
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('check_coverage: ${args.first} does not exist (run `flutter test --coverage`).');
    exit(66);
  }
  final cov = parseLcov(file.readAsStringSync());

  // Engine files on disk that the tests never loaded still count, at 0 %.
  final engineDir = Directory('lib/engine');
  if (engineDir.existsSync()) {
    for (final f in engineDir.listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.dart') || p.endsWith('.g.dart') || p.endsWith('.drift.dart')) {
        continue;
      }
      final rel = toRepoPath(p.startsWith('lib/') ? p : '/$p') ?? p;
      cov.putIfAbsent(rel, () => FileCov(rel, absent: true));
    }
  }

  final engine = cov.values.where((c) => c.path.startsWith('lib/engine/')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (engine.isEmpty) {
    stderr.writeln('check_coverage: no lib/engine/ files in ${args.first}.');
    exit(1);
  }

  final failures = <String>[];
  final rows = <List<String>>[];
  var restFound = 0, restHit = 0;
  for (final c in engine) {
    final strict = strictFiles.contains(c.path);
    final ok = strict ? !c.absent && c.hit == c.found : true;
    if (!strict && !c.absent) {
      restFound += c.found;
      restHit += c.hit;
    }
    if (strict && !ok) {
      failures.add(
        c.absent
            ? '${c.path} is not loaded by any test; 100 % required'
            : '${c.path} is ${fmt(c.pct)}; 100 % required',
      );
    }
    rows.add([
      c.path,
      c.absent ? '-' : '${c.hit}/${c.found}',
      c.absent ? 'not loaded' : fmt(c.pct),
      strict ? '100 %' : 'rest',
      strict ? (ok ? 'ok' : 'FAIL') : '',
    ]);
  }
  for (final s in strictFiles) {
    if (!engine.any((c) => c.path == s)) {
      rows.add([s, '-', '-', '100 %', 'absent']);
    }
  }
  final restPct = restFound == 0 ? 100.0 : restHit * 100 / restFound;
  final restOk = restPct >= restThreshold;
  if (!restOk) {
    failures.add('rest of lib/engine is ${fmt(restPct)}; >= ${fmt(restThreshold)} required');
  }
  rows.add([
    '(rest of lib/engine, aggregate)',
    '$restHit/$restFound',
    fmt(restPct),
    '>= ${fmt(restThreshold)}',
    restOk ? 'ok' : 'FAIL',
  ]);

  final header = ['file', 'lines', 'covered', 'gate', 'result'];
  final widths = List.generate(header.length, (i) {
    var w = header[i].length;
    for (final r in rows) {
      if (r[i].length > w) w = r[i].length;
    }
    return w;
  });
  String line(List<String> cells) =>
      '| ${List.generate(cells.length, (i) => cells[i].padRight(widths[i])).join(' | ')} |';
  stdout.writeln(line(header));
  stdout.writeln('|${widths.map((w) => '-' * (w + 2)).join('|')}|');
  for (final r in rows) {
    stdout.writeln(line(r));
  }

  if (failures.isNotEmpty) {
    stderr.writeln('');
    for (final f in failures) {
      stderr.writeln('coverage gate: $f');
    }
    exit(1);
  }
  stdout.writeln('\ncoverage gates: ok');
}
