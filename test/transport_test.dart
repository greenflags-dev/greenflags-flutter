import 'dart:convert';

import 'package:greenflags/src/transport.dart';
import 'package:greenflags/src/types.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('requestFlags', () {
    test('parses flags into a map keyed by flag key', () async {
      late Uri capturedUri;
      late Map<String, String> capturedHeaders;
      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'flags': [
                {'key': 'a', 'type': 'boolean', 'value': true},
                {
                  'key': 'b',
                  'type': 'string',
                  'value': 'x',
                  'geofence': {
                    'latitude': 1.0,
                    'longitude': 2.0,
                    'radiusMeters': 500,
                  },
                },
              ],
            },
          }),
          200,
        );
      });

      final flags = await requestFlags(
        url: 'https://app.greenflags.dev/',
        apiToken: 'gf_test',
        httpClient: client,
      );

      expect(capturedUri.toString(), 'https://app.greenflags.dev/v1/flags');
      expect(capturedHeaders['authorization'], 'Bearer gf_test');
      expect(flags, hasLength(2));
      expect(flags['a']!.value, isTrue);
      expect(flags['b']!.geofence!.radiusMeters, 500);
    });

    test('maps API error envelopes to GreenFlagsException', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'INVALID_TOKEN',
            'message': 'Invalid API token.',
          }),
          401,
        );
      });

      await expectLater(
        requestFlags(
          url: 'https://app.greenflags.dev',
          apiToken: 'bad',
          httpClient: client,
        ),
        throwsA(
          isA<GreenFlagsException>()
              .having((e) => e.code, 'code', 'INVALID_TOKEN')
              .having((e) => e.status, 'status', 401),
        ),
      );
    });

    test('throws PARSE_ERROR on non-JSON body', () async {
      final client = MockClient((request) async {
        return http.Response('<html>oops</html>', 200);
      });

      await expectLater(
        requestFlags(
          url: 'https://app.greenflags.dev',
          apiToken: 'gf_test',
          httpClient: client,
        ),
        throwsA(
          isA<GreenFlagsException>()
              .having((e) => e.code, 'code', 'PARSE_ERROR'),
        ),
      );
    });

    test('throws NETWORK_ERROR when the request itself fails', () async {
      final client = MockClient((request) async {
        throw Exception('connection refused');
      });

      await expectLater(
        requestFlags(
          url: 'https://app.greenflags.dev',
          apiToken: 'gf_test',
          httpClient: client,
        ),
        throwsA(
          isA<GreenFlagsException>()
              .having((e) => e.code, 'code', 'NETWORK_ERROR')
              .having((e) => e.status, 'status', 0),
        ),
      );
    });
  });
}
