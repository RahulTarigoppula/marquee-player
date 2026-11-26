import 'package:marquee/engine/version.dart';
import 'package:test/test.dart';

void main() {
  group('Version.tryParse', () {
    test('reads the shapes a release or a build can have', () {
      expect(Version.tryParse('v1.2.3'), const Version(1, 2, 3));
      expect(Version.tryParse('1.2.3'), const Version(1, 2, 3));
      expect(Version.tryParse('V1.2.3'), const Version(1, 2, 3));
      expect(Version.tryParse('0.0.123'), const Version(0, 0, 123));
      expect(Version.tryParse('  2.10.0\n'), const Version(2, 10, 0));
      expect(Version.tryParse('v2.1'), const Version(2, 1, 0));
    });

    test('keeps the build number and the pre-release apart', () {
      final v = Version.tryParse('1.2.3+45')!;
      expect((v.major, v.minor, v.patch, v.pre, v.build), (1, 2, 3, null, '45'));
      final b = Version.tryParse('v2.0.0-beta.1+7')!;
      expect((b.pre, b.build), ('beta.1', '7'));
    });

    test('never throws on garbage: it is simply not a version', () {
      for (final junk in <String?>[
        null,
        '',
        '   ',
        'v',
        'latest',
        '1',
        '1.',
        '1..2',
        '1.2.3.4',
        '1.2.x',
        '-1.2.3',
        '1.2.3-',
        '1.2.3+',
        'v1.2.3 final',
        '99999999999999999999.0.0',
        '1.2.3\u0000',
        '١.٢.٣',
      ]) {
        expect(Version.tryParse(junk), isNull, reason: '$junk');
      }
    });

    test('prints what a person reads', () {
      expect('${Version.tryParse('v2.1.0+88')}', '2.1.0');
      expect('${Version.tryParse('2.1')}', '2.1.0');
      expect('${Version.tryParse('2.1.0-rc.2')}', '2.1.0-rc.2');
    });
  });

  group('ordering', () {
    int cmp(String a, String b) => Version.tryParse(a)!.compareTo(Version.tryParse(b)!);

    test('compares the numbers as numbers', () {
      expect(cmp('1.2.3', '1.2.3'), 0);
      expect(cmp('1.10.0', '1.9.9'), 1);
      expect(cmp('2.0.0', '10.0.0'), -1);
      expect(cmp('1.2.4', '1.2.3'), 1);
      expect(cmp('0.0.123', '0.0.45'), 1);
    });

    test('ignores the build number', () {
      expect(cmp('1.2.3+45', '1.2.3+7'), 0);
      expect(Version.tryParse('1.2.3+45'), Version.tryParse('v1.2.3'));
      expect(Version.tryParse('1.2.3+45').hashCode, Version.tryParse('v1.2.3').hashCode);
    });

    test('puts a pre-release before its release, in semver order', () {
      expect(cmp('2.0.0-beta', '2.0.0'), -1);
      expect(cmp('2.0.0', '2.0.0-rc.1'), 1);
      expect(cmp('2.0.0-alpha', '2.0.0-beta'), -1);
      expect(cmp('2.0.0-beta.2', '2.0.0-beta.10'), -1);
      expect(cmp('2.0.0-beta.1', '2.0.0-beta'), 1);
      expect(cmp('2.0.0-1', '2.0.0-alpha'), -1);
      expect(cmp('2.0.0-alpha', '2.0.0-1'), 1);
      expect(cmp('2.0.0-rc.1', '2.0.0-rc.1'), 0);
      expect(Version.tryParse('2.0.0-rc.1') == Version.tryParse('2.0.0'), isFalse);
    });
  });

  group('isNewer', () {
    test('is true only for a later release', () {
      expect(isNewer('1.0.0', 'v1.0.1'), isTrue);
      expect(isNewer('1.0.0+12', 'v2.0.0'), isTrue);
      expect(isNewer('2.1.0', 'v2.1.0'), isFalse);
      expect(isNewer('2.1.0', 'v2.0.9'), isFalse);
      expect(isNewer('2.1.0-beta.1', 'v2.1.0'), isTrue);
      expect(isNewer('2.1.0', 'v2.1.0-beta.1'), isFalse);
    });

    test('is false when either side is not a version', () {
      expect(isNewer('', 'v9.9.9'), isFalse);
      expect(isNewer('dev', 'v9.9.9'), isFalse);
      expect(isNewer('1.0.0', 'nightly'), isFalse);
      expect(isNewer('1.0.0', ''), isFalse);
    });
  });

  group('what a release means for this build', () {
    test('a test build or an unreadable version cannot be compared', () {
      expect(canCompare('1.0.0'), isTrue);
      expect(canCompare('2.1.0+9'), isTrue);
      expect(canCompare('0.1.0'), isTrue);
      expect(canCompare('0.0.123'), isFalse);
      expect(canCompare('0.0.0'), isFalse);
      expect(canCompare('local'), isFalse);
      expect(canCompare(''), isFalse);
    });

    test('newer, up to date, or unknown', () {
      expect(compareRelease('1.0.0', 'v2.1.0'), UpdateVerdict.newer);
      expect(compareRelease('2.1.0', 'v2.1.0'), UpdateVerdict.upToDate);
      expect(compareRelease('2.2.0', 'v2.1.0'), UpdateVerdict.upToDate);
      expect(compareRelease('0.0.412', 'v2.1.0'), UpdateVerdict.unknown);
      expect(compareRelease('garbage', 'v2.1.0'), UpdateVerdict.unknown);
      expect(compareRelease('1.0.0', 'spring-release'), UpdateVerdict.unknown);
    });
  });

  group('updateCheckDue', () {
    final now = DateTime.utc(2026, 11, 26, 20);

    test('asks the first time and then once a day', () {
      expect(updateCheckDue(null, now), isTrue);
      expect(updateCheckDue(now.subtract(const Duration(minutes: 5)), now), isFalse);
      expect(updateCheckDue(now.subtract(const Duration(hours: 23, minutes: 59)), now), isFalse);
      expect(updateCheckDue(now.subtract(const Duration(days: 1)), now), isTrue);
      expect(updateCheckDue(now.subtract(const Duration(days: 30)), now), isTrue);
    });

    test('a stamp from the future does not block the check for good', () {
      expect(updateCheckDue(now.add(const Duration(days: 400)), now), isTrue);
    });

    test('honours another interval', () {
      final last = now.subtract(const Duration(hours: 2));
      expect(updateCheckDue(last, now, every: const Duration(hours: 1)), isTrue);
      expect(updateCheckDue(last, now, every: const Duration(hours: 3)), isFalse);
    });
  });
}
