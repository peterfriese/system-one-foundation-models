import Foundation
import SystemOneCore

/// An HTTP backend bridging System One requests to self-hosted or remote Laya servers (`laya-serve`).
///
/// See `tech-notes/0007-pluggable-system-one-backends-and-laya-serve.md`.
public struct LayaHTTPBackend: SystemOneBackend, Hashable, Sendable {
    public let endpoint: LayaEndpoint
    public let apiKey: String?
    public let session: URLSession
    public let timeoutInterval: TimeInterval

    public init(
        endpoint: LayaEndpoint = .localDefault,
        apiKey: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
        self.timeoutInterval = timeoutInterval
    }

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        var urlRequest = URLRequest(url: endpoint.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Bearer auth is optional: laya-serve without LAYA_API_KEY requires no authorization header
        if let key = apiKey, !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.timeoutInterval = timeoutInterval

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw SystemOneError.decodingError("Failed to encode SystemOneRequest: \(error.localizedDescription)")
        }

        let networkStartTime = CFAbsoluteTimeGetCurrent()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                throw CancellationError()
            }
            throw SystemOneError.networkError(error.localizedDescription)
        }
        let transportDuration = (CFAbsoluteTimeGetCurrent() - networkStartTime) * 1000.0

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SystemOneError.networkError("Invalid HTTP response received from server.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw SystemOneError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        do {
            var decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
            decoded.transportDurationMs = transportDuration

            // Check for server-supplied timing headers:
            // 1. x-envoy-upstream-service-time (standard Envoy/Traefik/Gateway header)
            // 2. server-timing (RFC 7668)
            // 3. x-inference-time / x-process-time
            if let serviceTimeHeader = httpResponse.value(forHTTPHeaderField: "x-envoy-upstream-service-time"),
               let serviceTimeMs = Double(serviceTimeHeader) {
                decoded.serverDurationMs = serviceTimeMs
            } else if let serverTimingHeader = httpResponse.value(forHTTPHeaderField: "server-timing"),
                      let dur = parseServerTimingDuration(serverTimingHeader) {
                decoded.serverDurationMs = dur
            } else if let inferenceHeader = httpResponse.value(forHTTPHeaderField: "x-inference-time-ms") ?? httpResponse.value(forHTTPHeaderField: "x-process-time"),
                      let inferenceMs = Double(inferenceHeader) {
                decoded.serverDurationMs = inferenceMs
            } else {
                // If the server omits internal timing headers (standard local laya-serve),
                // transportDuration represents the total HTTP socket transit and inference time.
                decoded.serverDurationMs = transportDuration
            }

            return decoded
        } catch {
            throw SystemOneError.decodingError("Failed to decode Laya response: \(error.localizedDescription)")
        }
    }

    private func parseServerTimingDuration(_ header: String) -> Double? {
        // e.g., "app;dur=42.5" or "inference;dur=18.2"
        for entry in header.components(separatedBy: ",") {
            let parts = entry.components(separatedBy: ";")
            for param in parts.dropFirst() {
                let kv = param.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if kv.count == 2 && kv[0] == "dur" {
                    return Double(kv[1])
                }
            }
        }
        return nil
    }
}
