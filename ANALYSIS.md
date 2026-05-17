# Code-Quality Audit — native_datastore

_Generated: 2026-05-17 · Languages: Dart, Swift, Kotlin · Files scanned: 16 hand-written sources (8 Dart, 5 Swift, 3 Kotlin); ~3,816 total LOC including pigeon-generated stubs_

## Executive Summary

`native_datastore` is a well-structured Flutter plugin with idiomatic layering, a clean Pigeon FFI contract, and strict lint configuration that passes cleanly. Risk surface is small and there are no Critical findings. The dominant systemic issue is **a triple-duplicated set of namespace prefix strings (`__list__:` / `__bytes__:` / `__datetime__:` / `__map__:`) across the Dart facade, Swift host, and Kotlin host** — every new typed value would require shotgun surgery across 6+ files in lockstep, which is the single highest-leverage refactor available. Secondary risks are an **iOS plugin instance lifetime gap** (no `detachFromEngineForRegistrar` counterpart to Android's `onDetachedFromEngine`), and a **public-API naming/return-type mismatch** between the Dart facade (`getDateTime`/`getMap`) and the Pigeon FFI (`getDateTimeMillis`/`getJsonMap`) that leaks encoding details across abstraction layers. Overall posture: production-grade for a v1.x plugin, with a clear "next sprint" refactor list rather than a fix-it-now list.

## Severity Tally
| Severity | Count |
|----------|-------|
| Critical | 0     |
| High     | 7     |
| Medium   | 18    |
| Low      | 24    |

## ISO/IEC 5055 Weakness Mapping

### Reliability
- **High** Callback can fire after scope cancellation race — Dart-side `Future` is leaked in `BinaryMessenger`'s pending-replies map until engine destruction — `android/src/main/kotlin/in/sudhi/native_datastore/NativeDatastorePlugin.kt:67-89`
- **High** No `detachFromEngineForRegistrar(_:)` on iOS — Pigeon handler closure keeps a strong reference to a stale plugin instance across engine teardown in `FlutterEngineGroup`/hot-restart scenarios — `ios/Classes/NativeDatastorePlugin.swift:15-18`
- **Medium** `clear()` always returns `Future<bool>` of `true` — the boolean is dead information that suggests false-positive failure modes — `lib/src/native_datastore_plugin.dart:242`, `android/.../NativeDatastorePlugin.kt:198`, `ios/Classes/NativeDatastorePlugin.swift:182`

### Security
- No findings. The plugin does not handle network input, untrusted deserialization, or credential material. Base64/JSON encoding/decoding paths use platform-native, well-vetted implementations.

### Performance Efficiency
- **Medium** `defaults.dictionaryRepresentation()` materialises the entire UserDefaults registry (incl. system-domain keys: locale, accessibility, AppleLanguages) on every `getAll()`/`getKeys()`/`clear()` — `ios/Classes/NativeDatastorePlugin.swift:184-189, 198-220, 226-243`
- **Medium** Android DataStore in-memory snapshot mirrors disk size with no eviction; `setBytes`/`setMap` invite unbounded growth — `android/.../NativeDatastorePlugin.kt:31-36, 207-264`
- **Medium** No size cap on `setBytes`/`setMap` — caller-controlled blob payloads are not rejected — `lib/src/native_datastore_plugin.dart:290, 351`

### Maintainability
- **High** Namespace prefix strings duplicated across three files with no shared source of truth — `lib/src/native_datastore_plugin.dart:66-71`, `ios/Classes/NativeDatastorePlugin.swift:7-10`, `android/.../NativeDatastorePlugin.kt:124,172,184-186,213-228,245-248,259-261`
- **High** OCP shotgun surgery — adding a new value type touches 6 places in lockstep (Pigeon spec, Dart facade, both native hosts, tests, docs) — plugin-wide
- **High** Android `remove`/`containsKey`/`getAll`/`getKeys` hand-roll the same prefix list inline at 8 sites — `android/.../NativeDatastorePlugin.kt:183-187,213-228,245-248,258-262`
- **High** `getAll()` returns `Future<Map<String, Object>>` with a heterogeneous, undocumented union of runtime types (string, int, double, bool, List<String>, Uint8List, millis-as-int, JSON-string) — `lib/src/native_datastore_plugin.dart:253`
- **High** Public `remove()` returns `Future<bool>` of "existed and was removed"; Dart convention (`Map.remove`) is to return the previous value — `lib/src/native_datastore_plugin.dart:232`
- **Medium** Dart facade and Pigeon FFI use two vocabularies for the same concept (`getDateTime` vs `getDateTimeMillis`, `getMap` vs `getJsonMap`) — `lib/src/native_datastore_plugin.dart:302,319,334,351` ↔ `pigeons/messages.dart:74,77,80,83`
- **Medium** Error class name asymmetry: `NativeDatastoreError` (Kotlin) vs `DatastoreError` (Swift) — `pigeons/messages.dart:12,16`
- **Medium** ISP — `DatastoreApi` is a single fat 22-method interface covering 5 orthogonal concerns — `pigeons/messages.dart:21-84`
- **Medium** DIP — Kotlin singleton DataStore bound to hard-coded filename `"native_datastore_prefs"` and iOS hard-coded `UserDefaults.standard`; no constructor injection for tests — `android/.../NativeDatastorePlugin.kt:31-36`, `ios/Classes/NativeDatastorePlugin.swift:5`
- **Medium** SRP — both host classes mix lifecycle + concurrency + namespacing + serialization concerns — `android/.../NativeDatastorePlugin.kt:38`, `ios/Classes/NativeDatastorePlugin.swift:3`
- **Medium** 19 near-identical "throws on empty key" tests + 22 near-identical "wraps PlatformException" tests; table-driven loop would cut ~400 lines — `test/native_datastore_test.dart:113-238, 446-627`
- **Medium** 21-place `queue.async { [self] in … }` boilerplate on iOS; the Kotlin side already has a `launchSafe` helper — `ios/Classes/NativeDatastorePlugin.swift:43,64,78,…,312`
- **Medium** Dartdoc verbatim copy-paste across 19 typed getter/setter pairs — a `{@template}/{@macro}` would halve doc volume — `lib/src/native_datastore_plugin.dart:113-271`

## Detailed Findings by Category

### 1. Structure & Boilerplate

**Folder layout** is idiomatic for a Flutter plugin (`lib/` + `lib/src/`, `pigeons/`, `ios/Classes/`, `android/src/main/kotlin/in/sudhi/native_datastore/`). `dart analyze` is clean against a strict `analysis_options.yaml`. Pigeon-generated files live alongside hand-written ones and are correctly excluded from lints.

**High** — Reserved-prefix list duplicated across three sources of truth:
- `lib/src/native_datastore_plugin.dart:66-71` (Dart `_reservedPrefixes`)
- `ios/Classes/NativeDatastorePlugin.swift:7-10` (named constants `listPrefix`/`bytesPrefix`/`dateTimePrefix`/`mapPrefix`)
- `android/.../NativeDatastorePlugin.kt:124,172,184-186,213-228,245-248,259-262,271,281,291,298,308,315` (literal magic strings, repeated 12+ times)

**High** — Android `remove()`, `containsKey()`, `getAll()`, `getKeys()` re-implement the same "prefix list iteration" inline:
- `android/.../NativeDatastorePlugin.kt:183-187` (remove)
- `android/.../NativeDatastorePlugin.kt:213-228` (getAll switch)
- `android/.../NativeDatastorePlugin.kt:245-248` (getKeys)
- `android/.../NativeDatastorePlugin.kt:258-262` (containsKey)

Mirror sites on iOS at `ios/Classes/NativeDatastorePlugin.swift:161-180, 196-243, 245-253`.

**Medium** — iOS Swift host has 21 distinct `queue.async { [self] in … completion(.success(...)) }` blocks (`ios/Classes/NativeDatastorePlugin.swift:43,64,78,97,116,125,132,139,146,153,162,183,197,226,246,259,269,278,296,305,312`). The Kotlin side has the `launchSafe` helper (`android/.../NativeDatastorePlugin.kt:67-89`); the Swift side never got the equivalent.

**Medium** — Dartdoc stanzas ("Returns null… Throws if key is empty…") are near-verbatim across 19 methods at `lib/src/native_datastore_plugin.dart:113-271`; a `{@template}/{@macro}` would halve the volume.

**Medium** — `test/native_datastore_test.dart` (736 lines): 19 identical empty-key tests (lines 113–238) and 22 identical PlatformException-wrap tests (lines 446–627). Table-driven loops would reduce ~400 lines to ~50 and auto-cover new API methods.

**Low** — Version-string drift: `pubspec.yaml:6` is `1.2.0`; `ios/native_datastore.podspec:3` is `'0.0.1'`; `android/build.gradle.kts:2` is `"1.0.0"`. Cosmetic.

**Low** — `example/ios/RunnerTests/RunnerTests.swift` is the empty `flutter create` scaffold. Either delete or fill in.

**Low** — `release.sh` is checked in at repo root; convention would put it under `tool/`.

**Low** — Two near-identical library descriptions at `lib/native_datastore.dart:5` and `lib/src/native_datastore_plugin.dart:38`.

### 2. SOLID & God Classes

No class crosses the "god class" bar (max ~22 public methods, ≤2 instance fields, ≤4 concerns). All cyclomatic complexity is well below 15. Hotspots cluster around the duplicated prefix-branch pattern (`getAll`/`remove`/`containsKey`/`getKeys` on both native sides at CC ~6); refactoring the prefix table drops each to CC ~2.

**High — OCP shotgun surgery.** Adding a new value type (`setEnum`/`setBigInt`/etc.) requires lockstep edits to:
1. `pigeons/messages.dart` (new getter/setter pair)
2. `lib/src/native_datastore_plugin.dart:66-71` + new typed facade method
3. `android/.../NativeDatastorePlugin.kt`: new override + edit `remove` (183-187), `containsKey` (258-262), `getAll` (211-234), `getKeys` (243-250)
4. `ios/Classes/NativeDatastorePlugin.swift`: same four sites at 161-180, 196-223, 225-243, 245-254
5. Tests
6. Docs

**High — Content coupling.** The four prefix strings (`__list__:`, `__bytes__:`, `__datetime__:`, `__map__:`) appear in three independent source files at 30+ sites with no shared declaration. A silent rename desynchronizes the three sides.

**High — Feature envy.** Type-encoding split-brain: Dart `setDateTime` at `lib/src/native_datastore_plugin.dart:319-325` does the `toUtc().millisecondsSinceEpoch` conversion while the native side owns the prefix. Same for `setMap` (Dart does `jsonEncode` at 351-357; native stores at `__map__:`). Neither side fully owns the typed value.

**Medium — SRP (Kotlin host).** `NativeDatastorePlugin.kt:38` mixes (a) Flutter lifecycle, (b) coroutine-scope management (`launchSafe` 67-89), (c) prefix namespacing (literals at 12+ sites), (d) Base64/JSON serialization (`setBytes` 277-284, `getBytes` 268-275, `setStringList` 168-175, `getStringList` 121-132).

**Medium — SRP (Swift host).** `NativeDatastorePlugin.swift:3` mixes lifecycle, serial-queue concurrency, prefix namespacing (20-38), and NSNumber/CFBoolean type discrimination (52-61). The probe helpers `isStoredAsBool`/`isFloatingPointNumber` should extract to a `UserDefaultsTypeProbe`.

**Medium — ISP.** `pigeons/messages.dart:21-84` is a 22-method fat interface covering scalar I/O (8), list I/O (2), introspection (5), bytes (2), datetime (2), map (2), trailing typed (3). Alternative backends (in-memory, secure-storage, web) cannot implement subsets.

**Medium — DIP, Android.** Top-level `Context.dataStore` extension property is bound to hard-coded filename `"native_datastore_prefs"` at `android/.../NativeDatastorePlugin.kt:31-36`. No injection seam for tests or multi-store scenarios.

**Medium — DIP, iOS.** `private let defaults = UserDefaults.standard` at `ios/Classes/NativeDatastorePlugin.swift:5`. No `init(defaults:)` seam.

**Medium — Inappropriate intimacy.** `android/.../NativeDatastorePlugin.kt:189-190` does `@Suppress("UNCHECKED_CAST") prefs.remove(k as Preferences.Key<Any>)` — reaching past the Preferences type system to treat keys as untyped data.

**Low — Dart facade DIP.** `NativeDatastore()` constructor news up a concrete `DatastoreApi()`, but the `withApi` named constructor at `lib/src/native_datastore_plugin.dart:59` provides a clean test seam.

**Low — No LSP violations.** No inheritance hierarchy beyond Pigeon-generated abstract classes, each fully implemented (no `NotImplementedError`/`fatalError` stubs).

### 3. Naming & Semantic Clarity

The type-keyed `getX`/`setX` pair convention is followed cleanly across all five surfaces (Dart facade, Pigeon contract, Swift host, Kotlin host, tests). No `put`/`store`/`save`/`write` drift. The blemishes are all on the FFI boundary and on a few public-API return-type semantics.

**High** — `lib/src/native_datastore_plugin.dart:253` `getAll()` returns `Future<Map<String, Object>>` with an undocumented runtime-type union (`String`/`int`/`double`/`bool`/`List<String>`/`Uint8List`/millis-`int`/JSON-`String`). Callers cannot statically distinguish a millis-int from a real int. Either rename to `getAllRaw`/`getAllEntries`, narrow the type, or surface a `Map<String, NativeValue>` sealed class.

**High** — `lib/src/native_datastore_plugin.dart:232` `remove(String key)` returns `Future<bool>` of "existed and was removed". Idiomatic Dart (`Map.remove`) returns the previous value. Rename `removeIfPresent` or change return semantic.

**Medium** — `lib/src/native_datastore_plugin.dart:242` `clear()` returns `Future<bool>` that is always `true` (see `android/.../NativeDatastorePlugin.kt:198`, `ios/Classes/NativeDatastorePlugin.swift:182`). Change to `Future<void>`.

**Medium — Dart facade ↔ Pigeon FFI vocabulary mismatch:**

| Dart facade | Pigeon FFI |
|---|---|
| `getDateTime`/`setDateTime` (302, 319) | `getDateTimeMillis`/`setDateTimeMillis` (`pigeons/messages.dart:74,77`) |
| `getMap`/`setMap` (334, 351) | `getJsonMap`/`setJsonMap` (`pigeons/messages.dart:80,83`) |
| `getBytes`/`setBytes` (279, 290) | `getBytes`/`setBytes` (consistent) |

Pick one vocabulary. The encoding (millis/JSON) is a host implementation detail and should not leak into the FFI names.

**Medium** — Error class asymmetry: `pigeons/messages.dart:12` `kotlinOptions.errorClassName: 'NativeDatastoreError'` vs `pigeons/messages.dart:16` `swiftOptions.errorClassName: 'DatastoreError'`.

**Medium** — `ios/Classes/NativeDatastorePlugin.swift:6` `private let prefix = "native_datastore."` is iOS-only (Android doesn't apply an analogous prefix because the DataStore file already namespaces). Rename to `keyNamespace`/`userDefaultsNamespace` so the identifier doesn't imply a cross-platform concept.

**Medium** — Bucket-prefix vocabulary split: Swift has named constants (`listPrefix`/`bytesPrefix`/…), Kotlin and Dart inline the literals.

**Low** — `pigeons/messages.dart:21` `DatastoreApi` vs Dart `NativeDatastore` (line 49 of plugin) vs `NativeDatastorePlugin` (both hosts). Consider `NativeDatastoreApi` for symmetry.

**Low** — `ios/Classes/NativeDatastorePlugin.swift:13` `queue` lacks qualifier — suggest `serialQueue`/`ioQueue`.

**Low** — `ios/Classes/NativeDatastorePlugin.swift:52` `isStoredAsBool` reads like a durable-storage probe but inspects an in-memory `Any` post-fetch. Rename `isBooleanNSNumber`/`isCFBoolean`.

**Low** — `ios/Classes/NativeDatastorePlugin.swift:163-167` local vars `pKey`/`pListKey`/`pBytesKey`/`pDateTimeKey`/`pMapKey` use Hungarian-ish `p` prefix; the `prefixedKey()` accessor already encodes that.

**Low** — `android/.../NativeDatastorePlugin.kt:67` `launchSafe` — "safe" is vague; consider `launchOnAttached`/`withAttachedScope`.

**Low** — Single-letter local `k` at `android/.../NativeDatastorePlugin.kt:188-189` (in a non-tight loop); rename `prefKey`.

### 4. Memory Safety

No Critical findings. No guaranteed leaks or use-after-free on the common path. The two High items are lifecycle gaps that surface under hot-restart / `FlutterEngineGroup` / `FlutterFragment` add-remove cycles.

**High** — `ios/Classes/NativeDatastorePlugin.swift:15-18` iOS plugin instance has **no teardown counterpart** to Android's `onDetachedFromEngine`. The `FlutterBinaryMessenger` retains the Pigeon dispatcher closure (which captures `instance`) for the lifetime of the engine. Fix: implement `detachFromEngineForRegistrar(_:)` and call `DatastoreApiSetup.setUp(binaryMessenger: …, api: nil)` to drop the handler. Also call `registrar.publish(instance)` in `register(with:)` so the framework wires the detach callback.

**High** — `android/.../NativeDatastorePlugin.kt:67-89` `launchSafe` has a narrow race window between the null-check (line 73) and `currentScope.launch` (line 79). If `onDetachedFromEngine` cancels the scope between these, the coroutine is created in cancelled state and the block never runs; the Dart-side `Completer` in `BinaryMessenger.pending-replies` is leaked until engine destruction. Fix: wrap the launched job with `invokeOnCompletion { cause -> if (cause is CancellationException) callback(Result.failure(IllegalStateException("plugin detached"))) }`.

**High (informational)** — `android/.../NativeDatastorePlugin.kt:31-36` DataStore singleton is anchored to `binding.applicationContext` (line 47) — safe today. Add a maintenance comment forbidding switching the context to anything Activity-scoped.

**Medium** — `ios/Classes/NativeDatastorePlugin.swift` 21 sites use `queue.async { [self] in … }`. `[self]` is a strong capture, not weak. While there's no traditional retain cycle (queue is owned by self), every in-flight block extends `self`'s lifetime during teardown. Switch to `[weak self] in guard let self else { completion(.failure(...)); return }`.

**Medium** — `ios/Classes/NativeDatastorePlugin.swift:184-189, 198-220, 226-243` `defaults.dictionaryRepresentation()` materialises the entire UserDefaults registration domain (incl. system-domain locale/accessibility/AppleLanguages keys — hundreds of entries) on every `getAll`/`getKeys`/`clear`. Maintain an internal `Set<String>` index keyed under `__index__` to avoid the full scan.

**Medium** — `android/.../NativeDatastorePlugin.kt:31-36, 93-132, 207-264` DataStore keeps an in-memory snapshot mirroring disk size, no LRU. `setBytes`/`setMap` callers can grow it unboundedly.

**Medium** — Unbounded growth at all `setBytes`/`setMap` sites: `lib/src/native_datastore_plugin.dart:290, 351`, `android/.../NativeDatastorePlugin.kt:277-284`, `ios/Classes/NativeDatastorePlugin.swift:268-273`. No size cap, no key-count cap. Recommend documenting "small preferences, not bulk binary" and rejecting payloads >1 MB.

**Medium** — `android/.../NativeDatastorePlugin.kt:179-203, 240-264` `remove`/`getAll`/`getKeys`/`containsKey` each iterate `prefs.asMap()` and build new collections per call. Not a leak (short-lived) but pairs poorly with unbounded growth.

**Low** — Dart side has no streams/controllers/timers, no `dispose()` surface needed. If a future `watch(key)` stream API is added it MUST cascade cancellation to native (`flow.cancel()` / KVO removal).

**Low** — `lib/src/native_datastore_plugin.dart:1` `import 'dart:async'` is unused.

**Low** — `android/.../NativeDatastorePlugin.kt:40-44, 57-58` `@Volatile` fields nulled correctly on detach — correct pattern, no fix.

**Low** — `ios/Classes/NativeDatastorePlugin.swift:209, 264` `FlutterStandardTypedData(bytes:)` copies the `Data` buffer; ARC releases the original cleanly.

**Lifetime traceability gap** — `ios/Classes/NativeDatastorePlugin.swift:15-18` `register(with:)` has no documented teardown path. A reader cannot determine "who frees the plugin instance" without consulting Flutter framework internals. Android side is symmetric and clear.

## Recommended Next Actions

1. **Centralize the typed-namespace table** — introduce a single source of truth for `__list__:`/`__bytes__:`/`__datetime__:`/`__map__:` (a Pigeon-generated constants table, or per-language named constants kept in sync by code review). Eliminates the OCP shotgun surgery, the High content-coupling smell, and ~30 magic-string sites in one move. Start in `pigeons/messages.dart` and update `lib/src/native_datastore_plugin.dart:66-71`, `ios/Classes/NativeDatastorePlugin.swift:7-10`, `android/.../NativeDatastorePlugin.kt:124,172,184-186,213-228,245-248,259-261`.

2. **Add iOS `detachFromEngineForRegistrar(_:)`** that calls `DatastoreApiSetup.setUp(binaryMessenger: …, api: nil)` and `registrar.publish(instance)` in `register(with:)`. Closes the iOS lifetime gap. Start in `ios/Classes/NativeDatastorePlugin.swift:15-18`.

3. **Guarantee Pigeon callback completion** under teardown race — wrap `launchSafe`'s launched job with `invokeOnCompletion` that posts a `failure` if cancelled before invoking the body. Start in `android/.../NativeDatastorePlugin.kt:67-89`.

4. **Unify FFI vocabulary with the facade** — rename Pigeon `getDateTimeMillis`/`setDateTimeMillis`/`getJsonMap`/`setJsonMap` to `getDateTime`/`setDateTime`/`getMap`/`setMap`. Unify `kotlinOptions.errorClassName` and `swiftOptions.errorClassName` to `NativeDatastoreError`. Start in `pigeons/messages.dart:12,16,74,77,80,83`. One regen cycle.

5. **Tighten public API return types** — change `clear()` to `Future<void>` (`lib/src/native_datastore_plugin.dart:242`); decide whether `remove` returns `Future<bool>` (rename `removeIfPresent`) or `Future<T?>` (idiomatic). Document the runtime-type union returned by `getAll()` at `lib/src/native_datastore_plugin.dart:253`, or rename `getAllRaw`. Public-API change → bump minor version.

6. **Refactor Swift to mirror Kotlin's `launchSafe`** — introduce a `onQueue<T>` helper and switch all 21 `queue.async { [self] in … }` sites to `[weak self] in guard let self else { completion(.failure(...)); return }`. Start in `ios/Classes/NativeDatastorePlugin.swift:13`.

7. **Inject native singletons** — add `init(defaults:)` to iOS (`ios/Classes/NativeDatastorePlugin.swift:5`) and constructor-injected `DataStore<Preferences>` on Android (`android/.../NativeDatastorePlugin.kt:31-36`). Mirrors the Dart-side `NativeDatastore.withApi` test seam.

8. **Collapse test boilerplate** — fold the 19 empty-key tests and 22 PlatformException-wrap tests into table-driven loops at `test/native_datastore_test.dart:113, 446`. Reduces ~400 lines to ~50 and auto-covers new API methods.

9. **Document/enforce a payload size policy** for `setBytes`/`setMap`. Either document "small preferences only" or reject payloads above a threshold with a clear `NativeDatastoreException`.

10. **Sync version strings** — `ios/native_datastore.podspec:3` and `android/build.gradle.kts:2` to match `pubspec.yaml:6` (`1.2.0`), or auto-derive in `release.sh`.

## Methodology

- **Linters used**: `dart analyze` (clean against strict `analysis_options.yaml`); `swiftlint`/`detekt`/`ktlint`/`tokei`/`cloc`/`jscpd`/`lizard`/`radon` not installed — analysis fell back to LLM heuristic review of hand-written sources only.
- **Languages detected**: Dart (8 files), Swift (5), Kotlin (3). Plus build/config: `pubspec.yaml`, `analysis_options.yaml`, `pigeons/messages.dart`, `android/build.gradle.kts`, `ios/native_datastore.podspec`.
- **Excluded paths**: `build/`, `.dart_tool/`, `Pods/`, `DerivedData/`, `.git/`, `node_modules/`. Pigeon-generated files (`*.g.dart`, `Messages.g.swift`, `Messages.g.kt`) were inspected for FFI signatures only and not critiqued as hand-written code.
- **Limitations**:
  - Memory analysis is static only; no Instruments Allocations, Android Studio Memory Profiler, or Dart Observatory was attached. The two High iOS/Android lifecycle items should be validated under hot-restart and `FlutterEngineGroup`/`FlutterFragment` add-remove with leak instrumentation before being treated as confirmed leaks rather than latent risk.
  - No security scanner (Semgrep/Bandit/MobSF) was run; the "no findings" verdict in the Security section is based on manual review of a narrow API surface (key/value persistence with no network or auth).
  - Cyclomatic complexity numbers are manual estimates (decision-point counts) rather than tool-measured.
