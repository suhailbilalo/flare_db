import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'flare_bindings_generated.dart';
import 'src/collection.dart';
import 'src/write_batch.dart';

export 'src/collection.dart';
export 'src/geo_point.dart';
export 'src/timestamp.dart';
export 'src/write_batch.dart';

/// The entry point for Flare Document Database.
///
/// Use this class to access collections and documents in a Firebase-style API.
///
/// Example:
/// ```dart
/// final db = FlareDatabase('my_app.db');
/// final users = db.collection('users');
/// users.doc('alice').set({'name': 'Alice'});
/// ```
class FlareDatabase {
  final FlareCore _engine;

  FlareDatabase(String path, {String? libraryPath, List<int>? encryptionKey})
    : _engine = FlareCore(libraryPath)
        ..open(path, encryptionKey: encryptionKey);

  /// Registers a secondary index on a specific JSON field for a collection.
  ///
  /// Example: `db.createIndex('users', 'role')`
  void createIndex(String collectionPath, String jsonField) {
    _engine.createIndex(collectionPath, jsonField);
  }

  /// Returns a [CollectionReference] for the specified [path].
  CollectionReference<Map<String, dynamic>> collection(String path) {
    return CollectionReference<Map<String, dynamic>>(path, this);
  }

  /// Returns a [DocumentReference] for the specified [path].
  DocumentReference<Map<String, dynamic>> doc(String path) {
    return DocumentReference<Map<String, dynamic>>(path, this);
  }

  /// Flushes all changes to disk.
  void sync() => _engine.sync();

  /// Closes the database.
  void close() => _engine.close();

  /// Internal engine access for collections.
  FlareCore get engine => _engine;

  final FlareMutex _mutex = FlareMutex();

  /// Creates a write batch for executing multiple operations atomically.
  WriteBatch batch() => WriteBatch(this);

  /// Executes a transaction function atomically with serialization (mutex protection).
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) updateFunction,
  ) async {
    return _mutex.protect(() async {
      final transaction = Transaction();
      final result = await updateFunction(transaction);
      for (final op in transaction.operations) {
        op();
      }
      sync();
      return result;
    });
  }
}

/// Internal wrapper for the native B-Tree engine.
class FlareCore implements Finalizable {
  static NativeFinalizer? _finalizer;

  late final FlareBindings _bindings;
  Pointer<DB>? _db;
  final Map<String, Map<String, int>> _collectionIndexes = {};

  FlareCore([String? libraryPath]) {
    final dylib = DynamicLibrary.open(libraryPath ?? _defaultLibraryName);
    _init(dylib);
  }

  static String get _defaultLibraryName {
    if (Platform.isWindows) {
      return 'flare_db.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'flare_db.framework/flare_db';
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return 'libflare_db.so';
    }
    throw UnsupportedError('Unsupported platform');
  }

  void _init(DynamicLibrary dylib) {
    _bindings = FlareBindings(dylib);
    _finalizer ??= NativeFinalizer(
      dylib.lookup<NativeFunction<Void Function(Pointer)>>('db_close').cast(),
    );
  }

  void open(String path, {List<int>? encryptionKey}) {
    final pathPtr = path.toNativeUtf8();
    Pointer<Uint8> keyPtr = nullptr;
    if (encryptionKey != null) {
      if (encryptionKey.length != 32) {
        throw ArgumentError("Key must be 32 bytes");
      }
      keyPtr = malloc<Uint8>(32);
      for (var i = 0; i < 32; i++) {
        keyPtr[i] = encryptionKey[i];
      }
    }

    // Retry logic for parallel opens
    for (var i = 0; i < 5; i++) {
      _db = _bindings.db_open(pathPtr.cast(), keyPtr.cast());
      if (_db != null && _db!.address != 0) break;
      sleep(Duration(milliseconds: 100 * (i + 1)));
    }

    malloc.free(pathPtr);
    if (keyPtr != nullptr) malloc.free(keyPtr);

    if (_db == null || _db!.address == 0) {
      throw Exception("Failed to open database");
    }

    // Load persisted secondary indexes from DB header
    for (var i = 0; i < 8; i++) {
      final namePtr = _bindings.db_get_index_name(_db!, i);
      if (namePtr != nullptr) {
        try {
          final indexName = namePtr.cast<Utf8>().toDartString();
          _bindings.db_free_string(namePtr.cast());
          final colonIdx = indexName.indexOf(':');
          if (colonIdx != -1) {
            final collection = indexName.substring(0, colonIdx);
            final field = indexName.substring(colonIdx + 1);
            _collectionIndexes.putIfAbsent(collection, () => {})[field] = i;
          }
        } catch (_) {}
      }
    }

    _finalizer!.attach(this, _db!.cast(), detach: this);
  }

  void close() {
    if (_db != null) {
      _finalizer!.detach(this);
      _bindings.db_close(_db!);
      _db = null;
    }
  }

  void createIndex(String collection, String field) {
    final indexName = '$collection:$field';
    final namePtr = indexName.toNativeUtf8();
    final idx = _bindings.db_create_index(_db!, namePtr.cast());
    malloc.free(namePtr);

    if (idx == -1) throw Exception("Max indexes reached");
    _collectionIndexes.putIfAbsent(collection, () => {})[field] = idx;
  }

  int put(String key, String json) {
    final oldJson = get(key);
    final keyPtr = key.toNativeUtf8();
    final jsonPtr = json.toNativeUtf8();
    final id = _bindings.db_put(_db!, keyPtr.cast(), jsonPtr.cast());

    // Update secondary indexes
    final pathParts = key.split('/');
    if (pathParts.length >= 2) {
      final collection = pathParts.sublist(0, pathParts.length - 1).join('/');
      final indexes = _collectionIndexes[collection];
      if (indexes != null) {
        try {
          final newData = jsonDecode(json);
          final oldData = oldJson != null ? jsonDecode(oldJson) : null;

          if (newData is Map) {
            indexes.forEach((field, idx) {
              final newVal = newData[field]?.toString();
              final oldVal = (oldData is Map)
                  ? oldData[field]?.toString()
                  : null;

              if (newVal != oldVal) {
                if (oldVal != null) {
                  final oldValPtr = oldVal.toNativeUtf8();
                  _bindings.db_remove_secondary(
                    _db!,
                    idx,
                    oldValPtr.cast(),
                    keyPtr.cast(),
                  );
                  malloc.free(oldValPtr);
                }
                if (newVal != null) {
                  final newValPtr = newVal.toNativeUtf8();
                  _bindings.db_put_secondary(
                    _db!,
                    idx,
                    newValPtr.cast(),
                    keyPtr.cast(),
                  );
                  malloc.free(newValPtr);
                }
              }
            });
          }
        } catch (_) {}
      }
    }

    malloc.free(keyPtr);
    malloc.free(jsonPtr);
    return id;
  }

  /// Internal: returns primary keys from a secondary index lookup.
  Iterable<String> getRangeBySecondary(
    String collection,
    String field,
    String value,
  ) sync* {
    final indexes = _collectionIndexes[collection];
    if (indexes == null || !indexes.containsKey(field)) return;

    final root = _bindings.db_get_root(_db!, indexes[field]!);
    if (root == 0) return;

    final prefix = '$value\x1F';
    final endKey = '$value '; // SPACE is \x20, which is > \x1F

    for (final entry in getRange(prefix, endKey, rootOffset: root)) {
      final parts = entry.key.split('\x1F');
      if (parts.length >= 2 && parts[0] == value) {
        yield parts.sublist(1).join('\x1F');
      }
    }
  }

  /// Internal: returns the primary key for a secondary index lookup (DEPRECATED).
  String? getBySecondary(String collection, String field, String value) {
    return getRangeBySecondary(collection, field, value).firstOrNull;
  }

  String? get(String key) {
    final keyPtr = key.toNativeUtf8();
    final resultPtr = _bindings.db_get_by_key(_db!, keyPtr.cast());
    malloc.free(keyPtr);
    if (resultPtr == nullptr) return null;
    try {
      final result = resultPtr.cast<Utf8>().toDartString();
      return result;
    } catch (_) {
      return null;
    } finally {
      _bindings.db_free_string(resultPtr.cast());
    }
  }

  bool delete(String key) {
    final oldJson = get(key);
    if (oldJson != null) {
      final pathParts = key.split('/');
      if (pathParts.length >= 2) {
        final collection = pathParts.sublist(0, pathParts.length - 1).join('/');
        final indexes = _collectionIndexes[collection];
        if (indexes != null) {
          try {
            final oldData = jsonDecode(oldJson);
            final keyPtr = key.toNativeUtf8();
            if (oldData is Map) {
              indexes.forEach((field, idx) {
                final oldVal = oldData[field]?.toString();
                if (oldVal != null) {
                  final oldValPtr = oldVal.toNativeUtf8();
                  _bindings.db_remove_secondary(
                    _db!,
                    idx,
                    oldValPtr.cast(),
                    keyPtr.cast(),
                  );
                  malloc.free(oldValPtr);
                }
              });
            }
            malloc.free(keyPtr);
          } catch (_) {}
        }
      }
    }
    final keyPtr = key.toNativeUtf8();
    final result = _bindings.db_delete(_db!, keyPtr.cast());
    malloc.free(keyPtr);
    return result;
  }

  void sync() => _bindings.db_sync(_db!);

  Iterable<MapEntry<String, String>> getRange(
    String prefix,
    String endKey, {
    int rootOffset = 0,
  }) sync* {
    final startPtr = prefix.toNativeUtf8();
    final endPtr = endKey.toNativeUtf8();
    final it = _bindings.db_iterator_open(
      _db!,
      rootOffset,
      startPtr.cast(),
      endPtr.cast(),
    );
    malloc.free(startPtr);
    malloc.free(endPtr);

    try {
      final keyPtrPtr = malloc<Pointer<Utf8>>();
      final jsonPtrPtr = malloc<Pointer<Utf8>>();
      try {
        while (_bindings.db_iterator_next(
          it,
          keyPtrPtr.cast(),
          jsonPtrPtr.cast(),
        )) {
          try {
            final key = keyPtrPtr.value.cast<Utf8>().toDartString();
            final json = jsonPtrPtr.value.cast<Utf8>().toDartString();
            yield MapEntry(key, json);
          } catch (_) {
            // Skip corrupted
          } finally {
            _bindings.db_free_string(jsonPtrPtr.value.cast());
          }
        }
      } finally {
        malloc.free(keyPtrPtr);
        malloc.free(jsonPtrPtr);
      }
    } finally {
      _bindings.db_iterator_close(it);
    }
  }
}
