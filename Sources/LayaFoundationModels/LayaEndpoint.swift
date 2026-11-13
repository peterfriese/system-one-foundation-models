import Foundation
import SystemOneCore

/// Defines connection endpoints for Laya System One HTTP servers.
public enum LayaEndpoint: Sendable, Hashable {
    /// Default local server port (`http://127.0.0.1:8000/v1/systemone`).
    case localDefault
    /// Alternative local server port (`http://127.0.0.1:8770/v1/systemone`).
    case localAlt
    /// Custom local server port (`http://127.0.0.1:<port>/v1/systemone`).
    case local(port: Int)
    /// Hosted public/enterprise endpoint (`https://api.impossibl.com/v1/systemone`).
    case hosted
    /// An arbitrary custom URL.
    case custom(URL)

    private static func makeStaticURL(scheme: String, host: String, port: Int? = nil, path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = path
        guard let built = components.url else {
            preconditionFailure("Static LayaEndpoint URL components must form a valid URL")
        }
        return built
    }

    private static let defaultURL = makeStaticURL(scheme: "http", host: "127.0.0.1", port: 8000, path: "/v1/systemone")
    private static let altURL = makeStaticURL(scheme: "http", host: "127.0.0.1", port: 8770, path: "/v1/systemone")
    private static let hostedURL = makeStaticURL(scheme: "https", host: "api.impossibl.com", path: "/v1/systemone")
    private static let invalidFallbackURL = makeStaticURL(scheme: "http", host: "127.0.0.1", port: 0, path: "/invalid-laya-endpoint")

    /// Validates endpoint parameters (port bounds, scheme, host) and constructs a guaranteed-valid `URL`.
    public func validatedURL() throws -> URL {
        switch self {
        case .localDefault:
            return Self.defaultURL
        case .localAlt:
            return Self.altURL
        case .local(let port):
            guard (1...65535).contains(port) else {
                throw SystemOneError.networkError("Invalid Laya local port \(port): must be within 1...65535.")
            }
            var components = URLComponents()
            components.scheme = "http"
            components.host = "127.0.0.1"
            components.port = port
            components.path = "/v1/systemone"
            guard let built = components.url else {
                throw SystemOneError.networkError("Failed to construct Laya local URL for port \(port).")
            }
            return built
        case .hosted:
            return Self.hostedURL
        case .custom(let customURL):
            guard let scheme = customURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = customURL.host, !host.isEmpty else {
                throw SystemOneError.networkError("Invalid custom Laya endpoint URL: '\(customURL.absoluteString)'.")
            }
            if let port = customURL.port, !(1...65535).contains(port) {
                throw SystemOneError.networkError("Invalid port \(port) in custom Laya endpoint URL.")
            }
            return customURL
        }
    }

    /// The resolved URL for the `POST /v1/systemone` endpoint (non-crashing even on invalid port inputs).
    public var url: URL {
        (try? validatedURL()) ?? Self.invalidFallbackURL
    }
}
