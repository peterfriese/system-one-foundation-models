import Foundation

/// A zero-dependency, concurrency-safe dynamic credential modifier for authenticating
/// against a backend proxy or mobile API gateway (e.g., Firebase App Check, DeviceCheck,
/// Cloudflare Access, or custom JWT providers).
///
/// `ProxyCredential` conforms to `Hashable` via an internal identity `UUID` so that
/// `LanguageModel.Configuration` and HTTP backend structs retain automatic `Hashable`
/// and `Sendable` synthesis.
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

    /// Sets `Authorization: Bearer <token>` using the dynamically resolved token.
    public static func bearer(
        _ provider: @escaping @Sendable () async throws -> String
    ) -> ProxyCredential {
        ProxyCredential { request in
            let token = try await provider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Sets a custom HTTP header with an optional prefix (e.g. `X-Firebase-AppCheck: <token>`).
    public static func header(
        name: String,
        prefix: String? = nil,
        provider: @escaping @Sendable () async throws -> String
    ) -> ProxyCredential {
        ProxyCredential { request in
            let token = try await provider()
            let value = prefix.map { "\($0) \(token)" } ?? token
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    /// Sets an attestation header (defaults to `X-Firebase-AppCheck`) using a dynamically resolved token.
    ///
    /// Zero-dependency convenience shorthand: the caller provides an async closure calling
    /// `AppCheck.appCheck().token(forcingRefresh: false).token` without `SystemOneCore`
    /// linking `FirebaseAppCheck`.
    public static func appCheck(
        headerName: String = "X-Firebase-AppCheck",
        _ provider: @escaping @Sendable () async throws -> String
    ) -> ProxyCredential {
        .header(name: headerName, provider: provider)
    }

    /// Applies arbitrary modifications to the outbound `URLRequest` before dispatch
    /// (e.g. combining `X-Firebase-AppCheck` with a user `Authorization: Bearer` header).
    public static func custom(
        _ modifier: @escaping @Sendable (inout URLRequest) async throws -> Void
    ) -> ProxyCredential {
        ProxyCredential(modifier: modifier)
    }
}
