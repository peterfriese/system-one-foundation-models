import Foundation
import FoundationModels
import SystemOneCore

// MARK: - Item Category Schema

/// Standard item categories for visual inspection and item triage with Cloudflare Clef.
@Generable
public enum ItemCategory: String, Sendable, CaseIterable, Codable {
    case snack
    case beverage
    case electronics
    case document
    case household
    case person
    case clothing
    case plant
    case accessory
    case unknown

    /// User-friendly display label.
    public var displayName: String {
        switch self {
        case .snack: return "Snack / Food"
        case .beverage: return "Beverage"
        case .electronics: return "Electronics"
        case .document: return "Document / Paper"
        case .household: return "Household Goods"
        case .person: return "Person / Hand"
        case .clothing: return "Clothing / Apparel"
        case .plant: return "Plant / Flora"
        case .accessory: return "Personal Accessory"
        case .unknown: return "Unknown Object"
        }
    }

    /// Associated SF Symbol name for Apple platforms.
    public var systemImageName: String {
        switch self {
        case .snack: return "fork.knife"
        case .beverage: return "cup.and.saucer.fill"
        case .electronics: return "laptopcomputer"
        case .document: return "doc.text.fill"
        case .household: return "house.fill"
        case .person: return "hand.raised.fill"
        case .clothing: return "tshirt.fill"
        case .plant: return "leaf.fill"
        case .accessory: return "key.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Visual Inspection Decision Schema

/// A multimodal visual inspection decision evaluating item presence, classification, physical condition, and safety.
@Generable
public struct VisualInspectionDecision: Sendable, Codable, Equatable {
    @Guide(description: "Is a physical item or subject clearly recognized in the camera view?")
    public var isRecognized: Bool

    @Guide(description: "Primary category classification of the recognized item")
    public var itemCategory: ItemCategory

    @Guide(description: "Physical condition rubric: 0 (unusable/damaged), 1 (worn), 2 (good), 3 (pristine)", .range(0...3))
    public var conditionScore: Int

    @Guide(description: "Safety approval: does the item satisfy safety standards without visible hazards, damage, or contamination?")
    public var safetyApproval: Bool

    public init(
        isRecognized: Bool = false,
        itemCategory: ItemCategory = .unknown,
        conditionScore: Int = 0,
        safetyApproval: Bool = false
    ) {
        self.isRecognized = isRecognized
        self.itemCategory = itemCategory
        self.conditionScore = conditionScore
        self.safetyApproval = safetyApproval
    }

    /// Human-readable condition label for rubric levels 0...3.
    public static func conditionLabel(for score: Int) -> String {
        switch score {
        case 0: return "Unusable / Damaged"
        case 1: return "Worn"
        case 2: return "Good"
        case 3: return "Pristine"
        default: return "Score \(score)"
        }
    }
}

// MARK: - Response Ergonomics for Visual Inspection

public extension LanguageModelSession.Response where Content == VisualInspectionDecision {
    /// Extracts the calibrated `ScoreValue` for `conditionScore`.
    var conditionScoreValue: ScoreValue? {
        scoreValue(for: "conditionScore")
    }

    /// Evaluates the calibrated routing judgement for `isRecognized`.
    func recognizedJudgement(policy: RoutingPolicy = .default) -> NoulJudgement {
        judgement(for: "isRecognized", policy: policy)
    }

    /// Evaluates the calibrated routing judgement for `safetyApproval`.
    func safetyJudgement(policy: RoutingPolicy = .default) -> NoulJudgement {
        judgement(for: "safetyApproval", policy: policy)
    }

    /// Evaluates the categorical decision action for `itemCategory`.
    func categoryDecision(policy: RoutingPolicy = .default) -> Decision {
        decision(for: "itemCategory", policy: policy)
    }

    /// Calibrated confidence score (0.0 to 1.0) for `itemCategory`, if available.
    var categoryConfidence: Double? {
        confidence(for: "itemCategory")
    }
}
