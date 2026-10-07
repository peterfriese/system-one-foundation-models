import Foundation
import Security

/// Thread-safe contract for securely persisting sensitive credentials.
public protocol KeychainServiceProtocol: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String) throws
    func delete(forKey key: String) throws
}

extension KeychainServiceProtocol {
    public func string(for key: KeychainKey) -> String? { string(forKey: key.rawValue) }
    public func set(_ value: String?, for key: KeychainKey) throws { try set(value, forKey: key.rawValue) }
    public func delete(for key: KeychainKey) throws { try delete(forKey: key.rawValue) }
}

/// Errors thrown by Apple Security framework keychain operations.
public struct KeychainError: LocalizedError, Sendable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) {
            return (message as String) + " (OSStatus \(status))"
        }
        return "Keychain operation failed with status \(status)"
    }
}

/// Pure Apple Security framework implementation of `KeychainServiceProtocol`.
///
/// Uses Apple's Data Protection Keychain (`kSecUseDataProtectionKeychain = true`)
/// with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
public final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private let serviceName: String
    private let lock = NSLock()

    public init(serviceName: String = "ai.typesafe.mailtriage") {
        self.serviceName = serviceName
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else {
            return nil
        }
        return string
    }

    public func set(_ value: String?, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let value = value, !value.isEmpty else {
            try deleteLocked(forKey: key)
            return
        }

        let data = Data(value.utf8)
        let query = baseQuery(forKey: key)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        var status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if status == errSecItemNotFound {
            var addAttributes = query
            addAttributes[kSecValueData as String] = data
            addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            status = SecItemAdd(addAttributes as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            }
        }

        if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try deleteLocked(forKey: key)
    }

    private func deleteLocked(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError(status: status)
        }
    }
}

/// Deterministic in-memory keychain for testing and previews.
public final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]

    public init(initialStorage: [String: String] = [:]) {
        self.storage = initialStorage
    }

    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: String?, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let value = value, !value.isEmpty {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    public func delete(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
