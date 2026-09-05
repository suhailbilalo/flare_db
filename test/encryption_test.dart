import 'dart:convert';
import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('Security Tests (Phase 3)', () {
    const dbPath = 'test_encryption.db';
    late String libPath;
    final testKey = List<int>.generate(32, (i) => i + 1);
    final List<FlareDatabase> openedDbs = [];

    FlareDatabase openDb({List<int>? key}) {
      final db = FlareDatabase(
        dbPath,
        libraryPath: libPath,
        encryptionKey: key,
      );
      openedDbs.add(db);
      return db;
    }

    setUp(() {
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

    test('Encryption obfuscates data on disk', () {
      {
        final db = openDb(key: testKey);
        db.collection('secrets').doc('top_secret').set({
          'password': 'SUPER_SECRET_PASSWORD_123',
          'note': 'This should not be visible in a hex editor',
        });
        db.sync();
        db.close();
      }

      final contents = File(dbPath).readAsStringSync(encoding: latin1);
      expect(
        contents.contains('SUPER_SECRET_PASSWORD_123'),
        isFalse,
        reason: 'Sensitive data was found in plain text in the database file!',
      );

      final db2 = openDb(key: testKey);
      final snap = db2.collection('secrets').doc('top_secret').get();
      expect(snap.data()?['password'], equals('SUPER_SECRET_PASSWORD_123'));
    });

    test('Opening with wrong key fails or returns null', () {
      {
        final db = openDb(key: testKey);
        db.collection('data').doc('d1').set({'val': 'ok'});
        db.sync();
        db.close();
      }

      final wrongKey = List<int>.generate(32, (i) => i + 2);
      final dbWrong = openDb(key: wrongKey);
      final snap = dbWrong.collection('data').doc('d1').get();
      expect(
        snap.exists,
        isFalse,
        reason: 'Should not be able to read data with wrong key',
      );
    });
  });
}
