import SwiftUI
import Security

/// Thread-safe keychain helper for storing sensitive credentials securely in the Apple Keychain.
public final class KeychainHelper: @unchecked Sendable {
    private static let lock = NSLock()
    private static let serviceName = "ai.typesafe.clefcamerascanner"
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    public static func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key] {
            return cached
        }

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
        cache[key] = string
        return string
    }

    public static func set(_ value: String?, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let value, !value.isEmpty else {
            try deleteItem(forKey: key)
            return
        }

        cache[key] = value

        let data = Data(value.utf8)
        let query = baseQuery(forKey: key)

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus), userInfo: [
                    NSLocalizedDescriptionKey: "SecItemAdd failed with status \(addStatus)"
                ])
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "SecItemUpdate failed with status \(status)"
            ])
        }
    }

    public static func delete(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try deleteItem(forKey: key)
    }

    private static func deleteItem(forKey key: String) throws {
        cache.removeValue(forKey: key)
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "SecItemDelete failed with status \(status)"
            ])
        }
    }
}

/// A property wrapper type that reflects a value stored in the Keychain
/// and provides two-way binding for SwiftUI views while persisting secrets securely.
@propertyWrapper
public struct KeychainStorage: DynamicProperty, Sendable {
    private let key: String
    private let defaultValue: String
    @State private var value: String

    public init(wrappedValue: String = "", _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
        let initial = KeychainHelper.string(forKey: key) ?? wrappedValue
        self._value = State(initialValue: initial)
    }

    public var wrappedValue: String {
        get {
            value
        }
        nonmutating set {
            value = newValue
            do {
                if newValue.isEmpty {
                    try KeychainHelper.delete(forKey: key)
                } else {
                    try KeychainHelper.set(newValue, forKey: key)
                }
            } catch {
                print("⚠️ [KeychainStorage] Failed to persist key '\(key)': \(error.localizedDescription)")
            }
        }
    }

    public var projectedValue: Binding<String> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}
