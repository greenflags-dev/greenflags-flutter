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

/// Percentage rollout rule: `percentage`% of users (bucketed
/// deterministically) receive the flag's value, the rest its off value.
class Rollout {
  const Rollout({required this.percentage});

  factory Rollout.fromJson(Map<String, Object?> json) =>
      Rollout(percentage: (json['percentage'] as num).toInt());

  final int percentage;

  Map<String, Object?> toJson() => {'percentage': percentage};
}

/// A weighted variant of a multivariate flag.
class FlagVariant {
  const FlagVariant({
    required this.name,
    required this.weight,
    required this.value,
  });

  factory FlagVariant.fromJson(Map<String, Object?> json) => FlagVariant(
        name: json['name'] as String,
        weight: (json['weight'] as num).toInt(),
        value: json['value'],
      );

  final String name;
  final int weight;
  final Object? value;

  Map<String, Object?> toJson() =>
      {'name': name, 'weight': weight, 'value': value};
}

/// A feature flag as served by `GET /v1/flags`.
///
/// [value] holds `bool`, `String`, `num`, `Map<String, Object?>` or `null`
/// depending on [type] (and geofence/rollout/variant evaluation).
class Flag {
  const Flag({
    required this.key,
    required this.type,
    required this.value,
    this.geofence,
    this.rollout,
    this.variants,
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
        rollout: json['rollout'] == null
            ? null
            : Rollout.fromJson(
                (json['rollout'] as Map).cast<String, Object?>(),
              ),
        variants: json['variants'] == null
            ? null
            : [
                for (final item in json['variants'] as List)
                  FlagVariant.fromJson((item as Map).cast<String, Object?>()),
              ],
      );

  final String key;
  final FlagType type;
  final Object? value;
  final Geofence? geofence;
  final Rollout? rollout;
  final List<FlagVariant>? variants;

  Flag copyWith({Object? value}) => Flag(
        key: key,
        type: type,
        value: value,
        geofence: geofence,
        rollout: rollout,
        variants: variants,
      );

  Map<String, Object?> toJson() => {
        'key': key,
        'type': type.wire,
        'value': value,
        if (geofence != null) 'geofence': geofence!.toJson(),
        if (rollout != null) 'rollout': rollout!.toJson(),
        if (variants != null)
          'variants': [for (final v in variants!) v.toJson()],
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
