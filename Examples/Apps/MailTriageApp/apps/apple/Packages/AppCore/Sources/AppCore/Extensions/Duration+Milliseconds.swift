import Foundation

extension Duration {
    /// Wall-clock milliseconds calculated from seconds and attoseconds.
    public var asMilliseconds: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) * 1_000.0 + Double(attoseconds) * 1e-15
    }

    /// Wall-clock seconds calculated from seconds and attoseconds.
    public var asSeconds: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}
