// Licence allow-list (G1, IMPLEMENTATION-PROMPT §10.7).
//
//   dart run tool/check_licences.dart                    runs `flutter pub deps --json` itself
//   flutter pub deps --json | dart run tool/check_licences.dart -
//
// Every hosted/git/path Dart package in the resolved graph must carry a LICENSE that reads as MIT,
// BSD, Apache-2.0, ISC, MPL-2.0 or Zlib. GPL and AGPL fail. LGPL is not on the allow-list for Dart
// packages either: the LGPL parts of Marquee (libmpv, FFmpeg) are dynamically linked native
// binaries shipped by MIT-licensed media_kit_libs_* packages, not Dart code, and their texts live
// in LICENSES/. Package locations come from .dart_tool/package_config.json (run `flutter pub get`
// first). Only dart: libraries are imported, so this runs without `pub get` of its own.
import 'dart:convert';
import 'dart:io';

/// Reviewed by hand: package name -> licence and the reason it is accepted. Keep this short.
const exceptions = <String, String>{};

const licenceFiles = [
  'LICENSE',
  'LICENSE.md',
  'LICENSE.txt',
  'LICENCE',
  'LICENCE.md',
  'COPYING',
  'license',
  'License.md',
];

enum Verdict { allowed, forbidden, unknown }

class Finding {
  Finding(this.name, this.version, this.licence, this.verdict, [this.note = '']);
  final String name;
  final String version;
  final String licence;
  final Verdict verdict;
  final String note;
}

/// Classifies licence text. The GPL family is checked before the permissive licences so that a GPL
/// text that happens to quote an MIT header can never pass.
(String, Verdict) classify(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  // MPL-2.0 names the GPL family in its "Secondary License" definition, so it is recognised
  // by its own title before the GPL checks run.
  if (t.contains('mozilla public license')) {
    return ('MPL-2.0', Verdict.allowed);
  }
  if (t.contains('gnu affero general public license')) {
    return ('AGPL', Verdict.forbidden);
  }
  if (t.contains('gnu lesser general public license') ||
      t.contains('gnu library general public license')) {
    return ('LGPL', Verdict.forbidden);
  }
  if (t.contains('gnu general public license')) {
    return ('GPL', Verdict.forbidden);
  }
  if (t.contains('apache license') &&
      (t.contains('version 2.0') || t.contains('apache.org/licenses'))) {
    return ('Apache-2.0', Verdict.allowed);
  }
  if (t.contains('permission is hereby granted, free of charge')) {
    return ('MIT', Verdict.allowed);
  }
  if (t.contains('redistribution and use in source and binary forms')) {
    return ('BSD', Verdict.allowed);
  }
  if (t.contains(
        'permission to use, copy, modify, and/or distribute this software for any purpose',
      ) ||
      t.contains('permission to use, copy, modify, and distribute this software for any purpose')) {
    return ('ISC', Verdict.allowed);
  }
  if (t.contains("provided 'as-is', without any express or implied warranty") &&
      t.contains('altered source versions must be plainly marked')) {
    return ('Zlib', Verdict.allowed);
  }
  return ('unrecognised', Verdict.unknown);
}

Map<String, String> packageRoots() {
  final f = File('.dart_tool/package_config.json');
  if (!f.existsSync()) {
    stderr.writeln(
      'check_licences: .dart_tool/package_config.json is missing — run `flutter pub get`.',
    );
    exit(2);
  }
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final base = f.absolute.uri;
  final out = <String, String>{};
  for (final p in (json['packages'] as List).cast<Map<String, dynamic>>()) {
    out[p['name'] as String] = base.resolve(p['rootUri'] as String).toFilePath();
  }
  return out;
}

Future<String> depsJson(List<String> args) async {
  if (args.contains('-') || args.contains('--stdin')) {
    return stdin.transform(utf8.decoder).join();
  }
  final r = await Process.run('flutter', ['pub', 'deps', '--json'], runInShell: true);
  if (r.exitCode != 0) {
    stderr.writeln('check_licences: `flutter pub deps --json` failed:\n${r.stderr}');
    exit(2);
  }
  return r.stdout as String;
}

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln('usage: dart run tool/check_licences.dart [- | --stdin]');
    return;
  }
  final raw = await depsJson(args);
  final start = raw.indexOf('{'); // flutter may print banners before the JSON
  if (start < 0) {
    stderr.writeln('check_licences: no JSON in `pub deps --json` output.');
    exit(2);
  }
  final deps = jsonDecode(raw.substring(start)) as Map<String, dynamic>;
  final rootName = deps['root'] as String?;
  final roots = packageRoots();

  final findings = <Finding>[];
  for (final p in (deps['packages'] as List).cast<Map<String, dynamic>>()) {
    final name = p['name'] as String;
    final version = '${p['version'] ?? ''}';
    final source = p['source'] as String? ?? '';
    if (name == rootName || p['kind'] == 'root' || source == 'sdk') continue;
    if (exceptions.containsKey(name)) {
      findings.add(
        Finding(name, version, exceptions[name]!, Verdict.allowed, 'reviewed exception'),
      );
      continue;
    }
    final dir = roots[name];
    if (dir == null) {
      findings.add(Finding(name, version, 'not in package_config', Verdict.unknown));
      continue;
    }
    File? lic;
    for (final n in licenceFiles) {
      final f = File('$dir${Platform.pathSeparator}$n');
      if (f.existsSync()) {
        lic = f;
        break;
      }
    }
    if (lic == null) {
      findings.add(Finding(name, version, 'no LICENSE file', Verdict.unknown));
      continue;
    }
    final (licence, verdict) = classify(lic.readAsStringSync());
    findings.add(Finding(name, version, licence, verdict));
  }
  findings.sort((a, b) => a.name.compareTo(b.name));

  final byLicence = <String, int>{};
  for (final f in findings.where((f) => f.verdict == Verdict.allowed)) {
    byLicence[f.licence] = (byLicence[f.licence] ?? 0) + 1;
  }
  stdout.writeln('licences: ${findings.length} packages checked');
  for (final e in byLicence.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    stdout.writeln('  ${e.key.padRight(12)} ${e.value}');
  }

  final bad = findings.where((f) => f.verdict != Verdict.allowed).toList();
  if (bad.isEmpty) {
    stdout.writeln('licence allow-list: ok');
    return;
  }
  stderr.writeln('');
  for (final f in bad) {
    final why = f.verdict == Verdict.forbidden ? 'forbidden' : 'needs review';
    stderr.writeln('licence gate: ${f.name} ${f.version} — ${f.licence} ($why)');
  }
  stderr.writeln(
    '\nAllowed: MIT, BSD, Apache-2.0, ISC, MPL-2.0, Zlib. '
    'Add a reviewed entry to `exceptions` in tool/check_licences.dart only with a reason.',
  );
  exit(1);
}
