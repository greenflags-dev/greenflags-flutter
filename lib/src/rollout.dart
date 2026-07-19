import 'dart:convert';

/// Deterministic rollout bucketing. Canonical algorithm:
/// `docs/rollout-hash-spec.md` (repo root). Must stay byte-identical to every
/// other GreenFlags evaluator — conformance vectors live in
/// `sdks/rollout-test-vectors.json`.

const int _fnvOffsetBasis = 0x811C9DC5;
const int _fnvPrime = 16777619;

int _fnv1a32(String input) {
  var hash = _fnvOffsetBasis;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    // Wrap mod 2^32: Dart ints are 64-bit (VM), mask after multiply.
    hash = (hash * _fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Bucket (0-99) a user falls into for a given flag. Stable for the same
/// flagKey + userKey pair across every GreenFlags SDK and the server.
int rolloutBucket(String flagKey, String userKey) {
  return _fnv1a32('$flagKey:$userKey') % 100;
}

bool isIncludedInRollout(String flagKey, String userKey, int percentage) {
  return rolloutBucket(flagKey, userKey) < percentage;
}

/// Spec: variants ordered by name in UTF-8 BYTE order. Dart's String
/// `compareTo` is UTF-16 code-unit order, which diverges for astral-plane
/// characters — compare encoded bytes explicitly.
int _compareUtf8(String a, String b) {
  final bytesA = utf8.encode(a);
  final bytesB = utf8.encode(b);
  final length = bytesA.length < bytesB.length ? bytesA.length : bytesB.length;
  for (var i = 0; i < length; i++) {
    if (bytesA[i] != bytesB[i]) {
      return bytesA[i] - bytesB[i];
    }
  }
  return bytesA.length - bytesB.length;
}

/// A (name, weight) pair for variant assignment.
class WeightedVariant {
  const WeightedVariant({required this.name, required this.weight});

  final String name;
  final int weight;
}

/// Assign a user to a weighted variant: cumulative ranges over the 0-99
/// bucket, variants sorted by name (UTF-8 byte order). Returns the variant
/// name, or `null` when the bucket falls beyond the total weight (base value
/// applies).
String? assignVariant(
  String flagKey,
  String userKey,
  List<WeightedVariant> variants,
) {
  final sorted = [...variants]..sort((a, b) => _compareUtf8(a.name, b.name));
  final bucket = rolloutBucket(flagKey, userKey);
  var cumulative = 0;
  for (final variant in sorted) {
    cumulative += variant.weight;
    if (bucket < cumulative) {
      return variant.name;
    }
  }
  return null;
}
