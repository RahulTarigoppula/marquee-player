// A Dart port of the MIT `parse-torrent-title` grammar, extended for anime brackets.
// Never guessit-js (LGPL-3.0). When confidence is `low`, Threading sends the RAW filename as
// `query=` and lets OpenSubtitles run guessit server-side.
import 'models/subtitles.dart';

const _videoExtensions = {
  'mkv', 'mp4', 'm4v', 'avi', 'webm', 'mov', 'ts', 'm2ts', 'mts', 'wmv', 'flv', 'mpg', //
  'mpeg', '3gp', 'ogv', 'vob', 'divx', 'rmvb',
};
const _subtitleExtensions = {'srt', 'ass', 'ssa', 'sub', 'vtt', 'idx', 'sup'};

final _resolution = RegExp(r'^(\d{3,4}p|4K|UHD)$', caseSensitive: false);
final _source = RegExp(
  r'^(BluRay|Blu-Ray|BDRip|BRRip|WEB-DL|WEBDL|WEBRip|WEB|HDTV|DVDRip|REMUX|HDRip)$',
  caseSensitive: false,
);
final _sourceUpperOnly = RegExp(r'^(CAM|TS|TC)$'); // too common as words in lower case
final _codec = RegExp(r'^(x264|x265|H264|H265|HEVC|AVC|XviD|DivX|AV1|VP9)$', caseSensitive: false);
final _audio = RegExp(
  r'^(AAC|AC3|EAC3|DDP?|DTS|DTS-HD|TrueHD|Atmos|FLAC|MP3|Opus)(\d)?$',
  caseSensitive: false,
);
final _flag = RegExp(
  r'^(PROPER|REPACK|REMASTERED|EXTENDED|UNRATED|HDR|HDR10|10bit|IMAX)$',
  caseSensitive: false,
);
final _year = RegExp(r'^(19|20)\d{2}$');
final _sxe = RegExp(r'^S(\d{1,2})E(\d{1,3})$', caseSensitive: false);
final _nxn = RegExp(r'^(\d{1,2})x(\d{1,3})$');
final _seasonEpisodeWords = RegExp(r'Season (\d+).*Episode (\d+)', caseSensitive: false);
final _animeGroup = RegExp(r'^\[([^\]\s]+)\]$');
final _crc = RegExp(r'^\[[0-9A-Fa-f]{8}\]$');
final _bareInt = RegExp(r'^\d{1,4}$');
final _tokenizer = RegExp(r'\[[^\]]*\]|\([^)]*\)|\S+');
final _alpha = RegExp(r'[A-Za-z]');

/// True for filenames the picker must never hand to the parser (subtitles are not videos).
bool isSubtitleFile(String filename) =>
    _subtitleExtensions.contains(_extensionOf(filename).toLowerCase());

String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot <= 0 ? '' : filename.substring(dot + 1);
}

String _unwrap(String t) =>
    (t.length > 2 && '([{'.contains(t[0]) && ')]}'.contains(t[t.length - 1]))
    ? t.substring(1, t.length - 1)
    : t;

/// A token counts if it — or any `-`-separated part of it — matches (keeps `WEB-DL` whole
/// while still reading `x264-AMIABLE` as codec + group).
bool _any(String token, bool Function(String) test) {
  final t = _unwrap(token);
  if (test(t)) return true;
  return t.contains('-') && t.split('-').any(test);
}

String? _first(String token, RegExp re) {
  final t = _unwrap(token);
  if (re.hasMatch(t)) return t;
  if (!t.contains('-')) return null;
  for (final p in t.split('-')) {
    if (re.hasMatch(p)) return p;
  }
  return null;
}

bool _isSource(String t) => _source.hasMatch(t) || _sourceUpperOnly.hasMatch(t);

bool _isQuality(String token) => _any(
  token,
  (t) =>
      _resolution.hasMatch(t) ||
      _isSource(t) ||
      _codec.hasMatch(t) ||
      _audio.hasMatch(t) ||
      _flag.hasMatch(t),
);

String _collapse(Iterable<String> tokens) =>
    tokens.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Parses a basename. Returns null for subtitle files (`.srt`/`.ass` are not videos).
ParsedName? parseName(String filename) {
  if (isSubtitleFile(filename)) return null;
  final raw = filename;
  var name = filename;
  final ext = _extensionOf(name).toLowerCase();
  if (_videoExtensions.contains(ext)) name = name.substring(0, name.length - ext.length - 1);
  final original = name;

  // [._] become spaces ONLY between word characters — keeps S02E04, x264, WEB-DL intact.
  name = name.replaceAllMapped(RegExp(r'(?<=[A-Za-z0-9])[._](?=[A-Za-z0-9])'), (_) => ' ');
  final tokens = _tokenizer.allMatches(name).map((m) => m.group(0)!).toList();
  if (tokens.isEmpty) return ParsedName(title: raw, raw: raw);

  final anime = _animeGroup.firstMatch(tokens.first);
  if (anime != null) return _parseAnime(tokens, anime.group(1)!, raw);

  // 2. quality boundary — everything after the FIRST quality token is metadata.
  var cut = tokens.indexWhere(_isQuality);
  if (cut < 0) cut = tokens.length;

  // 4. season / episode (before the year, so an S/E token bounds the title span).
  int? season, episode;
  var seIndex = -1;
  for (var i = 0; i < tokens.length; i++) {
    final m = _sxe.firstMatch(tokens[i]) ?? _nxn.firstMatch(tokens[i]);
    if (m != null) {
      season = int.parse(m.group(1)!);
      episode = int.parse(m.group(2)!);
      seIndex = i;
      break;
    }
  }
  if (seIndex < 0) {
    final m = _seasonEpisodeWords.firstMatch(name);
    if (m != null) {
      season = int.parse(m.group(1)!);
      episode = int.parse(m.group(2)!);
      seIndex = tokens.indexWhere((t) => t.toLowerCase() == 'season');
    }
  }
  final titleEnd = seIndex >= 0 && seIndex < cut ? seIndex : cut;

  // 3. year — the LAST 19xx/20xx token strictly before the title end.
  int? year;
  var yearIndex = -1;
  for (var i = titleEnd - 1; i >= 0; i--) {
    if (_year.hasMatch(_unwrap(tokens[i]))) {
      yearIndex = i;
      break;
    }
  }
  final titleTokens = <String>[
    for (var i = 0; i < titleEnd; i++)
      if (i != yearIndex) tokens[i],
  ];
  if (yearIndex >= 0) {
    if (titleTokens.isEmpty) {
      titleTokens.add(tokens[yearIndex]); // '1917.1080p' — the year IS the title
    } else {
      year = int.parse(_unwrap(tokens[yearIndex]));
    }
  }

  // 5. metadata from the tail.
  String? resolution, source, codec;
  var remastered = false, proper = false, extended = false, anyQuality = false;
  for (final t in tokens.skip(cut)) {
    resolution ??= _first(t, _resolution);
    source ??= _first(t, _source) ?? _first(t, _sourceUpperOnly);
    codec ??= _first(t, _codec);
    final u = _unwrap(t).toUpperCase();
    remastered |= u == 'REMASTERED';
    proper |= u == 'PROPER' || u == 'REPACK';
    extended |= u == 'EXTENDED';
    anyQuality |= _isQuality(t);
  }

  final title = _collapse(titleTokens.map(_stripDanglingDash)).trim();
  final group = _groupOf(original);
  final hasSE = season != null || episode != null;
  final alphaTokens = titleTokens.where(_alpha.hasMatch).length;

  return ParsedName(
    title: title.isEmpty ? original : title,
    year: year,
    season: season,
    episode: episode,
    resolution: resolution,
    source: source,
    videoCodecToken: codec,
    group: group,
    remastered: remastered,
    proper: proper,
    extended: extended,
    kind: hasSE ? FeatureKind.episode : FeatureKind.movie,
    confidence: (year != null || hasSE) && alphaTokens >= 1
        ? NameConfidence.high
        : (titleTokens.length >= 2 && anyQuality)
        ? NameConfidence.medium
        : NameConfidence.low,
    raw: raw,
  );
}

String _stripDanglingDash(String t) => t == '-' ? '' : t;

/// Token after the LAST '-' in the ORIGINAL name, unless it is a codec/resolution/source, or
/// contains a dot.
String? _groupOf(String original) {
  final dash = original.lastIndexOf('-');
  if (dash < 0 || dash == original.length - 1) return null;
  final g = original.substring(dash + 1).trim();
  if (g.isEmpty || g.contains('.') || g.contains(' ')) return null;
  if (_codec.hasMatch(g) || _resolution.hasMatch(g) || _isSource(g)) return null;
  if (original.toUpperCase().endsWith('WEB-DL')) return null;
  return g;
}

ParsedName _parseAnime(List<String> tokens, String group, String raw) {
  var body = tokens.skip(1).toList();
  while (body.isNotEmpty && _crc.hasMatch(body.last)) {
    body = body.sublist(0, body.length - 1);
  }
  final sep = body.indexOf('-');
  int? episode;
  var titleEnd = body.length;
  if (sep >= 0) {
    titleEnd = sep;
    for (final t in body.skip(sep + 1)) {
      if (_bareInt.hasMatch(t)) {
        episode = int.parse(t);
        break;
      }
    }
  }
  String? resolution;
  for (final t in body) {
    resolution ??= _first(t, _resolution);
  }
  final title = _collapse(body.take(titleEnd));
  return ParsedName(
    title: title.isEmpty ? raw : title,
    episode: episode,
    resolution: resolution,
    group: group,
    kind: FeatureKind.episode,
    confidence: NameConfidence.high,
    raw: raw,
  );
}

int _rank(NameConfidence c) => switch (c) {
  NameConfidence.high => 2,
  NameConfidence.medium => 1,
  NameConfidence.low => 0,
};

/// Parse only the basename; when that is `low`, try the parent directory and keep whichever
/// is more confident (`D:\Films\The Third Man (1949)\video.mkv`).
ParsedName? parsePath(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final base = parseName(parts.last);
  if (base == null || base.confidence != NameConfidence.low || parts.length < 2) return base;
  final parent = parseName(parts[parts.length - 2]);
  if (parent == null || _rank(parent.confidence) <= _rank(base.confidence)) return base;
  return ParsedName(
    title: parent.title,
    year: parent.year,
    season: parent.season,
    episode: parent.episode,
    resolution: base.resolution ?? parent.resolution,
    source: base.source ?? parent.source,
    videoCodecToken: base.videoCodecToken ?? parent.videoCodecToken,
    group: base.group ?? parent.group,
    remastered: parent.remastered,
    proper: parent.proper,
    extended: parent.extended,
    kind: parent.kind,
    confidence: parent.confidence,
    raw: base.raw,
  );
}
