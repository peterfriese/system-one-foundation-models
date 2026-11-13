import Foundation
import FoundationModels
import SystemOneFoundationModels

// MARK: - Choosable Release Gate Action

enum ReleaseGateAction: String, Choosable, CaseIterable {
    case approveCanary = "Approve Canary Rollout"
    case requireSecurityReview = "Require Security Review"
    case blockDeployment = "Block Production Deployment"

    var optionIdentifier: String {
        rawValue
    }

    var optionDescription: String? {
        switch self {
        case .approveCanary:
            return "Low-risk change with passing tests and clean blast-radius profile"
        case .requireSecurityReview:
            return "Touches authentication, IAM permissions, or billing schemas needing sign-off"
        case .blockDeployment:
            return "Active regression, failing migration check, or severe production outage risk"
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

print("=== 07-CloudOpenAIDecisions: Enterprise Release Gate Evaluation ===")
print("Backend: OpenAI Decisions API (gpt-6-luna)")
print("Binary footprint: Ultra-lean OpenAI-only trait (Zero Core ML, Jev, Laya, or Clef targets linked)")

guard let apiKey = nonEmptyEnv("OPENAI_API_KEY") else {
    print("""
    ================================================================================
      ⚠️  CONFIGURATION ERROR: MISSING OPENAI_API_KEY
    ================================================================================
      This example application requires a valid OpenAI API key to evaluate real
      OpenAI Decisions API models (gpt-6-luna). Synthetic mock bypasses are not
      permitted.

      Remediation:
        export OPENAI_API_KEY="sk-..."
        # Optional multi-tenant enterprise headers:
        # export OPENAI_ORGANIZATION="org-..."
        # export OPENAI_PROJECT="proj-..."
    ================================================================================
    """)
    exit(1)
}

let organization = nonEmptyEnv("OPENAI_ORGANIZATION")
let project = nonEmptyEnv("OPENAI_PROJECT")
let endpointURL: URL
if let rawURL = nonEmptyEnv("OPENAI_DECISIONS_URL") {
    guard let parsed = URL(string: rawURL),
          let scheme = parsed.scheme?.lowercased(), (scheme == "https" || scheme == "http"),
          parsed.host != nil else {
        print("Invalid OPENAI_DECISIONS_URL: '\(rawURL)'")
        exit(1)
    }
    endpointURL = parsed
} else {
    endpointURL = OpenAIDecisionsEndpoint.defaultURL
}

let endpoint = OpenAIDecisionsEndpoint(
    url: endpointURL,
    model: OpenAIDecisionsEndpoint.defaultModel,
    organization: organization,
    project: project
)

print("Mode: Live OpenAI Decisions API (Key: \(apiKey.prefix(5))..., Endpoint: \(endpoint.url.absoluteString))")

let model = OpenAIDecisionsLanguageModel(endpoint: endpoint, apiKey: apiKey)
let session = LanguageModelSession(model: model)

let changeSummary = """
CHANGE REQUEST #CR-4082
Service: checkout-token-vault (Tier-0 PCI scope)
Diff Summary: Updates OAuth2 JWT signature verification cache TTL from 60s to 24h and modifies
IAM role binding for cross-region KMS key decryption. Unit tests pass (142/142); no load test run.
"""

print("\n--- Release Change Request ---")
print(changeSummary.trimmingCharacters(in: .whitespacesAndNewlines))
print("------------------------------\n")

print("Evaluating release gate decisions via LanguageModelSession...")

// 1. Evaluate security-sensitive blast radius probability
let touchesAuthOrKeys = try await session.probability(
    of: "Does this change modify authentication, cryptographic key access, or PCI-scoped security controls?",
    state: changeSummary
)

// 2. Choose deployment gate action
let gateChoice = try await session.choice(
    "Select the release gate action for this production change request",
    from: ReleaseGateAction.self,
    state: changeSummary
)

// 3. Score operational blast radius rubric
let riskLevels = [
    "Minimal Risk",
    "Low Risk",
    "Moderate Risk",
    "High Blast Radius"
]
let blastRadiusScore = try await session.score(
    "Score the production blast radius of this change request",
    levels: riskLevels,
    state: changeSummary
)

let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
let securityJudgement = policy.decide(Probability(clamping: touchesAuthOrKeys))
let gateRouting = policy.decide(confidence: gateChoice.confidence)

print("\n=== Release Gate Decisions ===")
print("• Security/Crypto Control Impact: \(String(format: "%.1f%%", touchesAuthOrKeys * 100)) (Epistemic Routing: \(securityJudgement.decision))")
print("• Recommended Gate Action: \(gateChoice.value.rawValue) (Confidence: \(String(format: "%.1f%%", gateChoice.confidence * 100)), Policy: \(gateRouting))")
print("• Candidate Action Distribution:")
for (action, prob) in gateChoice.distribution.sorted(by: { $0.value > $1.value }) {
    print("    - \(action.rawValue): \(String(format: "%.1f%%", prob * 100))")
}
print("• Blast Radius Rubric Score: \(String(format: "%.2f", blastRadiusScore.value)) / \(riskLevels.count - 1).00 — \(blastRadiusScore.mostLikelyLevel) (Confidence: \(String(format: "%.1f%%", blastRadiusScore.confidence * 100)))")
print("\nEvaluation successfully completed via OpenAI Foundation Models.")
