import Foundation
import SystemOneCore

/// Utilities for temperature scaling and calibrated confidence calculation.
///
/// See `tech-notes/0008-on-device-coreml-decision-engine.md`.
public struct TemperatureCalibration: Sendable {
    public static let tempMin: Double = 0.5
    public static let tempMax: Double = 5.0

    /// Returns the calibration bucket key for a question type and option count.
    public static func tempBucket(qtype: Int, optionCount: Int) -> String {
        let typeName: String
        switch qtype {
        case 0: typeName = "choice"
        case 1: typeName = "score"
        case 2: typeName = "noul"
        default: typeName = "unknown"
        }

        let size: String
        if optionCount <= 2 {
            size = "2"
        } else if optionCount <= 5 {
            size = "3-5"
        } else if optionCount <= 10 {
            size = "6-10"
        } else {
            size = "11+"
        }
        return "\(typeName):\(size)"
    }

    /// Clamps temperature scaling to a reliable numerical range `[0.5, 5.0]`.
    public static func clampTemperature(_ t: Double) -> Double {
        if t.isNaN || t.isInfinite {
            return 1.0
        }
        return min(tempMax, max(tempMin, t))
    }

    /// Applies temperature scaling and softmax over raw logits to produce probabilities.
    public static func softmax(logits: [Double], temperature: Double) -> [Double] {
        guard !logits.isEmpty else { return [] }
        let uniform = Array(repeating: 1.0 / Double(logits.count), count: logits.count)
        guard logits.allSatisfy(\.isFinite) else { return uniform }

        let clampedTemp = clampTemperature(temperature)
        let scaled = logits.map { $0 / clampedTemp }
        guard let maxVal = scaled.max(), maxVal.isFinite else { return uniform }

        let exps = scaled.map { exp($0 - maxVal) }
        let sumExp = exps.reduce(0.0, +)
        guard sumExp.isFinite, sumExp > 0 else { return uniform }
        return exps.map { $0 / sumExp }
    }

    /// Computes calibrated answer confidence: `max(p)` across the candidate probabilities.
    /// Returns `0.0` when `probabilities` is empty or contains no finite values so `RoutingPolicy` safely escalates.
    public static func answerConfidence(probabilities: [Double]) -> Double {
        guard !probabilities.isEmpty,
              probabilities.allSatisfy(\.isFinite),
              let maxP = probabilities.max() else {
            return 0.0
        }
        return min(1.0, max(0.0, maxP))
    }
}
