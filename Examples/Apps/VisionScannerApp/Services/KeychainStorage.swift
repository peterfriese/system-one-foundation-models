import SwiftUI
import Security

/// Thread-safe keychain helper for storing sensitive credentials securely in the Apple Keychain.
///
/// Automatically handles unentitled macOS CLI executions (e.g. `swift run vision-scanner-app`)
/// where `kSecUseDataProtectionKeychain` returns `errSecMissingEntitlement` (`-34018`) by falling
/// back to the standard macOS login keychain (and in-memory session storage if Keychain access
/// is unavailable in a headless session) without failing on every keystroke.
public final class KeychainHelper: @unchecked Sendable {
    private static let lock = NSLock()
    private static let serviceName = "ai.typesafe.visionscanner"
    private static let legacyServiceName = "ai.typesafe.clefcamerascanner"
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    nonisolated(unsafe) private static var dataProtectionSupported: Bool = {
        #if os(macOS)
        // Bare SwiftPM executables (`swift run`) lack an app bundle and keychain-access-groups entitlement.
        return Bundle.main.bundleURL.pathExtension == "app"
        #else
        return true
        #endif
    }()
    nonisolated(unsafe) private static var keychainUnavailableLogged = false

    private static func baseQuery(
        forKey key: String,
        service: String = serviceName,
        useDataProtection: Bool
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    public static func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key] {
            return cached
        }

        if let value = readFromKeychain(forKey: key, service: serviceName, useDataProtection: dataProtectionSupported)
            ?? readFromKeychain(forKey: key, service: legacyServiceName, useDataProtection: dataProtectionSupported) {
            cache[key] = value
            return value
        }

        return nil
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

        let status = writeToKeychain(data: data, forKey: key, useDataProtection: dataProtectionSupported)
        if status == errSecSuccess {
            return
        }

        #if os(macOS)
        if status == errSecMissingEntitlement && dataProtectionSupported {
            dataProtectionSupported = false
            let fallbackStatus = writeToKeychain(data: data, forKey: key, useDataProtection: false)
            if fallbackStatus == errSecSuccess {
                return
            }
            if isUnentitledOrHeadlessKeychainStatus(fallbackStatus) {
                logSessionFallbackOnce(status: fallbackStatus)
                return
            }
            throw keychainError(operation: "SecItemSave", status: fallbackStatus)
        }
        #endif

        if isUnentitledOrHeadlessKeychainStatus(status) {
            logSessionFallbackOnce(status: status)
            return
        }

        throw keychainError(operation: "SecItemSave", status: status)
    }

    public static func delete(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try deleteItem(forKey: key)
    }

    // MARK: - Internal Locked Helpers

    private static func readFromKeychain(
        forKey key: String,
        service: String = serviceName,
        useDataProtection: Bool
    ) -> String? {
        var query = baseQuery(forKey: key, service: service, useDataProtection: useDataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        #if os(macOS)
        if status == errSecMissingEntitlement && useDataProtection {
            dataProtectionSupported = false
            return readFromKeychain(forKey: key, service: service, useDataProtection: false)
        }
        #endif

        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func writeToKeychain(data: Data, forKey key: String, useDataProtection: Bool) -> OSStatus {
        let query = baseQuery(forKey: key, useDataProtection: useDataProtection)
        var updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]
        if useDataProtection {
            updateAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }

        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            if useDataProtection {
                newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            return SecItemAdd(newQuery as CFDictionary, nil)
        }
        return status
    }

    private static func deleteItem(forKey key: String) throws {
        cache.removeValue(forKey: key)
        let query = baseQuery(forKey: key, useDataProtection: dataProtectionSupported)
        var status = SecItemDelete(query as CFDictionary)

        #if os(macOS)
        if status == errSecMissingEntitlement && dataProtectionSupported {
            dataProtectionSupported = false
            let fallbackQuery = baseQuery(forKey: key, useDataProtection: false)
            status = SecItemDelete(fallbackQuery as CFDictionary)
        }
        #endif

        if status == errSecSuccess || status == errSecItemNotFound || isUnentitledOrHeadlessKeychainStatus(status) {
            return
        }

        throw keychainError(operation: "SecItemDelete", status: status)
    }

    private static func isUnentitledOrHeadlessKeychainStatus(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement
            || status == errSecInteractionNotAllowed
            || status == errSecNotAvailable
    }

    private static func logSessionFallbackOnce(status: OSStatus) {
        guard !keychainUnavailableLogged else { return }
        keychainUnavailableLogged = true
        print("ℹ️ [KeychainStorage] Keychain persistence unavailable in unentitled/headless session (OSStatus \(status)); holding credential in session memory only.")
    }

    private static func keychainError(operation: String, status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "\(operation) failed with status \(status)"
        ])
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
