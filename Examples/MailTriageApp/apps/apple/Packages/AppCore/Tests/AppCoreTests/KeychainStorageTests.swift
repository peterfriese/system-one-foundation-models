import Foundation
import SwiftUI
import Testing
import FactoryKit
@testable import AppCore

@Suite("KeychainStorage & KeychainService Protocol Tests", .serialized)
struct KeychainStorageTests {

    @Test("KeychainStorage property wrapper reads default and writes to Container keychain with KeychainKey")
    @MainActor
    func testKeychainStoragePropertyWrapperBasic() {
        let mock = MockKeychainService()
        Container.shared.keychainService.register { mock }
        defer { Container.shared.keychainService.reset() }

        struct SettingsStub {
            @KeychainStorage(.typesafeApiKey) var secret: String = "initial_default"
        }

        let stub = SettingsStub()
        #expect(stub.secret == "initial_default")

        stub.secret = "ts_live_secret_456"
        #expect(stub.secret == "ts_live_secret_456")
        #expect(mock.string(for: .typesafeApiKey) == "ts_live_secret_456")

        // Clearing to empty string removes the key
        stub.secret = ""
        #expect(stub.secret == "initial_default")
        #expect(mock.string(for: .typesafeApiKey) == nil)
    }

    @Test("KeychainStorage projectedValue provides two-way binding for SwiftUI controls")
    @MainActor
    func testKeychainStorageBinding() {
        let mock = MockKeychainService()
        Container.shared.keychainService.register { mock }
        defer { Container.shared.keychainService.reset() }

        struct FormStub {
            @KeychainStorage(.cloudflareAccountId) var cloudflareAccountId: String = ""
            @KeychainStorage(.cloudflareApiToken) var cloudflareApiToken: String = ""
        }

        let form = FormStub()
        #expect(form.cloudflareAccountId.isEmpty)
        #expect(form.cloudflareApiToken.isEmpty)

        // Simulate SwiftUI TextField / SecureField writing to $projectedValue
        let accountBinding = form.$cloudflareAccountId
        accountBinding.wrappedValue = "cf_account_abc123"

        let tokenBinding = form.$cloudflareApiToken
        tokenBinding.wrappedValue = "cf_token_xyz789"

        #expect(form.cloudflareAccountId == "cf_account_abc123")
        #expect(form.cloudflareApiToken == "cf_token_xyz789")
        #expect(mock.string(for: .cloudflareAccountId) == "cf_account_abc123")
        #expect(mock.string(for: .cloudflareApiToken) == "cf_token_xyz789")
    }

    @Test("KeychainStorage supports direct dependency injection of KeychainServiceProtocol")
    @MainActor
    func testKeychainStorageWithCustomService() {
        let customMock = MockKeychainService(initialStorage: [KeychainKey.hostedVpcToken.rawValue: "preloadedValue"])

        struct CustomStub {
            @KeychainStorage private var injected: String

            init(service: any KeychainServiceProtocol) {
                _injected = KeychainStorage(.hostedVpcToken, defaultValue: "fallback", service: service)
            }

            var value: String {
                get { injected }
                set { injected = newValue }
            }
        }

        var stub = CustomStub(service: customMock)
        #expect(stub.value == "preloadedValue")

        stub.value = "mutatedValue"
        #expect(stub.value == "mutatedValue")
        #expect(customMock.string(for: .hostedVpcToken) == "mutatedValue")
    }

    @Test("KeychainKey enum defines all required credential keys with canonical rawValues")
    func testKeychainKeyEnumCases() {
        #expect(KeychainKey.allCases.count == 6)
        #expect(KeychainKey.cloudflareAccountId.rawValue == "cloudflareAccountId")
        #expect(KeychainKey.cloudflareApiToken.rawValue == "cloudflareApiToken")
        #expect(KeychainKey.typesafeApiKey.rawValue == "typesafeApiKey")
        #expect(KeychainKey.hostedVpcToken.rawValue == "hostedVpcToken")
        #expect(KeychainKey.huggingFaceToken.rawValue == "huggingFaceToken")
        #expect(KeychainKey.openaiApiKey.rawValue == "openai_api_key")
    }

    @Test("KeychainServiceProtocol extension methods bridge typed KeychainKey to string operations")
    func testKeychainServiceProtocolExtension() throws {
        let mock = MockKeychainService()

        for key in KeychainKey.allCases {
            #expect(mock.string(for: key) == nil)
            #expect(mock.string(forKey: key.rawValue) == nil)

            let testValue = "secret_val_\(key.rawValue)"
            try mock.set(testValue, for: key)

            #expect(mock.string(for: key) == testValue)
            #expect(mock.string(forKey: key.rawValue) == testValue)

            try mock.delete(for: key)

            #expect(mock.string(for: key) == nil)
            #expect(mock.string(forKey: key.rawValue) == nil)
        }
    }
}
