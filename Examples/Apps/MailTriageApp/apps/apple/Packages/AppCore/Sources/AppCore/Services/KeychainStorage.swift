import SwiftUI
import FactoryKit

/// A property wrapper type that reflects a value in the Keychain
/// and invalidates a view on a change in value in that storage.
///
/// Modeled on `@AppStorage`, it provides seamless two-way binding for SwiftUI views
/// while persisting secrets securely via `KeychainServiceProtocol`.
///
/// Direct SwiftUI Usage:
/// ```swift
/// @KeychainStorage(.cloudflareAccountId) var cloudflareAccountId: String = ""
/// @KeychainStorage(.cloudflareApiToken) var cloudflareApiToken: String = ""
///
/// TextField("Account ID", text: $cloudflareAccountId)
/// SecureField("Workers AI Token", text: $cloudflareApiToken)
/// ```
@propertyWrapper
public struct KeychainStorage: DynamicProperty, Sendable {
    private let key: String
    private let defaultValue: String
    private let service: any KeychainServiceProtocol
    @State private var value: String

    public init(
        wrappedValue: String = "",
        _ key: String,
        service: (any KeychainServiceProtocol)? = nil
    ) {
        self.key = key
        self.defaultValue = wrappedValue
        let resolved = service ?? Container.shared.keychainService()
        self.service = resolved
        let initial = resolved.string(forKey: key) ?? wrappedValue
        self._value = State(initialValue: initial)
    }

    public init(
        _ key: String,
        defaultValue: String = "",
        service: (any KeychainServiceProtocol)? = nil
    ) {
        self.init(wrappedValue: defaultValue, key, service: service)
    }

    public init(
        wrappedValue: String = "",
        _ key: KeychainKey,
        service: (any KeychainServiceProtocol)? = nil
    ) {
        self.init(wrappedValue: wrappedValue, key.rawValue, service: service)
    }

    public init(
        _ key: KeychainKey,
        defaultValue: String = "",
        service: (any KeychainServiceProtocol)? = nil
    ) {
        self.init(wrappedValue: defaultValue, key.rawValue, service: service)
    }

    public var wrappedValue: String {
        get {
            service.string(forKey: key) ?? defaultValue
        }
        nonmutating set {
            value = newValue
            do {
                if newValue.isEmpty {
                    try service.delete(forKey: key)
                } else {
                    try service.set(newValue, forKey: key)
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
