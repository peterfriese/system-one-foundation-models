import Foundation

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

    /// Computes the target URL for the endpoint.
    public var url: URL {
        switch self {
        case .workersAI(let accountID, let model):
            return URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/ai/run/\(model.workersAIIdentifier)")!
        case .gateway(let accountID, let gatewayID, let model):
            return URL(string: "https://gateway.ai.cloudflare.com/v1/\(accountID)/\(gatewayID)/workers-ai/\(model.workersAIIdentifier)")!
        case .local(let port, _):
            return URL(string: "http://localhost:\(port)/v1/evaluate")!
        case .custom(let customURL, _):
            return customURL
        }
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
}
