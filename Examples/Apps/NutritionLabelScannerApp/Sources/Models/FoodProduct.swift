import Foundation

// MARK: - Food Product Model

public struct NutritionFacts: Sendable, Equatable, Hashable {
    public let servingSize: String
    public let calories: Int
    public let totalFatGrams: Double
    public let saturatedFatGrams: Double
    public let sodiumMilligrams: Int
    public let totalCarbGrams: Double
    public let dietaryFiberGrams: Double
    public let totalSugarGrams: Double
    public let addedSugarGrams: Double
    public let proteinGrams: Double

    public var netCarbGrams: Double {
        max(0, totalCarbGrams - dietaryFiberGrams)
    }

    public init(
        servingSize: String,
        calories: Int,
        totalFatGrams: Double,
        saturatedFatGrams: Double,
        sodiumMilligrams: Int,
        totalCarbGrams: Double,
        dietaryFiberGrams: Double,
        totalSugarGrams: Double,
        addedSugarGrams: Double,
        proteinGrams: Double
    ) {
        self.servingSize = servingSize
        self.calories = calories
        self.totalFatGrams = totalFatGrams
        self.saturatedFatGrams = saturatedFatGrams
        self.sodiumMilligrams = sodiumMilligrams
        self.totalCarbGrams = totalCarbGrams
        self.dietaryFiberGrams = dietaryFiberGrams
        self.totalSugarGrams = totalSugarGrams
        self.addedSugarGrams = addedSugarGrams
        self.proteinGrams = proteinGrams
    }
}

public struct FoodProduct: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let brand: String
    public let name: String
    public let packageCategory: String
    public let barcode: String
    public let iconSystemName: String
    public let ingredientsText: String
    public let facilityWarning: String?
    public let nutrition: NutritionFacts

    public init(
        id: String,
        brand: String,
        name: String,
        packageCategory: String,
        barcode: String,
        iconSystemName: String,
        ingredientsText: String,
        facilityWarning: String?,
        nutrition: NutritionFacts
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.packageCategory = packageCategory
        self.barcode = barcode
        self.iconSystemName = iconSystemName
        self.ingredientsText = ingredientsText
        self.facilityWarning = facilityWarning
        self.nutrition = nutrition
    }

    /// Formats product state for Apple Foundation Models / Jev input.
    public func formattedState(for profile: DietaryProfile) -> String {
        var text = """
        User Active Dietary Profile: \(profile.title)
        Profile Rules: \(profile.promptGuidance)

        Food Product:
        - Brand: \(brand)
        - Name: \(name)
        - Category: \(packageCategory)
        - Barcode: \(barcode)

        Ingredients:
        \(ingredientsText)
        """

        if let warning = facilityWarning, !warning.isEmpty {
            text += "\n\nAllergen & Facility Statement:\n\(warning)"
        }

        text += """
        \n\nNutrition Facts (Per \(nutrition.servingSize)):
        - Calories: \(nutrition.calories)
        - Total Fat: \(nutrition.totalFatGrams)g (Sat: \(nutrition.saturatedFatGrams)g)
        - Sodium: \(nutrition.sodiumMilligrams)mg
        - Total Carbohydrate: \(nutrition.totalCarbGrams)g
        - Dietary Fiber: \(nutrition.dietaryFiberGrams)g
        - Net Carbohydrates: \(nutrition.netCarbGrams)g
        - Total Sugars: \(nutrition.totalSugarGrams)g (Added: \(nutrition.addedSugarGrams)g)
        - Protein: \(nutrition.proteinGrams)g
        """

        return text
    }
}

extension FoodProduct {
    public static let emptyWaitingForScan = FoodProduct(
        id: "waiting",
        brand: "Ready to Scan",
        name: "Point at Barcode or Label",
        packageCategory: "Live Scanner",
        barcode: "––",
        iconSystemName: "camera.viewfinder",
        ingredientsText: "Point camera at any barcode or nutrition label to verify dietary safety.",
        facilityWarning: nil,
        nutrition: NutritionFacts(
            servingSize: "––",
            calories: 0,
            totalFatGrams: 0,
            saturatedFatGrams: 0,
            sodiumMilligrams: 0,
            totalCarbGrams: 0,
            dietaryFiberGrams: 0,
            totalSugarGrams: 0,
            addedSugarGrams: 0,
            proteinGrams: 0
        )
    )
}
