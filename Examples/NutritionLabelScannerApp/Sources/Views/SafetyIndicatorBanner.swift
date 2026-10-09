import SwiftUI

// MARK: - (d) Safety Indicator Banner & Rubric Gauges

public struct SafetyIndicatorBanner: View {
    public let decision: DietarySafetyDecision?
    public let isSafeProbability: Double?
    public let latencyMs: Double
    public let profile: DietaryProfile
    public let isEvaluating: Bool

    public init(
        decision: DietarySafetyDecision?,
        isSafeProbability: Double?,
        latencyMs: Double,
        profile: DietaryProfile,
        isEvaluating: Bool
    ) {
        self.decision = decision
        self.isSafeProbability = isSafeProbability
        self.latencyMs = latencyMs
        self.profile = profile
        self.isEvaluating = isEvaluating
    }

    private var status: (tint: Color, icon: String, title: String, message: String) {
        if isEvaluating {
            return (.blue, "arrow.triangle.2.circlepath", "Analyzing...", "Evaluating against \(profile.shortName) profile")
        }

        guard let decision = decision else {
            return (.blue, "arrow.triangle.2.circlepath", "Scanning...", "Analyzing label via Jev System One")
        }

        if decision.isSafe {
            let detail = isSafeProbability.map { " (\(Int($0 * 100))% confidence)" } ?? ""
            return (
                .green,
                "checkmark.shield.fill",
                "Safe for \(profile.shortName)",
                "No conflicting allergens or ingredients detected\(detail)"
            )
        } else if decision.primaryFlag != .none {
            // Direct dietary conflict takes precedence over trace facility advisory
            return (
                .red,
                "xmark.octagon.fill",
                "Not Safe: \(decision.primaryFlag.displayName)",
                "Breaches \(profile.title) requirements"
            )
        } else if decision.allergenRisk == 1 {
            return (
                .orange,
                "exclamationmark.triangle.fill",
                "Advisory: Trace Exposure",
                "Manufactured on shared equipment with potential allergens"
            )
        } else {
            return (
                .red,
                "xmark.octagon.fill",
                "Not Safe: Conflict Detected",
                "Breaches \(profile.title) requirements"
            )
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main Hero Status Pill
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(status.tint.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: status.icon)
                        .font(.title3.bold())
                        .foregroundStyle(status.tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(status.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isEvaluating {
                    ProgressView()
                }
            }

            // (d) Supporting Indicator Badges
            if let decision = decision, !isEvaluating {
                let clampedAllergenRisk = min(max(0, decision.allergenRisk), 3)
                let clampedProcessingTier = min(max(0, decision.processingTier), 3)
                HStack(spacing: 8) {
                    // Allergen Level Gauge
                    IndicatorBadge(
                        label: "Allergen",
                        value: ["Clean", "Trace", "Hidden", "Direct"][clampedAllergenRisk],
                        tint: clampedAllergenRisk == 0 ? .green : (clampedAllergenRisk == 1 ? .orange : .red)
                    )

                    // NOVA Classification Index
                    IndicatorBadge(
                        label: "NOVA",
                        value: ["Whole (1)", "Culinary (2)", "Processed (3)", "Ultra-UPF (4)"][clampedProcessingTier],
                        tint: clampedProcessingTier <= 1 ? .green : (clampedProcessingTier == 2 ? .orange : .red)
                    )

                    // Calibrated Latency & Model
                    IndicatorBadge(
                        label: "Jev Latency",
                        value: String(format: "%.0f ms", latencyMs),
                        tint: .blue
                    )
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(status.tint.opacity(0.25), lineWidth: 1.5)
        )
    }
}

// MARK: - Compact Indicator Badge

private struct IndicatorBadge: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
