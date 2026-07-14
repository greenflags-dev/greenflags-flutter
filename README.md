# greenflags

Official Dart/Flutter SDK for consuming **GreenFlags feature flags** from any Dart environment: Flutter apps (iOS, Android, Web, Desktop), Dart servers, and CLIs.

Pure Dart — no Flutter dependency in the core. Built to minimize billable requests: one network call fetches the whole environment; every read after that is served from memory. Includes optional disk persistence so mobile apps can boot offline with the last known flags.

> **Status:** `0.1.0`, published on pub.dev. Full changelog in [`CHANGELOG.md`](./CHANGELOG.md).

```sh
dart pub add greenflags
# or, in a Flutter project:
flutter pub add greenflags
```

---

## Table of Contents

- [Why it exists](#why-it-exists)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
- [API Reference](#api-reference)
- [Offline Persistence](#offline-persistence)
- [Geofence](#geofence)
- [Types](#types)
- [Error Handling](#error-handling)
- [Billing Model](#billing-model)
- [Handling the `apiToken` in a Mobile App](#handling-the-apitoken-in-a-mobile-app)
- [Compatibility](#compatibility)
- [Development](#development)
- [Versioning](#versioning)
- [Roadmap](#roadmap)

---

## Why it exists

GreenFlags exposes a read endpoint (`GET /v1/flags`) where **every 2xx response counts as a billable read**. A naive SDK that fetches a flag on every widget build, or on every conditional check, can generate thousands of unnecessary requests and burn through your quota for no reason.

`greenflags` solves this with a **snapshot + cache** model:

1. One call (`refresh()`) fetches **every** flag in the `project + environment` tied to your API token.
2. That response is stored in memory (and optionally on disk — see [Offline Persistence](#offline-persistence)).
3. Every read after that (`getFlag`, `isEnabled`, `getAllFlags`, `getSnapshot`) is local — **zero additional requests**.

There is intentionally no method to fetch a single flag over the network — that would break the billing model.

## Features

- ✅ Pure Dart core — works in Flutter (all platforms), Dart servers, and CLIs. Single dependency: `package:http`.
- ✅ Snapshot + in-memory cache — billing-safe by design.
- ✅ Offline startup — optional `SnapshotStore` persists the last snapshot; `hydrate()` restores it before any network call.
- ✅ Opt-in polling (`startPolling`) — you decide if and how often it refreshes.
- ✅ `Stream` of evaluated snapshots — idiomatic Dart for reactive UIs.
- ✅ Fail-open — if the network fails, your app keeps working with the last good snapshot (or the `defaultValue` you set).
- ✅ Client-side geofence evaluation — the end-user's location never leaves the device.
- ✅ Injectable `http.Client` — trivial to mock in tests.

## Requirements

- **Dart SDK 3.4+** (Flutter 3.22+ ships it).
- A GreenFlags **API token**, generated from the [dashboard](https://app.greenflags.dev) for a specific `project + environment`. The token determines which flags the SDK sees — there's no separate `project`/`environment` to pass. See the [API docs](https://greenflags.dev/docs/) for the full contract.

## Installation

**Normal usage — from pub.dev:**
```sh
dart pub add greenflags
```

**For local SDK development** (testing changes before publishing), use a path dependency in the consumer's `pubspec.yaml`:
```yaml
dependencies:
  greenflags:
    path: ../path/to/sdks/flutter
```

## Quick Start

```dart
import 'package:greenflags/greenflags.dart';

final flags = GreenFlagsClient(
  url: 'https://app.greenflags.dev',
  apiToken: 'gf_your_token_here',
);

await flags.refresh(); // 1 billable request — fetches the whole environment

if (flags.isEnabled('new-checkout')) {
  // ship it
}
```

## Usage Guide

```dart
import 'package:greenflags/greenflags.dart';

final flags = GreenFlagsClient(
  url: 'https://app.greenflags.dev',
  apiToken: 'gf_your_token_here',
);

// 1. Fetch the initial snapshot (required before reading real flag values)
await flags.refresh();

// 2. Read flags — always from memory, never hits the network
final enabled = flags.isEnabled('my-feature');                    // boolean sugar
final theme   = flags.getFlag('theme', defaultValue: 'light');    // string
final limit   = flags.getFlag('rate-limit', defaultValue: 100);   // number
final config  = flags.getFlag('config', defaultValue: <String, Object?>{}); // json

// 3. List everything available
final all = flags.getAllFlags();          // List<Flag>
final snapshot = flags.getSnapshot();     // Map<String, Flag>

// 4. React to updates (fires on every successful refresh())
final sub = flags.snapshotStream.listen((snapshot) {
  // rebuild whatever depends on flags
});

// 5. Opt-in polling — without this, the SDK NEVER fetches data on its own
flags.startPolling(const Duration(seconds: 60)); // every tick = 1 billable request

// 6. Stop polling (the in-memory snapshot is preserved)
flags.stopPolling();

// 7. Clean up when done (closes the stream and the HTTP client)
await sub.cancel();
flags.dispose();
```

### Ground rules

- `getFlag` / `isEnabled` **never throw** — if the flag doesn't exist, or you haven't called `refresh()` yet, `getFlag` returns your `defaultValue` and `isEnabled` returns `false`.
- `refresh()` **can throw** (`GreenFlagsException`: network error, invalid token, quota exceeded) — wrap it in `try/catch` if you want to log failures. The previous snapshot is kept either way.
- Don't call `refresh()` on every build or every flag check — call it once at app startup, and use `startPolling` only if you need near-live data.
- In Flutter, call `dispose()` when the owning widget/state is disposed (or keep one app-wide client alive for the whole session).

## API Reference

### `GreenFlagsClient(...)`

```dart
GreenFlagsClient({
  required String url,        // API base URL, trailing slash optional (normalized either way)
  required String apiToken,   // token for the environment you're consuming
  Coordinates? coordinates,   // optional — end-user location, enables geofence evaluation
  SnapshotStore? store,       // optional — disk persistence for offline startup
  http.Client? httpClient,    // optional — inject/mock the HTTP client
})
```

### Methods

| Member | Signature | Description |
|---|---|---|
| `refresh` | `Future<void> refresh()` | 1 request to `GET /v1/flags`. Replaces the snapshot, persists it (if a `store` was provided) and emits on `snapshotStream`. Throws `GreenFlagsException` on network/API error. |
| `hydrate` | `Future<void> hydrate()` | Restores the last persisted snapshot from the `store` — instant, no network. Silently no-ops without a store, an empty store, or a corrupt cache. |
| `getSnapshot` | `Map<String, Flag> getSnapshot()` | Copy of the current snapshot, indexed by `key`, with geofence evaluation applied per flag (see [Geofence](#geofence)). |
| `getAllFlags` | `List<Flag> getAllFlags()` | Every flag in the current snapshot, geofence-evaluated. |
| `getFlag` | `Object? getFlag(String key, {Object? defaultValue})` | Reads a flag's evaluated value. Fail-open: returns `defaultValue` if missing. |
| `isEnabled` | `bool isEnabled(String key)` | `true` only when the flag exists and currently evaluates to `true`. Sugar for boolean flags. |
| `snapshotStream` | `Stream<Map<String, Flag>>` | Broadcast stream. Emits the evaluated snapshot after every successful `refresh()`/`hydrate()`, and when `setCoordinates` changes the evaluation. |
| `startPolling` | `void startPolling(Duration interval)` | Automatic `refresh()` every `interval`. Opt-in — no default. Fail-open (a failed tick doesn't break the next one). |
| `stopPolling` | `void stopPolling()` | Stops polling. The in-memory snapshot is preserved. |
| `setCoordinates` | `void setCoordinates(Coordinates? coords)` | Sets or clears the end-user's coordinates used for geofence evaluation, without a network request. Re-emits on `snapshotStream` immediately. |
| `dispose` | `void dispose()` | Stops polling, closes the stream, and closes the HTTP client (when owned by the SDK). The client must not be used afterwards. |

## Offline Persistence

Mobile apps start offline all the time. Provide a `SnapshotStore` (two methods: `read`/`write` a JSON string) and the client persists every successful snapshot; `hydrate()` restores it instantly on the next launch:

```dart
import 'package:shared_preferences/shared_preferences.dart';

class PrefsSnapshotStore implements SnapshotStore {
  PrefsSnapshotStore(this.prefs);
  final SharedPreferences prefs;
  static const _key = 'greenflags.snapshot';

  @override
  Future<String?> read() async => prefs.getString(_key);

  @override
  Future<void> write(String snapshotJson) => prefs.setString(_key, snapshotJson);
}

final flags = GreenFlagsClient(
  url: 'https://app.greenflags.dev',
  apiToken: 'gf_...',
  store: PrefsSnapshotStore(await SharedPreferences.getInstance()),
);

await flags.hydrate();        // instant: last known flags, from disk
unawaited(flags.refresh());   // fresh flags in the background
```

Details worth knowing:

- The **raw** (un-evaluated) flags are persisted — geofences re-evaluate against the *current* location after a restart, not the location from last week.
- Persistence is best-effort: a failing store never breaks `refresh()`, and a corrupt cache is ignored (the next `refresh()` overwrites it).
- `hydrate()` does not count as a billable read — it never touches the network.

## Geofence

Some flags can carry an optional geofence — a `{latitude, longitude, radiusMeters}` target radius configured in the dashboard. When the SDK has end-user coordinates (via the constructor or `setCoordinates`), it evaluates each geofenced flag **locally** — coordinates are never sent to the server:

- **Inside the radius** (`distance <= radiusMeters`, on-edge counts as inside): the flag's normal value is returned.
- **Outside the radius**: the flag returns its off value — `false` for `boolean` flags, `null` for `string` / `number` / `json` flags.
- **No coordinates supplied, or the flag has no geofence**: the flag's normal value is returned, unaffected.

> **Fail-open, by design:** if you never pass coordinates, geofenced flags behave exactly as non-geofenced ones — the geofence is silently ignored, not enforced. End-user location never leaves the device, but that also means a geofence is not a security boundary.

```dart
final flags = GreenFlagsClient(
  url: 'https://app.greenflags.dev',
  apiToken: 'gf_...',
  coordinates: const Coordinates(latitude: 19.4326, longitude: -99.1332),
);

await flags.refresh();
flags.isEnabled('store-promo'); // evaluated against the geofence, if any

// Coordinates can change at runtime without a refresh:
flags.setCoordinates(const Coordinates(latitude: 25.6866, longitude: -100.3161));
flags.setCoordinates(null); // back to "ignore geofence" for every flag
```

### Distance to a geofence

Need to *show* how far the end-user is from a geofence (e.g. "230 m away")? Use `geoDistanceMeters` — the exact great-circle (haversine) calculation the SDK runs internally, exported so you don't have to reimplement it:

```dart
import 'package:greenflags/greenflags.dart';

final meters = geoDistanceMeters(
  const Coordinates(latitude: 19.4326, longitude: -99.1332), // end-user
  const Coordinates(latitude: 19.4300, longitude: -99.1400), // geofence center
);
```

Formatting (units, decimals, locale) is left to your app.

## Types

```dart
enum FlagType { boolean, string, number, json }

class Coordinates {
  final double latitude;
  final double longitude;
}

class Flag {
  final String key;
  final FlagType type;
  final Object? value;      // bool | String | num | Map<String, Object?> | null
  final Geofence? geofence; // latitude, longitude, radiusMeters
}

class GreenFlagsException implements Exception {
  final String code;    // API error code, or NETWORK_ERROR / PARSE_ERROR
  final String message;
  final int status;     // HTTP status; 0 for network failures
}
```

These types mirror the backend contract (`GET /v1/flags`) exactly — no extra transformation happens on the client side. `value` is `null` when a non-boolean geofenced flag evaluates outside its radius.

## Error Handling

`refresh()` throws a `GreenFlagsException` on any network failure or error response from the backend:

```dart
try {
  await flags.refresh();
} on GreenFlagsException catch (err) {
  print('${err.code} ${err.status}: ${err.message}');
}
```

Codes that `GET /v1/flags` can actually return (the only ones reachable by this SDK, since it never calls the per-key endpoint):

| `code` | `status` | Cause |
|---|---|---|
| `INVALID_TOKEN` | 401 | Token missing, invalid, or revoked |
| `QUOTA_EXCEEDED` | 429 | Monthly read quota exhausted |
| `BILLING_NO_SUBSCRIPTION` | 429 | The workspace has no active subscription |
| `BILLING_CANCELED` | 429 | Subscription canceled |
| `BILLING_PAST_DUE` | 429 | Payment past due |
| `BILLING_TRIAL_EXPIRED` | 429 | Trial expired |
| `BILLING_LIMIT_REACHED` | 429 | Billing limit reached |
| `NETWORK_ERROR` | 0 | The request failed before a response was received (no connection, DNS, etc.) |
| `PARSE_ERROR` | response status | Body wasn't valid JSON, or was missing `data.flags` |
| `REQUEST_ERROR` | response status | Non-2xx response with no parseable error code in the envelope |

`getFlag()`, `isEnabled()`, `getAllFlags()`, `getSnapshot()` and `hydrate()` **never** throw any of these — they're always local reads.

## Billing Model

Every call to `refresh()` (manual or triggered by `startPolling`) is **exactly one HTTP request** to `GET /v1/flags`, and every 2xx response counts as one billable read on your account. All flag reads are 100% in memory — **zero requests**, no matter how many times you call them. `hydrate()` reads from disk — also zero requests.

Recommendation for mobile: `hydrate()` + one `refresh()` at app startup, then `startPolling` with a relaxed interval (60s or more) only if you need near-live flags while the app is in the foreground.

## Handling the `apiToken` in a Mobile App

A token shipped inside a mobile app **can be extracted from the binary** — assume a motivated user can read it. GreenFlags tokens are read-only and scoped to a single environment, so the blast radius is limited, but follow these rules:

- **Create a dedicated token for your mobile app** (dashboard → project → environment → API Tokens) — never reuse your backend's token.
- **Set a monthly quota on that token.** If it ever leaks, abuse is capped and you revoke it with one click (revocation is instant).
- **Don't hardcode the token in source.** Inject it at build time with `--dart-define`:

```sh
flutter build apk --dart-define=GREENFLAGS_TOKEN=gf_...
```

```dart
const token = String.fromEnvironment('GREENFLAGS_TOKEN');
```

- Flag **values** are visible in your UI anyway — treat flags as remote configuration, not as a place to hide secrets. Never put API keys or sensitive data inside a flag's value.

## Compatibility

| Environment | Supported | Notes |
|---|---|---|
| Flutter — Android / iOS | ✅ | |
| Flutter — Web | ✅ | `package:http` uses `fetch` under the hood |
| Flutter — macOS / Windows / Linux | ✅ | |
| Dart server / CLI (`dart run`) | ✅ | The core has no Flutter dependency |
| Dart SDK < 3.4 | ❌ | Uses Dart 3.4 language features |

## Development

```sh
cd sdks/flutter
dart pub get
dart analyze          # zero issues expected
dart test             # 16 tests, mocked HTTP — no real network needed
dart pub publish --dry-run
```

Tests use `package:http/testing.dart` (`MockClient`) — they cover envelope parsing, error mapping, geofence evaluation, offline hydrate/persist, fail-open behavior, and polling.

## Versioning

Semver, while in `0.x`: `MINOR` can include API changes (no stability guarantee yet), `PATCH` are fixes with no contract changes. Version-by-version detail in [`CHANGELOG.md`](./CHANGELOG.md).

## Roadmap

- `greenflags_flutter` — widget bindings (`FlagBuilder`, `provider`/`riverpod` helpers) built on this core.
- Ready-made `SnapshotStore` implementations (`shared_preferences`, `hive`).

## Related

- [API reference](https://greenflags.dev/docs/)
- [`@greenflags/client`](https://www.npmjs.com/package/@greenflags/client) — JavaScript/TypeScript SDK
- [`@greenflags/mcp`](https://www.npmjs.com/package/@greenflags/mcp) — MCP server for AI agents
