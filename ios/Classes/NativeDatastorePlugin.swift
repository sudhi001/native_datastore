import Flutter

public class NativeDatastorePlugin: NSObject, FlutterPlugin, DatastoreApi {

    private let defaults = UserDefaults.standard
    private let prefix = "in.sudhi.native_datastore."
    private let listPrefix = "__list__:"

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

    // MARK: - Getters

    func getString(key: String, completion: @escaping (Result<String?, Error>) -> Void) {
        let value = defaults.string(forKey: prefixedKey(key))
        completion(.success(value))
    }

    func getBool(key: String, completion: @escaping (Result<Bool?, Error>) -> Void) {
        let pKey = prefixedKey(key)
        if defaults.object(forKey: pKey) == nil {
            completion(.success(nil))
        } else {
            completion(.success(defaults.bool(forKey: pKey)))
        }
    }

    func getInt(key: String, completion: @escaping (Result<Int64?, Error>) -> Void) {
        let pKey = prefixedKey(key)
        if defaults.object(forKey: pKey) == nil {
            completion(.success(nil))
        } else {
            completion(.success(Int64(defaults.integer(forKey: pKey))))
        }
    }

    func getDouble(key: String, completion: @escaping (Result<Double?, Error>) -> Void) {
        let pKey = prefixedKey(key)
        if defaults.object(forKey: pKey) == nil {
            completion(.success(nil))
        } else {
            completion(.success(defaults.double(forKey: pKey)))
        }
    }

    func getStringList(key: String, completion: @escaping (Result<[String]?, Error>) -> Void) {
        let value = defaults.stringArray(forKey: prefixedListKey(key))
        completion(.success(value))
    }

    // MARK: - Setters

    func setString(key: String, value: String, completion: @escaping (Result<Void, Error>) -> Void) {
        defaults.set(value, forKey: prefixedKey(key))
        completion(.success(()))
    }

    func setBool(key: String, value: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        defaults.set(value, forKey: prefixedKey(key))
        completion(.success(()))
    }

    func setInt(key: String, value: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        defaults.set(value, forKey: prefixedKey(key))
        completion(.success(()))
    }

    func setDouble(key: String, value: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        defaults.set(value, forKey: prefixedKey(key))
        completion(.success(()))
    }

    func setStringList(key: String, value: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        defaults.set(value, forKey: prefixedListKey(key))
        completion(.success(()))
    }

    // MARK: - Remove / Clear

    func remove(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let pKey = prefixedKey(key)
        let pListKey = prefixedListKey(key)
        let existed = defaults.object(forKey: pKey) != nil || defaults.object(forKey: pListKey) != nil
        defaults.removeObject(forKey: pKey)
        defaults.removeObject(forKey: pListKey)
        completion(.success(existed))
    }

    func clear(completion: @escaping (Result<Bool, Error>) -> Void) {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.hasPrefix(prefix) {
                defaults.removeObject(forKey: key)
            }
        }
        completion(.success(true))
    }

    // MARK: - Query

    func getAll(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var result: [String: Any] = [:]
        let allDict = defaults.dictionaryRepresentation()
        for (key, value) in allDict {
            guard key.hasPrefix(prefix) else { continue }
            let strippedKey = String(key.dropFirst(prefix.count))
            if strippedKey.hasPrefix(listPrefix) {
                let realKey = String(strippedKey.dropFirst(listPrefix.count))
                result[realKey] = value
            } else {
                result[strippedKey] = value
            }
        }
        completion(.success(result))
    }

    func getKeys(completion: @escaping (Result<[String], Error>) -> Void) {
        var keys = Set<String>()
        for key in defaults.dictionaryRepresentation().keys {
            guard key.hasPrefix(prefix) else { continue }
            let strippedKey = String(key.dropFirst(prefix.count))
            if strippedKey.hasPrefix(listPrefix) {
                keys.insert(String(strippedKey.dropFirst(listPrefix.count)))
            } else {
                keys.insert(strippedKey)
            }
        }
        completion(.success(Array(keys)))
    }

    func containsKey(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let exists = defaults.object(forKey: prefixedKey(key)) != nil
            || defaults.object(forKey: prefixedListKey(key)) != nil
        completion(.success(exists))
    }
}
