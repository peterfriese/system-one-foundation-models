import Foundation
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif
import JevFoundationModels

/// A transport that delivers Jev requests to a secure Firebase Cloud Function proxy
/// authenticated with Apple App Attest via Firebase App Check.
///
/// See `docs/mobile-security.md` and `tech-notes/0004-secure-mobile-transport-appcheck.md`
/// for complete setup instructions.
public struct FirebaseAppCheckTransport: JevTransport, Sendable {
    /// The token acquisition strategy for Firebase App Check.
    public enum TokenStrategy: Sendable {
        /// Uses cached in-memory tokens (< 1 ms lookup).
        /// Recommended for interactive UI, low-latency loops, and continuous decisions.
        case cached

        /// Acquires a one-time consumable token with server-side replay protection (~40–120 ms token exchange).
        /// Recommended for sensitive operations, billing-sensitive decisions, or high-security actions.
        case singleUse
    }

    /// An explicit proxy endpoint URL. If `nil`, the endpoint passed to `send(...)` is used.
    public let proxyEndpoint: URL?
    public let session: URLSession
    public let tokenStrategy: TokenStrategy

    public init(
        proxyEndpoint: URL? = nil,
        session: URLSession = .shared,
        tokenStrategy: TokenStrategy = .cached
    ) {
        self.proxyEndpoint = proxyEndpoint
        self.session = session
        self.tokenStrategy = tokenStrategy
    }

    public func send(
        request: JevRequest,
        apiKey: String?,
        endpoint: URL
    ) async throws -> JevResponse {
        #if canImport(FirebaseAppCheck)
        // 1. Obtain App Check token based on strategy
        let tokenString: String
        switch tokenStrategy {
        case .cached:
            let token = try await AppCheck.appCheck().token(forcingRefresh: false)
            tokenString = token.token
        case .singleUse:
            let token = try await AppCheck.appCheck().limitedUseToken()
            tokenString = token.token
        }
        #else
        throw JevError.networkError("FirebaseAppCheck is not linked in this application target.")
        #endif

        // 2. Prepare HTTP request to the Cloud Function proxy
        guard let targetURL = proxyEndpoint else {
            throw JevError.networkError("FirebaseAppCheckTransport requires an explicit proxyEndpoint pointing to your authenticated Cloud Function reverse proxy.")
        }
        var urlRequest = URLRequest(url: targetURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !tokenString.isEmpty {
            urlRequest.setValue(tokenString, forHTTPHeaderField: "X-Firebase-AppCheck")
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw JevError.decodingError("Failed to encode JevRequest: \(error.localizedDescription)")
        }

        // 3. Dispatch over URLSession
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JevError.networkError("Invalid HTTP response received from proxy.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw JevError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        do {
            return try JSONDecoder().decode(JevResponse.self, from: data)
        } catch {
            throw JevError.decodingError("Failed to decode JevResponse from proxy: \(error.localizedDescription)")
        }
    }
}
