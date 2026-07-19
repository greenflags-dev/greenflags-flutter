/// GreenFlags — feature flags evaluated at the edge.
///
/// See https://greenflags.dev/docs/ for the API reference.
library;

export 'src/client.dart' show GreenFlagsClient;
export 'src/geo.dart' show geoDistanceMeters;
export 'src/persistence.dart' show SnapshotStore;
export 'src/rollout.dart' show assignVariant, rolloutBucket, WeightedVariant;
export 'src/types.dart'
    show
        Coordinates,
        Flag,
        FlagType,
        FlagVariant,
        Geofence,
        GreenFlagsException,
        Rollout;
