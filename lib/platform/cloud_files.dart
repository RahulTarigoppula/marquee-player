// Windows "Files On-Demand" (OneDrive and friends): a video that shows in the folder but lives
// in the cloud is DOWNLOADED the moment anything reads it. The library's background thumbnailer
// must never do that behind the viewer's back; opening the film yourself is a different matter.
// dart:io's FileStat does not expose these attribute bits, hence one kernel32 call.
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

const int _invalid = 0xFFFFFFFF;
const int _offline = 0x00001000; // FILE_ATTRIBUTE_OFFLINE
const int _recallOnOpen = 0x00040000; // FILE_ATTRIBUTE_RECALL_ON_OPEN
const int _recallOnDataAccess = 0x00400000; // FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS

typedef _GetAttrsC = Uint32 Function(Pointer<Utf16> path);
typedef _GetAttrsDart = int Function(Pointer<Utf16> path);

_GetAttrsDart? _getAttrs;

/// True when reading [path] would make a sync provider fetch it. False everywhere but
/// Windows, and false whenever the question cannot be asked (the file is then treated as local).
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
