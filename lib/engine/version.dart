// Release versions and the update rules. `v1.2.3`, `1.2.3`, `1.2.3+45` and `0.0.123` all
// parse; anything else is null, never an exception, and a null is never "newer". Whether to
// ask at all (once a day) and what an answer means for this build are decided here, in pure
// Dart, so both rules are tested without a network or a clock.

/// A release version. Ordered like semver: the three numbers, then a pre-release (`-beta.1`)
/// before its release. The build number (`+45`) is kept but never compared.
class Version implements Comparable<Version> {
  final int major, minor, patch;

  /// `beta.1` of `1.2.3-beta.1`; null for a plain release.
  final String? pre;

  /// `45` of `1.2.3+45`; null when the version has none.
  final String? build;

  const Version(this.major, this.minor, this.patch, {this.pre, this.build});

  // Nine digits at most: a longer run is not a version, and it keeps int.parse inside 64 bits.
  static final _shape = RegExp(
    r'^[vV]?(\d{1,9})\.(\d{1,9})(?:\.(\d{1,9}))?'
    r'(?:-([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?'
    r'(?:\+([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?$',
  );

  /// The version in [input] (`v2.1`, `2.1.0`, ` 2.1.0+7 `), or null when it is not one.
  static Version? tryParse(String? input) {
    final m = input == null ? null : _shape.firstMatch(input.trim());
    if (m == null) return null;
    return Version(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3] ?? '0'),
      pre: m[4],
      build: m[5],
    );
  }

  /// `0.0.x`: a local or CI test build. Its number says nothing about how old it is.
  bool get isTestBuild => major == 0 && minor == 0;

  @override
  int compareTo(Version other) {
    for (final d in [major - other.major, minor - other.minor, patch - other.patch]) {
      if (d != 0) return d.sign;
    }
    final a = pre, b = other.pre;
    if (a == null || b == null) return a == b ? 0 : (a == null ? 1 : -1);
    return _comparePre(a, b);
  }

  /// Semver §11: identifiers left to right; numbers by value and before words; fewer
  /// identifiers first when all the shared ones are equal.
  static int _comparePre(String a, String b) {
    final x = a.split('.'), y = b.split('.');
    for (var i = 0; i < x.length && i < y.length; i++) {
      final n = int.tryParse(x[i]), m = int.tryParse(y[i]);
      final int d;
      if (n != null && m != null) {
        d = n.compareTo(m);
      } else if (n == null && m == null) {
        d = x[i].compareTo(y[i]);
      } else {
        d = n != null ? -1 : 1;
      }
      if (d != 0) return d.sign;
    }
    return (x.length - y.length).sign;
  }

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is Version &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.pre == pre;

  @override
  int get hashCode => Object.hash(major, minor, patch, pre);

  /// `2.1.0` or `2.1.0-beta.1`: what a person reads. No `v`, no build number.
  @override
  String toString() => '$major.$minor.$patch${pre == null ? '' : '-$pre'}';
}

/// Whether [candidate] is a later version than [current]. False when either is not a version.
bool isNewer(String current, String candidate) {
  final a = Version.tryParse(current), b = Version.tryParse(candidate);
  return a != null && b != null && b > a;
}

/// Whether this build's version can be compared with a release at all. A test build
/// (`0.0.x`) or an unreadable version cannot: it is offered the release page, never nagged.
bool canCompare(String current) {
  final v = Version.tryParse(current);
  return v != null && !v.isTestBuild;
}

/// What a release means for the build that asked.
enum UpdateVerdict {
  /// The release is later than this build.
  newer,

  /// This build is the release, or later.
  upToDate,

  /// This build or the release has no comparable version.
  unknown,
}

UpdateVerdict compareRelease(String current, String candidate) {
  if (!canCompare(current) || Version.tryParse(candidate) == null) return UpdateVerdict.unknown;
  return isNewer(current, candidate) ? UpdateVerdict.newer : UpdateVerdict.upToDate;
}

/// The automatic check asks at most this often.
const Duration kUpdateCheckEvery = Duration(days: 1);

/// Whether the automatic check may ask again at [now], having last asked at [last]. A [last]
/// in the future (the clock was wrong, then fixed) counts as never, or it would block for good.
bool updateCheckDue(DateTime? last, DateTime now, {Duration every = kUpdateCheckEvery}) =>
    last == null || last.isAfter(now) || now.difference(last) >= every;
