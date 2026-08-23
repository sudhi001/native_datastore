import Flutter

public class NativeDatastorePlugin: NSObject, FlutterPlugin, DatastoreApi {

    // App-side namespace applied to every stored key so the plugin's entries
    // don't collide with system or app-level UserDefaults keys.
    private let keyNamespace = "native_datastore."

    // Per-type buckets sharing the flat UserDefaults key space. Keep these in
    // sync with the Dart `_BucketPrefix` constants and the Kotlin
    // `BucketPrefix` constants.
    private static let listBucket = "__list__:"
    private static let bytesBucket = "__bytes__:"
    private static let dateTimeBucket = "__datetime__:"
    private static let mapBucket = "__map__:"
    private static let typedBuckets = [listBucket, bytesBucket, dateTimeBucket, mapBucket]

    // `var` so `configure(appGroupId:)` can repoint storage at an App Group
    // suite. Only ever mutated on `serialQueue`, so access stays serialized.
    private var defaults = UserDefaults.standard

    /// Serial queue for all datastore operations to prevent race conditions.
    private let serialQueue = DispatchQueue(label: "native_datastore.serial")

    /// App Group container URL when `configure(appGroupId:)` repointed storage
    /// at a shared suite, else nil. Only mutated on `serialQueue`.
    private var appGroupContainer: URL?

    // Held strongly so the Pigeon handler closure isn't the only owner — gives
    // a deterministic place to nil it during teardown.
    private var secureInstance: SecureDatastorePlugin?

    private var changesChannel: FlutterEventChannel?
    private var changesHandler: DatastoreChangesStreamHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NativeDatastorePlugin()
        registrar.publish(instance)
        DatastoreApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        let secure = SecureDatastorePlugin()
        instance.secureInstance = secure
        SecureDatastoreApiSetup.setUp(binaryMessenger: registrar.messenger(), api: secure)

        let channel = FlutterEventChannel(
            name: "in.sudhi.native_datastore/changes",
            binaryMessenger: registrar.messenger()
        )
        let handler = DatastoreChangesStreamHandler(plugin: instance)
        channel.setStreamHandler(handler)
        instance.changesChannel = channel
        instance.changesHandler = handler
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        // Drop both Pigeon dispatchers so the messenger stops retaining the
        // plugin instances (and the closures they capture) after the engine
        // goes away.
        DatastoreApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        SecureDatastoreApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        changesChannel?.setStreamHandler(nil)
        changesHandler = nil
        changesChannel = nil
        secureInstance = nil
    }

    // MARK: - Change-stream support

    /// Snapshot of every namespaced key/value pair currently stored, keyed by
    /// the full (namespaced) key.
    fileprivate func namespacedSnapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(keyNamespace) {
            out[key] = value
        }
        return out
    }

    /// Strips the namespace and any bucket prefix from a stored key.
    fileprivate func userFacingKey(_ fullKey: String) -> String {
        let stripped = String(fullKey.dropFirst(keyNamespace.count))
        for bucket in Self.typedBuckets where stripped.hasPrefix(bucket) {
            return String(stripped.dropFirst(bucket.count))
        }
        return stripped
    }

    fileprivate func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        guard let a = a, let b = b else { return false }
        return (a as? NSObject)?.isEqual(b as? NSObject) ?? false
    }

    private func scalarKey(_ key: String) -> String { keyNamespace + key }
    private func bucketKey(_ bucket: String, _ key: String) -> String { keyNamespace + bucket + key }

    /// Dispatches `body` on the serial queue, completing on the same queue.
    /// Uses `[weak self]` so a teardown mid-flight short-circuits with a
    /// `plugin-detached` failure rather than keeping the instance alive
    /// for the duration of the queue backlog.
    /// Runs [body] under a cross-process advisory lock when storage is backed
    /// by an App Group.
    ///
    /// `serialQueue` only serialises callers inside *this* process. Once
    /// `configure(appGroupId:)` points storage at a shared suite, an app
    /// extension in a separate process can interleave its own read-modify-write
    /// between our read and our write, silently losing an update. The atomic
    /// operations this plugin advertises (increment, toggle, compare-and-set)
    /// would not actually be atomic there.
    ///
    /// `flock` on a file in the shared container gives the missing mutual
    /// exclusion. With no App Group configured there is no second process to
    /// race with, so the lock is skipped entirely and single-process callers
    /// pay nothing.
    fileprivate func withCrossProcessLock<T>(_ body: () -> T) -> T {
        guard let container = appGroupContainer else { return body() }
        let lockURL = container.appendingPathComponent(".native_datastore.lock")
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd != -1 else {
            // Cannot obtain the lock file — proceed rather than fail the call;
            // behaviour then matches the previous in-process-only guarantee.
            return body()
        }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return body() }
        defer { flock(fd, LOCK_UN) }
        // Pick up writes committed by other processes before reading.
        defaults.synchronize()
        let result = body()
        defaults.synchronize()
        return result
    }

    private func onQueue<T>(
        _ completion: @escaping (Result<T, Error>) -> Void,
        body: @escaping (NativeDatastorePlugin) -> T
    ) {
        serialQueue.async { [weak self] in
            guard let self else {
                completion(.failure(NativeDatastoreError(
                    code: "plugin-detached",
                    message: "NativeDatastorePlugin is no longer attached",
                    details: nil
                )))
                return
            }
            completion(.success(body(self)))
        }
    }

    /// Returns true if `value` was stored as a Bool (CFBoolean), not a numeric.
    /// `defaults.set(true, forKey:)` stores a CFBoolean, distinguishable from
    /// an NSNumber via CFGetTypeID.
    fileprivate func isStoredAsBool(_ value: Any) -> Bool {
        return CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    /// Returns true if `number` was stored as a floating-point value.
    /// NSNumber's objCType is "f" for Float and "d" for Double.
    fileprivate func isFloatingPointNumber(_ number: NSNumber) -> Bool {
        let kind = String(cString: number.objCType)
        return kind == "f" || kind == "d"
    }

    // MARK: - Getters

    func getString(key: String, completion: @escaping (Result<String?, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.string(forKey: plugin.scalarKey(key))
        }
    }

    func getBool(key: String, completion: @escaping (Result<Bool?, Error>) -> Void) {
        onQueue(completion) { plugin in
            guard let value = plugin.defaults.object(forKey: plugin.scalarKey(key)),
                  plugin.isStoredAsBool(value) else {
                return nil
            }
            return (value as! NSNumber).boolValue
        }
    }

    func getInt(key: String, completion: @escaping (Result<Int64?, Error>) -> Void) {
        onQueue(completion) { plugin in
            guard let value = plugin.defaults.object(forKey: plugin.scalarKey(key)),
                  !plugin.isStoredAsBool(value),
                  let number = value as? NSNumber,
                  !plugin.isFloatingPointNumber(number) else {
                return nil
            }
            return number.int64Value
        }
    }

    func getDouble(key: String, completion: @escaping (Result<Double?, Error>) -> Void) {
        onQueue(completion) { plugin in
            guard let value = plugin.defaults.object(forKey: plugin.scalarKey(key)),
                  !plugin.isStoredAsBool(value),
                  let number = value as? NSNumber else {
                return nil
            }
            return number.doubleValue
        }
    }

    func getStringList(key: String, completion: @escaping (Result<[String]?, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.stringArray(forKey: plugin.bucketKey(Self.listBucket, key))
        }
    }

    // MARK: - Setters

    func setString(key: String, value: String, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.set(value, forKey: plugin.scalarKey(key))
        }
    }

    func setBool(key: String, value: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.set(value, forKey: plugin.scalarKey(key))
        }
    }

    func setInt(key: String, value: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.set(value, forKey: plugin.scalarKey(key))
        }
    }

    func setDouble(key: String, value: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.set(value, forKey: plugin.scalarKey(key))
        }
    }

    func setStringList(key: String, value: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.set(value, forKey: plugin.bucketKey(Self.listBucket, key))
        }
    }

    // MARK: - Batch

    /// Reads many keys in one queue hop instead of one per key. Absent keys are
    /// omitted so callers can tell "missing" from "stored null".
    func getMany(keys: [String], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        onQueue(completion) { plugin in
            var result: [String: Any] = [:]
            for key in keys {
                if let value = plugin.defaults.stringArray(
                    forKey: plugin.bucketKey(Self.listBucket, key)
                ) {
                    result[key] = value
                    continue
                }
                if let data = plugin.defaults.data(forKey: plugin.bucketKey(Self.bytesBucket, key)) {
                    result[key] = FlutterStandardTypedData(bytes: data)
                    continue
                }
                for bucket in [Self.dateTimeBucket, Self.mapBucket] {
                    if let value = plugin.defaults.object(forKey: plugin.bucketKey(bucket, key)) {
                        result[key] = value
                        break
                    }
                }
                if result[key] == nil,
                   let value = plugin.defaults.object(forKey: plugin.scalarKey(key)) {
                    result[key] = value
                }
            }
            return result
        }
    }

    /// Writes many entries in one queue hop. Values must be String, Bool, Int,
    /// Double or [String].
    func setMany(entries: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            for (key, value) in entries {
                if let list = value as? [String] {
                    plugin.defaults.set(list, forKey: plugin.bucketKey(Self.listBucket, key))
                } else {
                    plugin.defaults.set(value, forKey: plugin.scalarKey(key))
                }
            }
        }
    }

    /// Removes many keys in one queue hop, returning how many were present.
    func removeMany(keys: [String], completion: @escaping (Result<Int64, Error>) -> Void) {
        onQueue(completion) { plugin in
            var removed: Int64 = 0
            for key in keys {
                var candidates = [plugin.scalarKey(key)]
                candidates.append(contentsOf: Self.typedBuckets.map { plugin.bucketKey($0, key) })
                var existed = false
                for candidate in candidates where plugin.defaults.object(forKey: candidate) != nil {
                    existed = true
                    plugin.defaults.removeObject(forKey: candidate)
                }
                if existed { removed += 1 }
            }
            return removed
        }
    }

    // MARK: - Remove / Clear

    func remove(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            var candidates = [plugin.scalarKey(key)]
            candidates.append(contentsOf: Self.typedBuckets.map { plugin.bucketKey($0, key) })
            var existed = false
            for candidate in candidates {
                if plugin.defaults.object(forKey: candidate) != nil {
                    existed = true
                    plugin.defaults.removeObject(forKey: candidate)
                }
            }
            return existed
        }
    }

    func clear(completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            for key in plugin.defaults.dictionaryRepresentation().keys
                where key.hasPrefix(plugin.keyNamespace) {
                plugin.defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Query

    func getAll(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        onQueue(completion) { plugin in
            var result: [String: Any] = [:]
            for (key, value) in plugin.defaults.dictionaryRepresentation() {
                guard key.hasPrefix(plugin.keyNamespace) else { continue }
                let stripped = String(key.dropFirst(plugin.keyNamespace.count))
                var realKey = stripped
                var matchedBucket: String? = nil
                for bucket in Self.typedBuckets where stripped.hasPrefix(bucket) {
                    realKey = String(stripped.dropFirst(bucket.count))
                    matchedBucket = bucket
                    break
                }
                if matchedBucket == Self.bytesBucket {
                    if let data = value as? Data {
                        result[realKey] = FlutterStandardTypedData(bytes: data)
                    }
                } else {
                    result[realKey] = value
                }
            }
            return result
        }
    }

    func getKeys(completion: @escaping (Result<[String], Error>) -> Void) {
        onQueue(completion) { plugin in
            var keys = Set<String>()
            for key in plugin.defaults.dictionaryRepresentation().keys {
                guard key.hasPrefix(plugin.keyNamespace) else { continue }
                let stripped = String(key.dropFirst(plugin.keyNamespace.count))
                var realKey = stripped
                for bucket in Self.typedBuckets where stripped.hasPrefix(bucket) {
                    realKey = String(stripped.dropFirst(bucket.count))
                    break
                }
                keys.insert(realKey)
            }
            return Array(keys)
        }
    }

    func containsKey(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            var candidates = [plugin.scalarKey(key)]
            candidates.append(contentsOf: Self.typedBuckets.map { plugin.bucketKey($0, key) })
            return candidates.contains { plugin.defaults.object(forKey: $0) != nil }
        }
    }

    // MARK: - Bytes (Uint8List)

    func getBytes(key: String, completion: @escaping (Result<FlutterStandardTypedData?, Error>) -> Void) {
        onQueue(completion) { plugin in
            guard let data = plugin.defaults.data(forKey: plugin.bucketKey(Self.bytesBucket, key)) else {
                return nil
            }
            return FlutterStandardTypedData(bytes: data)
        }
    }

    func setBytes(key: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.set(value.data, forKey: plugin.bucketKey(Self.bytesBucket, key))
        }
    }

    // MARK: - DateTime (millis since epoch)

    func getDateTime(key: String, completion: @escaping (Result<Int64?, Error>) -> Void) {
        onQueue(completion) { plugin in
            guard let value = plugin.defaults.object(forKey: plugin.bucketKey(Self.dateTimeBucket, key)),
                  !plugin.isStoredAsBool(value),
                  let number = value as? NSNumber,
                  !plugin.isFloatingPointNumber(number) else {
                return nil
            }
            return number.int64Value
        }
    }

    func setDateTime(key: String, value: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.set(value, forKey: plugin.bucketKey(Self.dateTimeBucket, key))
        }
    }

    // MARK: - JSON Map

    func getMap(key: String, completion: @escaping (Result<String?, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.string(forKey: plugin.bucketKey(Self.mapBucket, key))
        }
    }

    func setMap(key: String, value: String, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.defaults.set(value, forKey: plugin.bucketKey(Self.mapBucket, key))
        }
    }

    // MARK: - Atomic read-modify-write
    // Every op runs on `serialQueue`, so a read-then-write inside one `onQueue`
    // body is atomic with respect to all other datastore operations.

    func incrementInt(key: String, delta: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.withCrossProcessLock {
                let k = plugin.scalarKey(key)
                var current: Int64 = 0
                if let value = plugin.defaults.object(forKey: k),
                   !plugin.isStoredAsBool(value),
                   let number = value as? NSNumber,
                   !plugin.isFloatingPointNumber(number) {
                    current = number.int64Value
                }
                let newValue = current + delta
                plugin.defaults.set(newValue, forKey: k)
                return newValue
            }
        }
    }

    func incrementDouble(key: String, delta: Double, completion: @escaping (Result<Double, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.withCrossProcessLock {
                let k = plugin.scalarKey(key)
                var current = 0.0
                if let value = plugin.defaults.object(forKey: k),
                   !plugin.isStoredAsBool(value),
                   let number = value as? NSNumber {
                    current = number.doubleValue
                }
                let newValue = current + delta
                plugin.defaults.set(newValue, forKey: k)
                return newValue
            }
        }
    }

    func toggleBool(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.withCrossProcessLock {
                let k = plugin.scalarKey(key)
                var current = false
                if let value = plugin.defaults.object(forKey: k), plugin.isStoredAsBool(value) {
                    current = (value as! NSNumber).boolValue
                }
                let newValue = !current
                plugin.defaults.set(newValue, forKey: k)
                return newValue
            }
        }
    }

    func compareAndSetString(key: String, expected: String?, value: String?, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.withCrossProcessLock {
                let k = plugin.scalarKey(key)
                guard plugin.defaults.string(forKey: k) == expected else { return false }
                if let value = value {
                    plugin.defaults.set(value, forKey: k)
                } else {
                    plugin.defaults.removeObject(forKey: k)
                }
                return true
            }
        }
    }

    func compareAndSetInt(key: String, expected: Int64?, value: Int64?, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.withCrossProcessLock {
                let k = plugin.scalarKey(key)
                var current: Int64? = nil
                if let v = plugin.defaults.object(forKey: k),
                   !plugin.isStoredAsBool(v),
                   let number = v as? NSNumber,
                   !plugin.isFloatingPointNumber(number) {
                    current = number.int64Value
                }
                guard current == expected else { return false }
                if let value = value {
                    plugin.defaults.set(value, forKey: k)
                } else {
                    plugin.defaults.removeObject(forKey: k)
                }
                return true
            }
        }
    }

    func compareAndSetDouble(key: String, expected: Double?, value: Double?, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.withCrossProcessLock {
                let k = plugin.scalarKey(key)
                var current: Double? = nil
                if let v = plugin.defaults.object(forKey: k),
                   !plugin.isStoredAsBool(v),
                   let number = v as? NSNumber {
                    current = number.doubleValue
                }
                guard current == expected else { return false }
                if let value = value {
                    plugin.defaults.set(value, forKey: k)
                } else {
                    plugin.defaults.removeObject(forKey: k)
                }
                return true
            }
        }
    }

    func compareAndSetBool(key: String, expected: Bool?, value: Bool?, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            plugin.withCrossProcessLock {
                let k = plugin.scalarKey(key)
                var current: Bool? = nil
                if let v = plugin.defaults.object(forKey: k), plugin.isStoredAsBool(v) {
                    current = (v as! NSNumber).boolValue
                }
                guard current == expected else { return false }
                if let value = value {
                    plugin.defaults.set(value, forKey: k)
                } else {
                    plugin.defaults.removeObject(forKey: k)
                }
                return true
            }
        }
    }

    // MARK: - Migration from shared_preferences

    func migrateFromSharedPreferences(overwrite: Bool, completion: @escaping (Result<Int64, Error>) -> Void) {
        onQueue(completion) { plugin in
            // shared_preferences on iOS writes to UserDefaults.standard with a
            // "flutter." key prefix. Copy those into this plugin's namespace.
            let source = UserDefaults.standard
            var imported: Int64 = 0
            for (rawKey, value) in source.dictionaryRepresentation() {
                guard rawKey.hasPrefix("flutter.") else { continue }
                let key = String(rawKey.dropFirst("flutter.".count))
                if key.isEmpty { continue }

                var exists = plugin.defaults.object(forKey: plugin.scalarKey(key)) != nil
                for bucket in Self.typedBuckets
                    where plugin.defaults.object(forKey: plugin.bucketKey(bucket, key)) != nil {
                    exists = true
                }
                if exists && !overwrite { continue }

                if let s = value as? String {
                    plugin.defaults.set(s, forKey: plugin.scalarKey(key))
                } else if let arr = value as? [String] {
                    plugin.defaults.set(arr, forKey: plugin.bucketKey(Self.listBucket, key))
                } else if let number = value as? NSNumber {
                    if plugin.isStoredAsBool(number) {
                        plugin.defaults.set(number.boolValue, forKey: plugin.scalarKey(key))
                    } else if plugin.isFloatingPointNumber(number) {
                        plugin.defaults.set(number.doubleValue, forKey: plugin.scalarKey(key))
                    } else {
                        plugin.defaults.set(number.int64Value, forKey: plugin.scalarKey(key))
                    }
                } else {
                    continue
                }
                imported += 1
            }
            return imported
        }
    }

    // MARK: - Configuration

    func configure(multiProcess: Bool, appGroupId: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        // `multiProcess` is an Android-only concept. On iOS, cross-process
        // sharing (e.g. with an app extension) is achieved via an App Group
        // suite, so we repoint storage when an appGroupId is supplied.
        onQueue(completion) { plugin in
            if let appGroupId = appGroupId, let suite = UserDefaults(suiteName: appGroupId) {
                plugin.defaults = suite
                plugin.appGroupContainer = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
            } else {
                plugin.defaults = UserDefaults.standard
                plugin.appGroupContainer = nil
            }
        }
    }
}

/// Streams the set of user-facing keys that change. `UserDefaults` posts a
/// single global `didChangeNotification` for any write, so we diff a snapshot
/// of this plugin's namespaced keys to determine which keys actually changed.
class DatastoreChangesStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: NativeDatastorePlugin?
    private var sink: FlutterEventSink?
    private var snapshot: [String: Any] = [:]

    /// `UserDefaults.didChangeNotification` fires for *any* write in the app,
    /// not just this plugin's, and each one used to run a full
    /// `dictionaryRepresentation()` snapshot and diff synchronously on the
    /// posting thread — usually main. The diff now runs on this serial queue
    /// instead, so an app writing its own unrelated defaults no longer stalls
    /// the main thread on our bookkeeping.
    ///
    /// The queue is serial, so diffs stay strictly ordered and `snapshot` is
    /// only ever touched here.
    ///
    /// Deliberately *not* coalesced: collapsing a burst into a single diff
    /// would drop intermediate values, so two quick writes would surface only
    /// the last one. Watchers are documented to see each change, and the
    /// on-device integration test asserts it.
    private let diffQueue = DispatchQueue(label: "native_datastore.changes")

    init(plugin: NativeDatastorePlugin) {
        self.plugin = plugin
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // Guard against a second onListen without an intervening onCancel,
        // which would otherwise register a duplicate observer.
        NotificationCenter.default.removeObserver(self)
        sink = events
        snapshot = plugin?.namespacedSnapshot() ?? [:]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        return nil
    }

    @objc private func defaultsChanged() {
        diffQueue.async { [weak self] in self?.emitChanges() }
    }

    private func emitChanges() {
        guard let plugin = plugin, let sink = sink else { return }
        let current = plugin.namespacedSnapshot()
        var changed = Set<String>()
        for key in Set(current.keys).union(snapshot.keys) where
            !plugin.valuesEqual(current[key], snapshot[key]) {
            changed.insert(plugin.userFacingKey(key))
        }
        snapshot = current
        if !changed.isEmpty {
            let keys = Array(changed)
            DispatchQueue.main.async { sink(keys) }
        }
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self)
        sink = nil
        diffQueue.async { [weak self] in self?.snapshot = [:] }
        return nil
    }
}
