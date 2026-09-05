import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

void main() {
  group('Non-Unique Index Tests', () {
    const dbPath = 'test_non_unique.db';
    late String libPath;
    FlareDatabase? db;

    setUp(() {
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
      libPath = File('.dart_tool/lib/flare_db.dll').absolute.path;
    });

    tearDown(() {
      db?.close();
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
    });

    test('Index returns multiple documents for same key', () {
      db = FlareDatabase(dbPath, libraryPath: libPath);
      db!.createIndex('users', 'role');
      final col = db!.collection('users');

      col.doc('u1').set({'name': 'Alice', 'role': 'admin'});
      col.doc('u2').set({'name': 'Bob', 'role': 'admin'});
      col.doc('u3').set({'name': 'Charlie', 'role': 'user'});

      db!.sync();

      final admins = col.where('role', isEqualTo: 'admin').get();
      expect(admins.length, equals(2));
      expect(admins.any((s) => s.id == 'u1'), isTrue);
      expect(admins.any((s) => s.id == 'u2'), isTrue);
    });

    test('Updating field removes old index entry and adds new one', () {
      db = FlareDatabase(dbPath, libraryPath: libPath);
      db!.createIndex('users', 'role');
      final col = db!.collection('users');

      col.doc('u1').set({'name': 'Alice', 'role': 'admin'});
      db!.sync();

      expect(col.where('role', isEqualTo: 'admin').get().length, equals(1));

      // Change role to user
      col.doc('u1').set({'name': 'Alice', 'role': 'user'});
      db!.sync();

      expect(col.where('role', isEqualTo: 'admin').get().length, equals(0));
      expect(col.where('role', isEqualTo: 'user').get().length, equals(1));
    });

    test('Deleting document removes it from index', () {
      db = FlareDatabase(dbPath, libraryPath: libPath);
      db!.createIndex('users', 'role');
      final col = db!.collection('users');

      col.doc('u1').set({'name': 'Alice', 'role': 'admin'});
      db!.sync();

      expect(col.where('role', isEqualTo: 'admin').get().length, equals(1));

      col.doc('u1').delete();
      db!.sync();

      expect(col.where('role', isEqualTo: 'admin').get().length, equals(0));
    });
  });
}
