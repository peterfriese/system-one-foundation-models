import Foundation
import FoundationModels
import UniformTypeIdentifiers
@_exported import SystemOneCore

/// An Apple Foundation Models provider for Cloudflare Clef and Clef-Flash multimodal decision models.
public struct ClefLanguageModel: LanguageModel, Sendable {
    public struct Configuration: Hashable, Sendable {
        public var endpoint: ClefEndpoint
        public var apiToken: String?
        public var modelID: String
        public var backend: AnySystemOneBackend

        public init(
            endpoint: ClefEndpoint,
            apiToken: String? = nil,
            proxyCredential: ProxyCredential? = nil,
            session: URLSession = .shared,
            timeoutInterval: TimeInterval = 45,
            retryPolicy: RetryPolicy = .default
        ) {
            self.endpoint = endpoint
            self.apiToken = apiToken
            self.modelID = endpoint.modelIdentifier
            self.backend = AnySystemOneBackend(
                ClefHTTPBackend(
                    endpoint: endpoint,
                    apiToken: apiToken,
                    proxyCredential: proxyCredential,
                    session: session,
                    timeoutInterval: timeoutInterval,
                    retryPolicy: retryPolicy
                )
            )
        }

        public init(
            backend: ClefHTTPBackend,
            modelID: String? = nil
        ) {
            self.endpoint = backend.endpoint
            self.apiToken = backend.apiToken
            self.modelID = modelID ?? backend.endpoint.modelIdentifier
            self.backend = AnySystemOneBackend(backend)
        }

        public init(
            backend: any SystemOneBackend,
            modelID: String = ClefModel.clefFlash.rawValue,
            endpoint: ClefEndpoint = .local()
        ) {
            self.endpoint = endpoint
            self.apiToken = nil
            self.modelID = modelID
            self.backend = (backend as? AnySystemOneBackend) ?? AnySystemOneBackend(backend)
        }
    }

    public typealias Executor = ClefExecutor

    public var executorConfiguration: Configuration

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration, .vision])
    }

    /// Initializes `ClefLanguageModel` by auto-resolving Cloudflare Workers AI (`CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`),
    /// custom gateway (`CLEF_ENDPOINT`), or local runner (`CLEF_LOCAL_PORT`) from the environment.
    public init(
        apiKey: String? = nil,
        model: ClefModel = .clefFlash,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 45,
        retryPolicy: RetryPolicy = .default
    ) {
        let resolvedToken = apiKey ?? Self.nonEmptyEnv("CLOUDFLARE_API_TOKEN")

        if let rawEndpoint = Self.nonEmptyEnv("CLEF_ENDPOINT"), let customURL = URL(string: rawEndpoint) {
            self.executorConfiguration = Configuration(
                endpoint: .custom(customURL, model: model),
                apiToken: resolvedToken,
                session: session,
                timeoutInterval: timeoutInterval,
                retryPolicy: retryPolicy
            )
        } else if let accountID = Self.nonEmptyEnv("CLOUDFLARE_ACCOUNT_ID") {
            let endpoint: ClefEndpoint
            if let gatewayID = Self.nonEmptyEnv("CLOUDFLARE_GATEWAY_ID") {
                endpoint = .gateway(accountID: accountID, gatewayID: gatewayID, model: model)
            } else {
                endpoint = .workersAI(accountID: accountID, model: model)
            }
            if let resolvedToken, !resolvedToken.isEmpty {
                self.executorConfiguration = Configuration(
                    endpoint: endpoint,
                    apiToken: resolvedToken,
                    session: session,
                    timeoutInterval: timeoutInterval,
                    retryPolicy: retryPolicy
                )
            } else {
                let missingTokenBackend = AnySystemOneBackend { _ in
                    throw SystemOneError.missingAPIKey
                }
                self.executorConfiguration = Configuration(
                    backend: missingTokenBackend,
                    modelID: model.rawValue,
                    endpoint: endpoint
                )
            }
        } else if let rawPort = Self.nonEmptyEnv("CLEF_LOCAL_PORT"), let port = Int(rawPort) {
            self.executorConfiguration = Configuration(
                endpoint: .local(port: port, model: model),
                apiToken: resolvedToken,
                session: session,
                timeoutInterval: timeoutInterval,
                retryPolicy: retryPolicy
            )
        } else {
            let unconfiguredBackend = AnySystemOneBackend { _ in
                throw SystemOneError.authenticationFailed(
                    "Missing Cloudflare Clef configuration. Export CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN for Workers AI, or set CLEF_LOCAL_PORT=8000 for Tools/ClefLocalRunner/server.py."
                )
            }
            self.executorConfiguration = Configuration(
                backend: unconfiguredBackend,
                modelID: model.rawValue,
                endpoint: .local(model: model)
            )
        }
    }

    public init(
        endpoint: ClefEndpoint,
        apiToken: String? = nil,
        proxyCredential: ProxyCredential? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 45,
        retryPolicy: RetryPolicy = .default
    ) {
        let resolvedToken = proxyCredential == nil ? (apiToken ?? Self.nonEmptyEnv("CLOUDFLARE_API_TOKEN")) : apiToken
        self.executorConfiguration = Configuration(
            endpoint: endpoint,
            apiToken: resolvedToken,
            proxyCredential: proxyCredential,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        model: ClefModel = .clefFlash,
        credential: ProxyCredential,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 45,
        retryPolicy: RetryPolicy = .default
    ) {
        self.executorConfiguration = Configuration(
            endpoint: .custom(proxyEndpoint, model: model),
            apiToken: nil,
            proxyCredential: credential,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        model: ClefModel,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 45,
        retryPolicy: RetryPolicy = .default
    ) {
        self.init(
            proxyEndpoint: proxyEndpoint,
            model: model,
            credential: credential,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        model: ClefModel = .clefFlash,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 45,
        retryPolicy: RetryPolicy = .default,
        authorize: @escaping @Sendable (inout URLRequest) async throws -> Void
    ) {
        self.init(
            proxyEndpoint: proxyEndpoint,
            model: model,
            credential: .custom(authorize),
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        backend: any SystemOneBackend,
        modelID: String = ClefModel.clefFlash.rawValue
    ) {
        self.executorConfiguration = Configuration(
            backend: backend,
            modelID: modelID
        )
    }

    public init(configuration: Configuration) {
        self.executorConfiguration = configuration
    }

    /// Supported image attachment types (PNG, JPEG, WebP).
    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .webP)
    }

    /// Supported transcript data entry types (PNG, JPEG, WebP).
    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .webP)
    }

    private static func nonEmptyEnv(_ key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
