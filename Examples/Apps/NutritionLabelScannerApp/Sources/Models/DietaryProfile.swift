import Foundation

// MARK: - User Dietary Safety Profile

public struct DietaryProfile: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let shortName: String
    public let icon: String
    public let restrictionsDescription: String
    public let promptGuidance: String

    public init(
        id: String,
        title: String,
        shortName: String,
        icon: String,
        restrictionsDescription: String,
        promptGuidance: String
    ) {
        self.id = id
        self.title = title
        self.shortName = shortName
        self.icon = icon
        self.restrictionsDescription = restrictionsDescription
        self.promptGuidance = promptGuidance
    }
}

extension DietaryProfile {
    public static let celiacGlutenFree = DietaryProfile(
        id: "celiac",
        title: "Strict Celiac (Gluten-Free)",
        shortName: "Celiac",
        icon: "cross.case.fill",
        restrictionsDescription: "Zero tolerance for wheat, barley, rye, malt, triticale, spelt, or non-certified oats. Flag barley malt extract and shared lines.",
        promptGuidance: "User has severe Celiac Disease. Any trace of gluten, barley malt extract, maltodextrin from wheat, or shared wheat lines is hazardous."
    )

    public static let vegan = DietaryProfile(
        id: "vegan",
        title: "Strict Plant-Based / Vegan",
        shortName: "Vegan",
        icon: "leaf.fill",
        restrictionsDescription: "No animal products, meat, poultry, dairy, whey, casein, gelatin, honey, or insect-derived colorants (e.g. carmine/cochineal).",
        promptGuidance: "User eats strictly vegan. Disallow dairy, milk derivatives, egg whites, whey, lard, honey, gelatin, or carmine."
    )

    public static let keto = DietaryProfile(
        id: "keto",
        title: "Ketogenic / Low-Carb",
        shortName: "Keto",
        icon: "flame.fill",
        restrictionsDescription: "Net carbs must be <= 5g per serving. Avoid refined starches, cane sugar, syrups, maltodextrin, and flour.",
        promptGuidance: "User follows a strict ketogenic diet. Flag products exceeding 5g net carbs per serving or containing high-glycemic starches and sugars."
    )

    public static let diabetic = DietaryProfile(
        id: "diabetic",
        title: "Diabetic / Low Glycemic",
        shortName: "Diabetic",
        icon: "heart.text.square.fill",
        restrictionsDescription: "Added sugars must be <= 3g per serving. Minimize fast-acting sweeteners (corn syrup, sucrose, dextrose).",
        promptGuidance: "User manages diabetes/insulin sensitivity. Flag products with added sugars exceeding 3g per serving, high-fructose corn syrup, or dextrose."
    )

    public static let cleanWholeFood = DietaryProfile(
        id: "clean",
        title: "Whole Food / Anti-UPF",
        shortName: "Clean Food",
        icon: "apple.logo",
        restrictionsDescription: "Strict avoidance of NOVA 4 ultra-processed foods, industrial emulsifiers (lecithin, polysorbate), and refined seed oils.",
        promptGuidance: "User avoids ultra-processed foods (NOVA 4). Flag products with refined seed oils (canola, soybean, palm), gums, emulsifiers, or artificial flavorings."
    )

    public static let allProfiles: [DietaryProfile] = [
        .celiacGlutenFree,
        .vegan,
        .keto,
        .diabetic,
        .cleanWholeFood
    ]
}
