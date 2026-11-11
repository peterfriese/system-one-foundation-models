import Foundation

/// Target endpoint configuration for the Google Gemini Decisions API (`gemini-decision-1`).
///
/// See tech-notes/0018-gemini-decisions-api-architecture.md
public enum GeminiDecisionsEndpoint: Hashable, Sendable {
    /// Default hosted Google Gemini Decisions API endpoint (`https://generativelanguage.googleapis.com/v1beta/decisions`).
    case hosted(
        model: String = GeminiDecisionsEndpoint.defaultModel,
        clientRequestID: String? = nil
    )

    /// Custom HTTP or HTTPS endpoint (e.g. enterprise reverse proxy or Vertex/Cloud gateway).
    case custom(
        URL,
        model: String = GeminiDecisionsEndpoint.defaultModel,
        clientRequestID: String? = nil
    )

    /// Custom HTTP or HTTPS endpoint with labeled `url:`.
    public static func custom(
        url: URL,
        model: String = GeminiDecisionsEndpoint.defaultModel,
        clientRequestID: String? = nil
    ) -> GeminiDecisionsEndpoint {
        .custom(url, model: model, clientRequestID: clientRequestID)
    }

    /// The default official Google Gemini Decisions API URL.
    public static let defaultURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/decisions")!

    /// The default official System One decision model identifier for Google Gemini.
    public static let defaultModel = "gemini-decision-1"

    /// The target URL for this endpoint.
    public var url: URL {
        switch self {
        case .hosted:
            return Self.defaultURL
        case .custom(let customURL, _, _):
            return customURL
        }
    }

    /// The target model identifier to be transmitted over the wire.
    public var model: String {
        switch self {
        case .hosted(let model, _):
            return model
        case .custom(_, let model, _):
            return model
        }
    }

    /// Optional client request identifier (`X-Client-Request-Id` header).
    public var clientRequestID: String? {
        switch self {
        case .hosted(_, let clientRequestID):
            return clientRequestID
        case .custom(_, _, let clientRequestID):
            return clientRequestID
        }
    }

    /// Creates an endpoint with optional parameters.
    public init(
        url: URL = GeminiDecisionsEndpoint.defaultURL,
        model: String = GeminiDecisionsEndpoint.defaultModel,
        clientRequestID: String? = nil
    ) {
        if url == Self.defaultURL {
            self = .hosted(model: model, clientRequestID: clientRequestID)
        } else {
            self = .custom(url, model: model, clientRequestID: clientRequestID)
        }
    }
}
