import 'dart:io' show RandomAccessFile;
import 'dart:typed_data';

import 'models/media.dart';

/// Files under 128 KiB are rejected by the service. Not an error in Marquee — a branch.
class FileTooSmall implements Exception {
  final int size;
  const FileTooSmall(this.size);
  @override
  String toString() => 'FileTooSmall($size)';
}

/// The file vanished or could not be read between open() and the second chunk.
class HashUnavailable implements Exception {
  final Object cause;
  const HashUnavailable(this.cause);
  @override
  String toString() => 'HashUnavailable($cause)';
}

const int kChunk = 65536;
const int kMinSize = 2 * kChunk; // 131072

/// Reads exactly [length] bytes at [offset]. Implemented over a RandomAccessFile on native,
/// and by a stub in tests (the 2³² vector needs no 4 GB file).
typedef ChunkReader = Future<Uint8List> Function(int offset, int length);

/// hash = (fileSize + Σ le_u64(first 64 KiB) + Σ le_u64(last 64 KiB)) mod 2⁶⁴
///
/// Dart VM ints are 64-bit two's complement and WRAP on overflow — exactly the arithmetic the
/// spec asks for. `toUnsigned(64)` stops a negative wrap from printing a '-'.
Future<MovieHash> movieHashOf(ChunkReader read, int sizeBytes) async {
  if (sizeBytes < kMinSize) throw FileTooSmall(sizeBytes);

  Future<int> chunkSum(int offset) async {
    final Uint8List bytes;
    try {
      bytes = await read(offset, kChunk);
    } on Exception catch (e) {
      throw HashUnavailable(e);
    }
    if (bytes.length != kChunk) throw HashUnavailable(StateError('short read at $offset'));
    final bd = ByteData.sublistView(bytes);
    var s = 0;
    for (var i = 0; i < kChunk; i += 8) {
      s += bd.getUint64(i, Endian.little); // wraps at 2^64 — intended
    }
    return s;
  }

  final head = await chunkSum(0);
  final tail = await chunkSum(sizeBytes - kChunk); // NOT aligned to a chunk boundary
  return formatHash(sizeBytes + head + tail);
}

/// 16 lowercase hex digits, zero-padded, never a sign and never `0x`.
/// VM ints are signed, so a hash with the top bit set is printed as two unsigned halves.
MovieHash formatHash(int h) {
  final hi = (h >> 32) & 0xFFFFFFFF;
  final lo = h & 0xFFFFFFFF;
  return MovieHash(hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0'));
}

/// Adapter for a native file handle. Reads only the two chunks — never streams the file.
ChunkReader rafReader(RandomAccessFile raf) => (offset, length) async {
  await raf.setPosition(offset);
  return raf.read(length);
};
