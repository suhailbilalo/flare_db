import 'dart:io';

import 'package:flare_db/flare_db.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

class TestUser {
  final String name;
  final int age;
  final Timestamp? createdAt;
  final GeoPoint? location;

  TestUser({
    required this.name,
    required this.age,
    this.createdAt,
    this.location,
  });

  factory TestUser.fromMap(Map<String, dynamic> map) => TestUser(
    name: map['name'] as String,
    age: map['age'] as int,
    createdAt: map['createdAt'] != null
        ? Timestamp.fromMap(map['createdAt'] as Map<String, dynamic>)
        : null,
    location: map['location'] != null
        ? GeoPoint.fromMap(map['location'] as Map<String, dynamic>)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'age': age,
    if (createdAt != null) 'createdAt': createdAt!.toMap(),
    if (location != null) 'location': location!.toMap(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestUser &&
          name == other.name &&
          age == other.age &&
          createdAt == other.createdAt &&
          location == other.location;

  @override
  int get hashCode => Object.hash(name, age, createdAt, location);
}

void main() {
  late FlareDatabase db;
  const dbPath = 'test_document_store.db';

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

  test('Strongly typed collections with converters', () {
    final users = db
        .collection('users')
        .withConverter<TestUser>(
          fromFirestore: (snapshot) => TestUser.fromMap(snapshot.data()!),
          toFirestore: (user) => user.toMap(),
        );

    final user = TestUser(
      name: 'Bob',
      age: 25,
      createdAt: Timestamp.now(),
      location: const GeoPoint(10.0, 20.0),
    );
    users.doc('user1').set(user);

    final snapshot = users.doc('user1').get();
    expect(snapshot.exists, isTrue);
    expect(snapshot.id, equals('user1'));
    expect(snapshot.data()!.name, equals('Bob'));
    expect(snapshot.data()!.createdAt, isNotNull);
    expect(snapshot.data()!.location, equals(const GeoPoint(10.0, 20.0)));
  });

  test('Sub-collections', () {
    final userRef = db.doc('users/alice');
    final posts = userRef.collection('posts');

    posts.doc('p1').set({'title': 'Post 1'});

    expect(posts.path, equals('users/alice/posts'));
    expect(posts.doc('p1').get().exists, isTrue);
  });
}
