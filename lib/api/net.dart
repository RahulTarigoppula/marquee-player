// Reactive rate-limit handling: read X-RateLimit-*, honour Retry-After ONCE, never a fixed
// sleep, never a retry storm. Every HTTP status becomes a typed ThreadingFailure here.
import 'dart:async';
import 'dart:io' show SocketException, HttpException;

import 'package:http/http.dart' as http;

import '../engine/models/leader.dart';

const Duration kDefaultRetryAfter = Duration(seconds: 2);
const Duration kRequestTimeout = Duration(seconds: 12);

/// Alphabetically sorted query string — an unsorted query costs a 301 and, in a browser,
/// drops `moviehash_match` on the redirect.
String sortedQuery(Map<String, String> params) {
  final keys = params.keys.where((k) => params[k]!.isNotEmpty).toList()..sort();
  return keys
      .map((k) => '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(params[k]!)}')
      .join('&');
}

class RateLimit {
  final int? limit, remaining, reset;
  const RateLimit({this.limit, this.remaining, this.reset});
  factory RateLimit.from(Map<String, String> h) => RateLimit(
    limit: int.tryParse(h['x-ratelimit-limit'] ?? ''),
    remaining: int.tryParse(h['x-ratelimit-remaining'] ?? ''),
    reset: int.tryParse(h['x-ratelimit-reset'] ?? ''),
  );
}

int retryAfterSeconds(http.BaseResponse r) =>
    int.tryParse(r.headers['retry-after'] ?? '') ?? kDefaultRetryAfter.inSeconds;

ThreadingFailure failureForStatus(int status) => switch (status) {
  401 || 403 => ThreadingFailure.unauthorized,
  406 => ThreadingFailure.quotaExhausted,
  410 => ThreadingFailure.linkExpired,
  429 => ThreadingFailure.rateLimited,
  404 => ThreadingFailure.noResults,
  _ => ThreadingFailure.timeout,
};

/// Sends a request built by [make] (a fresh request per attempt). A 429 waits Retry-After
/// and retries exactly once; the second 429 becomes a stall. Network errors → offline.
Future<http.Response> send(
  http.Client client,
  http.BaseRequest Function() make, {
  Future<void> Function(Duration) wait = _delay,
  Set<int> passThrough = const {},
}) async {
  for (var attempt = 0; ; attempt++) {
    final http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(make()).timeout(kRequestTimeout));
    } on TimeoutException {
      throw const ThreadingException(ThreadingFailure.timeout);
    } on SocketException {
      throw const ThreadingException(ThreadingFailure.offline);
    } on HttpException {
      throw const ThreadingException(ThreadingFailure.offline);
    } on http.ClientException {
      throw const ThreadingException(ThreadingFailure.offline);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    if (passThrough.contains(res.statusCode)) return res;
    if (res.statusCode == 429 && attempt == 0) {
      await wait(Duration(seconds: retryAfterSeconds(res)));
      continue;
    }
    throw ThreadingException(
      failureForStatus(res.statusCode),
      retryAfterSeconds: res.statusCode == 429 ? retryAfterSeconds(res) : null,
    );
  }
}

Future<void> _delay(Duration d) => Future<void>.delayed(d);
