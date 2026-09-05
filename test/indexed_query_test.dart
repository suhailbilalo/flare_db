import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('Indexed Query Tests', () {
    const dbPath = 'test_indexed.db';
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

    test('Secondary index retrieval WITHOUT encryption', () {
      db = FlareDatabase(dbPath, libraryPath: libPath);

      db!.createIndex('users', 'email');
      final col = db!.collection('users');

      col.doc('user_123').set({
        'name': 'John Doe',
        'email': 'john@example.com',
      });

      db!.sync();

      final result = db!.engine.getBySecondary(
        'users',
        'email',
        'john@example.com',
      );
      expect(result, equals('users/user_123'));
    });

    test('Secondary index persists across database reopen', () {
      db = FlareDatabase(dbPath, libraryPath: libPath);
      db!.createIndex('users', 'role');
      db!.collection('users').doc('admin_1').set({
        'name': 'Admin',
        'role': 'superuser',
      });
      db!.sync();
      db!.close();

      // Re-open database without calling createIndex again
      db = FlareDatabase(dbPath, libraryPath: libPath);
      final results = db!
          .collection('users')
          .where('role', isEqualTo: 'superuser')
          .get();
      expect(results.length, equals(1));
      expect(results.first.id, equals('admin_1'));
      expect(results.first.data()?['name'], equals('Admin'));
    });
  });
}
