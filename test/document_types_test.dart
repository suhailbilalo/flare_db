import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

void main() {
  group('Flare Types Tests', () {
    test('Timestamp: now()', () {
      final t = Timestamp.now();
      expect(t.seconds, isPositive);
    });

    test('Timestamp: serialization', () {
      final t = Timestamp(123456, 789);
      final map = t.toMap();
      expect(map['_seconds'], 123456);
      expect(map['_nanoseconds'], 789);

      final t2 = Timestamp.fromMap(map);
      expect(t, equals(t2));
    });

    test('GeoPoint: equality', () {
      final g1 = GeoPoint(1.2, 3.4);
      final g2 = GeoPoint(1.2, 3.4);
      expect(g1, equals(g2));
    });

    test('GeoPoint: validation', () {
      expect(() => GeoPoint(91, 0), throwsA(isA<AssertionError>()));
      expect(() => GeoPoint(0, 181), throwsA(isA<AssertionError>()));
    });
  });
}
