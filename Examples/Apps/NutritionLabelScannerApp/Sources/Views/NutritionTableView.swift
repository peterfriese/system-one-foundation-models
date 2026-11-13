import SwiftUI

// MARK: - (b) Apple Health Style Nutrition Values Display

public struct NutritionTableView: View {
    public let nutrition: NutritionFacts

    public init(nutrition: NutritionFacts) {
        self.nutrition = nutrition
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Calories Display Card
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ENERGY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(nutrition.calories)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("kcal")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("SERVING SIZE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(nutrition.servingSize)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(14)
            .background(Color(uiColor: .tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Tabular Nutrient Rows
            VStack(spacing: 0) {
                NutrientRow(title: "Net Carbohydrates", value: String(format: "%.1f g", nutrition.netCarbGrams), isProminent: true)
                Divider()
                NutrientRow(title: "Total Carbohydrates", value: String(format: "%.1f g", nutrition.totalCarbGrams))
                Divider()
                NutrientRow(title: "Dietary Fiber", value: String(format: "%.1f g", nutrition.dietaryFiberGrams), isIndented: true)
                Divider()
                NutrientRow(title: "Total Sugars", value: String(format: "%.1f g", nutrition.totalSugarGrams), isIndented: true)
                Divider()
                NutrientRow(
                    title: "Added Sugars",
                    value: String(format: "%.1f g", nutrition.addedSugarGrams),
                    isIndented: true,
                    highlightColor: nutrition.addedSugarGrams > 5 ? .orange : nil
                )
                Divider()
                NutrientRow(title: "Total Fat", value: String(format: "%.1f g", nutrition.totalFatGrams))
                Divider()
                NutrientRow(title: "Saturated Fat", value: String(format: "%.1f g", nutrition.saturatedFatGrams), isIndented: true)
                Divider()
                NutrientRow(title: "Protein", value: String(format: "%.1f g", nutrition.proteinGrams), isProminent: true)
                Divider()
                NutrientRow(title: "Sodium", value: "\(nutrition.sodiumMilligrams) mg")
            }
            .padding(.horizontal, 14)
            .background(Color(uiColor: .tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Nutrient Row Component

private struct NutrientRow: View {
    let title: String
    let value: String
    var isProminent: Bool = false
    var isIndented: Bool = false
    var highlightColor: Color? = nil

    var body: some View {
        HStack {
            if isIndented {
                Text("–")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }

            Text(title)
                .font(isProminent ? .subheadline.bold() : .subheadline)
                .foregroundStyle(isIndented ? .secondary : .primary)

            Spacer()

            if let highlight = highlightColor {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(highlight)
            } else {
                Text(value)
                    .font(isProminent ? .subheadline.bold() : .subheadline)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 10)
    }
}
