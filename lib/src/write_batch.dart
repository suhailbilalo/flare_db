import 'dart:async';

import '../flare_db.dart';

/// A write batch allows grouping multiple set and delete operations
/// into a single atomic batch commit.
class WriteBatch {
  final FlareDatabase _db;
  final List<void Function()> _operations = [];

  WriteBatch(this._db);

  /// Exposes operations in the batch.
  List<void Function()> get operations => _operations;

  /// Sets data for a document reference within the batch.
  WriteBatch set<T>(DocumentReference<T> ref, T data) {
    _operations.add(() => ref.set(data));
    return this;
  }

  /// Deletes a document reference within the batch.
  WriteBatch delete<T>(DocumentReference<T> ref) {
    _operations.add(() => ref.delete());
    return this;
  }

  /// Commits all operations in the batch and syncs to disk.
  void commit() {
    for (final op in _operations) {
      op();
    }
    _db.sync();
  }
}

/// A transaction context for executing reads and writes atomically.
class Transaction {
  final List<void Function()> _operations = [];

  Transaction();

  /// Exposes operations in the transaction.
  List<void Function()> get operations => _operations;

  /// Sets data for a document reference within the transaction.
  Transaction set<T>(DocumentReference<T> ref, T data) {
    _operations.add(() => ref.set(data));
    return this;
  }

  /// Deletes a document reference within the transaction.
  Transaction delete<T>(DocumentReference<T> ref) {
    _operations.add(() => ref.delete());
    return this;
  }
}

/// A mutex lock for serializing asynchronous database operations and ensuring
/// thread safety and transaction isolation.
class FlareMutex {
  bool _locked = false;
  final List<Completer<void>> _queue = [];

  /// Executes an action exclusively, queueing concurrent callers.
  Future<T> protect<T>(Future<T> Function() action) async {
    while (_locked) {
      final completer = Completer<void>();
      _queue.add(completer);
      await completer.future;
    }
    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      }
    }
  }
}
