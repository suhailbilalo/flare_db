import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../flare_db.dart';

typedef FromFirestore<T> = T Function(
  DocumentSnapshot<Map<String, dynamic>> snapshot,
);
typedef ToFirestore<T> = Map<String, dynamic> Function(T value);

/// A snapshot of a document's data.
class DocumentSnapshot<T> {
  final String id;
  final String path;
  final T? _data;
  final bool exists;

  DocumentSnapshot(this.id, this.path, this._data, this.exists);

  /// Returns the data as the specified type [T].
  T? data() => _data;

  @override
  String toString() =>
      'DocumentSnapshot(id: $id, exists: $exists, data: $_data)';
}

/// A reference to a specific document in the database.
class DocumentReference<T> {
  final String path;
  final FlareDatabase _db;
  final FromFirestore<T>? _fromFirestore;
  final ToFirestore<T>? _toFirestore;

  DocumentReference(
    this.path,
    this._db, {
    this._fromFirestore,
    this._toFirestore,
  });

  String get id => path.split('/').last;

  /// Returns a [CollectionReference] for a sub-collection.
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return CollectionReference('$path/$collectionPath', _db);
  }

  /// Sets the data for this document.
  void set(T data) {
    Map<String, dynamic> map;
    final toFirestore = _toFirestore;
    if (toFirestore != null) {
      map = toFirestore(data);
    } else if (data is Map<String, dynamic>) {
      map = data;
    } else {
      throw Exception("No converter provided for type ${data.runtimeType}");
    }
    _db.engine.put(path, jsonEncode(map));
  }

  /// Retrieves the document snapshot.
  DocumentSnapshot<T> get() {
    final raw = _db.engine.get(path);
    if (raw == null) {
      return DocumentSnapshot(id, path, null, false);
    }

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final fromFirestore = _fromFirestore;
      if (fromFirestore != null) {
        final snapshot = DocumentSnapshot<Map<String, dynamic>>(
          id,
          path,
          map,
          true,
        );
        return DocumentSnapshot<T>(id, path, fromFirestore(snapshot), true);
      }

      return DocumentSnapshot<T>(id, path, map as T, true);
    } catch (e) {
      return DocumentSnapshot(id, path, null, false);
    }
  }

  /// Deletes the document.
  void delete() {
    _db.engine.delete(path);
  }

  /// Changes the type of this reference using a converter.
  DocumentReference<U> withConverter<U>({
    required FromFirestore<U> fromFirestore,
    required ToFirestore<U> toFirestore,
  }) {
    return DocumentReference<U>(
      path,
      _db,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
  }
}

/// A query for documents in a collection.
class Query<T> {
  final String path;
  final FlareDatabase _db;
  final FromFirestore<T>? _fromFirestore;
  final ToFirestore<T>? _toFirestore;
  final List<(_QueryOperation, String, dynamic)> _ops = [];

  Query(this.path, this._db, {this._fromFirestore, this._toFirestore});

  /// Filters the collection by field equality.
  Query<T> where(String field, {dynamic isEqualTo}) {
    final query = Query<T>(
      path,
      _db,
      fromFirestore: _fromFirestore,
      toFirestore: _toFirestore,
    );
    query._ops.addAll(_ops);
    query._ops.add((_QueryOperation.isEqualTo, field, isEqualTo));
    return query;
  }

  /// Changes the type of this query using a converter.
  Query<U> withConverter<U>({
    required FromFirestore<U> fromFirestore,
    required ToFirestore<U> toFirestore,
  }) {
    final query = Query<U>(
      path,
      _db,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
    query._ops.addAll(_ops);
    return query;
  }

  /// Executes the query and returns the results.
  List<DocumentSnapshot<T>> get() {
    // Optimization: Try to use secondary index if we have an equality filter
    for (final op in _ops) {
      if (op.$1 == _QueryOperation.isEqualTo && op.$3 is String) {
        final primKeys = _db.engine.getRangeBySecondary(
          path,
          op.$2,
          op.$3 as String,
        );
        if (primKeys.isNotEmpty) {
          final results = <DocumentSnapshot<T>>[];
          for (final primKey in primKeys) {
            final docRef = DocumentReference<T>(
              primKey,
              _db,
              fromFirestore: _fromFirestore,
              toFirestore: _toFirestore,
            );
            final snap = docRef.get();
            if (snap.exists) {
              // Re-verify other filters if any
              bool matches = true;
              final data = snap.data();
              if (data is Map<String, dynamic>) {
                for (final otherOp in _ops) {
                  if (otherOp.$1 == _QueryOperation.isEqualTo) {
                    if (data[otherOp.$2] != otherOp.$3) {
                      matches = false;
                      break;
                    }
                  }
                }
              } else if (data is! Map && _fromFirestore == null) {
                final mapData = snap.data() as Map<String, dynamic>;
                for (final otherOp in _ops) {
                  if (otherOp.$1 == _QueryOperation.isEqualTo) {
                    if (mapData[otherOp.$2] != otherOp.$3) {
                      matches = false;
                      break;
                    }
                  }
                }
              }
              if (matches) results.add(snap);
            }
          }
          if (results.isNotEmpty) return results;
        }
      }
    }

    // Fallback: full scan (slow but works for any query and keeps IDs accurate)
    final results = <DocumentSnapshot<T>>[];
    final prefix = '$path/';
    final endKey = '${path}0';

    for (final entry in _db.engine.getRange(prefix, endKey)) {
      if (entry.key.startsWith(prefix)) {
        final id = entry.key.substring(prefix.length);
        if (!id.contains('/')) {
          final map = jsonDecode(entry.value) as Map<String, dynamic>;

          bool matches = true;
          for (final op in _ops) {
            if (op.$1 == _QueryOperation.isEqualTo) {
              if (map[op.$2] != op.$3) {
                matches = false;
                break;
              }
            }
          }

          if (matches) {
            T data;
            final fromFirestore = _fromFirestore;
            if (fromFirestore != null) {
              data = fromFirestore(
                DocumentSnapshot<Map<String, dynamic>>(
                  id,
                  entry.key,
                  map,
                  true,
                ),
              );
            } else {
              data = map as T;
            }
            results.add(DocumentSnapshot<T>(id, entry.key, data, true));
          }
        }
      }
    }
    return results;
  }
}

enum _QueryOperation { isEqualTo }

/// A reference to a collection of documents.
class CollectionReference<T> extends Query<T> {
  CollectionReference(
    super.path,
    super._db, {
    super.fromFirestore,
    super.toFirestore,
  });

  static const _uuid = Uuid();

  /// Returns a [DocumentReference] for a document in this collection.
  DocumentReference<T> doc([String? docPath]) {
    final fullPath = docPath == null ? '$path/${_uuid.v4()}' : '$path/$docPath';
    return DocumentReference<T>(
      fullPath,
      _db,
      fromFirestore: _fromFirestore,
      toFirestore: _toFirestore,
    );
  }

  @override
  CollectionReference<U> withConverter<U>({
    required FromFirestore<U> fromFirestore,
    required ToFirestore<U> toFirestore,
  }) {
    return CollectionReference<U>(
      path,
      _db,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
  }
}
