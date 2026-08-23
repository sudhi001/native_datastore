## 1.7.1

Documentation and tooling only — no shipped code changed, and no behaviour
differs from 1.7.0. Released so the corrected performance figures reach pub.dev
rather than sitting only in the repository.

* **Corrected platform-specific performance claims in the 1.7.0 entry.** It
  presented the batch-write speedup as a general result. It is Android-only.
  * Writes on **iOS** go 35.60 ms → 34.00 ms (**1.05x**) — effectively nothing.
    The Android gain (162x) comes from collapsing N whole-file rewrites into
    one, and `UserDefaults` has no such rewrite to amortise. iOS still gets the
    **read** win (8.29 ms → 0.93 ms, 8.9x) from spending one channel hop
    instead of N.
  * "Writes are O(store size)" was likewise Android-only: iOS is flat from 0 to
    500 keys (183 µs → 167 µs).
  * The Base64 finding was Android-only too — iOS already stored `Data`
    natively, and its byte cost was already flat in payload size.
  * Every figure in the 1.7.0 entry now names the platform it was measured on.
* **The watcher-retention test now supports its conclusion.** The 1.6.2 entry
  reported "no leak" from a single 200-cycle attach/detach sample. Re-running
  that same cycle count repeatedly yields +5100 and −8765 bytes/cycle — the
  sample sat inside the noise band and established nothing either way.
  * `example/lib/profile_main.dart` now runs batches of 1000/2000/4000/8000 and
    reports bytes per cycle, which separates the two cases: a leak holds that
    figure roughly constant as cycles grow, while a heap reaching its working
    set lets it fall toward zero.
  * Measured on Android: −1282, 1493, 738, **189** bytes/cycle. It collapses,
    so there is no leak. The original conclusion was correct; the evidence
    offered for it was not.
* **Known gap:** the iOS figures above come from a simulator in debug mode —
  simulators reject `--profile`. They are sound as same-run ratios but are not
  real-device latencies.

## 1.7.0

Performance release, driven by profiling on an Android emulator (API 35, arm64,
profile mode) and an iOS simulator (debug mode — simulators reject `--profile`).
Ratios below are same-run comparisons; absolute microseconds are emulator and
simulator numbers and will differ on real hardware. Gains differ sharply by
platform, so each figure names the platform it was measured on.

* **New: batch API — `getMany`, `setMany`, `removeMany`.** Reading keys one at a
  time costs one channel hop each, and on Android each hop materialises the whole
  store snapshot; writing one at a time rewrites the whole preferences file per
  key. Batching collapses both into a single native transaction.
  * 200 keys, same run, **Android** (emulator, profile mode): reads
    **47.0 ms → 1.04 ms (45x)**, writes **374.3 ms → 2.31 ms (162x)**.
  * **iOS** (simulator, debug mode): reads **8.29 ms → 0.93 ms (8.9x)**, writes
    **35.60 ms → 34.00 ms (1.05x)**. The write win is Android-specific — it comes
    from collapsing N whole-file rewrites into one, and `UserDefaults` has no
    such rewrite to amortise. iOS still gets the read win, from spending one
    channel hop instead of N.
  * `setMany` is all-or-nothing: values are converted before the transaction
    opens, so an unsupported type fails before anything is written.
  * `getMany` omits absent keys rather than mapping them to `null`, so a missing
    key stays distinguishable from a stored one.
  * Values must be `String`, `bool`, `int`, `double` or `List<String>`; use the
    typed setters for `Uint8List`, `DateTime` and `Map`, which carry type
    information the batch path does not.
* **Byte payloads are stored natively on Android instead of Base64.** (iOS already
  stored `Data` natively; measurement confirms its byte cost was already flat in
  payload size, so this finding was Android-only.) Base64
  inflated every blob ~33% on disk and, because the JVM holds strings as UTF-16,
  roughly 2.7x in memory on top of the byte array itself. `setBytes`/`getBytes`
  now use DataStore's `byteArrayPreferencesKey`.
  * Cost is now essentially flat in payload size. Same run, 1 KB → 1 MB:
    `setBytes` **7.6 ms → 506 ms (66x growth)** before, **5.3 ms → 9.4 ms
    (1.8x)** after; `getBytes` **1.2 ms → 117.8 ms (96x)** before, **1.0 ms →
    0.95 ms (flat)** after.
  * Existing Base64 values are still read — the reader branches on the stored
    runtime type — so no migration is required.
  * The multi-process JSON serializer gained a `"ba"` type for byte payloads,
    which it previously dropped silently.
* **iOS: the change-stream diff no longer blocks the main thread.**
  `UserDefaults.didChangeNotification` fires for *any* write in the app, and each
  one ran a full `dictionaryRepresentation()` snapshot and diff synchronously on
  the posting thread — usually main. The diff now runs on a serial background
  queue, so an app writing its own unrelated defaults no longer stalls the main
  thread on this plugin's bookkeeping. A repeated `onListen` without an
  intervening `onCancel` no longer registers a duplicate observer.
  * The per-notification snapshot itself is unchanged. Coalescing bursts into a
    single diff was tried and reverted: it drops intermediate values, so two
    quick writes surfaced only the last.
* **Documented an iOS `watch*` limitation that predates this release.**
  `UserDefaults.didChangeNotification` is coalesced by the system, so several
  writes within one runloop turn post a single notification and an intermediate
  value can be skipped. Android's DataStore emits per write and is unaffected.
  The `watch*` doc comments now say so: treat the stream as "the current value,
  kept fresh", not "every value this key ever held". Found by running the
  on-device integration suite on an iOS simulator for the first time — the
  existing watch test fails on iOS at `main`, independently of this release's
  changes.
* **iOS fix: atomic operations are now atomic across processes.** `incrementInt`,
  `incrementDouble`, `toggleBool` and `compareAndSet*` were guarded only by an
  in-process serial queue. Once `configure(appGroupId:)` points storage at a
  shared suite, an app extension in another process could interleave its own
  read-modify-write and silently lose an update — so the operations this plugin
  advertises as atomic were not. They now take an advisory `flock` on a lock file
  in the App Group container. With no App Group configured there is no second
  process to race, and the lock is skipped entirely.
* **Android: the AndroidKeyStore key handle is cached** instead of being
  re-resolved on every encrypt and decrypt (two keystore-daemon round trips per
  secure operation). A crypto failure drops the cached handle and retries once,
  so a key invalidated out from under the process recovers instead of failing
  every subsequent call.
  * The per-thread `Cipher` instance is also cached, so `Cipher.getInstance`
    no longer walks the JCA provider list on every operation.
  * Honest note: none of the three secure-path changes (key caching, `Cipher`
    caching, dropping Base64 from ciphertext) produced a **measurable**
    improvement. The secure/regular read ratio held at 4.9x-5.3x across four
    clean runs. With those three candidate costs eliminated, the remaining
    overhead is the per-operation round trip to the keystore daemon that
    `cipher.init`/`doFinal` require for a non-extractable key — inherent to the
    security model, and not removable without extracting the key. The changes
    are kept because they delete genuinely redundant work that should matter
    more against a hardware-backed keystore and for large secure payloads, but
    that remains unmeasured.
* **`remove`/`removeMany` no longer scan the whole store.** `Preferences.Key`
  equality is by name alone, so a String-typed probe matches whatever type is
  stored under that name — turning removal into a few O(1) `contains` lookups
  instead of a pass over every key. `removeMany` now counts keys removed rather
  than bucket entries, matching its documented contract.
* **Tests:** 149 unit tests at 100% line coverage, plus on-device integration
  coverage for the batch API and for byte round-trips at 0 B, 1 B, 1 KB and
  256 KB. The integration suite now runs green on **both** an Android emulator
  and an iOS simulator.
* **Tooling:** added `example/lib/profile_main.dart`, a memory and scaling
  harness (`flutter run --profile -t lib/profile_main.dart`). It caught a real
  regression during this work: an early version of the byte change removed the
  legacy key immediately after writing the new one, and because `Preferences.Key`
  equality is by name alone, that deleted the value just written.

## 1.6.2

* **Fix: `cancel()` on a `watch*` subscription now completes immediately.**
  `NativeDatastore._watch` was an `async*` generator parked in
  `await for (… in _changes)`. A generator suspended at an `await` cannot be
  resumed by a cancellation, so `await subscription.cancel()` hung — and the
  underlying platform change observer stayed registered — until the next change
  event happened to arrive. The watcher is now built on an explicit
  `StreamController`, so cancelling tears the observer down at once.
  * A change arriving while the initial read is in flight is no longer dropped:
    the change subscription is opened before the first read.
  * Overlapping notifications can no longer deliver a stale value after a
    fresher one — reads are chained.
  * Errors from the change channel and from a failed re-read now surface as
    stream errors instead of being swallowed, and the watcher closes when the
    change stream closes.
* **pub.dev score: 160/160.** Shortened the `pubspec.yaml` description to the
  60–180 character range pana expects, and formatted every Dart file with the
  Dart 3.7+ formatter.
  * `tool/generate_pigeon.sh` now runs `dart format` on the generated bindings —
    Pigeon still emits the pre-3.7 short style, which would otherwise reintroduce
    the formatting failure on every regeneration.
  * CI (`pr.yml`, `release.yml`) gained a `dart format --set-exit-if-changed`
    step so formatting drift fails the build instead of the pub.dev report, plus
    a `tool/check_coverage.sh` gate that fails the build if line coverage drops
    below 100% and names the offending lines.
* **Android: migrated to built-in Kotlin, without raising the Flutter floor.**
  From AGP 9 the Flutter Gradle Plugin supplies Kotlin itself and a plugin that
  applies the Kotlin Gradle Plugin again fails the build. `android/build.gradle.kts`
  now applies KGP only when the consuming app's AGP major version is below 9, and
  configures `jvmTarget` through the KGP project extension instead of the removed
  `android.kotlinOptions{}` block. pana reports **Built-in Kotlin-ready**.
  * The `flutter` constraint stays at `>=3.3.0` — the conditional form documented
    for plugins that cannot require Flutter 3.44 is used deliberately, so no
    existing consumer is broken.
  * Verified by building the example app on both paths: AGP 8.11.1 (KGP applied)
    and AGP 9.0.1 with `android.builtInKotlin=true` (KGP skipped).
* **Example toolchain:** upgraded to Gradle 9.1.0, AGP 9.0.1 and Kotlin 2.3.20,
  and migrated the example app itself to built-in Kotlin. Flutter 3.47 warns that
  support for the previous versions will be dropped soon. This affects the demo
  app only — it does not change what the published plugin requires, though the
  example now needs a Flutter 3.44+ toolchain to build.
* **Android housekeeping:** the plugin's Gradle module `version` was stale at
  `1.5.3`; it now tracks the package version. Removed the leftover
  `android/settings.gradle`, which declared `rootProject.name = 'android_datastore'`
  and took precedence over the correctly named `android/settings.gradle.kts`.
* **Tests:** unit-test line coverage is now 100% (516/516). Added coverage for
  every typed `watch*` getter, the change-driven re-read and its key filter,
  subscription cancellation, change-stream and read errors, and the
  non-`PlatformException` arm of `SecureDatastore`'s error guard.

## 1.6.1

* Documentation only — no code or API changes.
  * README now links the project [Wiki](https://github.com/sudhi001/native_datastore/wiki)
    (task-focused guides: Getting Started, Secure Storage, Multi-Process Access,
    Troubleshooting) via a badge and a guides callout, while the README remains
    the canonical full API reference.
  * Added `SECURITY.md` describing the private vulnerability-reporting policy
    and the secure-storage threat model.

## 1.6.0

* **New: `SecureDatastore.configure({multiProcess, appGroupId})` for
  cross-process secrets.** Brings the regular store's multi-process support to
  encrypted storage. Opt-in and non-destructive — the default single-process
  secure store is untouched.
  * On Android, `multiProcess: true` opens the encrypted store with a
    `MultiProcessDataStore` in its own file
    (`native_datastore_secure_mp.json`). The AndroidKeyStore key is already
    process-agnostic, so only the file backing changes; existing secrets in the
    default file are not migrated.
  * On iOS, `appGroupId` is used as the Keychain access group
    (`kSecAttrAccessGroup`) so an app and its extensions can share secrets.
    Requires the Keychain Sharing capability in Xcode. (This is a Keychain
    access group string, distinct from the App Group suite used by the regular
    store.)
* **Example:** the Secure tab now has a **Multi-process access** toggle that
  calls `configure(multiProcess:)` live.
* **Tests:** end-to-end integration coverage for the secure store in both
  single-process and multi-process modes (`plugin_integration_test.dart`),
  verified on an iOS simulator and an Android emulator.
* **Benchmarks:** a runnable harness (`integration_test/benchmark_test.dart`)
  measuring regular vs secure set/get latency, with an illustrative results
  table in the README.
* **Docs:** README multi-process section and FAQ updated for `SecureDatastore`;
  new animated encryption diagram and a real secure-storage screen recording;
  a "what it protects" threat-model note.

## 1.5.3

* Documentation only — added a real screen recording of the bundled example app
  to the README ("See it in action"), showing the Regular and Secure stores
  running on a device.

## 1.5.2

* Documentation only — added a fourth animated diagram to the README
  illustrating why the atomic operations prevent lost updates (manual
  read-then-write vs `incrementInt()` under two concurrent writers).

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
