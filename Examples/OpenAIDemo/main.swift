import Foundation
import FoundationModels
import SystemOneCore
import OpenAIFoundationModels

// MARK: - @Generable Decision Schema

@Generable
enum TriageDepartment: String, Sendable, CaseIterable {
    case billing
    case technicalSupport
    case accountSecurity
    case sales
    case generalFeedback

    var displayName: String {
        switch self {
        case .billing: return "Billing & Invoicing"
        case .technicalSupport: return "Technical Support"
        case .accountSecurity: return "Account Security & Fraud"
        case .sales: return "Enterprise Sales"
        case .generalFeedback: return "General Inquiries"
        }
    }
}

@Generable
struct InboundEmailTriageDecision: Sendable {
    @Guide(description: "Determine whether the inquiry requires urgent escalation within 1 hour.")
    var isUrgent: Bool

    @Guide(description: "Select the primary operational department responsible for resolving this customer ticket.")
    var department: TriageDepartment

    @Guide(description: "Rate customer sentiment on a 1 (deeply frustrated) to 5 (delighted) rubric.", .range(1...5))
    var sentimentScore: Int
}

// MARK: - CLI Configuration & Parsing

struct DemoConfiguration {
    var apiKey: String?
    var organization: String?
    var project: String?
    var customURL: URL?
    var customPrompt: String?
}

func parseArguments() -> DemoConfiguration {
    var config = DemoConfiguration(
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        organization: ProcessInfo.processInfo.environment["OPENAI_ORGANIZATION"],
        project: ProcessInfo.processInfo.environment["OPENAI_PROJECT"],
        customURL: nil,
        customPrompt: nil
    )

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--key", "-k":
            config.apiKey = iterator.next()
        case "--org", "-o":
            config.organization = iterator.next()
        case "--proj", "-p":
            config.project = iterator.next()
        case "--url", "-u":
            if let val = iterator.next(), let url = URL(string: val) {
                config.customURL = url
            }
        case "--help", "-h":
            print("""
            OpenAI Decisions API (GPT-6 Luna) Demonstrator ⚡️

            USAGE:
              openai-demo [OPTIONS] [CUSTOM_PROMPT]

            OPTIONS:
              -k, --key <key>         OpenAI API Key (or OPENAI_API_KEY environment variable)
              -o, --org <id>          OpenAI Organization ID (or OPENAI_ORGANIZATION)
              -p, --proj <id>         OpenAI Project ID (or OPENAI_PROJECT)
              -u, --url <url>         Custom endpoint URL (default: https://api.openai.com/v1/decisions)
              -h, --help              Show help information
            """)
            exit(0)
        default:
            if !arg.hasPrefix("-") && config.customPrompt == nil {
                config.customPrompt = arg
            }
        }
    }

    return config
}

func formatPercentage(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}

// MARK: - Main Execution

let config = parseArguments()

// 1. Strict Verification of Credentials (AGENTS.md Directive 7)
guard let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
    print("""
    ==============================================================
    🛑 CONFIGURATION REQUIRED: OpenAI API Key Missing
    ==============================================================
    The OpenAI Decisions API requires an OpenAI API key with access to gpt-6-luna.

    To remediate, export your API key:
      export OPENAI_API_KEY="sk-..."

    Optionally configure multi-tenant enterprise headers:
      export OPENAI_ORGANIZATION="org-..."
      export OPENAI_PROJECT="proj-..."

    Then re-run:
      swift run openai-demo
    ==============================================================
    """)
    exit(1)
}

let endpointURL = config.customURL ?? OpenAIDecisionsEndpoint.defaultURL
let endpoint = OpenAIDecisionsEndpoint(
    url: endpointURL,
    model: OpenAIDecisionsEndpoint.defaultModel,
    organization: config.organization,
    project: config.project
)

let sampleEmail = config.customPrompt ?? """
Subject: URGENT: Production database connection failed after billing update
Hi team,
Our production services went down 10 minutes ago because our subscription status shows 'suspended'
even though our corporate credit card was charged $4,500 this morning.
We have 15,000 active users affected right now! Please restore database access immediately!
— Alex, VP Infrastructure
"""

print("""
==============================================================
  System One Foundation Models — OpenAI Decisions Demo ⚡️
==============================================================
Endpoint:     \(endpoint.url.absoluteString)
Model:        \(endpoint.model)
Organization: \(endpoint.organization ?? "none")
Project:      \(endpoint.project ?? "none")

Customer Ticket:
--------------------------------------------------------------
\(sampleEmail.trimmingCharacters(in: .whitespacesAndNewlines))
--------------------------------------------------------------

Evaluating decision via Apple Foundation Models LanguageModelSession...
""")

let languageModel = OpenAIDecisionsLanguageModel(
    endpoint: endpoint,
    apiKey: apiKey
)
let session = LanguageModelSession(model: languageModel)

let startTime = CFAbsoluteTimeGetCurrent()

do {
    let response = try await session.respond(
        to: sampleEmail,
        generating: InboundEmailTriageDecision.self
    )

    let totalDurationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
    let decision = response.content

    print("""

    Decision Evaluation Complete in \(String(format: "%.1f", totalDurationMs))ms!
    ==============================================================
      Structured Decision Result (@Generable InboundEmailTriageDecision)
    ==============================================================
      • isUrgent:         \(decision.isUrgent ? "URGENT 🚨" : "Normal 🟢")
      • department:       \(decision.department.displayName) (\(decision.department.rawValue))
      • sentimentScore:   Level \(decision.sentimentScore) / 5
    """)

    // Operational Confidence Routing
    let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
    print("Operational Confidence Routing (Policy: auto ≥ \(formatPercentage(policy.autoAtOrAbove)), escalate < \(formatPercentage(policy.escalateBelow))):")
    print("--------------------------------------------------------------")

    let urgentProb = response.probability(for: "isUrgent")
    let urgentProbStr = urgentProb.map(formatPercentage) ?? "n/a"
    if let p = urgentProb {
        if p >= policy.autoAtOrAbove {
            print("  • Urgency Judgement:   [AUTO-ESCALATE] ──► Confidently urgent (Prob: \(urgentProbStr))")
        } else if p < policy.escalateBelow {
            print("  • Urgency Judgement:   [AUTO-NORMAL]   ──► Confidently non-urgent (Prob: \(urgentProbStr))")
        } else {
            print("  • Urgency Judgement:   [CONFIRM]       ──► Borderline urgency (Prob: \(urgentProbStr))")
        }
    }

    let deptConf = response.confidence(for: "department")
    let deptConfStr = deptConf.map(formatPercentage) ?? "n/a"
    print("  • Department Routing:  \(decision.department.displayName) (Confidence: \(deptConfStr))")

    if let scoreVal = response.scoreValue(for: "sentimentScore") {
        print("  • Sentiment Score:     \(scoreVal.value) / 5 (Confidence: \(formatPercentage(scoreVal.confidence)))")
    }

    // Usage & Telemetry
    print("""

    Usage & Telemetry:
    --------------------------------------------------------------
      • Input Tokens:     \(response.usage.input.totalTokenCount) ($0.10 / 1M)
      • Output Tokens:    \(response.usage.output.totalTokenCount) ($0.00 / 1M — Non-autoregressive forward pass)
    """)
    if let serverMs = response.serverDurationMs {
        print(String(format: "  • Server Duration:  %.1fms (Model execution on OpenAI edge)", serverMs))
    }
    if let transportMs = response.transportDurationMs {
        print(String(format: "  • Transport Time:   %.1fms (HTTP roundtrip)", transportMs))
    }
    print(String(format: "  • Total Session:    %.1fms (Swift wall clock)", totalDurationMs))
    print("==============================================================\n")

} catch let error as SystemOneError {
    print("""

    ==============================================================
    ❌ SYSTEM ONE ERROR
    ==============================================================
    \(error.localizedDescription)

    💡 Troubleshooting:
    Verify your OPENAI_API_KEY has access to gpt-6-luna.
    ==============================================================
    """)
    exit(1)
} catch {
    print("""

    ==============================================================
    ❌ NETWORK / RUNTIME ERROR
    ==============================================================
    \(error.localizedDescription)
    ==============================================================
    """)
    exit(1)
}
