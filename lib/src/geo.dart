import 'dart:math' as math;

import 'types.dart';

const double _earthRadiusMeters = 6371000;

double _toRadians(double degrees) => degrees * math.pi / 180;

/// Great-circle distance between [a] and [b] in meters (haversine formula).
///
/// This is the exact calculation the SDK runs internally to evaluate geofenced
/// flags, exposed so apps can show the live distance to a geofence without
/// reimplementing it.
double geoDistanceMeters(Coordinates a, Coordinates b) {
  final phi1 = _toRadians(a.latitude);
  final phi2 = _toRadians(b.latitude);
  final deltaPhi = _toRadians(b.latitude - a.latitude);
  final deltaLambda = _toRadians(b.longitude - a.longitude);

  final h = math.pow(math.sin(deltaPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(deltaLambda / 2), 2);

  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));

  return _earthRadiusMeters * c;
}
