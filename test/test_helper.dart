import 'dart:io';

String getTestLibraryPath() {
  if (Platform.isWindows) {
    return File('.dart_tool/lib/flare_db.dll').absolute.path;
  } else if (Platform.isLinux) {
    final file = File('.dart_tool/lib/libflare_db.so');
    if (file.existsSync()) return file.absolute.path;
    return 'libflare_db.so';
  } else if (Platform.isMacOS) {
    final file = File('.dart_tool/lib/libflare_db.dylib');
    if (file.existsSync()) return file.absolute.path;
    return 'libflare_db.dylib';
  }
  return 'libflare_db.so';
}
