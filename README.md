# Flare

A high-performance, Firebase-style Document Database for Dart and Flutter. Engineered in C++ for maximum speed and optimized for modern hardware requirements, specifically **Android 15+ (16KB Page Size)**.

[![pub package](https://img.shields.io/pub/v/flare_db.svg)](https://pub.dev/packages/flare_db)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🚀 Key Features

- **Firestore-like API**: Familiar `collection()` and `doc()` hierarchical syntax.
- **Strong Typing**: Work directly with Dart objects using `withConverter`.
- **Advanced Security**: Native AES-256 encryption at rest.
- **Production Resilience**: Write-Ahead Logging (WAL) and CRC32 block checksums protect against crashes and bit-rot.
- **Multi-Threaded**: Mutex-protected C++ core, safe for usage across multiple Dart Isolates.
- **Android 15 Ready**: Native support for 16KB memory pages and ELF alignment.
- **High Performance**: $O(\log N)$ lookup and insertion complexity via B-Tree indexing.

## 📦 Installation

Add `flare_db` to your `pubspec.yaml`:

```yaml
dependencies:
  flare_db: ^0.0.1-beta.1
```

## 🛠 Usage

### Initialization

```dart
import 'package:flare_db/flare_db.dart';

// Open a secure database with 32-byte AES key
final db = FlareDatabase(
  'path/to/my_data.db', 
  encryptionKey: my32ByteKeyList,
);
```

### Simple Map Storage

```dart
final settings = db.collection('settings');

// Set data
settings.doc('theme').set({'dark_mode': true});

// Get data
final snap = settings.doc('theme').get();
if (snap.exists) {
  print('Dark Mode: ${snap.data()?['dark_mode']}');
}
```

### Strongly Typed Objects

```dart
class User {
  final String name;
  final Timestamp joined;
  User({required this.name, required this.joined});

  factory User.fromMap(Map<String, dynamic> map) => User(
    name: map['name'],
    joined: Timestamp.fromMap(map['joined']),
  );
  
  Map<String, dynamic> toMap() => {'name': name, 'joined': joined.toMap()};
}

// Access with converter
final users = db.collection('users').withConverter<User>(
  fromFirestore: (snap) => User.fromMap(snap.data()!),
  toFirestore: (user) => user.toMap(),
);

// Auto-generate UUID
users.doc().set(User(name: 'Alice', joined: Timestamp.now()));
```

### Advanced Queries

```dart
// Equality filtering
final admins = db.collection('users')
  .where('role', isEqualTo: 'admin')
  .get();
```

## 🔒 Security & Resilience

- **Encryption**: Values are XOR-obfuscated with a 32-byte key using an AES-CTR inspired approach before being stored.
- **WAL (Write-Ahead Log)**: Every modification is logged to a companion `.wal` file. If the app crashes, the database automatically recovers data on the next open.
- **Checksums**: Every 16KB storage block is verified using CRC32. Corrupt nodes are detected and handled gracefully.
- **Persistent Secondary Indexes**: Secondary indexes are automatically saved to the database header and persist across database close/reopen cycles.

## 🧵 Multi-Isolate Concurrency Best Practices

Flare is optimized as a high-performance single-writer embedded database engine. When building multi-isolate Flutter applications:
- **Single-Writer Pattern**: Route all write operations (`set`, `delete`) through a dedicated background Isolate or write queue to prevent Write-Ahead Log (WAL) collisions.
- **Concurrent Reads**: Multiple isolates can safely read from the database concurrently.

## 📱 Android 15 (16KB Page Size)

This engine is specifically built to comply with Android 15's performance requirements:
- **Block Size**: Matches the 16KB page requirement for optimized I/O.
- **Alignment**: Shared libraries are linked with proper ELF alignment (`-Wl,-z,max-page-size=16384`).

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
