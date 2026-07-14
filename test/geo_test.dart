import 'package:greenflags/src/geo.dart';
import 'package:greenflags/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('geoDistanceMeters', () {
    test('returns 0 for the same point', () {
      const point = Coordinates(latitude: 19.4326, longitude: -99.1332);
      expect(geoDistanceMeters(point, point), closeTo(0, 1e-6));
    });

    test('matches the Paris-London great-circle distance within 1%', () {
      const paris = Coordinates(latitude: 48.8566, longitude: 2.3522);
      const london = Coordinates(latitude: 51.5074, longitude: -0.1278);
      const expected = 343550.0; // meters, known reference
      final distance = geoDistanceMeters(paris, london);
      expect((distance - expected).abs() / expected, lessThan(0.01));
    });

    test('small distance across the antimeridian, not near-half-Earth', () {
      const a = Coordinates(latitude: 0, longitude: 179.9);
      const b = Coordinates(latitude: 0, longitude: -179.9);
      final distance = geoDistanceMeters(a, b);
      expect(distance, lessThan(30000));
      expect(distance, greaterThan(15000));
    });

    test('small finite distance near the pole with different longitudes', () {
      const a = Coordinates(latitude: 89.999, longitude: 0);
      const b = Coordinates(latitude: 89.999, longitude: 180);
      final distance = geoDistanceMeters(a, b);
      expect(distance.isFinite, isTrue);
      expect(distance, lessThan(300));
    });

    test('returns 0 at the exact pole regardless of longitude', () {
      const a = Coordinates(latitude: 90, longitude: 0);
      const b = Coordinates(latitude: 90, longitude: 137);
      expect(geoDistanceMeters(a, b), closeTo(0, 1e-6));
    });
  });
}
