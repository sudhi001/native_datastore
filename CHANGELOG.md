## 1.5.1

* Documentation only — no code or API changes. Expanded the README to help
  developers get started faster: three animated diagrams (architecture, reactive
  `watch`, and "your data survives app restarts"), a quick-reference **cheat
  sheet**, a **"which method should I use?"** decision table, and an **FAQ**.

## 1.5.0

Feature release bringing the plugin to parity with Jetpack DataStore's core
capabilities. All additive — no breaking changes.

* **New: reactive observation (`watch*`).** Observe a key as a `Stream` that
  emits the current value on subscription and a fresh value on every change:
  `watchString`, `watchBool`, `watchInt`, `watchDouble`, `watchStringList`,
  `watchBytes`, `watchDateTime`, `watchMap`, plus `watchChanges()` for the list
  of changed keys. Backed by DataStore's `Flow` on Android and
  `UserDefaults` change notifications on iOS, over a single shared event
  channel.
* **New: atomic read-modify-write.** `incrementInt` / `decrementInt`,
  `incrementDouble`, `toggleBool`, and `compareAndSet{String,Int,Double,Bool}`.
  Each runs as one native transaction (DataStore `edit {}` on Android, the
  serial queue on iOS), so concurrent callers never lose an update.
* **New: `migrateFromSharedPreferences({overwrite})`.** Imports existing
  `shared_preferences` values (scalars and string lists) into this store and
  returns the number of keys imported. Safe to call on every launch.
* **New: `configure({multiProcess, appGroupId})` for multi-process storage.**
  Opt-in and non-destructive — the default single-process store is untouched.
  On Android, `multiProcess: true` opens a `MultiProcessDataStore` (kept in its
  own file). On iOS, `appGroupId` backs storage with an App Group suite so app
  extensions and other processes in the group share data.
* Docs: expanded README with sections for all of the above.

## 1.4.0

* **New: Swift Package Manager support (iOS).** The plugin now ships a
  `Package.swift` alongside the existing CocoaPods `podspec`, so apps that have
  opted into Flutter's Swift Package Manager integration resolve
  `native_datastore` through SPM. **CocoaPods continues to work unchanged** —
  both build systems point at the same sources under
  `ios/native_datastore/Sources/native_datastore/`. No action is required from
  existing CocoaPods users.
* **New: iOS privacy manifest.** Added `PrivacyInfo.xcprivacy` declaring the
  `UserDefaults` required-reason API (`NSPrivacyAccessedAPICategoryUserDefaults`,
  reason `CA92.1`), satisfying Apple's App Store privacy-manifest requirement.
* **Raised iOS minimum deployment target to 13.0** (from 12.0) to match the
  minimum supported by current Flutter stable. iOS 12 is no longer supported by
  the Flutter framework.
* **Android dependency updates:** `androidx.datastore:datastore-preferences`
  `1.1.7 → 1.2.1` and `kotlinx-coroutines-android` `1.7.3 → 1.11.0`.
* **Fixed: Android build failure on current Kotlin toolchains.** The Pigeon-
  generated `Messages.g.kt` declared `package in.sudhi.native_datastore`
  without escaping `in`, a reserved Kotlin keyword, which fails to compile on
  Kotlin 2.x (`Package name must be a '.'-separated identifier list`). The
  generated file is now escaped (`` package `in`.sudhi.native_datastore ``).
  A new `tool/generate_pigeon.sh` wrapper regenerates the bindings and applies
  this escape automatically — use it instead of `dart run pigeon`.
* Tooling: `pigeon` `26 → 27` (bindings regenerated), `meta` `^1.17.0 → ^1.18.0`.
* **License changed from BSD-3-Clause to Apache License 2.0.** Both are permissive;
  Apache-2.0 adds an explicit patent grant and trademark protection, making the package
  safer to adopt for enterprise/corporate projects. Added a `NOTICE` file per Apache
  convention. This is not a restriction — existing usage remains free and unaffected.

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
