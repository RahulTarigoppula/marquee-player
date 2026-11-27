// Windows "Files On-Demand" (OneDrive and friends): a video that shows in the folder but lives
// in the cloud is DOWNLOADED the moment anything reads it. The library's background thumbnailer
// must never do that behind the viewer's back; opening the film yourself is a different matter.
// dart:io's FileStat does not expose these attribute bits, hence one kernel32 call.
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

const int _invalid = 0xFFFFFFFF;
const int _offline = 0x00001000; // FILE_ATTRIBUTE_OFFLINE
const int _recallOnOpen = 0x00040000; // FILE_ATTRIBUTE_RECALL_ON_OPEN
const int _recallOnDataAccess = 0x00400000; // FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS

typedef _GetAttrsC = Uint32 Function(Pointer<Utf16> path);
typedef _GetAttrsDart = int Function(Pointer<Utf16> path);

_GetAttrsDart? _getAttrs;

/// [isCloudOnlyFile], asked on a short-lived isolate of its own. The kernel call is
/// synchronous, and on a drive that has gone to sleep or a network share that is not there it
/// does not return for seconds (tens of them for an unreachable share): asked on the UI
/// isolate, that is a frozen window once per video tried. One isolate per question is cheap at
/// the pace the thumbnailer asks (one file at a time, with a pause between them).
Future<bool> isCloudOnlyFileOffThread(String path) async {
  if (!Platform.isWindows) return false;
  try {
    return await _ask(path);
  } on Object {
    return false; // the question could not be asked: local, as above
  }
}

// Its own function: the closure sent to the isolate carries [path] and nothing else.
Future<bool> _ask(String path) => Isolate.run(() => isCloudOnlyFile(path), debugName: 'cloud file');

/// True when reading [path] would make a sync provider fetch it. False everywhere but
/// Windows, and false whenever the question cannot be asked (the file is then treated as local).
/// Blocks until Windows answers: off the UI isolate, use [isCloudOnlyFileOffThread].
bool isCloudOnlyFile(String path) {
  if (!Platform.isWindows) return false;
  try {
    final f = _getAttrs ??= DynamicLibrary.open(
      'kernel32.dll',
    ).lookupFunction<_GetAttrsC, _GetAttrsDart>('GetFileAttributesW');
    final native = path.toNativeUtf16();
    try {
      final attrs = f(native);
      if (attrs == _invalid) return false;
      return attrs & (_offline | _recallOnOpen | _recallOnDataAccess) != 0;
    } finally {
      calloc.free(native);
    }
  } on Object {
    return false;
  }
}
