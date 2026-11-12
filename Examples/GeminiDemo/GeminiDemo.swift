import Foundation
import FoundationModels
import SystemOneCore
import GeminiFoundationModels

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
    var clientRequestID: String?
    var customURL: URL?
    var customPrompt: String?
}

func parseArguments() -> DemoConfiguration {
    let env = ProcessInfo.processInfo.environment
    var config = DemoConfiguration(
        apiKey: env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"],
        clientRequestID: nil,
        customURL: nil,
        customPrompt: nil
    )

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--key", "-k":
            config.apiKey = iterator.next()
        case "--request-id", "-r":
            config.clientRequestID = iterator.next()
        case "--url", "-u":
            if let val = iterator.next(), let url = URL(string: val) {
                config.customURL = url
            }
        case "--help", "-h":
            print("""
            Google Gemini Decisions API (gemini-decision-1) Demonstrator ⚡️

            USAGE:
              gemini-demo [OPTIONS] [CUSTOM_PROMPT]

            OPTIONS:
              -k, --key <key>         Gemini API Key (or GEMINI_API_KEY / GOOGLE_API_KEY environment variable)
              -r, --request-id <id>   Client Request ID header (X-Client-Request-Id)
              -u, --url <url>         Custom endpoint URL (default: https://generativelanguage.googleapis.com/v1beta/decisions)
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

@main
struct GeminiDemo {
    static func main() async {
        let config = parseArguments()

        // 1. Strict Verification of Credentials (AGENTS.md Directive 7)
        guard let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            print("""
            ==============================================================
            🛑 CONFIGURATION REQUIRED: Google Gemini API Key Missing
            ==============================================================
            The Google Gemini Decisions API requires a Gemini API key with access to gemini-decision-1.

            To remediate, export your API key:
              export GEMINI_API_KEY="AIza..."

            (Alternatively, you may set GOOGLE_API_KEY="AIza...")

            Then re-run:
              swift run gemini-demo
            ==============================================================
            """)
            exit(1)
        }

        let endpointURL = config.customURL ?? GeminiDecisionsEndpoint.defaultURL
        let endpoint = GeminiDecisionsEndpoint(
            url: endpointURL,
            model: GeminiDecisionsEndpoint.defaultModel,
            clientRequestID: config.clientRequestID
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
          System One Foundation Models — Google Gemini Decisions Demo ⚡️
        ==============================================================
        Endpoint:          \(endpoint.url.absoluteString)
        Model:             \(endpoint.model)
        Client Request ID: \(endpoint.clientRequestID ?? "none")

        Customer Ticket:
        --------------------------------------------------------------
        \(sampleEmail.trimmingCharacters(in: .whitespacesAndNewlines))
        --------------------------------------------------------------

        Evaluating decision via Apple Foundation Models LanguageModelSession...
        """)

        let languageModel = GeminiDecisionsLanguageModel(
            endpoint: endpoint,
            apiKey: apiKey
        )
        let session = LanguageModelSession(model: languageModel)

        let clock = ContinuousClock()
        let startTime = clock.now

        do {
            let response = try await session.respond(
                to: sampleEmail,
                generating: InboundEmailTriageDecision.self
            )

            let elapsed = startTime.duration(to: clock.now)
            let totalDurationMs = Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) / 1e15
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

            // Operational Confidence Routing (See tech-notes/0006-http-resilience-and-confidence-routing.md)
            let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
            print("Operational Confidence Routing (Policy: auto ≥ \(formatPercentage(policy.autoAtOrAbove)), escalate < \(formatPercentage(policy.escalateBelow)), undecided: \(formatPercentage(policy.undecidedBand.lowerBound))–\(formatPercentage(policy.undecidedBand.upperBound))):")
            print("--------------------------------------------------------------")

            let urgentProb = response.probability(for: "isUrgent")
            let urgentProbStr = urgentProb.map(formatPercentage) ?? "n/a"
            let judgement = response.judgement(for: "isUrgent", policy: policy)
            let decisivenessStr = formatPercentage(judgement.decisiveness)
            switch judgement.decision {
            case .auto:
                if judgement.answer == true {
                    print("  • Urgency Judgement:   [AUTO-ESCALATE] ──► Confidently urgent (Prob: \(urgentProbStr), Decisiveness: \(decisivenessStr))")
                } else {
                    print("  • Urgency Judgement:   [AUTO-NORMAL]   ──► Confidently non-urgent (Prob: \(urgentProbStr), Decisiveness: \(decisivenessStr))")
                }
            case .confirm:
                let leaning = judgement.answer == true ? "urgent" : "non-urgent"
                print("  • Urgency Judgement:   [CONFIRM]       ──► Leaning \(leaning), human review advised (Prob: \(urgentProbStr), Decisiveness: \(decisivenessStr))")
            case .escalate:
                print("  • Urgency Judgement:   [ESCALATE]      ──► Undecided / low decisiveness, manual triage required (Prob: \(urgentProbStr), Decisiveness: \(decisivenessStr))")
            }

            let deptConf = response.confidence(for: "department")
            let deptConfStr = deptConf.map(formatPercentage) ?? "n/a"
            print("  • Department Routing:  \(decision.department.displayName) (Confidence: \(deptConfStr))")

            if let scoreVal = response.scoreValue(for: "sentimentScore") {
                print("  • Sentiment Score:     \(String(format: "%.2f", scoreVal.value)) / 5 (Rounded: \(scoreVal.rounded), Confidence: \(formatPercentage(scoreVal.confidence)))")
            }

            // Usage & Telemetry
            print("""

            Usage & Telemetry:
            --------------------------------------------------------------
              • Input Tokens:     \(response.usage.input.totalTokenCount) ($0.10 / 1M)
              • Output Tokens:    \(response.usage.output.totalTokenCount) ($0.00 / 1M — Non-autoregressive forward pass)
            """)
            if let serverMs = response.serverDurationMs {
                print(String(format: "  • Server Duration:  %.1fms (Model execution on Google Gemini edge)", serverMs))
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
            Verify your GEMINI_API_KEY has access to gemini-decision-1.
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
    }
}
