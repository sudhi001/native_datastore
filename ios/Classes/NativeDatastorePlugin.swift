import Flutter

public class NativeDatastorePlugin: NSObject, FlutterPlugin, DatastoreApi {

    private let defaults = UserDefaults.standard
    private let prefix = "native_datastore."
    private let listPrefix = "__list__:"
    private let bytesPrefix = "__bytes__:"
    private let dateTimePrefix = "__datetime__:"
    private let mapPrefix = "__map__:"

    /// Serial queue for all datastore operations to prevent race conditions.
    private let queue = DispatchQueue(label: "native_datastore.serial")

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NativeDatastorePlugin()
        DatastoreApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    }

    private func prefixedKey(_ key: String) -> String {
        return prefix + key
    }

    private func prefixedListKey(_ key: String) -> String {
        return prefix + listPrefix + key
    }

    private func prefixedBytesKey(_ key: String) -> String {
        return prefix + bytesPrefix + key
    }

    private func prefixedDateTimeKey(_ key: String) -> String {
        return prefix + dateTimePrefix + key
    }

    private func prefixedMapKey(_ key: String) -> String {
        return prefix + mapPrefix + key
    }

    // MARK: - Getters

    func getString(key: String, completion: @escaping (Result<String?, Error>) -> Void) {
        queue.async { [self] in
            let value = defaults.string(forKey: prefixedKey(key))
            completion(.success(value))
        }
    }

    func getBool(key: String, completion: @escaping (Result<Bool?, Error>) -> Void) {
        queue.async { [self] in
            let pKey = prefixedKey(key)
            if defaults.object(forKey: pKey) == nil {
                completion(.success(nil))
            } else {
                completion(.success(defaults.bool(forKey: pKey)))
            }
        }
    }

    func getInt(key: String, completion: @escaping (Result<Int64?, Error>) -> Void) {
        queue.async { [self] in
            let pKey = prefixedKey(key)
            if defaults.object(forKey: pKey) == nil {
                completion(.success(nil))
            } else {
                completion(.success(Int64(defaults.integer(forKey: pKey))))
            }
        }
    }

    func getDouble(key: String, completion: @escaping (Result<Double?, Error>) -> Void) {
        queue.async { [self] in
            let pKey = prefixedKey(key)
            if defaults.object(forKey: pKey) == nil {
                completion(.success(nil))
            } else {
                completion(.success(defaults.double(forKey: pKey)))
            }
        }
    }

    func getStringList(key: String, completion: @escaping (Result<[String]?, Error>) -> Void) {
        queue.async { [self] in
            let value = defaults.stringArray(forKey: prefixedListKey(key))
            completion(.success(value))
        }
    }

    // MARK: - Setters

    func setString(key: String, value: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            defaults.set(value, forKey: prefixedKey(key))
            completion(.success(()))
        }
    }

    func setBool(key: String, value: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            defaults.set(value, forKey: prefixedKey(key))
            completion(.success(()))
        }
    }

    func setInt(key: String, value: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            defaults.set(value, forKey: prefixedKey(key))
            completion(.success(()))
        }
    }

    func setDouble(key: String, value: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            defaults.set(value, forKey: prefixedKey(key))
            completion(.success(()))
        }
    }

    func setStringList(key: String, value: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            defaults.set(value, forKey: prefixedListKey(key))
            completion(.success(()))
        }
    }

    // MARK: - Remove / Clear

    func remove(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        queue.async { [self] in
            let pKey = prefixedKey(key)
            let pListKey = prefixedListKey(key)
            let pBytesKey = prefixedBytesKey(key)
            let pDateTimeKey = prefixedDateTimeKey(key)
            let pMapKey = prefixedMapKey(key)
            let existed = defaults.object(forKey: pKey) != nil
                || defaults.object(forKey: pListKey) != nil
                || defaults.object(forKey: pBytesKey) != nil
                || defaults.object(forKey: pDateTimeKey) != nil
                || defaults.object(forKey: pMapKey) != nil
            defaults.removeObject(forKey: pKey)
            defaults.removeObject(forKey: pListKey)
            defaults.removeObject(forKey: pBytesKey)
            defaults.removeObject(forKey: pDateTimeKey)
            defaults.removeObject(forKey: pMapKey)
            completion(.success(existed))
        }
    }

    func clear(completion: @escaping (Result<Bool, Error>) -> Void) {
        queue.async { [self] in
            let allKeys = defaults.dictionaryRepresentation().keys
            for key in allKeys {
                if key.hasPrefix(prefix) {
                    defaults.removeObject(forKey: key)
                }
            }
            completion(.success(true))
        }
    }

    // MARK: - Query

    func getAll(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        queue.async { [self] in
            var result: [String: Any] = [:]
            let allDict = defaults.dictionaryRepresentation()
            for (key, value) in allDict {
                guard key.hasPrefix(prefix) else { continue }
                let strippedKey = String(key.dropFirst(prefix.count))
                if strippedKey.hasPrefix(listPrefix) {
                    let realKey = String(strippedKey.dropFirst(listPrefix.count))
                    result[realKey] = value
                } else if strippedKey.hasPrefix(bytesPrefix) {
                    let realKey = String(strippedKey.dropFirst(bytesPrefix.count))
                    if let data = value as? Data {
                        result[realKey] = FlutterStandardTypedData(bytes: data)
                    }
                } else if strippedKey.hasPrefix(dateTimePrefix) {
                    let realKey = String(strippedKey.dropFirst(dateTimePrefix.count))
                    result[realKey] = value
                } else if strippedKey.hasPrefix(mapPrefix) {
                    let realKey = String(strippedKey.dropFirst(mapPrefix.count))
                    result[realKey] = value
                } else {
                    result[strippedKey] = value
                }
            }
            completion(.success(result))
        }
    }

    func getKeys(completion: @escaping (Result<[String], Error>) -> Void) {
        queue.async { [self] in
            var keys = Set<String>()
            let prefixes = [listPrefix, bytesPrefix, dateTimePrefix, mapPrefix]
            for key in defaults.dictionaryRepresentation().keys {
                guard key.hasPrefix(prefix) else { continue }
                let strippedKey = String(key.dropFirst(prefix.count))
                var realKey = strippedKey
                for p in prefixes {
                    if strippedKey.hasPrefix(p) {
                        realKey = String(strippedKey.dropFirst(p.count))
                        break
                    }
                }
                keys.insert(realKey)
            }
            completion(.success(Array(keys)))
        }
    }

    func containsKey(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        queue.async { [self] in
            let exists = defaults.object(forKey: prefixedKey(key)) != nil
                || defaults.object(forKey: prefixedListKey(key)) != nil
                || defaults.object(forKey: prefixedBytesKey(key)) != nil
                || defaults.object(forKey: prefixedDateTimeKey(key)) != nil
                || defaults.object(forKey: prefixedMapKey(key)) != nil
            completion(.success(exists))
        }
    }

    // MARK: - Bytes (Uint8List)

    func getBytes(key: String, completion: @escaping (Result<FlutterStandardTypedData?, Error>) -> Void) {
        queue.async { [self] in
            guard let data = defaults.data(forKey: prefixedBytesKey(key)) else {
                completion(.success(nil))
                return
            }
            completion(.success(FlutterStandardTypedData(bytes: data)))
        }
    }

    func setBytes(key: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            defaults.set(value.data, forKey: prefixedBytesKey(key))
            completion(.success(()))
        }
    }

    // MARK: - DateTime (millis since epoch)

    func getDateTimeMillis(key: String, completion: @escaping (Result<Int64?, Error>) -> Void) {
        queue.async { [self] in
            let pKey = prefixedDateTimeKey(key)
            if defaults.object(forKey: pKey) == nil {
                completion(.success(nil))
            } else {
                completion(.success(Int64(defaults.integer(forKey: pKey))))
            }
        }
    }

    func setDateTimeMillis(key: String, value: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            defaults.set(value, forKey: prefixedDateTimeKey(key))
            completion(.success(()))
        }
    }

    // MARK: - JSON Map

    func getJsonMap(key: String, completion: @escaping (Result<String?, Error>) -> Void) {
        queue.async { [self] in
            let value = defaults.string(forKey: prefixedMapKey(key))
            completion(.success(value))
        }
    }

    func setJsonMap(key: String, value: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            defaults.set(value, forKey: prefixedMapKey(key))
            completion(.success(()))
        }
    }
}
