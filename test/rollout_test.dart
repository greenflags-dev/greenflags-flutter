import 'dart:convert';
import 'dart:io';

import 'package:greenflags/greenflags.dart';
import 'package:test/test.dart';

void main() {
  final raw = File('../rollout-test-vectors.json').readAsStringSync();
  final data = jsonDecode(raw) as Map<String, Object?>;
  final vectors = (data['vectors'] as List).cast<Map<String, Object?>>();
  final variantVectors =
      (data['variantVectors'] as List).cast<Map<String, Object?>>();

  group('rolloutBucket conformance', () {
    test('loads the shared vectors', () {
      expect(vectors.length, greaterThanOrEqualTo(20));
      expect(variantVectors.length, greaterThanOrEqualTo(8));
    });

    test('every vector matches', () {
      for (final vector in vectors) {
        final flagKey = vector['flagKey'] as String;
        final userKey = vector['userKey'] as String;
        final bucket = (vector['bucket'] as num).toInt();
        expect(
          rolloutBucket(flagKey, userKey),
          bucket,
          reason: 'bucket($flagKey, $userKey)',
        );
      }
    });
  });

  group('assignVariant conformance', () {
    test('every variant vector matches', () {
      for (final vector in variantVectors) {
        final flagKey = vector['flagKey'] as String;
        final userKey = vector['userKey'] as String;
        final expected = vector['assigned'] as String?;
        final variants = [
          for (final item
              in (vector['variants'] as List).cast<Map<String, Object?>>())
            WeightedVariant(
              name: item['name'] as String,
              weight: (item['weight'] as num).toInt(),
            ),
        ];
        expect(
          assignVariant(flagKey, userKey, variants),
          expected,
          reason: 'assign($flagKey, $userKey)',
        );
      }
    });

    test('input order does not matter; empty list returns null', () {
      final forward = assignVariant('checkout-theme', 'user-2', const [
        WeightedVariant(name: 'A', weight: 30),
        WeightedVariant(name: 'B', weight: 70),
      ]);
      final reversed = assignVariant('checkout-theme', 'user-2', const [
        WeightedVariant(name: 'B', weight: 70),
        WeightedVariant(name: 'A', weight: 30),
      ]);
      expect(forward, reversed);
      expect(assignVariant('any', 'user', const []), isNull);
    });
  });
}
