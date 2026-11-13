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

    /// Convenience access for the stored OpenAI API Key (`openai_api_key`).
    public var openaiAPIKey: String? {
        get { string(for: .openaiApiKey) }
        set { try? set(newValue, for: .openaiApiKey) }
    }

    /// Convenience access for the stored Google Gemini API Key (`gemini_api_key`).
    public var geminiAPIKey: String? {
        get { string(for: .geminiApiKey) }
        set { try? set(newValue, for: .geminiApiKey) }
    }

    /// Convenience access for the stored Authenticated Proxy Token (`reverse_proxy_token`).
    public var reverseProxyToken: String? {
        get { string(for: .reverseProxyToken) }
        set { try? set(newValue, for: .reverseProxyToken) }
    }
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
    /// Process-local fallback storage used only when the host executable is unsigned
    /// and lacks the macOS Data Protection Keychain entitlement (`errSecMissingEntitlement` / `-34018`),
    /// such as during `swift test` or `swift run BenchmarkCLI`.
    private var unentitledFallbackStorage: [String: String] = [:]

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
            return unentitledFallbackStorage[key]
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

        if status == errSecMissingEntitlement {
            unentitledFallbackStorage[key] = value
            return
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
        unentitledFallbackStorage.removeValue(forKey: key)
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecMissingEntitlement {
            return
        }
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError(status: status)
        }
    }
}
