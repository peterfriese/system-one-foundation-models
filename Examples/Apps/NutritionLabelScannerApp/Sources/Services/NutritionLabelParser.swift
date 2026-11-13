import Foundation
import Vision

// MARK: - Multilingual Nutrition Label & Ingredients OCR Parser (EU / DE / US / FR)

public struct NutritionLabelParser: Sendable {

    /// Reconstructs natural horizontal lines from 2D Vision text observations using vertical row clustering.
    /// Fixes the common problem where two-column nutrition tables are read column-by-column rather than row-by-row.
    public static func reconstructSpatialLines(from observations: [VNRecognizedTextObservation]) -> [String] {
        struct Fragment {
            let text: String
            let box: CGRect
        }

        let fragments = observations.compactMap { obs -> Fragment? in
            guard let str = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                  !str.isEmpty else { return nil }
            return Fragment(text: str, box: obs.boundingBox)
        }

        guard !fragments.isEmpty else { return [] }

        // Row clustering tolerance (2.8% of image height)
        let rowTolerance: CGFloat = 0.028
        var rows: [[Fragment]] = []

        for fragment in fragments {
            if let rowIndex = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.box.midY - fragment.box.midY) < rowTolerance
            }) {
                rows[rowIndex].append(fragment)
            } else {
                rows.append([fragment])
            }
        }

        // Sort rows from top to bottom (Vision Y is 0 at bottom, 1 at top)
        rows.sort { ($0.first?.box.midY ?? 0) > ($1.first?.box.midY ?? 0) }

        // Within each row, sort left-to-right (minX ascending)
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
               .map(\.text)
               .joined(separator: " ")
        }
    }

    /// Checks if a recognized OCR block contains markers indicative of a nutrition facts label or ingredients statement.
    public static func isNutritionLabelOrIngredients(_ text: String) -> Bool {
        let lower = text.lowercased()
        var markersFound = 0

        let multilingualMarkers = [
            // English (FDA / UK)
            "nutrition facts",
            "serving size",
            "calories",
            "total fat",
            "saturated fat",
            "sodium",
            "total carbohydrate",
            "dietary fiber",
            "sugars",
            "protein",
            "ingredients",
            "contains:",

            // German (EU / DACH)
            "nährwerte",
            "nährwert",
            "durchschnittliche nährwerte",
            "brennwert",
            "energie",
            "fettsäuren",
            "fett",
            "gesättigte",
            "gesättigten",
            "kohlenhydrate",
            "davon zucker",
            "zucker",
            "ballaststoffe",
            "eiweiß",
            "eiweiss",
            "weib", // Common OCR substitution for Eiweiß
            "salz",
            "zutaten",
            "kann spuren enthalten",
            "pro 100g",
            "pro 100 g",
            "1439 kj",
            "kcal",
            "kca",

            // French (EU)
            "valeurs nutritionnelles",
            "matières grasses",
            "acides gras saturés",
            "glucides",
            "dont sucres",
            "protéines",
            "sel",
            "ingrédients"
        ]

        for marker in multilingualMarkers {
            if lower.contains(marker) {
                markersFound += 1
            }
        }

        let hasIngredientsHeader = lower.contains("ingredients") || lower.contains("zutaten") || lower.contains("ingrédients")
        return markersFound >= 2 || (hasIngredientsHeader && text.count > 25)
    }

    /// Extracts structured NutritionFacts from raw OCR text across English (FDA) and European/German (EU) formats.
    public static func parseNutritionFacts(from text: String) -> NutritionFacts {
        let lower = text.lowercased()

        // 1. Serving Size
        var servingSize = "100g"
        if lower.contains("pro 100 g") || lower.contains("pro 100g") || lower.contains("pour 100 g") {
            servingSize = "100g"
        } else if let match = extractRegexMatch(pattern: #"(?:serving size|portionsgröße|portion)[\s:]*([^\n\r,]+)"#, in: lower) {
            servingSize = match.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Calories / Energie / Brennwert (kcal)
        // Handles "341 kcal", "341 kca", "1439 kJ / 341 kcal", "100 kJ / 24 kcal"
        let calories: Int = {
            if let kcalMatch = extractRegexMatch(pattern: #"(?:/\s*)?(\d+)\s*kca[l]?"#, in: lower),
               let val = Int(kcalMatch) {
                return val
            }
            if let calMatch = extractRegexMatch(pattern: #"(?:calories|energie|brennwert|energy)[\s:]*(\d+)"#, in: lower),
               let val = Int(calMatch) {
                return val
            }
            return 0
        }()

        // 3. Total Fat / Fett
        var totalFat = extractDecimal(
            pattern: #"(?<!gesättigte[n\s])(?:total fat|fett|matières grasses)[\s:]*[<>]?\s*([\d,\.]+)"#,
            in: lower
        ) ?? 0.0

        // 4. Saturated Fat / gesättigte Fettsäuren
        var satFat = extractDecimal(
            pattern: #"(?:davon\s+)?(?:gesättigte[n\s]*(?:fettsäuren)?|saturated fat|acides gras saturés)[\s:]*[<>]?\s*([\d,\.]+)"#,
            in: lower
        ) ?? 0.0

        // 5. Total Carbohydrate / Kohlenhydrate
        var totalCarbs = extractDecimal(
            pattern: #"(?:total carb(?:ohydrate)?s?|kohlenhydrate|glucides)[\s:]*[-–•\s]*[<>]?\s*([\d,\.]+)"#,
            in: lower
        ) ?? 0.0

        // 6. Fiber / Ballaststoffe
        var fiber = extractDecimal(
            pattern: #"(?:(?:dietary\s+)?fiber|ballaststoffe|fibres)[\s:]*[-–•\s]*[<>]?\s*([\d,\.]+)"#,
            in: lower
        ) ?? 0.0

        // 7. Total Sugars / Zucker
        var totalSugars = extractDecimal(
            pattern: #"(?:davon\s+zucker|total sugars?|zucker|dont sucres)[\s:]*[-–•\s]*[<>]?\s*([\d,\.]+)"#,
            in: lower
        ) ?? 0.0

        // 8. Added Sugars (FDA format)
        let addedSugars = extractDecimal(
            pattern: #"(?:includes|incl\.?)?\s*([\d,\.]+)\s*g?\s*added sugars?"#,
            in: lower
        ) ?? 0.0

        // 9. Protein / Eiweiß / Eiweiss / weib
        var protein = extractDecimal(
            pattern: #"(?:eiweiß|eiweiss|wei[bßB]|protein|protéines)[\s:]*[-–•\s]*[<>]?\s*([\d,\.]+)"#,
            in: lower
        ) ?? 0.0

        // 10. Sodium / Salz (1g Salz ≈ 400mg Sodium)
        var sodiumMilligrams: Int = {
            if let usSodium = extractFirstNumber(pattern: #"sodium[\s:]*(\d+)\s*mg"#, in: lower) {
                return usSodium
            }
            if let euSaltGrams = extractDecimal(pattern: #"(?:salz|salt|sel)[\s:]*[<>]?\s*([\d,\.]+)\s*g"#, in: lower) {
                return Int(euSaltGrams * 400.0)
            }
            return 0
        }()

        // Pass 2: Columnar EU Sequence Fallback
        // If row-based parsing yielded all zeros, extract standalone numbers with grams in document order
        if totalFat == 0.0 && totalCarbs == 0.0 && protein == 0.0 {
            let gramValues = extractSequentialGrams(from: text)
            // EU standard order: Fett, SatFat, Kohlenhydrate, Zucker, Ballaststoffe, Eiweiss, Salz
            if gramValues.count >= 4 {
                totalFat = gramValues[safe: 0] ?? 0.0
                if gramValues.count >= 6 {
                    satFat = gramValues[safe: 1] ?? 0.0
                    totalCarbs = gramValues[safe: 2] ?? 0.0
                    totalSugars = gramValues[safe: 3] ?? 0.0
                    fiber = gramValues[safe: 4] ?? 0.0
                    protein = gramValues[safe: 5] ?? 0.0
                    if let saltGrams = gramValues[safe: 6] {
                        sodiumMilligrams = Int(saltGrams * 400.0)
                    }
                } else {
                    totalCarbs = gramValues[safe: 1] ?? 0.0
                    fiber = gramValues[safe: 2] ?? 0.0
                    protein = gramValues[safe: 3] ?? 0.0
                    if let saltGrams = gramValues[safe: 4] {
                        sodiumMilligrams = Int(saltGrams * 400.0)
                    }
                }
            }
        }

        return NutritionFacts(
            servingSize: servingSize,
            calories: calories,
            totalFatGrams: totalFat,
            saturatedFatGrams: satFat,
            sodiumMilligrams: sodiumMilligrams,
            totalCarbGrams: totalCarbs,
            dietaryFiberGrams: fiber,
            totalSugarGrams: totalSugars,
            addedSugarGrams: addedSugars,
            proteinGrams: protein
        )
    }

    /// Isolates the ingredient list and allergen statement from the OCR block.
    public static func extractIngredientsAndAllergens(from text: String) -> (ingredients: String, warning: String?) {
        let lower = text.lowercased()

        // 1. Check for Allergen Warnings / Spurenhinweise
        var warning: String? = nil
        let warningKeywords = ["contains:", "kann spuren enthalten:", "kann spuren von", "spuren von:", "allergene:"]
        for kw in warningKeywords {
            if let kwRange = lower.range(of: kw) {
                let warningText = text[kwRange.upperBound...]
                    .components(separatedBy: CharacterSet.newlines)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let w = warningText, !w.isEmpty {
                    warning = "Allergens: " + w
                    break
                }
            }
        }

        // 2. Check for Ingredients header ("zutaten:", "ingredients:", "ingrédients:")
        let ingredientHeaders = ["zutaten:", "zutaten", "ingredients:", "ingrédients:"]
        for header in ingredientHeaders {
            if let headerRange = lower.range(of: header) {
                let ingredientsBody = text[headerRange.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (ingredientsBody, warning)
            }
        }

        // If this is purely a nutrition facts table without an explicit ingredients header, inform user
        if isNutritionLabelOrIngredients(text) && !lower.contains("zutaten") && !lower.contains("ingredients") {
            return ("Nutrition table scanned. Point camera at the 'Zutaten' / Ingredients list to verify allergen safety with Jev.", warning)
        }

        return (text.trimmingCharacters(in: .whitespacesAndNewlines), warning)
    }

    // MARK: - European Decimal & Regex Extraction Helpers

    private static func extractRegexMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        guard let first = results.first, first.numberOfRanges > 1 else { return nil }
        return nsString.substring(with: first.range(at: 1))
    }

    private static func extractDecimal(pattern: String, in text: String) -> Double? {
        guard let match = extractRegexMatch(pattern: pattern, in: text) else { return nil }
        var cleaned = match.replacingOccurrences(of: "<", with: "")
                           .replacingOccurrences(of: ">", with: "")
                           .replacingOccurrences(of: "-", with: "")
                           .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private static func extractFirstNumber(pattern: String, in text: String) -> Int? {
        guard let match = extractRegexMatch(pattern: pattern, in: text) else { return nil }
        return Int(match.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Extracts numbers that are attached to 'g' in document order (e.g. ["1.5", "50", "13", "26", "0.01"]).
    private static func extractSequentialGrams(from text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"[-–<>]?\s*([\d,\.]+)\s*g\b"#, options: [.caseInsensitive]) else { return [] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        var values = matches.compactMap { match -> Double? in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
            return Double(raw)
        }

        // If the first extracted value is 100.0 (the standard EU serving size header "pro 100g"), drop it
        if values.first == 100.0 && (text.lowercased().contains("100 g") || text.lowercased().contains("100g")) {
            values.removeFirst()
        }

        return values
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
