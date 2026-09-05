import 'dart:io';

/// Dynamically locates the compiled native library inside .dart_tool for test runs across Linux, macOS, and Windows.
String getTestLibraryPath() {
  final targetName = _targetLibraryFileName;

  final dartToolDir = Directory('.dart_tool');
  if (dartToolDir.existsSync()) {
    try {
      final matches = dartToolDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) {
            final fileName = f.path
                .split(Platform.pathSeparator)
                .last
                .toLowerCase();
            return fileName == targetName.toLowerCase() ||
                fileName == 'libflare_db.so' ||
                fileName == 'flare_db.dll' ||
                fileName == 'libflare_db.dylib';
          })
          .toList();

      if (matches.isNotEmpty) {
        return matches.first.absolute.path;
      }
    } catch (_) {}
  }

  final fallback = File('.dart_tool/lib/$targetName');
  if (fallback.existsSync()) {
    return fallback.absolute.path;
  }

  return targetName;
}

String get _targetLibraryFileName {
  if (Platform.isWindows) {
    return 'flare_db.dll';
  } else if (Platform.isMacOS) {
    return 'libflare_db.dylib';
  } else {
    return 'libflare_db.so';
  }
}
