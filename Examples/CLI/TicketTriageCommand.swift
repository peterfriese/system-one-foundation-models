import Foundation
import FoundationModels
import SystemOneCore

@Generable
enum Department: String, Sendable {
    case billing
    case engineering
    case sales
}

@Generable
struct TicketTriage: Sendable {
    @Guide(description: "Is this customer inquiry urgent or blocking?")
    var isUrgent: Bool

    @Guide(description: "Which team should resolve this issue?")
    var department: Department

    @Guide(description: "Customer frustration score from 0 (calm) to 2 (hostile)", .range(0...2))
    var frustrationLevel: Int
}

enum TicketTriageCommand {
    static func run(provider: ConfiguredProvider, arguments: [String]) async {
        let customText = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let ticket = customText.isEmpty ? defaultTicket : customText

        print("""
        ==============================================================
          System One CLI — Ticket Triage
        ==============================================================
        Provider: \(provider.provider.displayName)
        Endpoint: \(provider.endpointSummary)

        Input Context / State:
        --------------------------------------------------------------
        \(ticket)
        --------------------------------------------------------------

        Evaluating decision via Apple LanguageModelSession...
        """)

        let session = provider.makeSession()
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let response = try await session.respond(
                to: ticket,
                generating: TicketTriage.self
            )
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
            printResults(response, durationMs: durationMs, policy: policy)
        } catch {
            provider.failFastOnError(error)
        }
    }

    private static let defaultTicket = """
    Customer Ticket #8492:
    "I was double-charged on invoice #1042 this morning. The charge went through twice on our corporate Amex card, exceeding our department limit and pausing our production server deployment. Please refund the duplicate charge immediately!"
    """

    private static func printResults(
        _ response: LanguageModelSession.Response<TicketTriage>,
        durationMs: Double,
        policy: RoutingPolicy
    ) {
        print("\nEvaluation Complete in \(String(format: "%.1f", durationMs))ms!")
        print("==============================================================")
        print("  Structured Decision Result (@Generable TicketTriage)")
        print("==============================================================")
        print("  • isUrgent:         \(response.content.isUrgent)")
        print("  • department:       \(response.content.department)")
        print("  • frustrationLevel: \(response.content.frustrationLevel) / 2")

        print("\nOperational Confidence Routing (Policy: auto ≥ \(formatPercentage(policy.autoAtOrAbove)), escalate < \(formatPercentage(policy.escalateBelow))):")
        print("--------------------------------------------------------------")

        let deptDecision = response.decision(for: "department", policy: policy)
        let confStr = response.confidence(for: "department").map(formatPercentage) ?? "n/a"
        switch deptDecision {
        case .auto:
            print("  • Department Action:  [AUTO-ROUTE] ──► Route directly to \(response.content.department) inbox (Confidence: \(confStr))")
        case .confirm:
            print("  • Department Action:  [SUGGESTION] ──► Suggest \(response.content.department), prompt triage agent (Confidence: \(confStr))")
        case .escalate:
            print("  • Department Action:  [ESCALATE]   ──► Route to manual supervisor queue (Confidence: \(confStr))")
        }

        let urgentJudgement = response.judgement(for: "isUrgent", policy: policy)
        let probStr = response.probability(for: "isUrgent").map(formatPercentage) ?? "n/a"
        switch urgentJudgement.decision {
        case .auto:
            if urgentJudgement.answer == true {
                print("  • Urgency Action:     [P0 CRITICAL] ──► Confident urgent; page on-call response team (Prob: \(probStr))")
            } else {
                print("  • Urgency Action:     [STANDARD SLA] ──► Confident routine; standard queue (Prob: \(probStr))")
            }
        case .confirm:
            print("  • Urgency Action:     [CONFIRM PRIORITY] ──► Leaning priority; prompt agent to confirm (Prob: \(probStr))")
        case .escalate:
            print("  • Urgency Action:     [UNDECIDED ESCALATE] ──► Model inside 0.35...0.65 band; manual triage (Prob: \(probStr))")
        }

        if let frustrationScore = response.scoreValue(for: "frustrationLevel") {
            let normStr = frustrationScore.normalized.map { String(format: "%.2f", $0) } ?? "n/a"
            print("  • Frustration Rubric: Weighted: \(String(format: "%.2f", frustrationScore.value)) | Rounded: Level \(frustrationScore.rounded) | Normalized: \(normStr)")
        }

        print("\nUsage & Telemetry:")
        print("--------------------------------------------------------------")
        print("  • Input tokens:     \(response.usage.input.totalTokenCount)")
        print("  • Output tokens:    \(response.usage.output.totalTokenCount)")
        if let serverMs = response.serverDurationMs {
            print(String(format: "  • Server Duration:  %.1fms", serverMs))
        }
        if let transportMs = response.transportDurationMs {
            print(String(format: "  • Transport Time:   %.1fms", transportMs))
        }

        for entry in response.transcriptEntries {
            if case .response(let r) = entry {
                printPrettyAnalytics(from: r.metadata)
            }
        }
        print("==============================================================\n")
    }
}
