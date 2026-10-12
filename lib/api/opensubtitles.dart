// OpenSubtitles.com REST v1 — the only mandatory API. Native builds call it directly with the
// consumer key injected at build time (--dart-define=OS_API_KEY=…); the Worker is for Lite.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../engine/models/models.dart';
import '../engine/threading.dart' show SearchRequest;
import 'net.dart';

const String kOsApiKey = String.fromEnvironment('OS_API_KEY');
const String kMarqueeVersion = String.fromEnvironment('MARQUEE_VERSION', defaultValue: '1.0.0');
const String kDefaultHost = 'api.opensubtitles.com';

class LoginResult {
  final String token;
  final String baseUrl;
  final Quota quota;
  const LoginResult({required this.token, required this.baseUrl, required this.quota});
}

class DownloadLink {
  final String link;
  final String fileName;
  final int remaining;
  final DateTime? resetUtc;
  const DownloadLink({
    required this.link,
    required this.fileName,
    required this.remaining,
    this.resetUtc,
  });
}

class OpenSubtitlesClient {
  final http.Client client;

  /// The build's key (--dart-define), or the user's own key from the Ticket Office.
  String apiKey;
  final Future<void> Function(Duration) wait;
  String host;
  String? jwt;

  OpenSubtitlesClient({
    http.Client? client,
    this.apiKey = kOsApiKey,
    this.host = kDefaultHost,
    this.jwt,
    this.wait = _delay,
  }) : client = client ?? http.Client();

  bool get hasKey => apiKey.isNotEmpty;

  /// True when CI injected a consumer key, so the Ticket Office need not ask for one.
  static bool get hasBuiltInKey => kOsApiKey.isNotEmpty;

  Map<String, String> _headers({bool json = false}) => {
    'Api-Key': apiKey,
    'User-Agent': 'Marquee v$kMarqueeVersion',
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (jwt != null) 'Authorization': 'Bearer $jwt',
  };

  Uri _uri(String path, [Map<String, String>? params]) {
    final q = params == null ? '' : sortedQuery(params);
    return Uri.parse('https://$host/api/v1$path${q.isEmpty ? '' : '?$q'}');
  }

  /// The exact query a search sends — also the search_cache key.
  static Map<String, String> searchParams(SearchRequest r) {
    final hash = r.hash;
    final p = hash == null ? r.parsed : null;
    final query = hash != null ? null : (r.query ?? p?.title);
    final year = p?.kind == FeatureKind.movie ? p?.year : null;
    return {
      'languages': (r.languages.map((l) => l.toLowerCase()).toList()..sort()).join(','),
      if (hash != null) 'moviehash': hash.value,
      if (hash != null) 'moviehash_match': 'include',
      'query': ?query,
      if (year != null) 'year': '$year',
      if (p?.season != null) 'season_number': '${p?.season}',
      if (p?.episode != null) 'episode_number': '${p?.episode}',
      'order_by': 'download_count',
    };
  }

  static String cacheKey(SearchRequest r) => sortedQuery(searchParams(r));

  Future<String> searchRaw(SearchRequest r) async {
    final res = await send(
      client,
      () => http.Request('GET', _uri('/subtitles', searchParams(r)))..headers.addAll(_headers()),
      wait: wait,
    );
    return res.body;
  }

  static List<SubtitleCandidate> parseSearch(String body) {
    final j = jsonDecode(body);
    if (j is! Map<String, Object?>) return const [];
    final data = j['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map<String, Object?>>()
        .map(SubtitleCandidate.fromOpenSubtitles)
        .whereType<SubtitleCandidate>()
        .toList();
  }

  Future<List<SubtitleCandidate>> search(SearchRequest r) async => parseSearch(await searchRaw(r));

  Future<LoginResult> login(String username, String password) async {
    final res = await send(
      client,
      () => http.Request('POST', _uri('/login'))
        ..headers.addAll(_headers(json: true))
        ..body = jsonEncode({'username': username, 'password': password}),
      wait: wait,
    );
    final j = jsonDecode(res.body) as Map<String, Object?>;
    final user = (j['user'] as Map?)?.cast<String, Object?>() ?? const {};
    final token = j['token'] as String? ?? '';
    final base = j['base_url'] as String? ?? kDefaultHost;
    return LoginResult(
      token: token,
      baseUrl: base,
      quota: Quota(
        remaining: (user['allowed_downloads'] as num?)?.toInt(),
        total: (user['allowed_downloads'] as num?)?.toInt(),
        signedIn: true,
        vip: user['vip'] == true,
        level: user['level'] as String?,
      ),
    );
  }

  /// Current quota without spending a ticket.
  Future<Quota> userInfo() async {
    final res = await send(
      client,
      () => http.Request('GET', _uri('/infos/user'))..headers.addAll(_headers()),
      wait: wait,
    );
    final j = jsonDecode(res.body) as Map<String, Object?>;
    final d = (j['data'] as Map?)?.cast<String, Object?>() ?? const {};
    return Quota(
      remaining: (d['remaining_downloads'] as num?)?.toInt(),
      total: (d['allowed_downloads'] as num?)?.toInt(),
      resetUtc: DateTime.tryParse(d['reset_time_utc'] as String? ?? ''),
      signedIn: true,
      vip: d['vip'] == true,
      level: d['level'] as String?,
    );
  }

  /// THE ONLY CALL THAT SPENDS A TICKET.
  Future<DownloadLink> requestDownload(String fileId) async {
    final res = await send(
      client,
      () => http.Request('POST', _uri('/download'))
        ..headers.addAll(_headers(json: true))
        ..body = jsonEncode({'file_id': int.tryParse(fileId) ?? fileId, 'sub_format': 'srt'}),
      wait: wait,
    );
    final j = jsonDecode(res.body) as Map<String, Object?>;
    return DownloadLink(
      link: j['link'] as String? ?? '',
      fileName: j['file_name'] as String? ?? 'subtitle.srt',
      remaining: (j['remaining'] as num?)?.toInt() ?? 0,
      resetUtc: DateTime.tryParse(j['reset_time_utc'] as String? ?? ''),
    );
  }

  /// The temporary link: 410 once expired (mapped to linkExpired for the single retry).
  Future<Uint8List> fetchLink(String link) async {
    final res = await send(
      client,
      () =>
          http.Request('GET', Uri.parse(link))..headers['User-Agent'] = 'Marquee v$kMarqueeVersion',
      wait: wait,
    );
    return res.bodyBytes;
  }

  Future<void> logout() async {
    if (jwt == null) return;
    try {
      await send(
        client,
        () => http.Request('DELETE', _uri('/logout'))..headers.addAll(_headers()),
        wait: wait,
      );
    } on Exception {
      // Signing out locally is what matters; the server token simply expires.
    }
    jwt = null;
  }
}

Future<void> _delay(Duration d) => Future<void>.delayed(d);
