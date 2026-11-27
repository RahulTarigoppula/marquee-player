// The device library's rules: what a scanned video is, how videos group into folders, the four
// sort orders, the search match, a folder's neighbours (next / previous episode), what counts as
// "new", and the start-up cache. Pure Dart: the scanners (lib/platform/library_scan.dart) make
// the items, the Lobby draws them.
import 'dart:convert';
import 'dart:math' as math;

import 'filename.dart';
import 'models/settings.dart';
import 'models/subtitles.dart';
import 'playback.dart';

/// One video found on the device. [locator] is a Windows path or an Android MediaStore
/// content:// URI; [folderPath] is only a grouping key (a path, or MediaStore's RELATIVE_PATH).
class LibraryItem {
  final String locator;

  /// The file name, extension included (the filename parser's input).
  final String name;
  final String folderPath;
  final String folderName;
  final int sizeBytes;
  final int? durationMs;
  final int? width, height;

  /// When the file last changed (for a download: when it arrived). "Newest first" and the NEW
  /// mark both read it.
  final DateTime modifiedAt;

  const LibraryItem({
    required this.locator,
    required this.name,
    required this.folderPath,
    required this.folderName,
    required this.sizeBytes,
    this.durationMs,
    this.width,
    this.height,
    required this.modifiedAt,
  });

  /// A filesystem path as an item: the folder is the parent, named by its last segment
  /// (`D:` for a drive root).
  factory LibraryItem.fromPath(
    String path, {
    required int sizeBytes,
    required DateTime modifiedAt,
    int? durationMs,
    int? width,
    int? height,
  }) {
    final cut = math.max(path.lastIndexOf(r'\'), path.lastIndexOf('/'));
    final parent = cut <= 0 ? '' : path.substring(0, cut);
    final parts = parent.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
    return LibraryItem(
      locator: path,
      name: path.substring(cut + 1),
      folderPath: parent,
      folderName: parts.isEmpty ? parent : parts.last,
      sizeBytes: sizeBytes,
      durationMs: durationMs,
      width: width,
      height: height,
      modifiedAt: modifiedAt,
    );
  }

  /// What a probe learned (the Windows scan only stats files; the thumbnailer fills these in).
  LibraryItem withProbe({int? durationMs, int? width, int? height}) => LibraryItem(
    locator: locator,
    name: name,
    folderPath: folderPath,
    folderName: folderName,
    sizeBytes: sizeBytes,
    durationMs: durationMs ?? this.durationMs,
    width: width ?? this.width,
    height: height ?? this.height,
    modifiedAt: modifiedAt,
  );

  /// The same bytes as [other]: same place, size and change time.
  bool sameFileAs(LibraryItem other) =>
      locator == other.locator && sizeBytes == other.sizeBytes && modifiedAt == other.modifiedAt;

  /// A compact row for the start-up cache (thousands of these are stored as one JSON value).
  List<Object?> toRow() => [
    locator,
    name,
    folderPath,
    folderName,
    sizeBytes,
    durationMs,
    width,
    height,
    modifiedAt.millisecondsSinceEpoch,
  ];

  /// Null for anything that is not a row [toRow] wrote.
  static LibraryItem? fromRow(Object? row) {
    if (row is! List || row.length < 9) return null;
    final [locator, name, folderPath, folderName, size, duration, width, height, modified, ...] =
        row;
    if (locator is! String || name is! String || folderPath is! String || folderName is! String) {
      return null;
    }
    if (size is! num || modified is! num) return null;
    return LibraryItem(
      locator: locator,
      name: name,
      folderPath: folderPath,
      folderName: folderName,
      sizeBytes: size.toInt(),
      durationMs: duration is num ? duration.toInt() : null,
      width: width is num ? width.toInt() : null,
      height: height is num ? height.toInt() : null,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(modified.toInt()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryItem &&
      other.locator == locator &&
      other.name == name &&
      other.folderPath == folderPath &&
      other.folderName == folderName &&
      other.sizeBytes == sizeBytes &&
      other.durationMs == durationMs &&
      other.width == width &&
      other.height == height &&
      other.modifiedAt == modifiedAt;

  @override
  int get hashCode => Object.hash(locator, sizeBytes, durationMs, width, height, modifiedAt);
}

// ───────────────────────────── the start-up cache ─────────────────────────────

const int _cacheVersion = 1;

/// The cache holds at most this many videos: enough for an instant first screen, small enough
/// to encode and decode without a visible pause. A larger library fills in when the scan lands.
const int kLibraryCacheLimit = 5000;

Map<String, Object?> encodeLibraryCache(
  List<LibraryItem> items, {
  int limit = kLibraryCacheLimit,
}) => {
  'v': _cacheVersion,
  'items': [for (final i in items.take(limit)) i.toRow()],
};

/// The cached items, or null when there is no cache (or one from a format this build does not
/// know). Rows that do not read are skipped.
List<LibraryItem>? decodeLibraryCache(Object? json) {
  if (json is! Map || json['v'] != _cacheVersion) return null;
  final rows = json['items'];
  if (rows is! List) return null;
  return [for (final r in rows) ?LibraryItem.fromRow(r)];
}

/// The cache as the text that is stored. With [decodeLibraryCacheText] it is everything the
/// cache costs, in two plain functions of plain values, so the app can run either off the UI
/// isolate: thousands of rows take longer to encode or decode than a frame lasts.
String encodeLibraryCacheText(List<LibraryItem> items, {int limit = kLibraryCacheLimit}) =>
    jsonEncode(encodeLibraryCache(items, limit: limit));

/// The items in stored cache [text]; null when it is not a cache this build can read.
List<LibraryItem>? decodeLibraryCacheText(String text) {
  try {
    return decodeLibraryCache(jsonDecode(text));
  } on FormatException {
    return null;
  }
}

/// A fresh scan that only knows names and sizes keeps what was already learned about the same
/// file (duration, picture size), so a rescan never blanks the badges.
List<LibraryItem> carryProbes(List<LibraryItem> fresh, List<LibraryItem> known) {
  if (known.isEmpty) return fresh;
  final byLocator = {for (final k in known) k.locator: k};
  return [
    for (final f in fresh)
      switch (byLocator[f.locator]) {
        final k? when k.sameFileAs(f) => f.withProbe(
          durationMs: f.durationMs ?? k.durationMs,
          width: f.width ?? k.width,
          height: f.height ?? k.height,
        ),
        _ => f,
      },
  ];
}

/// True when two scans found the same files with the same details, in any order.
bool sameLibrary(List<LibraryItem> a, List<LibraryItem> b) {
  if (a.length != b.length) return false;
  final byLocator = {for (final i in a) i.locator: i};
  return b.every((i) => byLocator[i.locator] == i);
}

// ───────────────────────────── order ─────────────────────────────

/// What sorting and searching ask of an item's name, worked out once per item instead of once
/// per comparison (a sort) or once per keystroke (a search): on a library of thousands that
/// is the difference between a frozen window and an instant list.
class _ItemKeys {
  _ItemKeys(this._item) : name = naturalKey(_item.name);
  final LibraryItem _item;
  final NaturalKey name;
  String? _hay;
  String? _squashed;

  /// The file and folder name as the search reads them (see [searchFold]).
  String get hay => _hay ??= searchFold('${_item.name} ${_item.folderName}');

  /// [hay] with the spaces taken out, for a query typed as one word.
  String get squashed => _squashed ??= hay.replaceAll(' ', '');
}

/// Kept beside the items, not in them: an item stays a small constant value, and its keys go
/// when it does (a rescan that replaces the list drops the old keys with it).
final _itemKeys = Expando<_ItemKeys>('library item keys');

_ItemKeys _keysOf(LibraryItem item) => _itemKeys[item] ??= _ItemKeys(item);

int _byName(LibraryItem a, LibraryItem b) {
  if (identical(a, b)) return 0;
  final c = _keysOf(a).name.compareTo(_keysOf(b).name);
  return c != 0 ? c : a.locator.compareTo(b.locator);
}

/// [items] in the chosen order (a new list). Ties fall back to the natural name order, and
/// videos of unknown length sort after every known one under "Longest first".
List<LibraryItem> sortLibrary(Iterable<LibraryItem> items, LibrarySort sort) {
  int then(int c, LibraryItem a, LibraryItem b) => c != 0 ? c : _byName(a, b);
  List<LibraryItem> by(int Function(LibraryItem a, LibraryItem b) order) => [...items]..sort(order);
  switch (sort) {
    case LibrarySort.name:
      // The default order, and the one where every comparison reads the names: each item's
      // key is looked up once here, not twice per comparison.
      final keyed = [for (final i in items) (key: _keysOf(i).name, item: i)]
        ..sort((a, b) {
          final c = a.key.compareTo(b.key);
          return c != 0 ? c : a.item.locator.compareTo(b.item.locator);
        });
      return [for (final k in keyed) k.item];
    case LibrarySort.newest:
      return by((a, b) => then(b.modifiedAt.compareTo(a.modifiedAt), a, b));
    case LibrarySort.largest:
      return by((a, b) => then(b.sizeBytes.compareTo(a.sizeBytes), a, b));
    case LibrarySort.longest:
      return by((a, b) => then((b.durationMs ?? -1).compareTo(a.durationMs ?? -1), a, b));
  }
}

// ───────────────────────────── folders ─────────────────────────────

/// A folder of the library, as its card shows it.
class LibraryFolder {
  final String path;
  final String name;
  final int count;
  final int totalBytes;

  /// The sum of the known lengths (0 when none is known).
  final int totalDurationMs;

  /// The most recently changed video: its frame is the folder's picture.
  final LibraryItem newest;
  const LibraryFolder({
    required this.path,
    required this.name,
    required this.count,
    required this.totalBytes,
    required this.totalDurationMs,
    required this.newest,
  });

  DateTime get newestAt => newest.modifiedAt;
}

/// Groups [items] by folder and orders the folders by [sort] (name: natural order; newest: the
/// latest video; largest: total size; longest: total length).
List<LibraryFolder> groupFolders(
  Iterable<LibraryItem> items, {
  LibrarySort sort = LibrarySort.name,
}) {
  final groups = <String, List<LibraryItem>>{};
  for (final i in items) {
    (groups[i.folderPath] ??= []).add(i);
  }
  final folders = [
    for (final MapEntry(key: path, value: videos) in groups.entries)
      LibraryFolder(
        path: path,
        name: videos.first.folderName,
        count: videos.length,
        totalBytes: videos.fold(0, (sum, v) => sum + v.sizeBytes),
        totalDurationMs: videos.fold(0, (sum, v) => sum + (v.durationMs ?? 0)),
        newest: videos.reduce(
          (a, b) =>
              b.modifiedAt.isAfter(a.modifiedAt) ||
                  (b.modifiedAt == a.modifiedAt && _byName(b, a) < 0)
              ? b
              : a,
        ),
      ),
  ];
  // Each folder's name is cut up once, not once per comparison.
  final keys = {for (final f in folders) f: naturalKey(f.name)};
  int byName(LibraryFolder a, LibraryFolder b) {
    final c = keys[a]!.compareTo(keys[b]!);
    return c != 0 ? c : a.path.compareTo(b.path);
  }

  int then(int c, LibraryFolder a, LibraryFolder b) => c != 0 ? c : byName(a, b);
  return folders..sort(
    (a, b) => switch (sort) {
      LibrarySort.name => byName(a, b),
      LibrarySort.newest => then(b.newestAt.compareTo(a.newestAt), a, b),
      LibrarySort.largest => then(b.totalBytes.compareTo(a.totalBytes), a, b),
      LibrarySort.longest => then(b.totalDurationMs.compareTo(a.totalDurationMs), a, b),
    },
  );
}

/// The videos of one folder.
List<LibraryItem> inFolder(Iterable<LibraryItem> items, String folderPath) => [
  for (final i in items)
    if (i.folderPath == folderPath) i,
];

/// The videos either side of [locator] in its own folder, in natural order, and the folder's
/// first video (where "repeat the folder" starts again). All null when [locator] is not in the
/// library.
({String? previous, String? next, String? first}) libraryNeighbours(
  List<LibraryItem> items,
  String locator,
) {
  final current = items.where((i) => i.locator == locator).firstOrNull;
  if (current == null) return (previous: null, next: null, first: null);
  final folder = inFolder(items, current.folderPath)..sort(_byName);
  final at = folder.indexWhere((i) => i.locator == locator);
  return (
    previous: at > 0 ? folder[at - 1].locator : null,
    next: at < folder.length - 1 ? folder[at + 1].locator : null,
    first: folder.first.locator,
  );
}

// ───────────────────────────── search ─────────────────────────────

/// What a release name uses instead of a space: white space itself (what a regular
/// expression calls `\s`) and `. _ - [ ] ( ) { } + ,`.
bool _isSeparator(int unit) {
  if (unit < 0x80) {
    return switch (unit) {
      0x20 || 0x09 || 0x0A || 0x0B || 0x0C || 0x0D => true,
      0x2E || 0x5F || 0x2D || 0x5B || 0x5D || 0x28 || 0x29 || 0x7B || 0x7D || 0x2B || 0x2C => true,
      _ => false,
    };
  }
  return unit == 0xA0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000 ||
      unit == 0xFEFF;
}

/// Lower case, with the punctuation release names use instead of spaces folded to one space:
/// `The.Third_Man-1949` reads `the third man 1949`. Exactly
/// `toLowerCase().replaceAll(RegExp(r'[\s._\-\[\](){}+,]+'), ' ').trim()`, done by hand: it
/// runs once for every video of a library on the first key of a search.
String searchFold(String text) {
  final lower = text.toLowerCase();
  final end = lower.length;
  StringBuffer? out;
  var kept = 0; // lower[kept..at) is waiting to be copied
  var at = 0;
  while (at < end) {
    if (!_isSeparator(lower.codeUnitAt(at))) {
      at++;
      continue;
    }
    var to = at + 1;
    while (to < end && _isSeparator(lower.codeUnitAt(to))) {
      to++;
    }
    // A single space already reads as itself: most file names are copied in a few pieces.
    if (to - at > 1 || lower.codeUnitAt(at) != 0x20) {
      (out ??= StringBuffer())
        ..write(lower.substring(kept, at))
        ..write(' ');
      kept = to;
    }
    at = to;
  }
  if (out == null) return lower.trim();
  out.write(lower.substring(kept));
  return out.toString().trim();
}

/// A search as typed, folded once for the whole list.
class _Query {
  _Query(String text) : this._(searchFold(text));
  _Query._(String folded)
    : isEmpty = folded.isEmpty,
      words = folded.split(' '),
      squashed = folded.replaceAll(' ', '');
  final bool isEmpty;
  final List<String> words;
  final String squashed;

  bool matches(LibraryItem item) {
    if (isEmpty) return true;
    final keys = _keysOf(item);
    return words.every(keys.hay.contains) || keys.squashed.contains(squashed);
  }
}

/// Whether [item] answers [query]: every word of the query appears in the file or folder name
/// (in any order), or the query matches with the spaces taken out (`thirdman`). An empty query
/// matches everything.
bool matchesSearch(LibraryItem item, String query) => _Query(query).matches(item);

List<LibraryItem> searchLibrary(Iterable<LibraryItem> items, String query) {
  final q = _Query(query);
  return q.isEmpty
      ? [...items]
      : [
          for (final i in items)
            if (q.matches(i)) i,
        ];
}

// ───────────────────────────── what a card says ─────────────────────────────

/// A video counts as new for this long after it arrived.
const Duration kNewFor = Duration(days: 7);

/// The NEW mark: arrived within [kNewFor] and never played.
bool isNewItem(LibraryItem item, {required DateTime now, required bool played}) =>
    !played && !item.modifiedAt.isBefore(now.subtract(kNewFor));

/// `4K`, `1080p`, `720p`… from the picture size, or null when it is unknown or too small to be
/// worth a badge. The long edge counts too, so a 1920×800 scope film and a 1080×1920 phone
/// clip both read `1080p`.
String? resolutionBadge(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) return null;
  final long = math.max(width, height);
  final short = math.min(width, height);
  if (long >= 7000 || short >= 4000) return '8K';
  if (long >= 3200 || short >= 2000) return '4K';
  if (long >= 2400 || short >= 1300) return '1440p';
  if (long >= 1700 || short >= 1000) return '1080p';
  if (long >= 1200 || short >= 700) return '720p';
  if (short >= 460) return '480p';
  return null;
}

/// `1.4 GB`, `700 MB`, `512 KB` (binary units, as file managers show them). Empty when the
/// size is unknown.
String sizeText(int bytes) {
  if (bytes <= 0) return '';
  const kb = 1024, mb = kb * 1024, gb = mb * 1024;
  if (bytes >= gb) {
    final v = bytes / gb;
    return '${v >= 100 ? v.round() : v.toStringAsFixed(1)} GB';
  }
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${math.max(1, (bytes / kb).round())} KB';
}

String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 && isVideoFile(name) ? name.substring(0, dot) : name;
}

/// The title a library card shows. A release name the parser reads with confidence becomes
/// `The Third Man (1949)` or `Severance S02E03`; anything else (camera clips, home videos)
/// keeps its own name with the dots and underscores turned into spaces, never a guess.
String libraryTitle(String name) {
  final known = _titles[name];
  if (known != null) return known;
  // A bound, not a policy: a library larger than this works some titles out again.
  if (_titles.length >= _titleMemo) _titles.clear();
  return _titles[name] = _readTitle(name);
}

/// Titles already worked out, by file name. Reading one runs the whole filename parser, and a
/// card asks for its title on every build (a scrolling list builds cards all the time).
final _titles = <String, String>{};
const int _titleMemo = 8192;

String _readTitle(String name) {
  final stem = _stem(name);
  final plain = stem.replaceAll(RegExp(r'[._]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final parsed = parseName(name);
  if (parsed == null || parsed.confidence == NameConfidence.low || parsed.title.isEmpty) {
    return plain.isEmpty ? name : plain;
  }
  final season = parsed.season, episode = parsed.episode, year = parsed.year;
  if (episode != null) {
    String two(int n) => n.toString().padLeft(2, '0');
    return season != null
        ? '${parsed.title} S${two(season)}E${two(episode)}'
        : '${parsed.title} E${two(episode)}';
  }
  final release =
      parsed.resolution != null || parsed.source != null || parsed.videoCodecToken != null;
  // A bare year only counts when the name ENDS with it (`Name (1949)`): `holiday_2024_beach`
  // is a clip, not a film from 2024.
  final endsWithYear = year != null && RegExp('$year\\W*\$').hasMatch(stem);
  if (!release && !endsWithYear) return plain.isEmpty ? name : plain;
  return year != null ? '${parsed.title} ($year)' : parsed.title;
}

/// The cache key of an item's thumbnail: stable for the same file, different once the file is
/// replaced (its size or change time moves), so a stale frame is never shown and a file that
/// could not be read is tried again when it changes (or after [kThumbFailFor]).
String thumbKey(LibraryItem item) => urlResumeKey(
  '${item.locator}|${item.sizeBytes}|${item.modifiedAt.millisecondsSinceEpoch}',
).value;

// ───────────────────────────── videos that gave no frame ─────────────────────────────

/// A "this video gave no frame" mark is believed for this long, then the video is tried
/// again: what looked like a broken file may have been a busy system or a drive not ready.
const Duration kThumbFailFor = Duration(days: 14);

/// Whether a mark written at [markedAt] has had its time.
bool thumbFailExpired(DateTime markedAt, {required DateTime now}) =>
    now.difference(markedAt) > kThumbFailFor;

/// This many videos in a row with no frame, and not one success yet, is not that many broken
/// videos: it is the frame grabber itself that does not work on this run.
const int kThumbBreakAfter = 8;

/// The frame queue's circuit breaker. Until one frame has been made in this run of the app,
/// a video that gave none is only HELD here, not written down as broken: a cause that fails
/// every file alike (a filter this libmpv build lacks, no GPU in a remote session, a system
/// that answers nothing) must never mark a whole library. The first success proves the
/// grabber and the held marks are written; [kThumbBreakAfter] failures without one forget
/// them and stop the queue until the app is started again.
///
/// The price: a library whose first [kThumbBreakAfter] videos really are all unreadable gets
/// no frames in that run. It gets its title cards instead, and nothing is remembered wrongly.
class ThumbBreaker {
  final _held = <String>{};
  bool _proven = false;
  bool _tripped = false;

  /// No more frames in this run.
  bool get tripped => _tripped;

  /// [key] gave no frame earlier in this run and is waiting for the verdict: not asked again.
  bool holds(String key) => _held.contains(key);

  /// [key] gave no frame. True when that may be written down now.
  bool failed(String key) {
    if (_proven) return true;
    if (_tripped) return false;
    _held.add(key);
    if (_held.length >= kThumbBreakAfter) {
      _tripped = true;
      _held.clear();
    }
    return false;
  }

  /// A frame was made. Returns the keys held until now: their marks are real after all.
  List<String> succeeded() {
    _proven = true;
    final real = _held.toList();
    _held.clear();
    return real;
  }
}

/// The last segment of a folder path, whichever slash it uses (`C:\Users\me\Videos` reads
/// `Videos`); a bare drive (`D:\`) reads `D:`.
String pathLeaf(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

// ───────────────────────────── scanning rules ─────────────────────────────

/// How deep a folder scan goes below each library folder.
const int kScanMaxDepth = 6;

/// A scan stops collecting after this many videos.
const int kScanMaxItems = 20000;

const _skippedFolders = {
  'system volume information',
  'windows',
  'program files',
  'program files (x86)',
  'programdata',
  'appdata',
  'node_modules',
  'recovery',
  'msocache',
};

/// Folders a scan never enters: hidden (`.git`), system (`$RECYCLE.BIN`) and the places where
/// applications keep their own files.
bool isSkippedFolder(String name) =>
    name.isEmpty ||
    name.startsWith('.') ||
    name.startsWith(r'$') ||
    _skippedFolders.contains(name.toLowerCase());

/// Whether a scan lists [name]: a video container, and not a hidden or partial file.
bool isLibraryVideo(String name) =>
    !name.startsWith('.') && !name.startsWith('~') && isVideoFile(name);
