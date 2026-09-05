/// A GeoPoint represents a geographical point by its latitude and longitude.
///
/// This is designed to be compatible with Cloud Firestore's GeoPoint.
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude)
    : assert(latitude >= -90 && latitude <= 90),
      assert(longitude >= -180 && longitude <= 180);

  factory GeoPoint.fromMap(Map<String, dynamic> map) {
    return GeoPoint(
      (map['_latitude'] as num).toDouble(),
      (map['_longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    '_latitude': latitude,
    '_longitude': longitude,
    '_type': 'GeoPoint',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;

  @override
  String toString() => 'GeoPoint(latitude: $latitude, longitude: $longitude)';
}
