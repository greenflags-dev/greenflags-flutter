/// Storage for the last known snapshot so a mobile app can serve flags on
/// startup while offline. The SDK serializes the snapshot to a JSON string;
/// implementations only need to persist that string.
///
/// In Flutter, back this with `shared_preferences`:
///
/// ```dart
/// class PrefsSnapshotStore implements SnapshotStore {
///   PrefsSnapshotStore(this.prefs);
///   final SharedPreferences prefs;
///   static const _key = 'greenflags.snapshot';
///
///   @override
///   Future<String?> read() async => prefs.getString(_key);
///
///   @override
///   Future<void> write(String snapshotJson) =>
///       prefs.setString(_key, snapshotJson);
/// }
/// ```
abstract interface class SnapshotStore {
  Future<String?> read();
  Future<void> write(String snapshotJson);
}
