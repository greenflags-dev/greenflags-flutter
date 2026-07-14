/// GreenFlags — feature flags evaluated at the edge.
///
/// See https://greenflags.dev/docs/ for the API reference.
library;

export 'src/client.dart' show GreenFlagsClient;
export 'src/geo.dart' show geoDistanceMeters;
export 'src/persistence.dart' show SnapshotStore;
export 'src/types.dart'
    show Coordinates, Flag, FlagType, Geofence, GreenFlagsException;
