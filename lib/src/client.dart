import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'geo.dart';
import 'persistence.dart';
import 'rollout.dart';
import 'transport.dart';
import 'types.dart';

String _generateAnonymousId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  // RFC 4122 v4 shape.
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Client for the GreenFlags read API.
///
/// ```dart
/// final flags = GreenFlagsClient(
///   url: 'https://app.greenflags.dev',
///   apiToken: 'gf_...',
/// );
/// await flags.refresh();
/// if (flags.isEnabled('new-checkout')) { ... }
/// ```
///
/// Every read path (getFlag/isEnabled/getAllFlags/getSnapshot and the
/// snapshots emitted on [snapshotStream]) goes through geofence evaluation —
/// the raw cached snapshot is never exposed.
class GreenFlagsClient {
  GreenFlagsClient({
    required String url,
    required String apiToken,
    Coordinates? coordinates,
    String? user,
    SnapshotStore? store,
    http.Client? httpClient,
  })  : _url = url.trim().replaceFirst(RegExp(r'/$'), ''),
        _apiToken = apiToken,
        _coordinates = coordinates,
        _explicitUser = user,
        _store = store,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  final String _url;
  final String _apiToken;
  final SnapshotStore? _store;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Coordinates? _coordinates;
  String? _explicitUser;
  String? _anonymousId;
  Map<String, Flag> _snapshot = {};

  String _resolveUserKey() {
    final explicit = _explicitUser;
    if (explicit != null) {
      return explicit;
    }
    // In-memory anonymous identity: deterministic within this client's
    // lifetime. Pass a stable `user` for cross-session stickiness.
    return _anonymousId ??= _generateAnonymousId();
  }
  Timer? _pollingTimer;
  final StreamController<Map<String, Flag>> _controller =
      StreamController.broadcast();

  /// Emits the evaluated snapshot after every successful [refresh] or
  /// [hydrate], and whenever [setCoordinates] changes the evaluation.
  Stream<Map<String, Flag>> get snapshotStream => _controller.stream;

  /// Fetches the environment's flags from the API and replaces the local
  /// snapshot. Throws [GreenFlagsException] on failure (previous snapshot
  /// is kept).
  Future<void> refresh() async {
    _snapshot = await requestFlags(
      url: _url,
      apiToken: _apiToken,
      httpClient: _httpClient,
    );
    await _persist();
    _notify();
  }

  /// Loads the last persisted snapshot (if a [SnapshotStore] was provided),
  /// so flags are available on startup before the first network call.
  /// Silently does nothing when there is no store or no stored snapshot.
  Future<void> hydrate() async {
    final store = _store;
    if (store == null) {
      return;
    }
    String? raw;
    try {
      raw = await store.read();
    } catch (_) {
      return;
    }
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      final restored = <String, Flag>{};
      for (final item in decoded) {
        if (item is Map) {
          final flag = Flag.fromJson(item.cast<String, Object?>());
          restored[flag.key] = flag;
        }
      }
      _snapshot = restored;
      _notify();
    } catch (_) {
      // Corrupt cache: ignore, the next refresh() overwrites it.
    }
  }

  /// The evaluated snapshot, keyed by flag key.
  Map<String, Flag> getSnapshot() {
    return {
      for (final entry in _snapshot.entries)
        entry.key: _evaluate(entry.value),
    };
  }

  /// All evaluated flags.
  List<Flag> getAllFlags() => _snapshot.values.map(_evaluate).toList();

  /// The evaluated value of [key], or [defaultValue] when the flag does not
  /// exist in the snapshot.
  Object? getFlag(String key, {Object? defaultValue}) {
    final flag = _snapshot[key];
    if (flag == null) {
      return defaultValue;
    }
    return _evaluate(flag).value;
  }

  /// True when [key] is a boolean flag currently evaluating to `true`.
  bool isEnabled(String key) => getFlag(key) == true;

  /// Refreshes every [interval] until [stopPolling] or [dispose]. Errors are
  /// swallowed: the previous snapshot stays available.
  void startPolling(Duration interval) {
    stopPolling();
    _pollingTimer = Timer.periodic(interval, (_) {
      refresh().catchError((_) {});
    });
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Sets (or clears, with `null`) the end-user location used for geofence
  /// evaluation. No network request is made.
  void setCoordinates(Coordinates? coords) {
    _coordinates = coords;
    _notify();
  }

  /// Sets (or clears, with `null`) the stable user key used for percentage
  /// rollout and variant bucketing. Clearing reverts to an in-memory
  /// anonymous id. No network request is made.
  void setUser(String? user) {
    _explicitUser = user;
    _notify();
  }

  /// Stops polling and releases resources. The client must not be used
  /// afterwards.
  void dispose() {
    stopPolling();
    _controller.close();
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Flag _offValue(Flag flag) =>
      flag.copyWith(value: flag.type == FlagType.boolean ? false : null);

  // Evaluation chain per docs/rollout-hash-spec.md: geofence first, then
  // variants/rollout, AND semantics. A rule with missing input is skipped.
  Flag _evaluate(Flag flag) {
    final coords = _coordinates;
    final geofence = flag.geofence;
    if (coords != null && geofence != null) {
      final center = Coordinates(
        latitude: geofence.latitude,
        longitude: geofence.longitude,
      );
      final outside =
          geoDistanceMeters(coords, center) > geofence.radiusMeters;
      if (outside) {
        return _offValue(flag);
      }
    }

    final variants = flag.variants;
    if (variants != null && variants.isNotEmpty) {
      final assigned = assignVariant(flag.key, _resolveUserKey(), [
        for (final v in variants)
          WeightedVariant(name: v.name, weight: v.weight),
      ]);
      if (assigned == null) {
        return flag; // beyond total weight → base value
      }
      final variant = variants.firstWhere((v) => v.name == assigned);
      return flag.copyWith(value: variant.value);
    }

    final rollout = flag.rollout;
    if (rollout != null) {
      final included =
          isIncludedInRollout(flag.key, _resolveUserKey(), rollout.percentage);
      if (!included) {
        return _offValue(flag);
      }
    }

    return flag;
  }

  void _notify() {
    if (!_controller.isClosed) {
      _controller.add(getSnapshot());
    }
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) {
      return;
    }
    try {
      // Raw (un-evaluated) flags: geofence evaluation happens on read, so a
      // location change after restart still evaluates correctly.
      final raw = jsonEncode([
        for (final flag in _snapshot.values) flag.toJson(),
      ]);
      await store.write(raw);
    } catch (_) {
      // Persistence is best-effort; never fail a refresh over it.
    }
  }
}
