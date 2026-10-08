import Foundation

/// Target endpoint configuration for the OpenAI Decisions API (`gpt-6-luna`).
public enum OpenAIDecisionsEndpoint: Hashable, Sendable {
    /// Default hosted OpenAI Decisions API endpoint (`https://api.openai.com/v1/decisions`).
    case hosted(
        model: String = OpenAIDecisionsEndpoint.defaultModel,
        organization: String? = nil,
        project: String? = nil,
        clientRequestID: String? = nil
    )

    /// Custom HTTP or HTTPS endpoint (e.g. enterprise reverse proxy or AI gateway).
    case custom(
        URL,
        model: String = OpenAIDecisionsEndpoint.defaultModel,
        organization: String? = nil,
        project: String? = nil,
        clientRequestID: String? = nil
    )

    /// The default official OpenAI Decisions API URL.
    public static let defaultURL = URL(string: "https://api.openai.com/v1/decisions")!

    /// The default official System One decision model identifier.
    public static let defaultModel = "gpt-6-luna"

    /// The target URL for this endpoint.
    public var url: URL {
        switch self {
        case .hosted:
            return Self.defaultURL
        case .custom(let customURL, _, _, _, _):
            return customURL
        }
    }

    /// The target model identifier to be transmitted over the wire.
    public var model: String {
        switch self {
        case .hosted(let model, _, _, _):
            return model
        case .custom(_, let model, _, _, _):
            return model
        }
    }

    /// Optional organization identifier (`OpenAI-Organization` header).
    public var organization: String? {
        switch self {
        case .hosted(_, let organization, _, _):
            return organization
        case .custom(_, _, let organization, _, _):
            return organization
        }
    }

    /// Optional project identifier (`OpenAI-Project` header).
    public var project: String? {
        switch self {
        case .hosted(_, _, let project, _):
            return project
        case .custom(_, _, _, let project, _):
            return project
        }
    }

    /// Optional client request identifier (`X-Client-Request-Id` header).
    public var clientRequestID: String? {
        switch self {
        case .hosted(_, _, _, let clientRequestID):
            return clientRequestID
        case .custom(_, _, _, _, let clientRequestID):
            return clientRequestID
        }
    }

    /// Creates an endpoint with optional parameters.
    public init(
        url: URL = OpenAIDecisionsEndpoint.defaultURL,
        model: String = OpenAIDecisionsEndpoint.defaultModel,
        organization: String? = nil,
        project: String? = nil,
        clientRequestID: String? = nil
    ) {
        if url == Self.defaultURL {
            self = .hosted(model: model, organization: organization, project: project, clientRequestID: clientRequestID)
        } else {
            self = .custom(url, model: model, organization: organization, project: project, clientRequestID: clientRequestID)
        }
    }
}
