import Foundation
import FoundationModels
import SystemOneFoundationModels

// 1. Compile-time proof that `traits: ["Remote"]` EXCLUDES on-device Core ML (`LayaOnDevice`):
#if canImport(LayaOnDevice)
#error("LayaOnDevice must NOT be compiled when building with the 'Remote' persona trait!")
#endif

// 2. Compile-time proof that `traits: ["Remote"]` ACTIVATES all 5 networked System One providers:
#if !(canImport(JevFoundationModels) && canImport(LayaFoundationModels) && canImport(ClefFoundationModels) && canImport(OpenAIFoundationModels) && canImport(GeminiFoundationModels))
#error("Expected all 5 remote System One providers (Jev, LayaServe, Clef, OpenAI, Gemini) under 'Remote' trait!")
#endif

// MARK: - Structured @Generable Decision

@Generable
enum EscalationQueue: String, CaseIterable, Sendable {
    case automatedSelfService = "automated_self_service"
    case accountSpecialist = "account_specialist"
    case incidentCommander = "incident_commander"
}

@Generable
struct IncidentRoutingDecision: Sendable {
    @Guide(description: "Does this report describe a production-impacting outage or security incident?")
    var isProductionIncident: Bool

    @Guide(description: "Which operational queue should own this report?")
    var queue: EscalationQueue

    @Guide(description: "Severity rubric from 0 (informational) to 3 (critical Sev-0)", .range(0...3))
    var severityLevel: Int
}

// MARK: - Remote Provider Resolver

struct ActiveRemoteBackend: Sendable {
    let label: String
    let makeSession: @Sendable () -> LanguageModelSession

    static func resolveFromEnvironment() -> ActiveRemoteBackend? {
        let env = ProcessInfo.processInfo.environment

        if let proxyRaw = env["SYSTEM_ONE_PROXY_URL"], let proxyURL = URL(string: proxyRaw) {
            let credential: ProxyCredential
            if let token = env["SYSTEM_ONE_PROXY_TOKEN"], !token.isEmpty {
                credential = .bearer { token }
            } else {
                credential = .custom { _ in }
            }
            let model = SystemOneLanguageModel(proxyEndpoint: proxyURL, credential: credential)
            return ActiveRemoteBackend(label: "SystemOneProxyBackend (\(proxyURL.host ?? proxyRaw))") {
                LanguageModelSession(model: model)
            }
        }
        if let key = env["TYPESAFE_API_KEY"], !key.isEmpty {
            let model = JevLanguageModel(apiKey: key)
            return ActiveRemoteBackend(label: "JevLanguageModel (TypeSafe Cloud)") {
                LanguageModelSession(model: model)
            }
        }
        if let key = env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"], !key.isEmpty {
            let model = GeminiLanguageModel(apiKey: key)
            return ActiveRemoteBackend(label: "GeminiLanguageModel (Google Gemini Decisions)") {
                LanguageModelSession(model: model)
            }
        }
        if let key = env["OPENAI_API_KEY"], !key.isEmpty {
            let model = OpenAILanguageModel(apiKey: key)
            return ActiveRemoteBackend(label: "OpenAILanguageModel (OpenAI Decisions)") {
                LanguageModelSession(model: model)
            }
        }
        if let accountID = env["CLOUDFLARE_ACCOUNT_ID"], !accountID.isEmpty,
           let token = env["CLOUDFLARE_API_TOKEN"], !token.isEmpty {
            let model = ClefLanguageModel(endpoint: .workersAI(accountID: accountID, model: .clefFlash), apiToken: token)
            return ActiveRemoteBackend(label: "ClefLanguageModel (Cloudflare Workers AI)") {
                LanguageModelSession(model: model)
            }
        }
        if let rawURL = env["LAYA_SERVE_URL"], let url = URL(string: rawURL) {
            let model = LayaLanguageModel(endpoint: .custom(url), apiKey: env["LAYA_API_KEY"])
            return ActiveRemoteBackend(label: "LayaLanguageModel (\(url.absoluteString))") {
                LanguageModelSession(model: model)
            }
        }
        return nil
    }
}

print("=== 09-RemotePersonaRouter: Multi-Cloud 'Remote' Persona Trait ===")
print("Compiled Providers: Jev • LayaServe • Clef • OpenAI • Gemini • SystemOneProxyBackend")
print("Excluded Providers: LayaOnDevice (Zero Core ML / ANE binary weight for server & thin-client builds)\n")

guard let backend = ActiveRemoteBackend.resolveFromEnvironment() else {
    print("""
    ================================================================================
      ⚠️  CONFIGURATION ERROR: NO REMOTE PROVIDER CREDENTIALS DETECTED
    ================================================================================
      09-RemotePersonaRouter compiles all 5 remote System One providers under the
      aggregate `traits: ["Remote"]` persona without linking Core ML (`LayaOnDevice`).
      Provide credentials for at least one remote backend to run live evaluation:

      Remediation (pick any remote provider):
        export TYPESAFE_API_KEY="your-typesafe-key"
        # or: export GEMINI_API_KEY="AIza..."
        # or: export OPENAI_API_KEY="sk-..."
        # or: export CLOUDFLARE_ACCOUNT_ID="..." CLOUDFLARE_API_TOKEN="..."
        # or: export LAYA_SERVE_URL="http://127.0.0.1:8000"
        # or: export SYSTEM_ONE_PROXY_URL="https://your-proxy.example.com/evaluate"
    ================================================================================
    """)
    exit(1)
}

print("Selected Remote Backend: \(backend.label)")

let incidentReport = """
ALERT #INC-7721: Primary EU-West Postgres read-replica lag jumped to 140 seconds
following schema migration #418; 18% of checkout read queries are timing out.
"""

print("\n--- Incoming Incident ---")
print(incidentReport.trimmingCharacters(in: .whitespacesAndNewlines))
print("-------------------------\n")

do {
    let session = backend.makeSession()
    let start = CFAbsoluteTimeGetCurrent()
    let response = try await session.respond(
        to: incidentReport,
        generating: IncidentRoutingDecision.self
    )
    let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

    let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
    let incidentJudgement = response.judgement(for: "isProductionIncident", policy: policy)
    let queueAction = response.decision(for: "queue", policy: policy)

    print("=== Structured Routing Result (\(String(format: "%.1fms", elapsedMs))) ===")
    print("• isProductionIncident: \(response.content.isProductionIncident) (Routing: \(incidentJudgement.decision))")
    print("• queue:                \(response.content.queue.rawValue) (Policy: \(queueAction))")
    print("• severityLevel:        \(response.content.severityLevel) / 3")
} catch {
    print("\n❌ Remote evaluation failed: \(error.localizedDescription)")
    exit(1)
}
