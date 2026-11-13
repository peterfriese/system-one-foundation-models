import Foundation
import FoundationModels
import SystemOneFoundationModels

// Compile-time verification that `traits: ["All"]` activates all 6 System One provider modules:
#if !(canImport(LayaOnDevice) && canImport(LayaFoundationModels) && canImport(JevFoundationModels) && canImport(ClefFoundationModels) && canImport(OpenAIFoundationModels) && canImport(GeminiFoundationModels))
#error("Expected all 6 System One provider modules to be available under traits: [\"All\"]")
#endif

// MARK: - Choosable Priority

enum ActionPriority: String, Choosable, CaseIterable, Sendable {
    case routine = "Routine"
    case elevated = "Elevated"
    case urgent = "Urgent"

    var optionIdentifier: String { rawValue }

    var optionDescription: String? {
        switch self {
        case .routine:
            return "General inquiries, minor cosmetic issues, non-blocking requests"
        case .elevated:
            return "Single-user workflow blockage, degraded performance, intermittent glitches"
        case .urgent:
            return "Total service outage, data corruption, severe revenue loss or security breach"
        }
    }
}

// MARK: - Escalation Cloud Tier Resolution

enum CloudEscalationTier: Sendable {
    case jev(JevLanguageModel)
    case gemini(GeminiLanguageModel)
    case openai(OpenAILanguageModel)
    case clef(ClefLanguageModel)
    case layaServe(LayaLanguageModel)

    var name: String {
        switch self {
        case .jev: return "Cloud Jev (TypeSafe AI)"
        case .gemini: return "Cloud Gemini Decisions (Google)"
        case .openai: return "Cloud OpenAI Decisions"
        case .clef: return "Cloudflare Clef Workers AI"
        case .layaServe: return "Remote Laya-Serve Cluster"
        }
    }

    func makeSession() -> LanguageModelSession {
        switch self {
        case .jev(let model): return LanguageModelSession(model: model)
        case .gemini(let model): return LanguageModelSession(model: model)
        case .openai(let model): return LanguageModelSession(model: model)
        case .clef(let model): return LanguageModelSession(model: model)
        case .layaServe(let model): return LanguageModelSession(model: model)
        }
    }

    static func resolveFromEnvironment() -> CloudEscalationTier? {
        let env = ProcessInfo.processInfo.environment
        if let key = env["TYPESAFE_API_KEY"], !key.isEmpty {
            return .jev(JevLanguageModel(apiKey: key))
        }
        if let key = env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"], !key.isEmpty {
            return .gemini(GeminiLanguageModel(apiKey: key))
        }
        if let key = env["OPENAI_API_KEY"], !key.isEmpty {
            return .openai(OpenAILanguageModel(apiKey: key))
        }
        if let accountID = env["CLOUDFLARE_ACCOUNT_ID"], !accountID.isEmpty,
           let token = env["CLOUDFLARE_API_TOKEN"], !token.isEmpty {
            return .clef(ClefLanguageModel(endpoint: .workersAI(accountID: accountID, model: .clefFlash), apiToken: token))
        }
        if let rawURL = env["LAYA_SERVE_URL"], let url = URL(string: rawURL) {
            return .layaServe(LayaLanguageModel(endpoint: .custom(url), apiKey: env["LAYA_API_KEY"]))
        }
        return nil
    }
}

// MARK: - Hybrid Router Orchestrator

actor HybridRouter {
    private let localSession: LanguageModelSession
    private let cloudTier: CloudEscalationTier
    private let cloudSession: LanguageModelSession
    private let policy: RoutingPolicy

    init(
        localEngine: LayaCoreMLEngine,
        cloudTier: CloudEscalationTier,
        policy: RoutingPolicy = RoutingPolicy(escalateBelow: 0.80, autoAtOrAbove: 0.80)
    ) {
        self.policy = policy
        self.localSession = LanguageModelSession(model: LayaOnDeviceLanguageModel(engine: localEngine))
        self.cloudTier = cloudTier
        self.cloudSession = cloudTier.makeSession()
    }

    struct RouteResult: Sendable {
        let text: String
        let resolvedPriority: ActionPriority
        let confidence: Double
        let tier: String
        let latencyEstimate: String
    }

    func classify(text: String) async throws -> RouteResult {
        // Step 1: Evaluate locally on Apple Neural Engine via LayaOnDevice
        let localChoice = try await localSession.choice(
            "Determine the triage priority",
            from: ActionPriority.self,
            state: text
        )

        // Step 2: Check confidence against routing policy threshold (0.80)
        let decision = policy.decide(confidence: localChoice.confidence)

        if decision == .auto {
            return RouteResult(
                text: text,
                resolvedPriority: localChoice.value,
                confidence: localChoice.confidence,
                tier: "On-Device Laya (Apple Neural Engine)",
                latencyEstimate: "< 2ms (0 bytes sent, $0 cloud cost)"
            )
        } else {
            // Step 3: Confidence < 0.80 -> Escalate to configured cloud decision provider
            let cloudChoice = try await cloudSession.choice(
                "Determine the triage priority",
                from: ActionPriority.self,
                state: text
            )

            return RouteResult(
                text: text,
                resolvedPriority: cloudChoice.value,
                confidence: cloudChoice.confidence,
                tier: "\(cloudTier.name) (Escalated: Local confidence \(String(format: "%.1f%%", localChoice.confidence * 100)) < 80%)",
                latencyEstimate: "~30-80ms round-trip"
            )
        }
    }
}

// MARK: - Main Execution

print("=== 04-HybridRouter: Local-First Intelligent Confidence Routing ===")
print("Active Trait: All (LayaOnDevice + Jev + LayaServe + Clef + OpenAI + Gemini)")
print("Policy: Local Laya evaluated first on ANE; escalates to Cloud when confidence < 80%\n")

func resolveModelURL() -> URL? {
    if let envPath = ProcessInfo.processInfo.environment["LAYA_MODEL_PATH"], !envPath.isEmpty {
        let url = URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    let standardURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/dev.peterfriese.mailtriageapp/Models/LayaDecisionModel.mlmodelc")
    if FileManager.default.fileExists(atPath: standardURL.path) {
        return standardURL
    }

    return nil
}

var missingPrerequisites: [String] = []
var remediations: [String] = []

let resolvedCloudTier = CloudEscalationTier.resolveFromEnvironment()
if resolvedCloudTier == nil {
    missingPrerequisites.append("• No cloud escalation credential found (TYPESAFE_API_KEY, GEMINI_API_KEY, OPENAI_API_KEY, CLOUDFLARE_API_TOKEN, or LAYA_SERVE_URL).")
    remediations.append("export TYPESAFE_API_KEY=\"your-key\"  # or GEMINI_API_KEY / OPENAI_API_KEY")
}

let modelURL = resolveModelURL()
if modelURL == nil {
    let standardPath = "~/Library/Application Support/dev.peterfriese.mailtriageapp/Models/LayaDecisionModel.mlmodelc"
    missingPrerequisites.append("• Compiled Core ML model not found at \(standardPath) or LAYA_MODEL_PATH.")
    remediations.append("export LAYA_MODEL_PATH=\"/path/to/LayaDecisionModel.mlmodelc\"")
}

if !missingPrerequisites.isEmpty {
    print("""
    ================================================================================
      ⚠️  CONFIGURATION ERROR: MISSING HYBRID ROUTER PREREQUISITES
    ================================================================================
      The Hybrid Router evaluates requests locally on Apple Neural Engine first,
      escalating to a cloud System One provider when confidence falls below 80%.
      Synthetic mocks and fallbacks are not permitted.

      Missing Configuration:
    \(missingPrerequisites.map { "  " + $0 }.joined(separator: "\n"))

      Remediation:
    \(remediations.map { "  " + $0 }.joined(separator: "\n"))
    ================================================================================
    """)
    exit(1)
}

guard let validModelURL = modelURL, let validCloudTier = resolvedCloudTier else {
    exit(1)
}

let tokenizer = ModernBERTTokenizer.defaultTokenizer()
let localEngine: LayaCoreMLEngine
do {
    localEngine = try LayaCoreMLEngine(modelURL: validModelURL, tokenizer: tokenizer)
} catch {
    print("""
    ================================================================================
      ⚠️  CONFIGURATION ERROR: FAILED TO LOAD CORE ML MODEL
    ================================================================================
      Failed to load Core ML model at: \(validModelURL.path)
      Underlying error: \(error.localizedDescription)

      Remediation:
        xcrun coremlc compile LayaDecisionModel.mlpackage <output-dir>
        export LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc"
    ================================================================================
    """)
    exit(1)
}

print("Escalation Target: \(validCloudTier.name)\n")
let router = HybridRouter(localEngine: localEngine, cloudTier: validCloudTier)

let scenarioA = "URGENT: 500 Internal Server Error when processing credit card transactions. 14 customers failed."
let scenarioB = "Noticed a slight formatting typo in the staging documentation footer, but not sure if it matters."

print("--- Scenario A: Clear Outage Alert ---")
let resultA = try await router.classify(text: scenarioA)
print("Input: \"\(resultA.text)\"")
print("Decision Tier: \(resultA.tier)")
print("Priority: \(resultA.resolvedPriority.rawValue)")
print("Confidence: \(String(format: "%.1f%%", resultA.confidence * 100))")
print("Latency: \(resultA.latencyEstimate)\n")

print("--- Scenario B: Ambiguous / Borderline Note ---")
let resultB = try await router.classify(text: scenarioB)
print("Input: \"\(resultB.text)\"")
print("Decision Tier: \(resultB.tier)")
print("Priority: \(resultB.resolvedPriority.rawValue)")
print("Confidence: \(String(format: "%.1f%%", resultB.confidence * 100))")
print("Latency: \(resultB.latencyEstimate)\n")

print("Hybrid edge-to-cloud evaluation completed successfully.")
