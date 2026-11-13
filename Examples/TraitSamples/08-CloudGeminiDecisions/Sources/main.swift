import Foundation
import FoundationModels
import SystemOneFoundationModels

// Compile-time verification that `traits: ["Gemini"]` links ONLY GeminiFoundationModels + SystemOneCore:
#if canImport(LayaOnDevice) || canImport(JevFoundationModels) || canImport(LayaFoundationModels) || canImport(ClefFoundationModels) || canImport(OpenAIFoundationModels)
#error("Unexpected sibling provider module compiled when building with isolated traits: [\"Gemini\"]")
#endif

// MARK: - Choosable Moderation Action

enum ContentModerationAction: String, Choosable, CaseIterable, Sendable {
    case publishImmediately = "Publish Immediately"
    case holdForHumanReview = "Hold for Human Review"
    case quarantineViolation = "Quarantine Policy Violation"

    var optionIdentifier: String { rawValue }

    var optionDescription: String? {
        switch self {
        case .publishImmediately:
            return "Safe community contribution adhering to platform safety and authenticity guidelines"
        case .holdForHumanReview:
            return "Ambiguous claims, borderline promotional links, or context-dependent moderation edge case"
        case .quarantineViolation:
            return "Credential phishing, malicious links, impersonation, or clear safety policy breach"
        }
    }
}

func nonEmptyEnv(_ key: String) -> String? {
    guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return nil
    }
    return raw
}

print("=== 08-CloudGeminiDecisions: Calibrated Trust & Safety Triage ===")
print("Backend: Google Gemini Decisions API (gemini-decision-1)")
print("Binary footprint: Ultra-lean Gemini-only trait (Zero Core ML, Jev, Laya, Clef, or OpenAI targets linked)")

guard let apiKey = nonEmptyEnv("GEMINI_API_KEY") ?? nonEmptyEnv("GOOGLE_API_KEY") else {
    print("""
    ================================================================================
      ⚠️  CONFIGURATION ERROR: MISSING GEMINI_API_KEY
    ================================================================================
      This example application requires a valid Google Gemini API key to evaluate
      real Gemini Decisions models. Synthetic mock bypasses are not permitted.

      Remediation:
        export GEMINI_API_KEY="AIza..."
        swift run --package-path Examples/TraitSamples/08-CloudGeminiDecisions
    ================================================================================
    """)
    exit(1)
}

let modelName = nonEmptyEnv("GEMINI_MODEL") ?? GeminiDecisionsEndpoint.defaultModel
let endpoint: GeminiDecisionsEndpoint
if let rawURL = nonEmptyEnv("GEMINI_DECISIONS_URL") {
    guard let parsed = URL(string: rawURL) else {
        print("Invalid GEMINI_DECISIONS_URL: '\(rawURL)'")
        exit(1)
    }
    endpoint = GeminiDecisionsEndpoint(url: parsed, model: modelName)
} else {
    endpoint = GeminiDecisionsEndpoint(model: modelName)
}

let model = GeminiLanguageModel(endpoint: endpoint, apiKey: apiKey)
let session = LanguageModelSession(model: model)

let postSubmission = """
SUBMISSION #POST-9184
Author Account Age: 2 hours (0 prior posts)
Post Body: "Urgent notice for workspace admins: SSO certificates expire in 30 minutes!
Re-authenticate your admin session immediately at https://sso-verify-portal-check.example/login
to prevent workspace lockout."
"""

print("\n--- Submitted Community Post ---")
print(postSubmission.trimmingCharacters(in: .whitespacesAndNewlines))
print("--------------------------------\n")

print("Evaluating calibrated logprob decisions via LanguageModelSession...")

do {
    let phishingProb = try await session.probability(
        of: "Does this post attempt credential phishing, social engineering, or admin impersonation?",
        state: postSubmission
    )

    let moderationChoice = try await session.choice(
        "Select the moderation enforcement action for this submission",
        from: ContentModerationAction.self,
        state: postSubmission
    )

    let severityLevels = [
        "Benign",
        "Low Risk",
        "Suspicious",
        "Critical Phishing Threat"
    ]
    let severityScore = try await session.score(
        "Score the trust & safety threat severity of this post",
        levels: severityLevels,
        state: postSubmission
    )

    let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
    let phishingJudgement = policy.decide(Probability(clamping: phishingProb))
    let actionRouting = policy.decide(confidence: moderationChoice.confidence)

    print("\n=== Gemini Calibrated Decisions ===")
    print("• Phishing / Impersonation Probability: \(String(format: "%.1f%%", phishingProb * 100)) (Routing: \(phishingJudgement.decision))")
    print("• Moderation Action: \(moderationChoice.value.rawValue) (Confidence: \(String(format: "%.1f%%", moderationChoice.confidence * 100)), Policy: \(actionRouting))")
    print("• Candidate Distribution:")
    for (action, prob) in moderationChoice.distribution.sorted(by: { $0.value > $1.value }) {
        print("    - \(action.rawValue): \(String(format: "%.1f%%", prob * 100))")
    }
    print("• Threat Severity Score: \(String(format: "%.2f", severityScore.value)) / \(severityLevels.count - 1).00 — \(severityScore.mostLikelyLevel)")
    print("\nEvaluation successfully completed via Gemini Foundation Models.")
} catch {
    print("\n❌ Gemini Decisions evaluation failed: \(error.localizedDescription)")
    exit(1)
}
