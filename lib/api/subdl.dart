// Subdl — optional fallback (rung 4). Search with the USER's own key; download ANONYMOUSLY
// (no api_key on dl.subdl.com). The payload is a zip, unzipped in memory with hard limits.
import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../engine/models/models.dart';
import '../engine/threading.dart' show SearchRequest;
import 'net.dart';

const int kMaxZipEntryBytes = 2 * 1024 * 1024;

class UnsafeZip implements Exception {
  final String reason;
  const UnsafeZip(this.reason);
  @override
  String toString() => 'UnsafeZip($reason)';
}

class ZipText {
  final String name;
  final Uint8List bytes;
  const ZipText(this.name, this.bytes);
}

bool _unsafeName(String n) =>
    n.contains('..') || n.startsWith('/') || n.contains('\\') || RegExp(r'^[A-Za-z]:').hasMatch(n);

/// Returns the first `.srt` (else `.ass`/`.ssa`) entry. Rejects traversal names, oversized
/// entries and unknown compression. Nothing is ever written from a zip-supplied path.
ZipText extractSubtitle(Uint8List zip) {
  final bd = ByteData.sublistView(zip);
  // End of central directory: scan back for 0x06054b50.
  var eocd = -1;
  for (var i = zip.length - 22; i >= 0 && i >= zip.length - 65557; i--) {
    if (bd.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const UnsafeZip('not a zip');
  final count = bd.getUint16(eocd + 10, Endian.little);
  var p = bd.getUint32(eocd + 16, Endian.little);
  ZipText? srt, ass;
  for (var n = 0; n < count; n++) {
    if (p + 46 > zip.length || bd.getUint32(p, Endian.little) != 0x02014b50) {
      throw const UnsafeZip('bad central directory');
    }
    final method = bd.getUint16(p + 10, Endian.little);
    final compSize = bd.getUint32(p + 20, Endian.little);
    final size = bd.getUint32(p + 24, Endian.little);
    final nameLen = bd.getUint16(p + 28, Endian.little);
    final extraLen = bd.getUint16(p + 30, Endian.little);
    final commentLen = bd.getUint16(p + 32, Endian.little);
    final local = bd.getUint32(p + 42, Endian.little);
    final name = utf8.decode(zip.sublist(p + 46, p + 46 + nameLen), allowMalformed: true);
    p += 46 + nameLen + extraLen + commentLen;

    if (_unsafeName(name)) throw UnsafeZip('path traversal: $name');
    final lower = name.toLowerCase();
    final isSrt = lower.endsWith('.srt');
    final isAss = lower.endsWith('.ass') || lower.endsWith('.ssa');
    if (!isSrt && !isAss) continue;
    if ((isSrt && srt != null) || (isAss && ass != null)) continue;
    if (size > kMaxZipEntryBytes || compSize > kMaxZipEntryBytes) {
      throw UnsafeZip('entry too large: $name');
    }
    final lnameLen = bd.getUint16(local + 26, Endian.little);
    final lextraLen = bd.getUint16(local + 28, Endian.little);
    final start = local + 30 + lnameLen + lextraLen;
    if (start + compSize > zip.length) throw const UnsafeZip('truncated entry');
    final raw = Uint8List.sublistView(zip, start, start + compSize);
    final Uint8List bytes = switch (method) {
      0 => Uint8List.fromList(raw),
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(raw)),
      _ => throw UnsafeZip('unsupported compression $method'),
    };
    if (bytes.length > kMaxZipEntryBytes) throw UnsafeZip('entry too large: $name');
    final entry = ZipText(name, bytes);
    if (isSrt) {
      srt = entry;
    } else {
      ass = entry;
    }
  }
  final found = srt ?? ass;
  if (found == null) throw const UnsafeZip('no subtitle in zip');
  return found;
}

class SubdlClient {
  final http.Client client;
  final String? apiKey; // the USER's own key, from secure storage
  SubdlClient({http.Client? client, this.apiKey}) : client = client ?? http.Client();

  Future<List<SubtitleCandidate>> search(SearchRequest r) async {
    final key = apiKey;
    if (key == null || key.isEmpty) return const [];
    final p = r.parsed;
    final params = {
      'api_key': key,
      'languages': r.languages.map((l) => l.toUpperCase()).join(','),
      'type': p?.kind == FeatureKind.episode ? 'tv' : 'movie',
      'film_name': r.query ?? p?.title ?? '',
      if (p?.year != null) 'year': '${p?.year}',
      if (p?.season != null) 'season_number': '${p?.season}',
      if (p?.episode != null) 'episode_number': '${p?.episode}',
    };
    final uri = Uri.parse('https://api.subdl.com/api/v1/subtitles?${sortedQuery(params)}');
    final res = await send(client, () => http.Request('GET', uri));
    return parseSearch(res.body);
  }

  static List<SubtitleCandidate> parseSearch(String body) {
    final j = jsonDecode(body);
    if (j is! Map<String, Object?>) return const [];
    final subs = j['subtitles'];
    if (subs is! List) return const [];
    return [
      for (final s in subs.whereType<Map<String, Object?>>())
        if (s['url'] is String)
          SubtitleCandidate(
            provider: SubtitleProvider.subdl,
            id: s['url']! as String,
            language: ((s['language'] as String?) ?? 'en').toLowerCase(),
            release: s['release_name'] as String?,
            hearingImpaired: s['hi'] == true,
            moviehashMatch: false, // Subdl has no hash search: it can never light MATCH
          ),
    ];
  }

  /// Anonymous download from dl.subdl.com — the key is never sent to that host.
  Future<ZipText> download(String urlPath) async {
    final path = urlPath.startsWith('/subtitle/') ? urlPath.substring(10) : urlPath;
    if (path.contains('..') || path.contains('://')) {
      throw const UnsafeZip('bad Subdl path');
    }
    final uri = Uri.parse('https://dl.subdl.com/subtitle/$path');
    final res = await send(client, () => http.Request('GET', uri));
    return extractSubtitle(res.bodyBytes);
  }
}
