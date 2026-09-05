import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('Flare Resilience Tests', () {
    const dbPath = 'test_resilience.db';
    late String libPath;
    final List<FlareDatabase> openedDbs = [];

    FlareDatabase openDb() {
      final db = FlareDatabase(dbPath, libraryPath: libPath);
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

    test('Crash Recovery via WAL', () {
      {
        final db = openDb();
        db.collection('users').doc('alice').set({'name': 'Alice'});
        db.close(); // Closed without sync, data in WAL
      }

      final db2 = openDb();
      final snap = db2.collection('users').doc('alice').get();
      expect(snap.exists, isTrue);
      expect(snap.data()?['name'], equals('Alice'));
    });

    test('Corruption detection (Checksums)', () {
      {
        final db = openDb();
        db.collection('docs').doc('d1').set({'content': 'important data'});
        db.sync();
        db.close();
      }

      final walFile = File('$dbPath.wal');
      if (walFile.existsSync()) {
        expect(walFile.lengthSync(), equals(0));
      }

      final bytes = File(dbPath).readAsBytesSync();
      bytes[16384 + 100] ^= 0xFF; // Corrupt middle of root node
      File(dbPath).writeAsBytesSync(bytes);

      final dbCorrupt = openDb();
      final snap = dbCorrupt.collection('docs').doc('d1').get();
      expect(snap.exists, isFalse);
    });
  });
}
