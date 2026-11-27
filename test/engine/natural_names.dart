// Shared by the order tests: names shaped like a real library, and the comparison the natural
// order was DEFINED by before names were cut up once (lib/engine/playback.dart, NaturalKey).
// The old function is kept here, word for word, as the yardstick the new one must match.
import 'dart:math';

final _chunk = RegExp(r'\d+|\D+');

/// `naturalCompare` as it stood before keys: both names lower-cased and cut up on every call.
int legacyNaturalCompare(String a, String b) {
  final xs = _chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final ys = _chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final x = xs[i], y = ys[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null
        ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length))
        : x.compareTo(y);
    if (c != 0) return c;
  }
  final c = xs.length.compareTo(ys.length);
  return c != 0 ? c : a.compareTo(b);
}

const _shows = ['Severance', 'severance', 'The Bear', 'Dark', 'DARK', 'Shōgun', 'Борис', '映画'];
const _films = ['The.Third.Man', 'Spirited_Away', 'chungking express', 'Late Spring', 'M'];
const _tags = ['1080p.BluRay.x264', '720p.WEB-DL', '2160p.HDR.HEVC', 'REMUX', ''];
const _ext = ['mkv', 'mp4', 'MKV', 'avi', 'webm'];

/// [count] names, the same every run: episodes (padded and not, in both letter cases), camera
/// clips, release names, bare numbers, twins that differ only by a zero or a capital, digit
/// runs too long to be a number, and a few oddities (empty, spaces, no extension).
List<String> generatedNames(int count, {int seed = 7}) {
  final r = Random(seed);
  T pick<T>(List<T> from) => from[r.nextInt(from.length)];
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  final names = <String>['', ' ', '0', '00', '007', '7', 'a', 'A', 'a1', 'a01', 'a1x', 'A1X'];
  while (names.length < count) {
    names.add(switch (r.nextInt(9)) {
      0 =>
        '${pick(_shows)} S${pad(1 + r.nextInt(3), 2)}E${pad(1 + r.nextInt(24), 2)}.${pick(_ext)}',
      1 => '${pick(_shows)} - Episode ${1 + r.nextInt(120)}.${pick(_ext)}',
      2 => '${pick(_shows)}.s${1 + r.nextInt(3)}e${1 + r.nextInt(24)}.${pick(_tags)}.${pick(_ext)}',
      3 =>
        'VID_${2019 + r.nextInt(7)}${pad(1 + r.nextInt(12), 2)}${pad(1 + r.nextInt(28), 2)}'
            '_${pad(r.nextInt(240000), 6)}.mp4',
      4 => '${pick(_films)}.${1930 + r.nextInt(95)}.${pick(_tags)}.${pick(_ext)}',
      5 => '${r.nextInt(300)}.${pick(_ext)}',
      6 => '${pick(_films)} (${1 + r.nextInt(12)}) [${pad(r.nextInt(100), 1 + r.nextInt(4))}]',
      7 => 'clip ${'9' * (17 + r.nextInt(8))}${r.nextInt(10)} part ${r.nextInt(4)}',
      _ => '${pick(_shows)}${r.nextInt(30)}${pick(['', 'b', 'B', ' ', '.'])}${r.nextInt(30)}',
    });
  }
  return names;
}
