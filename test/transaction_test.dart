import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

void main() {
  group('Flare Transactions and Batched Writes', () {
    const dbPath = 'test_transaction.db';
    late String libPath;
    FlareDatabase? db;

    setUp(() {
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
      if (Platform.isWindows) {
        libPath = File('.dart_tool/lib/flare_db.dll').absolute.path;
      } else {
        throw UnsupportedError('Only windows for this test setup');
      }
    });

    tearDown(() {
      db?.close();
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
    });

    test('Batch writes commit successfully', () {
      db = FlareDatabase(dbPath, libraryPath: libPath);
      final col = db!.collection('items');

      final batch = db!.batch();
      batch.set(col.doc('item1'), {'name': 'Item 1'});
      batch.set(col.doc('item2'), {'name': 'Item 2'});
      batch.commit();

      expect(col.doc('item1').get().exists, isTrue);
      expect(col.doc('item2').get().exists, isTrue);
      expect(col.doc('item1').get().data()?['name'], equals('Item 1'));
    });

    test('Transactions execute and commit atomically', () async {
      db = FlareDatabase(dbPath, libraryPath: libPath);
      final col = db!.collection('accounts');

      col.doc('acc1').set({'balance': 100});

      await db!.runTransaction((tx) async {
        final snap = col.doc('acc1').get();
        final bal = snap.data()?['balance'] as int;
        tx.set(col.doc('acc1'), {'balance': bal - 50});
        tx.set(col.doc('acc2'), {'balance': 50});
      });

      expect(col.doc('acc1').get().data()?['balance'], equals(50));
      expect(col.doc('acc2').get().data()?['balance'], equals(50));
    });
  });
}
