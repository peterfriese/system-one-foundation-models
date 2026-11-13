import Foundation
import Observation
import FactoryKit
import SystemOneCore

/// Observable configuration manager for System One endpoints and credentials.
// Thread-safe via NSLock per AGENTS.md Principle 2
@Observable
public final class BackendConfigurationStore: @unchecked Sendable {
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let customKeychain: (any KeychainServiceProtocol)?
    @ObservationIgnored internal let environmentOverride: [String: String]?

    @ObservationIgnored private var _openaiOrganization: String
    @ObservationIgnored private var _openaiProject: String
    @ObservationIgnored private var _jevCloudURL: String
    @ObservationIgnored private var _localServeURL: String
    @ObservationIgnored private var _hostedVpcURL: String
    @ObservationIgnored private var _coreMLDownloadURL: String
    @ObservationIgnored private var _reverseProxyURL: String
    @ObservationIgnored private var _reverseProxyCredentialMode: ProxyCredentialMode
    @ObservationIgnored private var _reverseProxyHeaderName: String

    private var keychain: any KeychainServiceProtocol {
        customKeychain ?? Container.shared.keychainService()
    }

    public static let defaultJevCloudURL = "https://api.typesafe.ai/v1/systemone"
    public static let defaultLocalServeURL = "http://127.0.0.1:8000/v1/systemone"
    public static let defaultHostedVpcURL = "https://api.impossibl.com/v1/systemone"
    public static let defaultCoreMLDownloadURL = ""
    public static let defaultReverseProxyURL = ""
    public static let defaultReverseProxyHeaderName = "X-Firebase-AppCheck"

    private static let fallbackLocalServeURL: URL = {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 8000
        components.path = "/v1/systemone"
        guard let built = components.url else {
            preconditionFailure("Static fallbackLocalServeURL components must form a valid URL")
        }
        return built
    }()

    /// Normalizes System One endpoint URLs to ensure they target the `/v1/systemone` route (SEC-4).
    /// - Rejects non-HTTP/HTTPS schemes (`file://`, `javascript:`, etc.) and returns the fallback URL.
    /// - Requires HTTPS for remote network endpoints. Permissive unencrypted HTTP is restricted strictly to loopback addresses (`127.0.0.1`, `localhost`, `::1`). Remote HTTP endpoints are automatically promoted to HTTPS.
    /// - If the input ends in `/v1`, appends `/systemone`.
    /// - If the input ends in port `:8000` or root host, appends `/v1/systemone`.
    public static func normalizeSystemOneEndpoint(_ urlString: String, defaultURL: String) -> URL {
        let fallback = URL(string: defaultURL) ?? fallbackLocalServeURL
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            return fallback
        }

        let isLoopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        if scheme == "http" && !isLoopback {
            components.scheme = "https"
        }

        var path = components.path
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }

        if path.isEmpty || path == "/" {
            components.path = "/v1/systemone"
        } else if path.hasSuffix("/systemone") {
            components.path = path
        } else if path.hasSuffix("/v1") {
            components.path = path + "/systemone"
        } else {
            components.path = path + "/v1/systemone"
        }

        return components.url ?? fallback
    }

    private enum Keys {
        static let jevCloudURL = "ai.typesafe.mailtriage.jevCloudURL"
        static let localServeURL = "ai.typesafe.mailtriage.localServeURL"
        static let hostedVpcURL = "ai.typesafe.mailtriage.hostedVpcURL"
        static let coreMLDownloadURL = "ai.typesafe.mailtriage.coreMLDownloadURL"
        static let openaiOrganization = "ai.typesafe.mailtriage.openaiOrganization"
        static let openaiProject = "ai.typesafe.mailtriage.openaiProject"
        static let reverseProxyURL = "ai.typesafe.mailtriage.reverseProxyURL"
        static let reverseProxyCredentialMode = "ai.typesafe.mailtriage.reverseProxyCredentialMode"
        static let reverseProxyHeaderName = "ai.typesafe.mailtriage.reverseProxyHeaderName"
    }

    /// Returns `true` when a credential string is empty or matches common `.env.example` placeholder patterns.
    public static func isPlaceholderCredential(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("your_") || lower.contains("placeholder")
    }

    private static func sanitizeBearerCredential(_ raw: String?) -> String? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasPrefix("Bearer ") {
            trimmed = String(trimmed.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    public var openaiOrganization: String {
        get {
            access(keyPath: \.openaiOrganization)
            return lock.withLock { _openaiOrganization }
        }
        set {
            withMutation(keyPath: \.openaiOrganization) {
                lock.withLock {
                    _openaiOrganization = newValue
                    userDefaults.set(newValue, forKey: Keys.openaiOrganization)
                }
            }
        }
    }

    public var openaiProject: String {
        get {
            access(keyPath: \.openaiProject)
            return lock.withLock { _openaiProject }
        }
        set {
            withMutation(keyPath: \.openaiProject) {
                lock.withLock {
                    _openaiProject = newValue
                    userDefaults.set(newValue, forKey: Keys.openaiProject)
                }
            }
        }
    }

    public var openaiAPIKey: String {
        get {
            access(keyPath: \.openaiAPIKey)
            return lock.withLock {
                if let stored = Self.sanitizeBearerCredential(keychain.string(for: .openaiApiKey)) {
                    return stored
                }
                if !(keychain is KeychainService) && environmentOverride == nil {
                    return ""
                }
                let env = environmentOverride ?? ProcessInfo.processInfo.environment
                if let envCandidate = Self.sanitizeBearerCredential(env["OPENAI_API_KEY"]),
                   !Self.isPlaceholderCredential(envCandidate) {
                    return envCandidate
                }
                if environmentOverride == nil,
                   let dotEnvCandidate = Self.sanitizeBearerCredential(Self.loadKeyFromDotEnv("OPENAI_API_KEY")),
                   !Self.isPlaceholderCredential(dotEnvCandidate) {
                    return dotEnvCandidate
                }
                return ""
            }
        }
        set {
            withMutation(keyPath: \.openaiAPIKey) {
                lock.withLock {
                    let sanitized = Self.sanitizeBearerCredential(newValue)
                    try? keychain.set(sanitized, for: .openaiApiKey)
                }
            }
        }
    }

    public var geminiAPIKey: String {
        get {
            access(keyPath: \.geminiAPIKey)
            return lock.withLock {
                if let stored = Self.sanitizeBearerCredential(keychain.string(for: .geminiApiKey)) {
                    return stored
                }
                if !(keychain is KeychainService) && environmentOverride == nil {
                    return ""
                }
                let env = environmentOverride ?? ProcessInfo.processInfo.environment
                if let geminiEnv = Self.sanitizeBearerCredential(env["GEMINI_API_KEY"]),
                   !Self.isPlaceholderCredential(geminiEnv) {
                    return geminiEnv
                }
                if let googleEnv = Self.sanitizeBearerCredential(env["GOOGLE_API_KEY"]),
                   !Self.isPlaceholderCredential(googleEnv) {
                    return googleEnv
                }
                if environmentOverride == nil,
                   let dotEnvCandidate = Self.sanitizeBearerCredential(
                       Self.loadKeyFromDotEnv("GEMINI_API_KEY") ?? Self.loadKeyFromDotEnv("GOOGLE_API_KEY")
                   ),
                   !Self.isPlaceholderCredential(dotEnvCandidate) {
                    return dotEnvCandidate
                }
                return ""
            }
        }
        set {
            withMutation(keyPath: \.geminiAPIKey) {
                lock.withLock {
                    let sanitized = Self.sanitizeBearerCredential(newValue)
                    try? keychain.set(sanitized, for: .geminiApiKey)
                }
            }
        }
    }

    public var jevCloudURL: String {
        get {
            access(keyPath: \.jevCloudURL)
            return lock.withLock { _jevCloudURL }
        }
        set {
            withMutation(keyPath: \.jevCloudURL) {
                lock.withLock {
                    _jevCloudURL = newValue
                    userDefaults.set(newValue, forKey: Keys.jevCloudURL)
                }
            }
        }
    }

    public var localServeURL: String {
        get {
            access(keyPath: \.localServeURL)
            return lock.withLock { _localServeURL }
        }
        set {
            withMutation(keyPath: \.localServeURL) {
                lock.withLock {
                    _localServeURL = newValue
                    userDefaults.set(newValue, forKey: Keys.localServeURL)
                }
            }
        }
    }

    public var hostedVpcURL: String {
        get {
            access(keyPath: \.hostedVpcURL)
            return lock.withLock { _hostedVpcURL }
        }
        set {
            withMutation(keyPath: \.hostedVpcURL) {
                lock.withLock {
                    _hostedVpcURL = newValue
                    userDefaults.set(newValue, forKey: Keys.hostedVpcURL)
                }
            }
        }
    }

    public var coreMLDownloadURL: String {
        get {
            access(keyPath: \.coreMLDownloadURL)
            return lock.withLock { _coreMLDownloadURL }
        }
        set {
            withMutation(keyPath: \.coreMLDownloadURL) {
                lock.withLock {
                    _coreMLDownloadURL = newValue
                    userDefaults.set(newValue, forKey: Keys.coreMLDownloadURL)
                }
            }
        }
    }

    public var typesafeApiKey: String {
        get {
            access(keyPath: \.typesafeApiKey)
            return lock.withLock {
                if !(keychain is KeychainService) && environmentOverride == nil {
                    return keychain.string(for: .typesafeApiKey) ?? ""
                }
                let env = environmentOverride ?? ProcessInfo.processInfo.environment
                if let envKey = env["TYPESAFE_API_KEY"],
                   !Self.isPlaceholderCredential(envKey) {
                    try? keychain.set(envKey, for: .typesafeApiKey)
                    return envKey
                }
                let key = keychain.string(for: .typesafeApiKey) ?? ""
                if !key.isEmpty { return key }
                if environmentOverride == nil,
                   let dotEnvKey = Self.loadKeyFromDotEnv("TYPESAFE_API_KEY"),
                   !Self.isPlaceholderCredential(dotEnvKey) {
                    try? keychain.set(dotEnvKey, for: .typesafeApiKey)
                    return dotEnvKey
                }
                return ""
            }
        }
        set {
            withMutation(keyPath: \.typesafeApiKey) {
                lock.withLock {
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? keychain.set(trimmed.isEmpty ? nil : trimmed, for: .typesafeApiKey)
                }
            }
        }
    }

    /// In DEBUG builds, attempts to load a key from a `.env` file located in the bundle or current working directory (SEC-2).
    /// Never crawls parent directories or references `#filePath` to avoid path leakage into compiled binaries
    /// and sandbox violations. In non-DEBUG builds, returns `nil`.
    public static func loadKeyFromDotEnv(_ key: String) -> String? {
        #if DEBUG
        var candidateURLs: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        ]
        if let resourceURL = Bundle.main.resourceURL {
            candidateURLs.append(resourceURL.appendingPathComponent(".env"))
        }

        for dotEnvURL in candidateURLs {
            if FileManager.default.fileExists(atPath: dotEnvURL.path) {
                if let value = parseDotEnvFile(at: dotEnvURL, key: key) {
                    return value
                }
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    /// Parses a `.env` file at the specified URL for a given key.
    public static func parseDotEnvFile(at url: URL, key: String) -> String? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        return parseDotEnvContent(content, key: key)
    }

    /// Parses the content of a `.env` file for a given key (`KEY=VALUE` or `KEY="VALUE"` or `KEY='VALUE'`).
    public static func parseDotEnvContent(_ content: String, key: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let equalsIndex = line.firstIndex(of: "=") else {
                continue
            }
            let lineKey = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            guard lineKey == key else {
                continue
            }
            var val = String(line[line.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            if (val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2) ||
               (val.hasPrefix("'") && val.hasSuffix("'") && val.count >= 2) {
                val = String(val.dropFirst().dropLast())
            }
            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if !Self.isPlaceholderCredential(trimmed) {
                return trimmed
            }
        }
        return nil
    }

    public var hostedVpcToken: String {
        get {
            access(keyPath: \.hostedVpcToken)
            return lock.withLock { keychain.string(for: .hostedVpcToken) ?? "" }
        }
        set {
            withMutation(keyPath: \.hostedVpcToken) {
                lock.withLock {
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? keychain.set(trimmed.isEmpty ? nil : trimmed, for: .hostedVpcToken)
                }
            }
        }
    }

    public var huggingFaceToken: String {
        get {
            access(keyPath: \.huggingFaceToken)
            return lock.withLock { keychain.string(for: .huggingFaceToken) ?? "" }
        }
        set {
            withMutation(keyPath: \.huggingFaceToken) {
                lock.withLock {
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? keychain.set(trimmed.isEmpty ? nil : trimmed, for: .huggingFaceToken)
                }
            }
        }
    }

    public var cloudflareAccountId: String {
        get {
            access(keyPath: \.cloudflareAccountId)
            return lock.withLock {
                if let key = keychain.string(for: .cloudflareAccountId), !key.isEmpty {
                    return key
                }
                if !(keychain is KeychainService) && environmentOverride == nil {
                    return ""
                }
                let env = environmentOverride ?? ProcessInfo.processInfo.environment
                if let envKey = env["CLOUDFLARE_ACCOUNT_ID"], !Self.isPlaceholderCredential(envKey) {
                    return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if environmentOverride == nil,
                   let dotEnvKey = Self.loadKeyFromDotEnv("CLOUDFLARE_ACCOUNT_ID"),
                   !Self.isPlaceholderCredential(dotEnvKey) {
                    return dotEnvKey
                }
                return ""
            }
        }
        set {
            withMutation(keyPath: \.cloudflareAccountId) {
                lock.withLock {
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? keychain.set(trimmed.isEmpty ? nil : trimmed, for: .cloudflareAccountId)
                }
            }
        }
    }

    public var cloudflareApiToken: String {
        get {
            access(keyPath: \.cloudflareApiToken)
            return lock.withLock {
                if let key = keychain.string(for: .cloudflareApiToken), !key.isEmpty {
                    return key
                }
                if !(keychain is KeychainService) && environmentOverride == nil {
                    return ""
                }
                let env = environmentOverride ?? ProcessInfo.processInfo.environment
                if let envKey = env["CLOUDFLARE_API_TOKEN"], !Self.isPlaceholderCredential(envKey) {
                    return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if environmentOverride == nil,
                   let dotEnvKey = Self.loadKeyFromDotEnv("CLOUDFLARE_API_TOKEN"),
                   !Self.isPlaceholderCredential(dotEnvKey) {
                    return dotEnvKey
                }
                return ""
            }
        }
        set {
            withMutation(keyPath: \.cloudflareApiToken) {
                lock.withLock {
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? keychain.set(trimmed.isEmpty ? nil : trimmed, for: .cloudflareApiToken)
                }
            }
        }
    }

    public convenience init(userDefaults: UserDefaults = .standard, keychain: (any KeychainServiceProtocol)? = nil) {
        self.init(userDefaults: userDefaults, keychain: keychain, environmentOverride: nil)
    }

    internal init(
        userDefaults: UserDefaults = .standard,
        keychain: (any KeychainServiceProtocol)? = nil,
        environmentOverride: [String: String]?
    ) {
        self.userDefaults = userDefaults
        self.customKeychain = keychain
        self.environmentOverride = environmentOverride
        self._jevCloudURL = userDefaults.string(forKey: Keys.jevCloudURL) ?? Self.defaultJevCloudURL

        // Migration and normalization for local serve URL
        let storedLocal = userDefaults.string(forKey: Keys.localServeURL)
        if storedLocal == "http://127.0.0.1:8000/v1" || storedLocal == "http://127.0.0.1:8000" {
            self._localServeURL = Self.defaultLocalServeURL
            userDefaults.set(Self.defaultLocalServeURL, forKey: Keys.localServeURL)
        } else if let storedLocal, !storedLocal.isEmpty {
            let normalized = Self.normalizeSystemOneEndpoint(storedLocal, defaultURL: Self.defaultLocalServeURL).absoluteString
            self._localServeURL = normalized
            if normalized != storedLocal {
                userDefaults.set(normalized, forKey: Keys.localServeURL)
            }
        } else {
            self._localServeURL = Self.defaultLocalServeURL
        }

        // Migration and normalization for hosted VPC URL
        let storedVPC = userDefaults.string(forKey: Keys.hostedVpcURL)
        if storedVPC == "https://api.impossibl.com/v1" || storedVPC == "https://api.impossibl.com" {
            self._hostedVpcURL = Self.defaultHostedVpcURL
            userDefaults.set(Self.defaultHostedVpcURL, forKey: Keys.hostedVpcURL)
        } else if let storedVPC, !storedVPC.isEmpty {
            let normalized = Self.normalizeSystemOneEndpoint(storedVPC, defaultURL: Self.defaultHostedVpcURL).absoluteString
            self._hostedVpcURL = normalized
            if normalized != storedVPC {
                userDefaults.set(normalized, forKey: Keys.hostedVpcURL)
            }
        } else {
            self._hostedVpcURL = Self.defaultHostedVpcURL
        }

        let storedCoreML = userDefaults.string(forKey: Keys.coreMLDownloadURL)
        if let storedCoreML,
           !storedCoreML.contains("typesafe/laya-421m-coreml"),
           !storedCoreML.contains("LayaModernBERT.mlmodelc.zip"),
           !storedCoreML.contains("aac6fef/laya-mlx"),
           !storedCoreML.lowercased().hasSuffix(".safetensors") {
            self._coreMLDownloadURL = storedCoreML
        } else {
            self._coreMLDownloadURL = Self.defaultCoreMLDownloadURL
            if storedCoreML != nil {
                userDefaults.set(Self.defaultCoreMLDownloadURL, forKey: Keys.coreMLDownloadURL)
            }
        }

        self._openaiOrganization = userDefaults.string(forKey: Keys.openaiOrganization) ?? ""
        self._openaiProject = userDefaults.string(forKey: Keys.openaiProject) ?? ""
        self._reverseProxyURL = userDefaults.string(forKey: Keys.reverseProxyURL) ?? Self.defaultReverseProxyURL
        if let rawMode = userDefaults.string(forKey: Keys.reverseProxyCredentialMode),
           let parsedMode = ProxyCredentialMode(rawValue: rawMode) {
            self._reverseProxyCredentialMode = parsedMode
        } else {
            self._reverseProxyCredentialMode = .bearer
        }
        self._reverseProxyHeaderName = userDefaults.string(forKey: Keys.reverseProxyHeaderName) ?? Self.defaultReverseProxyHeaderName
    }

    public var reverseProxyURL: String {
        get {
            access(keyPath: \.reverseProxyURL)
            return lock.withLock {
                let stored = _reverseProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stored.isEmpty {
                    return stored
                }
                if !(keychain is KeychainService) && environmentOverride == nil {
                    return ""
                }
                let env = environmentOverride ?? ProcessInfo.processInfo.environment
                for envKey in ["SYSTEM_ONE_PROXY_URL", "TYPESAFE_PROXY_URL"] {
                    if let candidate = env[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !Self.isPlaceholderCredential(candidate) {
                        return candidate
                    }
                }
                if environmentOverride == nil,
                   let dotEnvCandidate = (Self.loadKeyFromDotEnv("SYSTEM_ONE_PROXY_URL") ?? Self.loadKeyFromDotEnv("TYPESAFE_PROXY_URL"))?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !Self.isPlaceholderCredential(dotEnvCandidate) {
                    return dotEnvCandidate
                }
                return ""
            }
        }
        set {
            withMutation(keyPath: \.reverseProxyURL) {
                lock.withLock {
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    _reverseProxyURL = trimmed
                    userDefaults.set(trimmed, forKey: Keys.reverseProxyURL)
                }
            }
        }
    }

    public var reverseProxyCredentialMode: ProxyCredentialMode {
        get {
            access(keyPath: \.reverseProxyCredentialMode)
            return lock.withLock { _reverseProxyCredentialMode }
        }
        set {
            withMutation(keyPath: \.reverseProxyCredentialMode) {
                lock.withLock {
                    _reverseProxyCredentialMode = newValue
                    userDefaults.set(newValue.rawValue, forKey: Keys.reverseProxyCredentialMode)
                }
            }
        }
    }

    public var reverseProxyHeaderName: String {
        get {
            access(keyPath: \.reverseProxyHeaderName)
            return lock.withLock { _reverseProxyHeaderName }
        }
        set {
            withMutation(keyPath: \.reverseProxyHeaderName) {
                lock.withLock {
                    _reverseProxyHeaderName = newValue
                    userDefaults.set(newValue, forKey: Keys.reverseProxyHeaderName)
                }
            }
        }
    }

    public var reverseProxyToken: String {
        get {
            access(keyPath: \.reverseProxyToken)
            return lock.withLock {
                if let stored = Self.sanitizeBearerCredential(keychain.string(for: .reverseProxyToken)) {
                    return stored
                }
                if !(keychain is KeychainService) && environmentOverride == nil {
                    return ""
                }
                let env = environmentOverride ?? ProcessInfo.processInfo.environment
                for envKey in ["SYSTEM_ONE_PROXY_TOKEN", "TYPESAFE_PROXY_TOKEN"] {
                    if let candidate = Self.sanitizeBearerCredential(env[envKey]),
                       !Self.isPlaceholderCredential(candidate) {
                        return candidate
                    }
                }
                if environmentOverride == nil,
                   let dotEnvCandidate = Self.sanitizeBearerCredential(
                       Self.loadKeyFromDotEnv("SYSTEM_ONE_PROXY_TOKEN") ?? Self.loadKeyFromDotEnv("TYPESAFE_PROXY_TOKEN")
                   ),
                   !Self.isPlaceholderCredential(dotEnvCandidate) {
                    return dotEnvCandidate
                }
                return ""
            }
        }
        set {
            withMutation(keyPath: \.reverseProxyToken) {
                lock.withLock {
                    let sanitized = Self.sanitizeBearerCredential(newValue)
                    try? keychain.set(sanitized, for: .reverseProxyToken)
                }
            }
        }
    }

    /// Builds a `SystemOneCore.ProxyCredential` reflecting the configured proxy credential mode, header, and optional token.
    public func makeProxyCredential(tokenOverride: String? = nil) -> ProxyCredential {
        let resolvedToken = Self.sanitizeBearerCredential(tokenOverride)
            ?? {
                let storedOrEnv = self.reverseProxyToken
                return storedOrEnv.isEmpty ? nil : storedOrEnv
            }()

        guard let token = resolvedToken, !token.isEmpty else {
            return .custom { _ in }
        }

        switch reverseProxyCredentialMode {
        case .bearer:
            return .bearer { token }
        case .appCheck:
            let trimmedHeader = reverseProxyHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveHeader = trimmedHeader.isEmpty ? Self.defaultReverseProxyHeaderName : trimmedHeader
            return .appCheck(headerName: effectiveHeader) { token }
        }
    }

    public func resetToDefaults() {
        jevCloudURL = Self.defaultJevCloudURL
        localServeURL = Self.defaultLocalServeURL
        hostedVpcURL = Self.defaultHostedVpcURL
        coreMLDownloadURL = Self.defaultCoreMLDownloadURL
        reverseProxyURL = Self.defaultReverseProxyURL
        reverseProxyCredentialMode = .bearer
        reverseProxyHeaderName = Self.defaultReverseProxyHeaderName
        typesafeApiKey = ""
        hostedVpcToken = ""
        huggingFaceToken = ""
        cloudflareAccountId = ""
        cloudflareApiToken = ""
        openaiOrganization = ""
        openaiProject = ""
        openaiAPIKey = ""
        geminiAPIKey = ""
        reverseProxyToken = ""
    }
}
