import 'dart:async';
import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('Flare Thread Safety Tests', () {
    late String dbPath;
    late String libPath;
    final List<FlareDatabase> openedDbs = [];

    FlareDatabase openDb() {
      final db = FlareDatabase(dbPath, libraryPath: libPath);
      openedDbs.add(db);
      return db;
    }

    setUp(() {
      dbPath = 'test_thread_safety_${DateTime.now().microsecondsSinceEpoch}.db';
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
      libPath = getTestLibraryPath();
    });

    tearDown(() {
      for (final db in openedDbs) {
        try {
          db.close();
        } catch (_) {}
      }
      openedDbs.clear();
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
    });

    test('Concurrent operations serialization with FlareMutex', () async {
      final db = openDb();
      db.collection('init').doc('k').set({'v': 0});
      db.sync();

      const numTasks = 10;
      const writesPerTask = 50;

      final futures = <Future>[];
      for (var i = 0; i < numTasks; i++) {
        final taskIdx = i;
        futures.add(
          db.runTransaction((tx) async {
            final col = db.collection('stress');
            for (var j = 0; j < writesPerTask; j++) {
              tx.set(col.doc('task_${taskIdx}_$j'), {'val': j});
            }
          }),
        );
      }

      await Future.wait(futures);

      final initDoc = db.collection('init').doc('k').get();
      expect(initDoc.exists, isTrue, reason: 'Init document vanished!');

      final totalDocs = db.collection('stress').get().length;
      expect(totalDocs, equals(numTasks * writesPerTask));
    });
  });
}
