import 'dart:io';

import 'package:flare_db/flare.dart';
import 'package:test/test.dart';

void main() {
  group('FlareDatabase Functional Tests', () {
    const dbPath = 'test_functional.db';
    late FlareDatabase db;

    setUp(() {
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
      String? libPath;
      if (Platform.isWindows) {
        libPath = File('.dart_tool/lib/flare.dll').absolute.path;
      }
      db = FlareDatabase(dbPath, libraryPath: libPath);
    });

    tearDown(() {
      db.close();
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
    });

    test('Stress: 1,000 documents via Collection API', () {
      final col = db.collection('stress');
      final count = 1000;
      for (var i = 0; i < count; i++) {
        col.doc('k_$i').set({'val': i, 'active': true});
      }
      db.sync();
      for (var i = 0; i < count; i++) {
        final snap = col.doc('k_$i').get();
        expect(snap.data()!['val'], equals(i));
      }
    });
  });
}
