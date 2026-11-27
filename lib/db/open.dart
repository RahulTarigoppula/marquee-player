// How the app opens its database (main.dart). Tests build a MarqueeDatabase their own way and
// never come through here: this file is the only one in lib/db that needs the plugins.
//
// Android: the file drift_flutter always used, opened the way it always was.
// Windows: the application-support folder (%APPDATA%\<company>\<app>), with write-ahead
// logging; a database from an older version is moved there first (see location.dart for the
// rules, and for why it left Documents). Whenever the move cannot be made the old file is
// opened exactly as before.
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'location.dart';

/// drift_flutter names the file `<name>.sqlite`.
const String _name = 'marquee';

/// The executor behind the app's [GeneratedDatabase]. Returns at once: the file is found (and,
/// once, moved) and opened on a background isolate while the first frame is being built; the
/// first query waits for it.
QueryExecutor openMarqueeDatabase() {
  if (!Platform.isWindows) return driftDatabase(name: _name);
  return DatabaseConnection.delayed(
    Future(() async {
      final place = await _windowsPlace();
      final opened = place == null || place.legacy
          // As every version before this one opened it: Documents, rollback journal.
          ? driftDatabase(name: _name)
          : driftDatabase(name: _name, native: _appDataOptions(place.path));
      return opened is DatabaseConnection ? opened : DatabaseConnection(opened);
    }),
  );
}

/// Where the database is on this PC, after the one-time move. Null when Windows will not even
/// name the Documents folder: drift_flutter then fails, or copes, just as it used to.
Future<DatabasePlace?> _windowsPlace() async {
  final String legacy;
  try {
    // drift_flutter's own default, spelled out: this is the file older versions wrote.
    legacy = p.join((await getApplicationDocumentsDirectory()).path, '$_name.sqlite');
  } on Object {
    return null;
  }
  try {
    final support = await getApplicationSupportDirectory();
    return await settleDatabase(legacyPath: legacy, path: p.join(support.path, '$_name.sqlite'));
  } on Object {
    return (path: legacy, legacy: true);
  }
}

DriftNativeOptions _appDataOptions(String path) => DriftNativeOptions(
  databasePath: () async => path,
  // Runs on the database isolate each time the file is opened, so it must not reach for
  // anything outside itself.
  setup: (db) {
    try {
      // Write-ahead logging: the resume point saved every five seconds becomes one append to
      // one file, instead of a journal created and deleted around every write.
      final answer = db.select('PRAGMA journal_mode = WAL');
      final mode = answer.isEmpty ? null : answer.first.values.first;
      // Only with the log in place is "normal" as safe against a power cut as "full" was.
      if (mode == 'wal') db.execute('PRAGMA synchronous = NORMAL');
    } on Object {
      // The journal it always had: slower, never wrong.
    }
  },
);
