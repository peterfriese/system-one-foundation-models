import Foundation

/// Supported Cloudflare Clef multimodal decision model variants.
public enum ClefModel: String, Codable, Sendable, CaseIterable {
    case clef = "clef"
    case clefFlash = "clef-flash"

    /// The Cloudflare Workers AI model identifier string.
    public var workersAIIdentifier: String {
        switch self {
        case .clef:
            return "@cf/cloudflare/clef"
        case .clefFlash:
            return "@cf/cloudflare/clef-flash"
        }
    }

    /// User-friendly display title for the model.
    public var displayName: String {
        switch self {
        case .clef:
            return "Cloudflare Clef (27B)"
        case .clefFlash:
            return "Cloudflare Clef-Flash (9B)"
        }
    }
}
