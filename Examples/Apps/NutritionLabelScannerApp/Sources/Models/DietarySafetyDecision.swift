import Foundation
import FoundationModels

// MARK: - @Generable Decision Schema for Dietary Safety & Nutrition

@Generable
public enum DietaryFlag: String, Sendable, CaseIterable, Codable {
    case none
    case hiddenGluten
    case dairyOrLactose
    case seedOils
    case highAddedSugar
    case artificialSweeteners
    case excessiveSodium
    case animalDerivatives

    public var displayName: String {
        switch self {
        case .none: return "Clean / No Flags"
        case .hiddenGluten: return "Hidden Gluten (e.g. Barley/Malt)"
        case .dairyOrLactose: return "Dairy / Lactose"
        case .seedOils: return "Refined Seed / Vegetable Oils"
        case .highAddedSugar: return "High Added Sugars (>10g)"
        case .artificialSweeteners: return "Artificial / Non-Nutritive Sweeteners"
        case .excessiveSodium: return "High Sodium (>400mg)"
        case .animalDerivatives: return "Animal Derivatives / Non-Vegan"
        }
    }

    public var iconName: String {
        switch self {
        case .none: return "checkmark.seal.fill"
        case .hiddenGluten: return "exclamationmark.triangle.fill"
        case .dairyOrLactose: return "drop.triangle.fill"
        case .seedOils: return "flame.fill"
        case .highAddedSugar: return "cube.transparent.fill"
        case .artificialSweeteners: return "atom"
        case .excessiveSodium: return "water.waves"
        case .animalDerivatives: return "leaf.arrow.triangle.circlepath"
        }
    }
}

@Generable
public struct DietarySafetyDecision: Sendable, Equatable, Codable {
    @Guide(description: """
    Answer true ONLY if the product is fully compliant with the user's dietary restriction profile, \
    free of conflicting ingredients, hidden aliases, and high-risk allergens. \
    Answer false if any allergen, restricted derivative, or conflicting threshold is breached.
    """)
    public var isSafe: Bool

    @Guide(
        description: """
        Allergen and cross-contamination risk rubric: \
        0 = Certified clean or allergen-free; \
        1 = Ambiguous or trace facility risk ('May contain traces of...'); \
        2 = Contains derived ingredient or hidden alias; \
        3 = Contains explicit direct allergen.
        """,
        .range(0...3)
    )
    public var allergenRisk: Int

    @Guide(
        description: """
        NOVA food processing classification index: \
        0 = Group 1 (Unprocessed or minimally processed whole foods); \
        1 = Group 2 (Processed culinary ingredients like oils, butter, salt); \
        2 = Group 3 (Processed foods, canned goods, simple cheeses, whole bread); \
        3 = Group 4 (Ultra-processed food products with industrial additives, emulsifiers, isolates).
        """,
        .range(0...3)
    )
    public var processingTier: Int

    @Guide(description: "The primary dietary conflict, allergen risk, or nutritional warning flag detected in this item.")
    public var primaryFlag: DietaryFlag

    public init(
        isSafe: Bool,
        allergenRisk: Int,
        processingTier: Int,
        primaryFlag: DietaryFlag
    ) {
        self.isSafe = isSafe
        self.allergenRisk = allergenRisk
        self.processingTier = processingTier
        self.primaryFlag = primaryFlag
    }
}
