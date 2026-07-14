# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/). Versioning: [SemVer](https://semver.org/) (while in `0.x`, a MINOR release may include breaking changes; strict semver applies from `1.0.0` onward).

## [0.2.0] - 2026-07-11

### Added
- `geoDistanceMeters(a, b)` — exported from `package:greenflags/greenflags.dart`. Returns the great-circle distance in meters between two `Coordinates`, the same haversine calculation the SDK runs internally for geofence evaluation. Lets apps show the live distance to a geofence without reimplementing it. No behavior change to flag evaluation.

## [0.1.0] - 2026-07-10

### Added
- Initial release, mirroring `@greenflags/client` 0.2.x semantics in pure Dart.
- `GreenFlagsClient` with `refresh`, `getSnapshot`, `getAllFlags`, `getFlag` (with `defaultValue`), `isEnabled`, `snapshotStream`, `startPolling`/`stopPolling`, `setCoordinates`, `dispose`.
- Client-side geofence evaluation (haversine): outside the radius a `boolean` flag evaluates to `false`, other types to `null`. Every read path goes through evaluation — the raw snapshot is never exposed.
- Offline persistence via the `SnapshotStore` interface: `hydrate()` restores the last snapshot on startup; `refresh()` writes through. Raw flags are persisted so geofences re-evaluate against the current location after restart.
- Typed `GreenFlagsException` with API error `code`, `message` and HTTP `status` (`NETWORK_ERROR`/`PARSE_ERROR` client-side).
- Auth via `Authorization: Bearer` header against `GET /v1/flags`.
