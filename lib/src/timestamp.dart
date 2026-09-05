/// A Timestamp represents a point in time independent of any time zone or calendar,
/// represented as seconds and fractions of seconds at nanosecond resolution in UTC Epoch time.
///
/// This is designed to be compatible with Cloud Firestore's Timestamp.
class Timestamp {
  final int seconds;
  final int nanoseconds;

  const Timestamp(this.seconds, this.nanoseconds);

  factory Timestamp.now() {
    final now = DateTime.now().toUtc();
    return Timestamp.fromDate(now);
  }

  factory Timestamp.fromDate(DateTime date) {
    final seconds = date.millisecondsSinceEpoch ~/ 1000;
    final nanoseconds = (date.millisecondsSinceEpoch % 1000) * 1000000;
    return Timestamp(seconds, nanoseconds);
  }

  DateTime toDate() {
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000 + (nanoseconds ~/ 1000000),
      isUtc: true,
    );
  }

  factory Timestamp.fromMap(Map<String, dynamic> map) {
    return Timestamp(map['_seconds'] as int, map['_nanoseconds'] as int);
  }

  Map<String, dynamic> toMap() => {
    '_seconds': seconds,
    '_nanoseconds': nanoseconds,
    '_type': 'Timestamp',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Timestamp &&
          seconds == other.seconds &&
          nanoseconds == other.nanoseconds;

  @override
  int get hashCode => seconds.hashCode ^ nanoseconds.hashCode;

  @override
  String toString() =>
      'Timestamp(seconds: $seconds, nanoseconds: $nanoseconds)';
}
