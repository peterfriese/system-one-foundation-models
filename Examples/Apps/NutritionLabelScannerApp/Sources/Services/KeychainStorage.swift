import SwiftUI
import Security

/// Thread-safe Keychain helper for storing API tokens in NutritionLabelScannerApp.
public final class NutritionKeychainHelper: @unchecked Sendable {
    private static let lock = NSLock()
    private static let serviceName = "com.typesafe.examples.NutritionLabelScanner"
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

    public static func set(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let value, !value.isEmpty else {
            cache.removeValue(forKey: key)
            let query = baseQuery(forKey: key)
            _ = SecItemDelete(query as CFDictionary)
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
            _ = SecItemAdd(newQuery as CFDictionary, nil)
        }
    }
}

/// Property wrapper providing two-way SwiftUI binding backed by `NutritionKeychainHelper`.
@propertyWrapper
public struct KeychainStorage: DynamicProperty, Sendable {
    private let key: String
    @State private var value: String

    public init(wrappedValue: String = "", _ key: String) {
        self.key = key
        let initial = NutritionKeychainHelper.string(forKey: key) ?? wrappedValue
        self._value = State(initialValue: initial)
    }

    public var wrappedValue: String {
        get { value }
        nonmutating set {
            value = newValue
            NutritionKeychainHelper.set(newValue.isEmpty ? nil : newValue, forKey: key)
        }
    }

    public var projectedValue: Binding<String> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}
