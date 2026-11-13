import Foundation
import FoundationModels
import SystemOneCore

func formatPercentage(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}

func extractRawJSONString(from content: GeneratedContent) -> String {
    if let str = try? content.value(String.self) {
        return str
    }
    return content.jsonString
}

func printPrettyAnalytics(from metadata: [String: GeneratedContent]) {
    print("\nDecision Analytics & Calibration:")
    print("--------------------------------------------------------------")

    if let modelContent = metadata["model"] {
        let modelID = (try? modelContent.value(String.self))
            ?? modelContent.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        print("  • Model:            \(modelID)")
    }

    if let confContent = metadata["confidence"] {
        let rawJSON = extractRawJSONString(from: confContent)
        if let confData = rawJSON.data(using: .utf8),
           let confDict = try? JSONSerialization.jsonObject(with: confData) as? [String: Double] {
            print("\n  Confidence Scores:")
            for key in confDict.keys.sorted() {
                let confVal = confDict[key] ?? 0.0
                let paddedKey = key.padding(toLength: 18, withPad: " ", startingAt: 0)
                print("    • \(paddedKey) \(formatPercentage(confVal))")
            }
        }
    }

    if let probsContent = metadata["probabilities"] {
        let rawJSON = extractRawJSONString(from: probsContent)
        if let probsData = rawJSON.data(using: .utf8),
           let probsDict = try? JSONSerialization.jsonObject(with: probsData) as? [String: [String: Double]] {
            print("\n  Calibrated Probabilities:")
            for key in probsDict.keys.sorted() {
                print("    • \(key):")
                let subDict = probsDict[key] ?? [:]
                for outcome in subDict.keys.sorted() {
                    let prob = subDict[outcome] ?? 0.0
                    let paddedOutcome = outcome.padding(toLength: 14, withPad: " ", startingAt: 0)
                    print("      - \(paddedOutcome) \(formatPercentage(prob))")
                }
            }
        }
    }
}
