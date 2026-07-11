/// Flag value types supported by GreenFlags.
enum FlagType {
  boolean('boolean'),
  string('string'),
  number('number'),
  json('json');

  const FlagType(this.wire);

  /// Wire name as returned by the API.
  final String wire;

  static FlagType fromWire(String value) {
    return FlagType.values.firstWhere(
      (t) => t.wire == value,
      orElse: () => FlagType.json,
    );
  }
}

/// A geographic point (decimal degrees).
class Coordinates {
  const Coordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Geographic scope of a flag value: inside the radius the flag keeps its
/// value, outside it evaluates to its off value.
class Geofence {
  const Geofence({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  factory Geofence.fromJson(Map<String, Object?> json) => Geofence(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        radiusMeters: (json['radiusMeters'] as num).toDouble(),
      );

  final double latitude;
  final double longitude;
  final double radiusMeters;

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
      };
}

/// A feature flag as served by `GET /v1/flags`.
///
/// [value] holds `bool`, `String`, `num`, `Map<String, Object?>` or `null`
/// depending on [type] (and geofence evaluation).
class Flag {
  const Flag({
    required this.key,
    required this.type,
    required this.value,
    this.geofence,
  });

  factory Flag.fromJson(Map<String, Object?> json) => Flag(
        key: json['key'] as String,
        type: FlagType.fromWire(json['type'] as String),
        value: json['value'],
        geofence: json['geofence'] == null
            ? null
            : Geofence.fromJson(
                (json['geofence'] as Map).cast<String, Object?>(),
              ),
      );

  final String key;
  final FlagType type;
  final Object? value;
  final Geofence? geofence;

  Flag copyWith({Object? value}) =>
      Flag(key: key, type: type, value: value, geofence: geofence);

  Map<String, Object?> toJson() => {
        'key': key,
        'type': type.wire,
        'value': value,
        if (geofence != null) 'geofence': geofence!.toJson(),
      };
}

/// Error raised by the SDK. [code] mirrors the API error codes
/// (e.g. `INVALID_TOKEN`, `QUOTA_EXCEEDED`) plus the client-side
/// `NETWORK_ERROR` and `PARSE_ERROR`. [status] is the HTTP status
/// (0 for network failures).
class GreenFlagsException implements Exception {
  const GreenFlagsException(this.code, this.message, this.status);

  final String code;
  final String message;
  final int status;

  @override
  String toString() => 'GreenFlagsException($code, $status): $message';
}
