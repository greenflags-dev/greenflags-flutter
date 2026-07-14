import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'geo.dart';
import 'persistence.dart';
import 'transport.dart';
import 'types.dart';

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
    SnapshotStore? store,
    http.Client? httpClient,
  })  : _url = url.trim().replaceFirst(RegExp(r'/$'), ''),
        _apiToken = apiToken,
        _coordinates = coordinates,
        _store = store,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  final String _url;
  final String _apiToken;
  final SnapshotStore? _store;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Coordinates? _coordinates;
  Map<String, Flag> _snapshot = {};
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

  /// Stops polling and releases resources. The client must not be used
  /// afterwards.
  void dispose() {
    stopPolling();
    _controller.close();
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Flag _evaluate(Flag flag) {
    final coords = _coordinates;
    final geofence = flag.geofence;
    if (coords == null || geofence == null) {
      return flag;
    }
    final center = Coordinates(
      latitude: geofence.latitude,
      longitude: geofence.longitude,
    );
    final outside = geoDistanceMeters(coords, center) > geofence.radiusMeters;
    if (!outside) {
      return flag;
    }
    return flag.copyWith(value: flag.type == FlagType.boolean ? false : null);
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
