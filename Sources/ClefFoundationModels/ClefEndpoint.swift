import Foundation
import SystemOneCore

/// Target endpoint topology for Clef multimodal decision models.
public enum ClefEndpoint: Hashable, Sendable {
    /// Direct Cloudflare Workers AI edge REST API.
    case workersAI(accountID: String, model: ClefModel = .clefFlash)
    /// Cloudflare AI Gateway with centralized caching, observability, and rate limiting.
    case gateway(accountID: String, gatewayID: String, model: ClefModel = .clefFlash)
    /// Local inference runner (Docker Model Runner, vLLM, Cog, MLX).
    case local(port: Int = 8000, model: ClefModel = .clefFlash)
    /// Custom fully-qualified HTTP/HTTPS URL endpoint.
    case custom(URL, model: ClefModel = .clefFlash)

    private static let invalidFallbackURL: URL = {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 0
        components.path = "/invalid-clef-endpoint"
        guard let built = components.url else {
            preconditionFailure("Static ClefEndpoint.invalidFallbackURL components must form a valid URL")
        }
        return built
    }()

    /// Validates endpoint parameters (`accountID`, `gatewayID`, `port`, URL scheme/host) and returns a safe `URL`.
    public func validatedURL() throws -> URL {
        switch self {
        case .workersAI(let accountID, let model):
            try Self.validateIdentifier(accountID, label: "accountID")
            guard let built = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/ai/run/\(model.workersAIIdentifier)") else {
                throw SystemOneError.networkError("Failed to construct Cloudflare Workers AI URL for accountID '\(accountID)'.")
            }
            return built

        case .gateway(let accountID, let gatewayID, let model):
            try Self.validateIdentifier(accountID, label: "accountID")
            try Self.validateIdentifier(gatewayID, label: "gatewayID")
            guard let built = URL(string: "https://gateway.ai.cloudflare.com/v1/\(accountID)/\(gatewayID)/workers-ai/\(model.workersAIIdentifier)") else {
                throw SystemOneError.networkError("Failed to construct Cloudflare AI Gateway URL for accountID '\(accountID)' and gatewayID '\(gatewayID)'.")
            }
            return built

        case .local(let port, _):
            guard (1...65535).contains(port) else {
                throw SystemOneError.networkError("Invalid Clef local runner port \(port): must be within 1...65535.")
            }
            var components = URLComponents()
            components.scheme = "http"
            components.host = "localhost"
            components.port = port
            components.path = "/v1/evaluate"
            guard let built = components.url else {
                throw SystemOneError.networkError("Failed to construct Clef local runner URL for port \(port).")
            }
            return built

        case .custom(let customURL, _):
            guard let scheme = customURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = customURL.host, !host.isEmpty else {
                throw SystemOneError.networkError("Invalid custom Clef endpoint URL: '\(customURL.absoluteString)'.")
            }
            if let port = customURL.port, !(1...65535).contains(port) {
                throw SystemOneError.networkError("Invalid port \(port) in custom Clef endpoint URL.")
            }
            return customURL
        }
    }

    /// Computes the target URL for the endpoint (non-crashing even on malformed identifiers or ports).
    public var url: URL {
        (try? validatedURL()) ?? Self.invalidFallbackURL
    }

    /// The selected Clef model.
    public var model: ClefModel {
        switch self {
        case .workersAI(_, let model):
            return model
        case .gateway(_, _, let model):
            return model
        case .local(_, let model):
            return model
        case .custom(_, let model):
            return model
        }
    }

    /// The model identifier sent over the wire.
    public var modelIdentifier: String {
        model.rawValue
    }

    private static func validateIdentifier(_ raw: String, label: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == raw else {
            throw SystemOneError.networkError("Invalid Cloudflare \(label): must not be empty or contain leading/trailing whitespace.")
        }
        guard !raw.contains(".."),
              !raw.contains("/"),
              !raw.contains("\\"),
              !raw.contains("?"),
              !raw.contains("#"),
              !raw.contains("%"),
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            throw SystemOneError.networkError("Invalid Cloudflare \(label) '\(raw)': contains disallowed URL path or control characters.")
        }
    }
}
