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

    private let defaults = UserDefaults.standard

    /// Serial queue for all datastore operations to prevent race conditions.
    private let serialQueue = DispatchQueue(label: "native_datastore.serial")

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NativeDatastorePlugin()
        registrar.publish(instance)
        DatastoreApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        // Drop the Pigeon dispatcher so the messenger stops retaining `self`
        // (and the closures it captures) after the engine goes away.
        DatastoreApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    }

    private func scalarKey(_ key: String) -> String { keyNamespace + key }
    private func bucketKey(_ bucket: String, _ key: String) -> String { keyNamespace + bucket + key }

    /// Dispatches `body` on the serial queue, completing on the same queue.
    /// Uses `[weak self]` so a teardown mid-flight short-circuits with a
    /// `plugin-detached` failure rather than keeping the instance alive
    /// for the duration of the queue backlog.
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
}
