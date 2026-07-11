import 'dart:convert';

import 'package:http/http.dart' as http;

import 'types.dart';

/// Fetches all flags of the token's environment. Internal.
Future<Map<String, Flag>> requestFlags({
  required String url,
  required String apiToken,
  required http.Client httpClient,
}) async {
  final base = url.trim().replaceFirst(RegExp(r'/$'), '');
  final uri = Uri.parse('$base/v1/flags');

  http.Response response;
  try {
    response = await httpClient.get(
      uri,
      headers: {'authorization': 'Bearer $apiToken'},
    );
  } catch (err) {
    throw GreenFlagsException('NETWORK_ERROR', err.toString(), 0);
  }

  Object? body;
  try {
    body = jsonDecode(response.body);
  } catch (_) {
    throw GreenFlagsException(
      'PARSE_ERROR',
      'Invalid response from server',
      response.statusCode,
    );
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final envelope = body is Map ? body : const <String, Object?>{};
    throw GreenFlagsException(
      envelope['error'] as String? ?? 'REQUEST_ERROR',
      envelope['message'] as String? ?? 'Request failed',
      response.statusCode,
    );
  }

  final envelope = body is Map ? body.cast<String, Object?>() : null;
  final data = envelope?['data'];
  final flagsRaw = data is Map ? data['flags'] : null;
  if (flagsRaw is! List) {
    throw GreenFlagsException(
      'PARSE_ERROR',
      'Invalid response from server',
      response.statusCode,
    );
  }

  final result = <String, Flag>{};
  for (final raw in flagsRaw) {
    if (raw is Map) {
      final flag = Flag.fromJson(raw.cast<String, Object?>());
      result[flag.key] = flag;
    }
  }
  return result;
}
