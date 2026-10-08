import Foundation

/// Errors that can occur when executing requests with a System One decision model.
public enum SystemOneError: LocalizedError, Sendable, Equatable, Hashable {
    /// A structured @Generable schema is required; arbitrary text generation is not supported.
    case structuredOutputRequired
    /// The provided schema could not be converted into valid System One decision questions.
    case invalidSchema(String)
    /// No API key was configured while using a transport requiring authentication.
    case missingAPIKey
    /// An error returned by the HTTP API or backend service.
    case apiError(statusCode: Int, message: String)
    /// Network or communication error. Note that `CancellationError` is never wrapped.
    case networkError(String)
    /// Response parsing or decoding error.
    case decodingError(String)
    /// Generic backend error.
    case backendError(String)
    /// On-device model execution error.
    case modelExecutionError(String)
    /// The model refused to evaluate a question due to safety policy.
    case safetyRefusal(reason: String, questionName: String)
    /// Authentication or authorization failure (e.g. invalid or revoked API key).
    case authenticationFailed(String)
    /// API quota or credit limit exhausted.
    case quotaExceeded(String)

    public var errorDescription: String? {
        switch self {
        case .structuredOutputRequired:
            return "System One decision models require a @Generable schema. Free-form text generation is not supported."
        case .invalidSchema(let details):
            return "Failed to convert @Generable schema to System One questions: \(details)"
        case .missingAPIKey:
            return "An API key is required when using a transport that enforces authentication. Use a reverse-proxy transport or local engine to authenticate without embedding a key."
        case .apiError(let statusCode, let message):
            return "System One backend returned error \(statusCode): \(message)"
        case .networkError(let details):
            return "Network error: \(details)"
        case .decodingError(let details):
            return "Failed to synthesize or decode response: \(details)"
        case .backendError(let details):
            return "Backend error: \(details)"
        case .modelExecutionError(let details):
            return "On-device model execution error: \(details)"
        case .safetyRefusal(let reason, let questionName):
            return "Safety policy refusal on question '\(questionName)': \(reason)"
        case .authenticationFailed(let details):
            return "Authentication failed: \(details)"
        case .quotaExceeded(let details):
            return "Quota exceeded: \(details)"
        }
    }
}
