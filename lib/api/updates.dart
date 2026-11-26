// The update check: ONE unauthenticated GET to GitHub's public releases API, and only when the
// user asked for it (the button, or the automatic check they turned on). The request carries
// nothing about the user or the device: no version, no platform, no identifier, no query, a
// fixed User-Agent. Which download suits this device is worked out here, from the answer.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' show HttpException, Platform, SocketException;

import 'package:http/http.dart' as http;

import '../engine/version.dart';

const String kProjectPage = 'https://github.com/RahulTarigoppula/marquee-player';
const String kIssuesPage = '$kProjectPage/issues';
const String kLatestReleasePage = '$kProjectPage/releases/latest';
const String kLatestReleaseApi =
    'https://api.github.com/repos/RahulTarigoppula/marquee-player/releases/latest';

const Duration kUpdateTimeout = Duration(seconds: 8);

/// How much of the release notes "What's new" shows.
const int kNotesLength = 600;

/// The installer a platform updates with: the file names the release workflow publishes.
enum UpdateTarget {
  windows('marquee-windows-x64-setup.exe'),
  android('marquee-android-arm64-v8a.apk'),
  androidArm32('marquee-android-armeabi-v7a.apk'),
  androidX64('marquee-android-x86_64.apk'),

  /// No installer is published for this platform: the release page it is.
  other(null);

  final String? asset;
  const UpdateTarget(this.asset);

  /// On Android the APK must match the ABI this build runs as, or it will not install.
  static UpdateTarget get current {
    if (Platform.isWindows) return windows;
    if (!Platform.isAndroid) return other;
    final abi = Abi.current();
    if (abi == Abi.androidArm64) return android;
    if (abi == Abi.androidArm) return androidArm32;
    if (abi == Abi.androidX64) return androidX64;
    return other;
  }
}

class Release {
  /// The git tag, e.g. `v2.1.0`.
  final String tag;

  /// The release's title; the tag when it has none.
  final String name;

  /// The release's page on GitHub.
  final String pageUrl;
  final DateTime? publishedAt;

  /// The notes as plain text, at most about [kNotesLength] characters. May be empty.
  final String notes;

  /// The installer for this platform, or [pageUrl] when the release has none.
  final String downloadUrl;

  const Release({
    required this.tag,
    required this.name,
    required this.pageUrl,
    required this.downloadUrl,
    this.publishedAt,
    this.notes = '',
  });

  /// False when [downloadUrl] is only the release page.
  bool get hasInstaller => downloadUrl != pageUrl;

  /// `2.1.0` for the tag `v2.1.0`; the tag itself when it is not a version.
  String get version => Version.tryParse(tag)?.toString() ?? tag;

  /// Null when [json] is not a release (no tag).
  static Release? fromJson(Object? json, UpdateTarget target) {
    if (json is! Map<String, Object?>) return null;
    final tag = json['tag_name'];
    if (tag is! String || tag.trim().isEmpty) return null;
    final name = json['name'];
    final body = json['body'];
    final published = json['published_at'];
    final page = _onGitHub(json['html_url']) ?? kLatestReleasePage;
    String? installer;
    final assets = json['assets'];
    if (target.asset != null && assets is List) {
      for (final a in assets.whereType<Map<String, Object?>>()) {
        if (a['name'] == target.asset) {
          installer = _onGitHub(a['browser_download_url']);
          break;
        }
      }
    }
    return Release(
      tag: tag.trim(),
      name: name is String && name.trim().isNotEmpty ? name.trim() : tag.trim(),
      pageUrl: page,
      downloadUrl: installer ?? page,
      publishedAt: published is String ? DateTime.tryParse(published) : null,
      notes: body is String ? plainNotes(body) : '',
    );
  }

  /// These addresses are handed to the browser, so only an https github.com one is believed.
  static String? _onGitHub(Object? url) {
    if (url is! String) return null;
    final u = Uri.tryParse(url);
    return u != null && u.scheme == 'https' && u.host == 'github.com' ? url : null;
  }
}

enum UpdateFailure { offline, timeout, rateLimited, noRelease, unexpected }

class UpdateException implements Exception {
  final UpdateFailure failure;
  const UpdateException(this.failure);

  /// One plain sentence with the next step.
  String get sentence => switch (failure) {
    UpdateFailure.offline => "You're offline. Try again when you're connected.",
    UpdateFailure.timeout => "GitHub didn't answer. Try again in a moment.",
    UpdateFailure.rateLimited => 'GitHub asked us to wait a while. Try again in an hour.',
    UpdateFailure.noRelease => 'No version has been published to download yet.',
    UpdateFailure.unexpected => "GitHub's answer couldn't be read. Try again later.",
  };

  @override
  String toString() => 'UpdateException(${failure.name})';
}

class UpdatesClient {
  final http.Client client;
  final Duration timeout;

  UpdatesClient({http.Client? client, this.timeout = kUpdateTimeout})
    : client = client ?? http.Client();

  /// Everything the request says. Keep it this dull: it is the privacy promise in Settings.
  static const headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'Marquee'};

  /// The latest published release. One request, no retry; every failure is an
  /// [UpdateException].
  Future<Release> latest(UpdateTarget target) async {
    final http.Response res;
    try {
      res = await client.get(Uri.parse(kLatestReleaseApi), headers: headers).timeout(timeout);
    } on TimeoutException {
      throw const UpdateException(UpdateFailure.timeout);
    } on SocketException {
      throw const UpdateException(UpdateFailure.offline);
    } on HttpException {
      throw const UpdateException(UpdateFailure.offline);
    } on http.ClientException {
      throw const UpdateException(UpdateFailure.offline);
    }
    switch (res.statusCode) {
      case 200:
        break;
      case 404:
        throw const UpdateException(UpdateFailure.noRelease);
      // GitHub answers 403 (or 429) once an address has used its hourly allowance.
      case 403 || 429:
        throw const UpdateException(UpdateFailure.rateLimited);
      default:
        throw const UpdateException(UpdateFailure.unexpected);
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const UpdateException(UpdateFailure.unexpected);
    }
    final release = Release.fromJson(json, target);
    if (release == null) throw const UpdateException(UpdateFailure.unexpected);
    return release;
  }
}

/// Release notes are markdown; "What's new" is a short plain paragraph. Drops the markup,
/// keeps the words and the line breaks, and stops near [max] characters at a word.
String plainNotes(String markdown, {int max = kNotesLength}) {
  var s = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  s = s
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(RegExp(r'^\s*```.*$', multiLine: true), '') // fences go, the code stays
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '') // images
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!) // links: their text
      .replaceAll(RegExp(r'</?[A-Za-z][^>\n]*>'), ''); // inline HTML
  final lines = <String>[];
  for (var line in s.split('\n')) {
    line = line.trimRight();
    if (RegExp(r'^\s*([-*_]\s*){3,}$').hasMatch(line)) continue; // a rule
    line = line
        .replaceFirst(RegExp(r'^\s*(>\s*)+'), '') // quote
        .replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '') // heading
        .replaceFirst(RegExp(r'^\s*[-*+]\s+'), '• ') // bullet
        .replaceAll(RegExp(r'\*+|`+|~~'), '')
        // Underscores only where they mark emphasis: `file_name` keeps its own.
        .replaceAll(RegExp(r'(?<![A-Za-z0-9])_+|_+(?![A-Za-z0-9])'), '')
        .trim();
    // GitHub's generated footer is a bare compare link: noise without the link.
    if (line.startsWith('Full Changelog:')) continue;
    lines.add(line);
  }
  s = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (max <= 0 || s.length <= max) return s;
  var cut = s.substring(0, max);
  final space = cut.lastIndexOf(RegExp(r'\s'));
  if (space > max * 0.8) cut = cut.substring(0, space);
  return '${cut.trimRight()}…';
}
