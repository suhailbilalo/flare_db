import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

void main() {
  group('Production Stress & Concurrency Tests', () {
    const dbPath = 'test_production_stress.db';
    late String libPath;
    FlareDatabase? db;

    setUp(() {
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
      if (Platform.isWindows) {
        libPath = File('.dart_tool/lib/flare_db.dll').absolute.path;
      } else {
        libPath = '.dart_tool/lib/libflare_db.so';
      }
      db = FlareDatabase(dbPath, libraryPath: libPath);
    });

    tearDown(() {
      db?.close();
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
    });

    test('High-Volume 5,000 Document Write/Read/Query Stress Test', () {
      final col = db!.collection('production_items');
      db!.createIndex('production_items', 'category');

      // 1. Bulk write 5,000 documents across 5 categories
      const totalDocs = 5000;
      for (var i = 0; i < totalDocs; i++) {
        final category = 'cat_${i % 5}';
        col.doc('item_$i').set({
          'index': i,
          'category': category,
          'name': 'Item number $i',
          'timestamp': Timestamp.now().toMap(),
        });
      }
      db!.sync();

      // 2. Verify total count and index queries
      for (var catIdx = 0; catIdx < 5; catIdx++) {
        final category = 'cat_$catIdx';
        final results = col.where('category', isEqualTo: category).get();
        expect(results.length, equals(totalDocs ~/ 5));
      }

      // 3. Random updates and deletes
      for (var i = 0; i < 1000; i += 2) {
        col.doc('item_$i').delete();
      }
      db!.sync();

      // Verify remaining count
      var remainingCount = 0;
      for (var i = 0; i < totalDocs; i++) {
        if (col.doc('item_$i').get().exists) {
          remainingCount++;
        }
      }
      expect(remainingCount, equals(totalDocs - (1000 ~/ 2)));
    });
  });
}
