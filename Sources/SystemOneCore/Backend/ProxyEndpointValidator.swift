import Foundation

/// Validates proxy endpoint URLs to prevent accidental transmission of attestation or bearer tokens
/// over unencrypted HTTP connections to remote hosts.
public enum ProxyEndpointValidator: Sendable {
    /// Validates that `url` uses `https://` for remote hosts or `http://` strictly for local loopback
    /// (`localhost`, `127.0.0.1`, `::1`, `[::1]`).
    ///
    /// - Throws: `SystemOneError.networkError` if the URL scheme is insecure for a non-loopback host.
    public static func validate(_ url: URL) throws {
        let scheme = url.scheme?.lowercased()
        if scheme == "https", let host = url.host, !host.isEmpty {
            return
        }
        if scheme == "http", let host = url.host?.lowercased() {
            if host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" {
                return
            }
        }
        throw SystemOneError.networkError(
            "Insecure proxy endpoint: HTTPS is required for remote proxy connections."
        )
    }
}
