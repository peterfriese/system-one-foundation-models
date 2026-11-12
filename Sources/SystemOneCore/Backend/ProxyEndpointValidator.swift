import Foundation

/// Validates proxy endpoint URLs to prevent accidental transmission of attestation or bearer tokens
/// over unencrypted HTTP connections to remote hosts.
///
/// See tech-notes/0010-proxy-transport-and-dynamic-attestation.md
public enum ProxyEndpointValidator: Sendable {
    /// Validates that `url` uses `https://` for remote hosts or `http://` strictly for local loopback
    /// (`localhost`, `127.0.0.1`, `::1`, `[::1]`), has a non-empty host, and embeds no URL credentials.
    ///
    /// - Throws: `SystemOneError.networkError` if the URL embeds credentials, omits a host, or uses an insecure scheme.
    public static func validate(_ url: URL) throws {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.user != nil || url.password != nil || components?.user != nil || components?.password != nil {
            throw SystemOneError.networkError(
                "Proxy endpoint URL must not contain embedded user credentials."
            )
        }

        let rawHost = url.host(percentEncoded: false) ?? components?.host
        guard let scheme = url.scheme?.lowercased(),
              let host = rawHost?.lowercased(),
              !host.isEmpty else {
            throw SystemOneError.networkError(
                "Invalid proxy endpoint URL '\(url.absoluteString)': missing scheme or host."
            )
        }

        if scheme == "https" {
            return
        }
        if scheme == "http", host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" {
            return
        }

        throw SystemOneError.networkError(
            "Insecure proxy endpoint: HTTPS is required for remote proxy connections (\(url.absoluteString))."
        )
    }
}
