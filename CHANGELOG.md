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
