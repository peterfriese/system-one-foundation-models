import Foundation
import FoundationModels
import SystemOneCore
import LayaOnDevice
import LayaFoundationModels
import JevFoundationModels
import ClefFoundationModels
import OpenAIFoundationModels
import GeminiFoundationModels

// MARK: - Typed Multi-Provider Configuration Error (Principle 7: Fail-Fast Remediation)

public enum NutritionProviderConfigurationError: LocalizedError, Sendable {
    case missingLayaOnDeviceModel(String)
    case invalidLayaServeURL(String)
    case missingJevAPIKey
    case missingClefCredentials
    case missingOpenAIAPIKey
    case missingGeminiAPIKey
    case missingReverseProxyURL
    case invalidReverseProxyURL(String)

    public var errorDescription: String? {
        switch self {
        case .missingLayaOnDeviceModel(let detail):
            return """
            On-Device Laya Core ML model not configured (\(detail)). \
            Import a compiled LayaDecisionModel.mlmodelc in Provider Settings or set LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc".
            """
        case .invalidLayaServeURL(let raw):
            return """
            Invalid Laya server URL ('\(raw)'). Start `laya-serve` and set LAYA_SERVE_URL="http://127.0.0.1:8000" \
            (or configure the endpoint in Provider Settings).
            """
        case .missingJevAPIKey:
            return """
            Missing TypeSafe Jev API key. Enter your key in Provider Settings, pass `-TYPESAFE_API_KEY <key>`, \
            or `export TYPESAFE_API_KEY="ts-..."` (or switch to Authenticated Reverse Proxy).
            """
        case .missingClefCredentials:
            return """
            Missing Cloudflare Clef configuration. Enter your Account ID and API Token in Provider Settings, \
            `export CLOUDFLARE_ACCOUNT_ID="..." CLOUDFLARE_API_TOKEN="..."`, or set `CLEF_LOCAL_PORT=8000`.
            """
        case .missingOpenAIAPIKey:
            return """
            Missing OpenAI API key for OpenAI Decisions (gpt-6-luna). Enter your key in Provider Settings \
            or `export OPENAI_API_KEY="sk-..."`.
            """
        case .missingGeminiAPIKey:
            return """
            Missing Gemini API key for Google Gemini Decisions (gemini-decision-1). Enter your key in Provider Settings \
            or `export GEMINI_API_KEY="AIza..."` (or `GOOGLE_API_KEY`).
            """
        case .missingReverseProxyURL:
            return """
            Missing Reverse Proxy URL. Enter an HTTPS gateway URL in Provider Settings or \
            `export SYSTEM_ONE_PROXY_URL="https://..."` (or `TYPESAFE_PROXY_URL`).
            """
        case .invalidReverseProxyURL(let detail):
            return detail
        }
    }
}

// MARK: - All 7 System One Provider Modes

public enum NutritionScannerProvider: String, CaseIterable, Identifiable, Sendable {
    case layaOnDevice = "laya-on-device"
    case layaServe = "laya-serve"
    case jevCloud = "jev-cloud"
    case clef = "cloudflare-clef"
    case openAI = "openai-decisions"
    case gemini = "gemini-decisions"
    case reverseProxy = "reverse-proxy"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .layaOnDevice: return "On-Device Laya Core ML (Offline)"
        case .layaServe: return "Local Laya Server (laya-serve)"
        case .jevCloud: return "TypeSafe Jev Cloud"
        case .clef: return "Cloudflare Clef"
        case .openAI: return "OpenAI Decisions (gpt-6-luna)"
        case .gemini: return "Google Gemini Decisions (gemini-decision-1)"
        case .reverseProxy: return "Authenticated Reverse Proxy"
        }
    }

    public var shortName: String {
        switch self {
        case .layaOnDevice: return "Laya Core ML"
        case .layaServe: return "Laya Server"
        case .jevCloud: return "Jev Cloud"
        case .clef: return "Cloudflare Clef"
        case .openAI: return "OpenAI Luna"
        case .gemini: return "Gemini Decision"
        case .reverseProxy: return "Reverse Proxy"
        }
    }

    public var systemImageName: String {
        switch self {
        case .layaOnDevice: return "cpu.fill"
        case .layaServe: return "server.rack"
        case .jevCloud: return "bolt.shield.fill"
        case .clef: return "bolt.horizontal.icloud.fill"
        case .openAI: return "sparkles"
        case .gemini: return "wand.and.stars"
        case .reverseProxy: return "lock.shield.fill"
        }
    }

    /// Whether this provider accepts multimodal image `Attachment`s alongside text state.
    public var effectiveSupportsVision: Bool {
        switch self {
        case .layaOnDevice, .layaServe, .jevCloud:
            return false
        case .clef, .openAI, .gemini:
            return true
        case .reverseProxy:
            if UserDefaults.standard.object(forKey: "nutritionProxySupportsVision") != nil {
                return UserDefaults.standard.bool(forKey: "nutritionProxySupportsVision")
            }
            if let env = Self.trimmedNonEmpty(ProcessInfo.processInfo.environment["SYSTEM_ONE_PROXY_VISION"])?.lowercased() {
                return env != "false" && env != "0"
            }
            return true
        }
    }

    /// Auto-selects the first configured provider on launch from CLI flags, Keychain/AppStorage, or environment variables.
    public static var autoDetectedDefault: NutritionScannerProvider {
        if let rawOverride = resolveSetting(
            appStorageKey: nil,
            envKeys: ["SYSTEM_ONE_PROVIDER"],
            flags: ["--provider", "-PROVIDER", "-SYSTEM_ONE_PROVIDER"]
        ), let matched = matchProvider(rawOverride) {
            return matched
        }

        if resolveSetting(
            appStorageKey: "nutritionProxyURL",
            envKeys: ["SYSTEM_ONE_PROXY_URL", "TYPESAFE_PROXY_URL"],
            flags: ["--proxy-url", "-SYSTEM_ONE_PROXY_URL", "-TYPESAFE_PROXY_URL"]
        ) != nil {
            return .reverseProxy
        }

        if hasConfiguredOnDeviceLayaModel() {
            return .layaOnDevice
        }

        if resolveSetting(
            appStorageKey: nil,
            envKeys: ["LAYA_SERVE_URL", "LAYA_ENDPOINT"],
            flags: ["--laya-url", "-LAYA_SERVE_URL", "-LAYA_ENDPOINT"]
        ) != nil {
            return .layaServe
        }

        if resolveSecret(
            keychainKey: "typesafeAPIKey",
            envKeys: ["TYPESAFE_API_KEY"],
            flags: ["--api-key", "-TYPESAFE_API_KEY"]
        ) != nil {
            return .jevCloud
        }

        if (resolveSetting(appStorageKey: "cloudflareAccountID", envKeys: ["CLOUDFLARE_ACCOUNT_ID"], flags: []) != nil &&
            resolveSecret(keychainKey: "cloudflareAPIToken", envKeys: ["CLOUDFLARE_API_TOKEN"], flags: []) != nil) ||
            resolveSetting(appStorageKey: nil, envKeys: ["CLEF_ENDPOINT", "CLEF_LOCAL_PORT"], flags: []) != nil {
            return .clef
        }

        if resolveSecret(
            keychainKey: "openAIAPIKey",
            envKeys: ["OPENAI_API_KEY"],
            flags: ["-OPENAI_API_KEY"]
        ) != nil {
            return .openAI
        }

        if resolveSecret(
            keychainKey: "geminiAPIKey",
            envKeys: ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
            flags: ["-GEMINI_API_KEY", "-GOOGLE_API_KEY"]
        ) != nil {
            return .gemini
        }

        if let savedRaw = trimmedNonEmpty(UserDefaults.standard.string(forKey: "selectedNutritionProvider")),
           let saved = NutritionScannerProvider(rawValue: savedRaw) {
            return saved
        }

        return .jevCloud
    }

    /// Instantiates a configured `any LanguageModel` for this provider, failing fast with
    /// `NutritionProviderConfigurationError` whenever required credentials or model files are absent.
    public func resolveConfiguredModel() throws -> any LanguageModel {
        switch self {
        case .layaOnDevice:
            return try makeLayaOnDeviceModel()
        case .layaServe:
            return try makeLayaServeModel()
        case .jevCloud:
            guard let apiKey = Self.resolveSecret(
                keychainKey: "typesafeAPIKey",
                envKeys: ["TYPESAFE_API_KEY"],
                flags: ["--api-key", "-apiKey", "-TYPESAFE_API_KEY", "-key"]
            ) else {
                throw NutritionProviderConfigurationError.missingJevAPIKey
            }
            return JevLanguageModel(apiKey: apiKey)
        case .clef:
            return try makeClefModel()
        case .openAI:
            guard let apiKey = Self.resolveSecret(
                keychainKey: "openAIAPIKey",
                envKeys: ["OPENAI_API_KEY"],
                flags: ["-OPENAI_API_KEY"]
            ) else {
                throw NutritionProviderConfigurationError.missingOpenAIAPIKey
            }
            return OpenAIDecisionsLanguageModel(apiKey: apiKey)
        case .gemini:
            guard let apiKey = Self.resolveSecret(
                keychainKey: "geminiAPIKey",
                envKeys: ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
                flags: ["-GEMINI_API_KEY", "-GOOGLE_API_KEY"]
            ) else {
                throw NutritionProviderConfigurationError.missingGeminiAPIKey
            }
            return GeminiDecisionsLanguageModel(apiKey: apiKey)
        case .reverseProxy:
            return try makeReverseProxyModel()
        }
    }

    // MARK: - Concrete Provider Factories

    private func makeLayaOnDeviceModel() throws -> LayaOnDeviceLanguageModel {
        let explicitPath = Self.resolveSetting(
            appStorageKey: "layaModelPath",
            envKeys: ["LAYA_MODEL_PATH"],
            flags: ["--laya-model-path", "-LAYA_MODEL_PATH"]
        )

        do {
            if let explicitPath {
                let expanded = (explicitPath as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                return try LayaOnDeviceLanguageModel(modelURL: url)
            }
            return try LayaOnDeviceLanguageModel()
        } catch {
            throw NutritionProviderConfigurationError.missingLayaOnDeviceModel(error.localizedDescription)
        }
    }

    private func makeLayaServeModel() throws -> LayaLanguageModel {
        let rawURL = Self.resolveSetting(
            appStorageKey: "layaServeURL",
            envKeys: ["LAYA_SERVE_URL", "LAYA_ENDPOINT"],
            flags: ["--laya-url", "-LAYA_SERVE_URL", "-LAYA_ENDPOINT"]
        ) ?? "http://127.0.0.1:8000"

        guard let parsed = URL(string: rawURL),
              let scheme = parsed.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              let host = parsed.host, !host.isEmpty else {
            throw NutritionProviderConfigurationError.invalidLayaServeURL(rawURL)
        }

        let endpointURL: URL
        if parsed.path.isEmpty || parsed.path == "/" {
            endpointURL = parsed.appendingPathComponent("v1/systemone")
        } else {
            endpointURL = parsed
        }

        let apiKey = Self.resolveSecret(
            keychainKey: "layaServeAPIKey",
            envKeys: ["LAYA_API_KEY"],
            flags: ["-LAYA_API_KEY"]
        )

        let modelID = Self.resolveSetting(
            appStorageKey: "layaServeModelID",
            envKeys: ["LAYA_MODEL_ID"],
            flags: ["-LAYA_MODEL_ID"]
        ) ?? "english"

        return LayaLanguageModel(
            endpoint: .custom(endpointURL),
            modelID: modelID,
            apiKey: apiKey
        )
    }

    private func makeClefModel() throws -> ClefLanguageModel {
        let use27B = UserDefaults.standard.bool(forKey: "clefUse27BModel")
        let clefVariant: ClefModel = use27B ? .clef : .clefFlash

        let apiToken = Self.resolveSecret(
            keychainKey: "cloudflareAPIToken",
            envKeys: ["CLOUDFLARE_API_TOKEN"],
            flags: ["-CLOUDFLARE_API_TOKEN"]
        )

        if let customEndpoint = Self.resolveSetting(
            appStorageKey: "clefCustomEndpoint",
            envKeys: ["CLEF_ENDPOINT"],
            flags: ["-CLEF_ENDPOINT"]
        ), let url = URL(string: customEndpoint), url.scheme != nil, url.host != nil {
            let evalURL = url.path.hasSuffix("/v1/evaluate") ? url : url.appendingPathComponent("v1/evaluate")
            return ClefLanguageModel(endpoint: .custom(evalURL, model: clefVariant), apiToken: apiToken)
        }

        if let accountID = Self.resolveSetting(
            appStorageKey: "cloudflareAccountID",
            envKeys: ["CLOUDFLARE_ACCOUNT_ID"],
            flags: ["-CLOUDFLARE_ACCOUNT_ID"]
        ), let apiToken {
            let endpoint: ClefEndpoint
            if let gatewayID = Self.resolveSetting(
                appStorageKey: "cloudflareGatewayID",
                envKeys: ["CLOUDFLARE_GATEWAY_ID"],
                flags: ["-CLOUDFLARE_GATEWAY_ID"]
            ) {
                endpoint = .gateway(accountID: accountID, gatewayID: gatewayID, model: clefVariant)
            } else {
                endpoint = .workersAI(accountID: accountID, model: clefVariant)
            }
            return ClefLanguageModel(endpoint: endpoint, apiToken: apiToken)
        }

        if let rawPort = Self.resolveSetting(
            appStorageKey: "clefLocalPort",
            envKeys: ["CLEF_LOCAL_PORT"],
            flags: ["-CLEF_LOCAL_PORT"]
        ), let port = Int(rawPort) {
            return ClefLanguageModel(endpoint: .local(port: port, model: clefVariant), apiToken: apiToken)
        }

        throw NutritionProviderConfigurationError.missingClefCredentials
    }

    private func makeReverseProxyModel() throws -> SystemOneLanguageModel {
        guard let rawURL = Self.resolveSetting(
            appStorageKey: "nutritionProxyURL",
            envKeys: ["SYSTEM_ONE_PROXY_URL", "TYPESAFE_PROXY_URL"],
            flags: ["--proxy-url", "-SYSTEM_ONE_PROXY_URL", "-TYPESAFE_PROXY_URL", "-proxyURL"]
        ) else {
            throw NutritionProviderConfigurationError.missingReverseProxyURL
        }

        guard let candidateURL = URL(string: rawURL) else {
            throw NutritionProviderConfigurationError.invalidReverseProxyURL(
                "Invalid proxy URL '\(rawURL)'. Provide an https:// endpoint (or http://127.0.0.1:<port> for local dev)."
            )
        }

        do {
            try ProxyEndpointValidator.validate(candidateURL)
        } catch {
            throw NutritionProviderConfigurationError.invalidReverseProxyURL(error.localizedDescription)
        }

        let appCheckToken = Self.resolveSecret(
            keychainKey: "firebaseAppCheckToken",
            envKeys: ["FIREBASE_APPCHECK_TOKEN"],
            flags: ["--appcheck-token", "-FIREBASE_APPCHECK_TOKEN"]
        )
        let bearerToken = Self.resolveSecret(
            keychainKey: "systemOneProxyBearerToken",
            envKeys: ["SYSTEM_ONE_PROXY_TOKEN", "TYPESAFE_PROXY_TOKEN"],
            flags: ["--proxy-token", "-SYSTEM_ONE_PROXY_TOKEN", "-TYPESAFE_PROXY_TOKEN"]
        )

        let credential: ProxyCredential
        if let appCheckToken {
            credential = .appCheck { appCheckToken }
        } else if let bearerToken {
            credential = .bearer { bearerToken }
        } else {
            credential = .custom { _ in }
        }

        let modelID = Self.resolveSetting(
            appStorageKey: "nutritionProxyModelID",
            envKeys: ["SYSTEM_ONE_PROXY_MODEL"],
            flags: ["-SYSTEM_ONE_PROXY_MODEL"]
        ) ?? "systemone-default"

        return SystemOneLanguageModel(
            proxyEndpoint: candidateURL,
            credential: credential,
            modelID: modelID,
            supportsVision: effectiveSupportsVision
        )
    }

    // MARK: - Model Import Helper (Copies Core ML Bundle into Application Support)

    /// Copies a user-selected `.mlmodelc` or `.mlpackage` folder from `.fileImporter` into Application Support
    /// so it remains accessible across launches after the security-scoped resource closes.
    public static func importCoreMLModel(from securityScopedURL: URL) throws -> String {
        let accessed = securityScopedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                securityScopedURL.stopAccessingSecurityScopedResource()
            }
        }

        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("LayaModels", isDirectory: true)

        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let destination = appSupport.appendingPathComponent(securityScopedURL.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: securityScopedURL, to: destination)

        let adjacentTokenizer = securityScopedURL.deletingLastPathComponent().appendingPathComponent("tokenizer.json")
        if fm.fileExists(atPath: adjacentTokenizer.path) {
            let destTokenizer = appSupport.appendingPathComponent("tokenizer.json")
            if fm.fileExists(atPath: destTokenizer.path) {
                try? fm.removeItem(at: destTokenizer)
            }
            try? fm.copyItem(at: adjacentTokenizer, to: destTokenizer)
        }

        UserDefaults.standard.set(destination.path, forKey: "layaModelPath")
        return destination.path
    }

    // MARK: - Internal Lookup Utilities

    private static func hasConfiguredOnDeviceLayaModel() -> Bool {
        let fm = FileManager.default
        if let rawPath = resolveSetting(
            appStorageKey: "layaModelPath",
            envKeys: ["LAYA_MODEL_PATH"],
            flags: ["--laya-model-path", "-LAYA_MODEL_PATH"]
        ) {
            let expanded = (rawPath as NSString).expandingTildeInPath
            if fm.fileExists(atPath: expanded) {
                return true
            }
        }
        if Bundle.main.url(forResource: "LayaDecisionModel", withExtension: "mlmodelc") != nil ||
           Bundle.main.url(forResource: "LayaDecisionModel", withExtension: "mlpackage") != nil {
            return true
        }
        return false
    }

    private static func matchProvider(_ raw: String) -> NutritionScannerProvider? {
        let normalized = raw.lowercased()
        if let exact = NutritionScannerProvider(rawValue: normalized) {
            return exact
        }
        switch normalized {
        case "laya", "ondevice", "coreml": return .layaOnDevice
        case "layaserve", "laya-server": return .layaServe
        case "jev", "typesafe": return .jevCloud
        case "clef", "cloudflare": return .clef
        case "openai", "luna", "gpt-6-luna": return .openAI
        case "gemini", "google", "gemini-decision-1": return .gemini
        case "proxy", "reverseproxy": return .reverseProxy
        default: return nil
        }
    }

    internal static func resolveSetting(
        appStorageKey: String?,
        envKeys: [String],
        flags: [String]
    ) -> String? {
        if !flags.isEmpty, let cliVal = resolveLaunchArgument(flags: flags) {
            return cliVal
        }
        if let appStorageKey, let stored = trimmedNonEmpty(UserDefaults.standard.string(forKey: appStorageKey)) {
            return stored
        }
        for envKey in envKeys {
            if let env = trimmedNonEmpty(ProcessInfo.processInfo.environment[envKey]) {
                return env
            }
        }
        return nil
    }

    internal static func resolveSecret(
        keychainKey: String,
        envKeys: [String],
        flags: [String]
    ) -> String? {
        if !flags.isEmpty, let cliVal = resolveLaunchArgument(flags: flags) {
            return cliVal
        }
        if let stored = trimmedNonEmpty(NutritionKeychainHelper.string(forKey: keychainKey)) {
            return stored
        }
        for envKey in envKeys {
            if let ud = trimmedNonEmpty(UserDefaults.standard.string(forKey: envKey)) {
                return ud
            }
            if let env = trimmedNonEmpty(ProcessInfo.processInfo.environment[envKey]) {
                return env
            }
        }
        return nil
    }

    private static func resolveLaunchArgument(flags: [String]) -> String? {
        let args = ProcessInfo.processInfo.arguments
        for i in 0..<args.count {
            let arg = args[i]
            if flags.contains(arg), i + 1 < args.count {
                let next = args[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !next.hasPrefix("-") && !next.isEmpty {
                    return next
                }
            }
            for flag in flags where arg.hasPrefix("\(flag)=") {
                let value = String(arg.dropFirst(flag.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
