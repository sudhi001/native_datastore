import Flutter
import Foundation
import Security

/// Thin Keychain Services wrapper for `kSecClassGenericPassword` items scoped
/// to this plugin's service identifier.
///
/// Items are written with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
/// readable after the device unlocks once per boot (including from background
/// work), never migrated to a new device or restored from backup.
final class KeychainStore {
    static let service = "in.sudhi.native_datastore.secure"
    static let accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    // Per-type buckets so `setString("token", …)` and `setBytes("token", …)`
    // live in distinct Keychain entries.
    static let stringBucket = "__str__:"
    static let bytesBucket = "__bytes__:"
    static let typedBuckets = [stringBucket, bytesBucket]

    /// Keychain access group (`kSecAttrAccessGroup`) applied to every query.
    /// Set by `configure` so an app and its extensions/processes sharing the
    /// group see the same secrets. `nil` scopes items to this app only.
    /// Requires the "Keychain Sharing" capability enabled in Xcode.
    var accessGroup: String?

    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
                return "Keychain error \(status): \(message)"
            }
        }
    }

    /// Base query scoped to this plugin's service (and access group, when set).
    /// Every method builds on this so the access group is applied uniformly.
    private func baseQuery(account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service
        ]
        if let account { query[kSecAttrAccount as String] = account }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    func set(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessible
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = Self.accessible
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    func get(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess { throw KeychainError.status(status) }
        return result as? Data
    }

    /// Returns `true` if an item existed and was removed.
    func remove(account: String) throws -> Bool {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw KeychainError.status(status)
    }

    func clear() throws {
        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainError.status(status)
    }

    /// All Keychain account names under this service, including bucket prefixes.
    func allAccounts() throws -> [String] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        if status != errSecSuccess { throw KeychainError.status(status) }
        guard let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    func contains(account: String) throws -> Bool {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw KeychainError.status(status)
    }
}

/// Pigeon host implementation for `SecureDatastoreApi`. Owned by
/// `NativeDatastorePlugin` (the FlutterPlugin entry point); see its
/// `register(with:)` / `detachFromEngine(for:)` for lifecycle wiring.
final class SecureDatastorePlugin: NSObject, SecureDatastoreApi {
    private let keychain = KeychainStore()
    private let serialQueue = DispatchQueue(label: "native_datastore.secure.serial")

    /// Maps an internal failure to the stable code vocabulary where one
    /// applies, and otherwise leaves it alone for Pigeon's default wrapping.
    ///
    /// Without this a Keychain failure reached Dart with its own description
    /// string as `PlatformException.code` — a value no app could match and one
    /// Android had no equivalent for.
    private static func pigeonError(_ error: Error) -> Error {
        if error is NativeDatastoreError {
            return error
        }
        if let keychainError = error as? KeychainStore.KeychainError {
            return NativeDatastoreError(
                code: ErrorCode.keychain,
                message: keychainError.errorDescription,
                details: nil
            )
        }
        return error
    }

    private func onQueue<T>(
        _ completion: @escaping (Result<T, Error>) -> Void,
        body: @escaping (SecureDatastorePlugin) throws -> T
    ) {
        serialQueue.async { [weak self] in
            guard let self else {
                completion(.failure(NativeDatastoreError(
                    code: ErrorCode.detached,
                    message: "SecureDatastorePlugin is no longer attached",
                    details: nil
                )))
                return
            }
            do {
                completion(.success(try body(self)))
            } catch {
                completion(.failure(Self.pigeonError(error)))
            }
        }
    }

    // MARK: - String

    func getString(key: String, completion: @escaping (Result<String?, Error>) -> Void) {
        onQueue(completion) { plugin in
            guard let data = try plugin.keychain.get(account: KeychainStore.stringBucket + key) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
    }

    func setString(key: String, value: String, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            guard let data = value.data(using: .utf8) else {
                throw NativeDatastoreError(
                    code: ErrorCode.encoding,
                    message: "Failed to UTF-8 encode value",
                    details: nil
                )
            }
            try plugin.keychain.set(data, account: KeychainStore.stringBucket + key)
        }
    }

    // MARK: - Bytes

    func getBytes(key: String, completion: @escaping (Result<FlutterStandardTypedData?, Error>) -> Void) {
        onQueue(completion) { plugin in
            guard let data = try plugin.keychain.get(account: KeychainStore.bytesBucket + key) else {
                return nil
            }
            return FlutterStandardTypedData(bytes: data)
        }
    }

    func setBytes(key: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            try plugin.keychain.set(value.data, account: KeychainStore.bytesBucket + key)
        }
    }

    // MARK: - Lifecycle / introspection

    func remove(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            // `map` then `contains`, not `contains` alone: a user key can hold
            // both a string and a bytes entry, and `remove` has to delete both.
            // `contains` would stop at the first bucket that had something.
            try KeychainStore.typedBuckets
                .map { try plugin.keychain.remove(account: $0 + key) }
                .contains(true)
        }
    }

    func clear(completion: @escaping (Result<Void, Error>) -> Void) {
        onQueue(completion) { plugin in
            try plugin.keychain.clear()
        }
    }

    func getKeys(completion: @escaping (Result<[String], Error>) -> Void) {
        onQueue(completion) { plugin in
            let accounts = try plugin.keychain.allAccounts()
            var keys = Set<String>()
            for account in accounts {
                var realKey = account
                for bucket in KeychainStore.typedBuckets where account.hasPrefix(bucket) {
                    realKey = String(account.dropFirst(bucket.count))
                    break
                }
                keys.insert(realKey)
            }
            return Array(keys)
        }
    }

    func containsKey(key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        onQueue(completion) { plugin in
            try KeychainStore.typedBuckets.contains { bucket in
                try plugin.keychain.contains(account: bucket + key)
            }
        }
    }

    // MARK: - Configuration

    func configure(multiProcess: Bool, appGroupId: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        // `multiProcess` is an Android-only concept. On iOS, cross-process
        // sharing (e.g. with an app extension) is achieved via a Keychain
        // access group, so `appGroupId` is used as the access group here.
        onQueue(completion) { plugin in
            plugin.keychain.accessGroup = appGroupId
        }
    }
}
