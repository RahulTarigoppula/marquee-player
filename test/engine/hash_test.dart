import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:marquee/engine/hash.dart';

ChunkReader bytesReader(Uint8List all, {List<int>? reads}) => (offset, length) async {
  reads?.add(length);
  return Uint8List.sublistView(all, offset, (offset + length).clamp(0, all.length));
};

void main() {
  group('moviehash', () {
    test('pads the hash to 16 hex digits and accepts exactly 128 KiB', () async {
      final h = await movieHashOf(bytesReader(Uint8List(131072)), 131072);
      expect(h.value, '0000000000020000');
      expect(h.isValid, isTrue);
    });

    test('wraps the chunk sums as unsigned 64-bit', () async {
      final all = Uint8List(131072)..fillRange(0, 131072, 0xFF);
      final h = await movieHashOf(bytesReader(all), 131072);
      expect(h.value, '000000000001c000');
    });

    test('reads the tail chunk from an unaligned offset', () async {
      final offsets = <int>[];
      final all = Uint8List(200000);
      final h = await movieHashOf((offset, length) async {
        offsets.add(offset);
        return Uint8List.sublistView(all, offset, offset + length);
      }, 200000);
      expect(h.value, '0000000000030d40');
      expect(offsets, contains(200000 - kChunk));
    });

    test('rejects a file one byte under 128 KiB as too small', () async {
      expect(
        () => movieHashOf(bytesReader(Uint8List(131071)), 131071),
        throwsA(isA<FileTooSmall>()),
      );
    });

    test('keeps 64-bit precision for a 4 GiB file', () async {
      const size = 4294967296;
      final offsets = <int>[];
      final h = await movieHashOf((offset, length) async {
        offsets.add(offset);
        return Uint8List(length);
      }, size);
      expect(h.value, '0000000100000000');
      expect(offsets, [0, size - 65536]);
    });

    test('reads exactly 131072 bytes from a 4 GiB file', () async {
      var bytesRead = 0;
      await movieHashOf((offset, length) async {
        bytesRead += length;
        return Uint8List(length);
      }, 4 * 1024 * 1024 * 1024);
      expect(bytesRead, 131072);
    });

    test('formats a hash with the top bit set without a sign or prefix', () async {
      final bytes = Uint8List(131072);
      bytes[7] = 0x80;
      final h = await movieHashOf(bytesReader(bytes), 131072);
      expect(h.value, '8000000000020000');
      expect(h.value, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(formatHash(-1).value, 'ffffffffffffffff');
      expect(formatHash(-2).value, 'fffffffffffffffe');
      expect(formatHash(0x7fffffffffffffff).value, '7fffffffffffffff');
    });

    test('wraps a failed read as hash unavailable', () async {
      expect(
        () => movieHashOf((o, l) async => throw const FileSystemException('gone'), 200000),
        throwsA(isA<HashUnavailable>()),
      );
    });

    test('wraps a short read as hash unavailable', () async {
      expect(
        () => movieHashOf((o, l) async => Uint8List(10), 200000),
        throwsA(isA<HashUnavailable>()),
      );
    });

    test('hashes a real file through a RandomAccessFile reading only two chunks', () async {
      final dir = await Directory.systemTemp.createTemp('marquee_hash');
      final f = File('${dir.path}/zeros.bin')..writeAsBytesSync(Uint8List(200000));
      final raf = await f.open();
      final h = await movieHashOf(rafReader(raf), 200000);
      await raf.close();
      await dir.delete(recursive: true);
      expect(h.value, '0000000000030d40');
    });

    test('matches the published breakdance.avi vector', () async {
      final path = Platform.environment['MARQUEE_BREAKDANCE'];
      if (path == null || !File(path).existsSync()) {
        markTestSkipped('breakdance.avi not fetched (set MARQUEE_BREAKDANCE) — skipped');
        return;
      }
      final f = File(path);
      final raf = await f.open();
      final h = await movieHashOf(rafReader(raf), f.lengthSync());
      await raf.close();
      expect(h.value, '8e245d9679d31e12');
    });
  });
}
