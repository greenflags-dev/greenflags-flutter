import 'dart:async';
import 'dart:convert';

import 'package:greenflags/greenflags.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Client flagsServer(List<Map<String, Object?>> flags) {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'success': true,
        'data': {'flags': flags},
      }),
      200,
    );
  });
}

class MemoryStore implements SnapshotStore {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String snapshotJson) async {
    stored = snapshotJson;
  }
}

void main() {
  group('GreenFlagsClient', () {
    test('refresh + getFlag + isEnabled + default value', () async {
      final client = GreenFlagsClient(
        url: 'https://app.greenflags.dev',
        apiToken: 'gf_test',
        httpClient: flagsServer([
          {'key': 'on', 'type': 'boolean', 'value': true},
          {'key': 'banner', 'type': 'string', 'value': 'hello'},
        ]),
      );

      await client.refresh();

      expect(client.isEnabled('on'), isTrue);
      expect(client.getFlag('banner'), 'hello');
      expect(client.getFlag('missing', defaultValue: 42), 42);
      expect(client.getAllFlags(), hasLength(2));
      client.dispose();
    });

    test('geofence: outside radius returns off value, inside keeps value',
        () async {
      final client = GreenFlagsClient(
        url: 'https://app.greenflags.dev',
        apiToken: 'gf_test',
        httpClient: flagsServer([
          {
            'key': 'geo-bool',
            'type': 'boolean',
            'value': true,
            'geofence': {
              // CDMX Zócalo, 1km radius
              'latitude': 19.4326, 'longitude': -99.1332, 'radiusMeters': 1000,
            },
          },
          {
            'key': 'geo-string',
            'type': 'string',
            'value': 'promo',
            'geofence': {
              'latitude': 19.4326, 'longitude': -99.1332, 'radiusMeters': 1000,
            },
          },
        ]),
      );
      await client.refresh();

      // No coordinates set: geofence not evaluated, values unaffected.
      expect(client.isEnabled('geo-bool'), isTrue);

      // Inside the radius (a few meters away).
      client.setCoordinates(
        const Coordinates(latitude: 19.4327, longitude: -99.1333),
      );
      expect(client.isEnabled('geo-bool'), isTrue);
      expect(client.getFlag('geo-string'), 'promo');

      // Outside the radius (Monterrey, ~700km away).
      client.setCoordinates(
        const Coordinates(latitude: 25.6866, longitude: -100.3161),
      );
      expect(client.isEnabled('geo-bool'), isFalse);
      expect(client.getFlag('geo-string'), isNull);

      // Clearing coordinates restores un-geofenced evaluation.
      client.setCoordinates(null);
      expect(client.isEnabled('geo-bool'), isTrue);
      client.dispose();
    });

    test('snapshotStream emits evaluated snapshots on refresh', () async {
      final client = GreenFlagsClient(
        url: 'https://app.greenflags.dev',
        apiToken: 'gf_test',
        httpClient: flagsServer([
          {'key': 'on', 'type': 'boolean', 'value': true},
        ]),
      );

      final first = client.snapshotStream.first;
      await client.refresh();
      final snapshot = await first;
      expect(snapshot['on']!.value, isTrue);
      client.dispose();
    });

    test('failed refresh keeps the previous snapshot', () async {
      var calls = 0;
      final client = GreenFlagsClient(
        url: 'https://app.greenflags.dev',
        apiToken: 'gf_test',
        httpClient: MockClient((request) async {
          calls += 1;
          if (calls == 1) {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'flags': [
                    {'key': 'on', 'type': 'boolean', 'value': true},
                  ],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'success': false,
              'error': 'INVALID_TOKEN',
              'message': 'Invalid API token.',
            }),
            401,
          );
        }),
      );

      await client.refresh();
      expect(client.isEnabled('on'), isTrue);

      await expectLater(client.refresh(), throwsA(isA<GreenFlagsException>()));
      // Previous snapshot survives the failure.
      expect(client.isEnabled('on'), isTrue);
      client.dispose();
    });

    test('persists on refresh and hydrates on startup (offline boot)',
        () async {
      final store = MemoryStore();

      final online = GreenFlagsClient(
        url: 'https://app.greenflags.dev',
        apiToken: 'gf_test',
        store: store,
        httpClient: flagsServer([
          {'key': 'on', 'type': 'boolean', 'value': true},
        ]),
      );
      await online.refresh();
      online.dispose();
      expect(store.stored, isNotNull);

      // A brand-new client (fresh app start, no network) hydrates from disk.
      final offline = GreenFlagsClient(
        url: 'https://app.greenflags.dev',
        apiToken: 'gf_test',
        store: store,
        httpClient: MockClient(
          (request) async => throw Exception('offline'),
        ),
      );
      expect(offline.isEnabled('on'), isFalse);
      await offline.hydrate();
      expect(offline.isEnabled('on'), isTrue);
      offline.dispose();
    });

    test('hydrate ignores corrupt cache', () async {
      final store = MemoryStore()..stored = '{not json[';
      final client = GreenFlagsClient(
        url: 'https://app.greenflags.dev',
        apiToken: 'gf_test',
        store: store,
        httpClient: flagsServer(const []),
      );
      await client.hydrate();
      expect(client.getAllFlags(), isEmpty);
      client.dispose();
    });

    test('polling refreshes periodically and stop halts it', () async {
      var calls = 0;
      final client = GreenFlagsClient(
        url: 'https://app.greenflags.dev',
        apiToken: 'gf_test',
        httpClient: MockClient((request) async {
          calls += 1;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'flags': <Object>[]},
            }),
            200,
          );
        }),
      );

      client.startPolling(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 70));
      client.stopPolling();
      final callsAtStop = calls;
      expect(callsAtStop, greaterThanOrEqualTo(2));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, callsAtStop);
      client.dispose();
    });
  });
}
