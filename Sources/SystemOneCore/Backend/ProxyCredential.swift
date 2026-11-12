import Foundation

/// A zero-dependency, concurrency-safe dynamic credential modifier for authenticating
/// against a backend proxy or mobile API gateway (e.g., Firebase App Check, DeviceCheck,
/// Cloudflare Access, or custom JWT providers).
///
/// `ProxyCredential` conforms to `Hashable` via an internal identity `UUID` so that
/// `LanguageModel.Configuration` and HTTP backend structs retain automatic `Hashable`
/// and `Sendable` synthesis.
///
/// - Important: Each factory invocation mints a new identity `UUID` unless an explicit `id:` is
///   supplied. In SwiftUI, store your `ProxyCredential`, `LanguageModel`, or `LanguageModelSession`
///   in `@State`, an `@Observable` ViewModel, or your DI container rather than recreating it inside
///   `View.body` on every render pass.
///
/// See `docs/architecture/ADR-2026-11-12-01-universal-proxy-credentials.md` and
/// `tech-notes/0010-proxy-transport-and-dynamic-attestation.md`.
public struct ProxyCredential: Sendable, Hashable {
    private let id: UUID
    private let modifier: @Sendable (inout URLRequest) async throws -> Void

    public init(
        id: UUID = UUID(),
        modifier: @escaping @Sendable (inout URLRequest) async throws -> Void
    ) {
        self.id = id
        self.modifier = modifier
    }

    public static func == (lhs: ProxyCredential, rhs: ProxyCredential) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Applies the credential mutation to an outbound `URLRequest`.
    /// Invoked on every attempt (including retries) so short-lived or rotating tokens stay fresh.
    public func apply(to request: inout URLRequest) async throws {
        try await modifier(&request)
    }

    private static func containsHeaderControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar == "\r" || scalar == "\n" || scalar.value == 0
        }
    }

    /// Sets `Authorization: Bearer <token>` using the dynamically resolved token.
    ///
    /// Automatically strips a duplicate leading `"Bearer "` prefix (case-insensitive) and rejects
    /// empty tokens or CR/LF/NUL header control characters.
    public static func bearer(
        id: UUID = UUID(),
        _ provider: @escaping @Sendable () async throws -> String
    ) -> ProxyCredential {
        ProxyCredential(id: id) { request in
            let rawToken = try await provider()
            if Self.containsHeaderControlCharacters(rawToken) {
                throw SystemOneError.authenticationFailed(
                    "Invalid proxy bearer token: CR/LF/NUL header control characters are not permitted."
                )
            }
            var cleanToken = rawToken.trimmingCharacters(in: .whitespaces)
            while true {
                let lower = cleanToken.lowercased()
                if lower == "bearer" {
                    cleanToken = ""
                    break
                } else if lower.hasPrefix("bearer ") {
                    cleanToken = String(cleanToken.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
            }
            guard !cleanToken.isEmpty else {
                throw SystemOneError.authenticationFailed(
                    "Proxy credential provider returned an empty token."
                )
            }
            request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Sets a custom HTTP header with an optional prefix (e.g. `X-Firebase-AppCheck: <token>`).
    public static func header(
        name: String,
        prefix: String? = nil,
        id: UUID = UUID(),
        provider: @escaping @Sendable () async throws -> String
    ) -> ProxyCredential {
        ProxyCredential(id: id) { request in
            if Self.containsHeaderControlCharacters(name) {
                throw SystemOneError.authenticationFailed(
                    "Invalid proxy credential header name: CR/LF/NUL control characters are not permitted."
                )
            }
            let cleanName = name.trimmingCharacters(in: .whitespaces)
            guard !cleanName.isEmpty else {
                throw SystemOneError.authenticationFailed(
                    "Proxy credential header name must not be empty."
                )
            }

            let sanitizedPrefix: String?
            if let prefix {
                if Self.containsHeaderControlCharacters(prefix) {
                    throw SystemOneError.authenticationFailed(
                        "Invalid proxy credential header prefix: CR/LF/NUL control characters are not permitted."
                    )
                }
                let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
                sanitizedPrefix = trimmedPrefix.isEmpty ? nil : trimmedPrefix
            } else {
                sanitizedPrefix = nil
            }

            let rawToken = try await provider()
            if Self.containsHeaderControlCharacters(rawToken) {
                throw SystemOneError.authenticationFailed(
                    "Invalid proxy credential token: CR/LF/NUL control characters are not permitted."
                )
            }
            let cleanToken = rawToken.trimmingCharacters(in: .whitespaces)
            guard !cleanToken.isEmpty else {
                throw SystemOneError.authenticationFailed(
                    "Proxy credential provider returned an empty token."
                )
            }

            let value = sanitizedPrefix.map { "\($0) \(cleanToken)" } ?? cleanToken
            request.setValue(value, forHTTPHeaderField: cleanName)
        }
    }

    /// Sets an attestation header (defaults to `X-Firebase-AppCheck`) using a dynamically resolved token.
    ///
    /// Zero-dependency convenience shorthand: the caller provides an async closure calling
    /// `AppCheck.appCheck().token(forcingRefresh: false).token` without `SystemOneCore`
    /// linking `FirebaseAppCheck`.
    public static func appCheck(
        headerName: String = "X-Firebase-AppCheck",
        id: UUID = UUID(),
        _ provider: @escaping @Sendable () async throws -> String
    ) -> ProxyCredential {
        .header(name: headerName, id: id, provider: provider)
    }

    /// Applies arbitrary modifications to the outbound `URLRequest` before dispatch
    /// (e.g. combining `X-Firebase-AppCheck` with a user `Authorization: Bearer` header,
    /// or computing an HMAC signature over `request.httpBody`).
    public static func custom(
        id: UUID = UUID(),
        _ modifier: @escaping @Sendable (inout URLRequest) async throws -> Void
    ) -> ProxyCredential {
        ProxyCredential(id: id, modifier: modifier)
    }
}
