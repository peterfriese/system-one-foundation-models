import Foundation
import SystemOneCore

/// An HTTP backend bridging System One requests to Cloudflare Workers AI, AI Gateway, or local Clef servers.
public struct ClefHTTPBackend: SystemOneBackend, Sendable, Hashable {
    public let endpoint: ClefEndpoint
    public let apiToken: String?
    public let session: URLSession
    public let timeoutInterval: TimeInterval
    public let retryPolicy: RetryPolicy

    public init(
        endpoint: ClefEndpoint,
        apiToken: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 45,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = endpoint
        self.apiToken = apiToken
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
    }

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        var attempts = 0
        let maxAttempts = retryPolicy.maxAttempts

        while true {
            attempts += 1
            do {
                return try await performSingleEvaluation(request: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let resError as HTTPResponseError {
                let statusCode = resError.httpResponse.statusCode
                let isLastAttempt = attempts >= maxAttempts

                guard retryPolicy.retryableStatuses.contains(statusCode), !isLastAttempt else {
                    let body = String(data: resError.data, encoding: .utf8) ?? "Unknown error"
                    throw SystemOneError.apiError(statusCode: statusCode, message: body)
                }

                let delay: Duration
                if statusCode == 429, let retryAfterDelay = retryPolicy.retryAfter(from: resError.httpResponse) {
                    delay = retryAfterDelay
                } else {
                    delay = retryPolicy.backoff(afterAttempt: attempts)
                }

                try await Task.sleep(for: delay)
                continue
            } catch let error as SystemOneError {
                switch error {
                case .networkError:
                    if attempts < maxAttempts && !Task.isCancelled {
                        let delay = retryPolicy.backoff(afterAttempt: attempts)
                        try await Task.sleep(for: delay)
                        continue
                    }
                    throw error
                case .apiError(let statusCode, _):
                    if retryPolicy.retryableStatuses.contains(statusCode), attempts < maxAttempts {
                        let delay = retryPolicy.backoff(afterAttempt: attempts)
                        try await Task.sleep(for: delay)
                        continue
                    }
                    throw error
                default:
                    throw error
                }
            } catch {
                if attempts < maxAttempts && !Task.isCancelled {
                    let delay = retryPolicy.backoff(afterAttempt: attempts)
                    try await Task.sleep(for: delay)
                    continue
                }
                throw SystemOneError.networkError(error.localizedDescription)
            }
        }
    }

    private struct HTTPResponseError: Error {
        let httpResponse: HTTPURLResponse
        let data: Data
    }

    private func performSingleEvaluation(request: SystemOneRequest) async throws -> SystemOneResponse {
        var urlRequest = URLRequest(url: endpoint.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = timeoutInterval

        if let token = apiToken, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if case .gateway = endpoint {
            urlRequest.setValue("system-one-foundation-models", forHTTPHeaderField: "cf-aig-metadata-app")
            urlRequest.setValue("clef-multimodal", forHTTPHeaderField: "cf-aig-metadata-tag")
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw SystemOneError.decodingError("Failed to serialize SystemOneRequest: \(error.localizedDescription)")
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
            throw HTTPResponseError(httpResponse: httpResponse, data: data)
        }

        return try decodeResponse(data: data, httpResponse: httpResponse, transportDuration: transportDuration)
    }

    // See tech-notes/0016-cloudflare-workers-ai-v4-response-envelope.md
    private func decodeResponse(data: Data, httpResponse: HTTPURLResponse, transportDuration: Double) throws -> SystemOneResponse {
        do {
            var decoded: SystemOneResponse

            if let direct = try? JSONDecoder().decode(SystemOneResponse.self, from: data) {
                decoded = direct
            } else if let envelope = try? JSONDecoder().decode(CloudflareAPIEnvelope.self, from: data) {
                if envelope.success == false {
                    let errorMessage = envelope.errors?.first?.message ?? "Cloudflare API request failed"
                    throw SystemOneError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
                }
                if let result = envelope.result {
                    decoded = result
                } else {
                    decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
                }
            } else {
                decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
            }

            decoded.transportDurationMs = transportDuration

            // Check Cloudflare telemetry headers:
            // 1. server-timing (RFC 7668, e.g. "cfL4;dur=12, inference;dur=45")
            // 2. x-envoy-upstream-service-time
            if let serverTimingHeader = httpResponse.value(forHTTPHeaderField: "server-timing"),
               let dur = parseServerTimingDuration(serverTimingHeader) {
                decoded.serverDurationMs = dur
            } else if let envoyHeader = httpResponse.value(forHTTPHeaderField: "x-envoy-upstream-service-time"),
                      let envoyMs = Double(envoyHeader) {
                decoded.serverDurationMs = envoyMs
            } else {
                decoded.serverDurationMs = transportDuration
            }

            return decoded
        } catch let error as SystemOneError {
            throw error
        } catch {
            throw SystemOneError.decodingError("Failed to decode Clef response: \(error.localizedDescription)")
        }
    }

    private func parseServerTimingDuration(_ header: String) -> Double? {
        // e.g. "cfL4;dur=12, inference;dur=45" or "inference;dur=22.4"
        var fallbackDuration: Double? = nil

        for entry in header.components(separatedBy: ",") {
            let parts = entry.components(separatedBy: ";")
            guard let metricName = parts.first?.trimmingCharacters(in: .whitespaces) else { continue }

            for param in parts.dropFirst() {
                let kv = param.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if kv.count == 2 && kv[0] == "dur", let durVal = Double(kv[1]) {
                    if metricName.lowercased() == "inference" {
                        return durVal
                    } else if fallbackDuration == nil {
                        fallbackDuration = durVal
                    }
                }
            }
        }
        return fallbackDuration
    }
}

// MARK: - Cloudflare API Envelope Types

private struct CloudflareAPIEnvelope: Codable, Sendable {
    let result: SystemOneResponse?
    let success: Bool?
    let errors: [CloudflareAPIError]?
}

private struct CloudflareAPIError: Codable, Sendable {
    let code: Int?
    let message: String?
}
