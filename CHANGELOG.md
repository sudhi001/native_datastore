## 1.3.2

* Fixed OIDC authentication in the GitHub Actions release workflow. The publish
  job now explicitly requests a GitHub OIDC token for the `https://pub.dev`
  audience and registers it via `dart pub token add` before publishing, so
  `dart pub publish` no longer falls back to interactive browser auth when
  used with `subosito/flutter-action` (which doesn't auto-configure pub.dev
  credentials the way `dart-lang/setup-dart@v1.3+` does).
* No code changes — package contents are identical to 1.3.1.

## 1.3.1
  - Nothing special just a build automation with Github actions
## 1.3.0

* **New: `SecureDatastore` for encrypted-at-rest storage.** A separate class
  (`SecureDatastore()`) backed by **Keychain Services** on iOS
  (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
  and **AndroidKeyStore-backed AES-256-GCM** over a dedicated DataStore file on
  Android (hardware-backed key where available, fresh 96-bit IV per write).
  Surface: `setString`/`getString`, `setBytes`/`getBytes`, plus
  `remove`/`clear`/`getKeys`/`containsKey`. Values are capped at 1 MiB. Android
  requires API 23 (Marshmallow) or higher; older devices receive a clear
  `UnsupportedOperationException` from the secure API only — the regular
  `NativeDatastore` still works.
* **Breaking — `clear()` now returns `Future<void>`** instead of `Future<bool>`. The previous
  `bool` was always `true` on success; callers awaiting the result need no change beyond removing
  any comparison against the return value.
* **iOS plugin lifetime hardening:** added `detachFromEngine(for:)` + `registrar.publish(...)` so
  the `FlutterBinaryMessenger` releases the Pigeon dispatcher (and the plugin instance it captures)
  when the engine is torn down. Prevents stale instances under hot-restart and `FlutterEngineGroup`.
* **iOS retain-extension fix:** every queue dispatch now uses `[weak self]` via a new internal
  `onQueue<T>` helper. A teardown mid-flight short-circuits with a `plugin-detached` error instead
  of pinning the plugin alive for the duration of the serial-queue backlog.
* **Android cancellation-race fix:** `launchOnAttached` (formerly `launchSafe`) now guarantees the
  Pigeon callback fires exactly once, even when the coroutine scope is cancelled *before* the body
  runs. Previously such a race could leave the Dart-side `Future` hanging in `BinaryMessenger`'s
  pending-replies map until the engine itself was destroyed.
* **Bounded payloads:** `setBytes` and `setMap` now reject values larger than 1 MiB with a clear
  `NativeDatastoreException`. UserDefaults and DataStore are designed for small preferences; use a
  database or the filesystem for bulk binary storage.
* **Internal refactor (no behavior change):**
  - Centralized bucket prefixes (`__list__:`, `__bytes__:`, `__datetime__:`, `__map__:`) as named
    constants per language with a clear sync comment. Eliminates 30+ magic-string sites that
    previously had to be edited in lockstep.
  - Pigeon FFI method names match the Dart facade: `getDateTimeMillis`/`setDateTimeMillis` →
    `getDateTime`/`setDateTime`, `getJsonMap`/`setJsonMap` → `getMap`/`setMap`. The wire encoding
    (millis / JSON) is now an implementation detail of the host.
  - Swift error class renamed to `NativeDatastoreError` to match Kotlin.
  - `getAll()` documentation now explicitly enumerates the runtime-type union of returned values
    (including `Uint8List` for bytes, raw millis-`int` for DateTime, raw JSON-`String` for Map).
  - Renamed for clarity: Swift `prefix` → `keyNamespace`, `queue` → `serialQueue`; Kotlin
    `launchSafe` → `launchOnAttached`.
  - Repeated dartdoc on typed getters/setters consolidated via `{@template}`/`{@macro}`.


## 1.2.0

* **Android resilience on aggressive-kill OEMs (MIUI, ColorOS, OriginOS, HyperOS, etc.):**
  added `ReplaceFileCorruptionHandler` so a half-written prefs file (caused by the OS killing the
  process mid-write) auto-recovers as empty instead of throwing `CorruptionException` on every
  subsequent call.
* **iOS strict numeric typing:** `getBool` / `getInt` / `getDouble` / `getDateTimeMillis` now use
  `CFGetTypeID` and `NSNumber.objCType` to return `null` instead of silently coercing across
  stored types (e.g., `getInt` after `setBool` no longer returns `1`).
* **Reserved-prefix key validation:** user keys starting with the internal sentinels
  `__list__:`, `__bytes__:`, `__datetime__:`, `__map__:` are now rejected with a clear error,
  preventing silent collisions with typed-storage slots.
* **Stronger error wrapping:** `_guard` now also wraps non-`PlatformException` errors (e.g.,
  `FormatException` from corrupt stored JSON, `JsonUnsupportedObjectError` from a non-encodable
  `setMap` value) so every public method honors its documented "throws `NativeDatastoreException`"
  contract.
* **Android detach race:** `onDetachedFromEngine` now cancels the coroutine scope before tearing
  down the Pigeon channel, and `launchSafe` rethrows `CancellationException` so an in-flight
  callback never tries to reply through a dead channel.
* **Note:** the plugin is single-process. If your app runs a secondary process (e.g., a push
  service) that also writes preferences, see the README's "Multi-process limitation" section.

## 1.1.2

* Released on 2026-04-06.

## 1.1.1

* Released on 2026-04-06.

## 1.1.0

* Released on 2026-04-06.

## 1.1.0

* Added 3 new data types:
  - `Uint8List` -- binary data via `getBytes()` / `setBytes()` (Base64 on Android, native Data on iOS).
  - `DateTime` -- date/time via `getDateTime()` / `setDateTime()` (stored as UTC milliseconds since epoch).
  - `Map<String, dynamic>` -- JSON maps via `getMap()` / `setMap()` (stored as JSON string).
* Updated `remove()`, `containsKey()`, `getAll()`, and `getKeys()` to support new types.
* Added "Set All Types" button in example app to demo all 8 data types.
* Updated README with supported types table, error handling guide, null handling examples, and storage details.
* Expanded unit tests from 57 to 78 covering all new types.
* Expanded integration tests to cover all 8 types including null returns.
* **Breaking (iOS):** Changed UserDefaults key prefix from `in.sudhi.native_datastore.` to `native_datastore.` -- removes personal domain from a public library. Existing iOS data stored with the old prefix will not be accessible after this update.

## 1.0.2

* Released on 2026-04-03.

## 1.0.0

* Released on 2026-04-03.

## 0.0.1

* Initial release with support for Android (Jetpack DataStore) and iOS (UserDefaults).
* Type-safe key-value storage: String, int, double, bool, and List<String>.
* Full CRUD operations: get, set, remove, clear, getAll, getKeys, containsKey.
* Built with Pigeon for type-safe platform communication.
