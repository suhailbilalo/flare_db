import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('Flare Query Tests', () {
    const dbPath = 'test_query.db';
    late FlareDatabase db;

    setUp(() {
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
      final libPath = getTestLibraryPath();
      db = FlareDatabase(dbPath, libraryPath: libPath);
    });

    tearDown(() {
      db.close();
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      if (File('$dbPath.wal').existsSync()) File('$dbPath.wal').deleteSync();
    });

    test('where() equality filter', () {
      final col = db.collection('users');
      col.doc('u1').set({'name': 'Alice', 'role': 'admin'});
      col.doc('u2').set({'name': 'Bob', 'role': 'user'});
      col.doc('u3').set({'name': 'Charlie', 'role': 'user'});
      db.sync();

      final admins = col.where('role', isEqualTo: 'admin').get();
      expect(admins.length, equals(1));
      expect(admins[0].data()?['name'], equals('Alice'));

      final users = col.where('role', isEqualTo: 'user').get();
      expect(users.length, equals(2));
      expect(users.any((s) => s.data()?['name'] == 'Bob'), isTrue);
      expect(users.any((s) => s.data()?['name'] == 'Charlie'), isTrue);
    });
  });
}
