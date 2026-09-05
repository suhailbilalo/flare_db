// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('Flare Bloat Tests', () {
    const dbPath = 'test_bloat.db';
    late String libPath;
    FlareDatabase? db;

    setUp(() {
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
      libPath = getTestLibraryPath();
    });

    tearDown(() {
      db?.close();
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
    });

    test('B-Tree deletion reclaims space and prevents infinite growth', () {
      db = FlareDatabase(dbPath, libraryPath: libPath);
      final col = db!.collection('test');

      // 1. Initial insertions
      for (var i = 0; i < 1000; i++) {
        col.doc('key_$i').set({
          'data': 'some constant data string to take space',
        });
      }
      db!.sync();
      final sizeAfterInsert = File(dbPath).lengthSync();
      print('Size after 1,000 inserts: $sizeAfterInsert');

      // 2. Delete all
      for (var i = 0; i < 1000; i++) {
        col.doc('key_$i').delete();
      }
      db!.sync();
      final sizeAfterDelete = File(dbPath).lengthSync();
      print('Size after 1,000 deletes: $sizeAfterDelete');

      // 3. Re-insert same keys
      for (var i = 0; i < 1000; i++) {
        col.doc('key_$i').set({
          'data': 'some constant data string to take space',
        });
      }
      db!.sync();
      final sizeAfterReinsert = File(dbPath).lengthSync();
      print('Size after 1,000 re-inserts: $sizeAfterReinsert');

      expect(
        sizeAfterReinsert,
        lessThanOrEqualTo(sizeAfterInsert * 1.1),
        reason:
            'File grew too much after re-inserting same data. Potential bloat!',
      );
    });
  });
}
