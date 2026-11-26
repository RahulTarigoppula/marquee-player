// The device library's rules: what a scanned video is, how videos group into folders, the four
// sort orders, the search match, a folder's neighbours (next / previous episode), what counts as
// "new", and the start-up cache. Pure Dart: the scanners (lib/platform/library_scan.dart) make
// the items, the Lobby draws them.
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

int _byName(LibraryItem a, LibraryItem b) {
  final c = naturalCompare(a.name, b.name);
  return c != 0 ? c : a.locator.compareTo(b.locator);
}

/// [items] in the chosen order (a new list). Ties fall back to the natural name order, and
/// videos of unknown length sort after every known one under "Longest first".
List<LibraryItem> sortLibrary(Iterable<LibraryItem> items, LibrarySort sort) {
  int then(int c, LibraryItem a, LibraryItem b) => c != 0 ? c : _byName(a, b);
  return [...items]..sort(
    (a, b) => switch (sort) {
      LibrarySort.name => _byName(a, b),
      LibrarySort.newest => then(b.modifiedAt.compareTo(a.modifiedAt), a, b),
      LibrarySort.largest => then(b.sizeBytes.compareTo(a.sizeBytes), a, b),
      LibrarySort.longest => then((b.durationMs ?? -1).compareTo(a.durationMs ?? -1), a, b),
    },
  );
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
  int byName(LibraryFolder a, LibraryFolder b) {
    final c = naturalCompare(a.name, b.name);
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

final _separators = RegExp(r'[\s._\-\[\](){}+,]+');

/// Lower case, with the punctuation release names use instead of spaces folded to one space:
/// `The.Third_Man-1949` reads `the third man 1949`.
String searchFold(String text) => text.toLowerCase().replaceAll(_separators, ' ').trim();

/// Whether [item] answers [query]: every word of the query appears in the file or folder name
/// (in any order), or the query matches with the spaces taken out (`thirdman`). An empty query
/// matches everything.
bool matchesSearch(LibraryItem item, String query) {
  final q = searchFold(query);
  if (q.isEmpty) return true;
  final hay = searchFold('${item.name} ${item.folderName}');
  if (q.split(' ').every(hay.contains)) return true;
  return hay.replaceAll(' ', '').contains(q.replaceAll(' ', ''));
}

List<LibraryItem> searchLibrary(Iterable<LibraryItem> items, String query) =>
    searchFold(query).isEmpty
    ? [...items]
    : [
        for (final i in items)
          if (matchesSearch(i, query)) i,
      ];

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
/// could not be read is tried again only when it changes.
String thumbKey(LibraryItem item) => urlResumeKey(
  '${item.locator}|${item.sizeBytes}|${item.modifiedAt.millisecondsSinceEpoch}',
).value;

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
