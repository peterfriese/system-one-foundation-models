import Foundation
import FoundationModels
import SystemOneFoundationModels

// MARK: - Choosable Warehouse Disposition

enum ParcelDisposition: String, Choosable, CaseIterable {
    case acceptToInventory = "Accept to Inventory"
    case holdForInspection = "Hold for Quality Inspection"
    case quarantineDamaged = "Quarantine Damaged Shipment"

    var optionIdentifier: String {
        rawValue
    }

    var optionDescription: String? {
        switch self {
        case .acceptToInventory:
            return "Intact packaging and item in good condition ready for fulfillment"
        case .holdForInspection:
            return "Minor cosmetic wear or ambiguous labeling requiring manual operator check"
        case .quarantineDamaged:
            return "Crushed parcel, structural damage, or safety hazard requiring quarantine"
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

func probeLocalRunner(url: URL, timeout: TimeInterval = 1.5) async -> Bool {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = timeout

    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeout
    config.timeoutIntervalForResource = timeout
    let session = URLSession(configuration: config)

    do {
        _ = try await session.data(for: request)
        return true
    } catch {
        return false
    }
}

func resolveImageURL(explicitPath: String?) -> URL {
    if let explicitPath {
        let expanded = (explicitPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("""
            ================================================================================
              ⚠️  CONFIGURATION ERROR: IMAGE FILE NOT FOUND
            ================================================================================
              Specified image file does not exist:
                \(url.path)

              Remediation:
                swift run EdgeClefVision /path/to/parcel.jpg
            ================================================================================
            """)
            exit(1)
        }
        return url
    }

    let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRelativeSample = sourceDir
        .appendingPathComponent("../../../Quickstarts/ClefQuickstart/sample.jpg")
        .standardizedFileURL
    let cwdSample = URL(fileURLWithPath: "Examples/Quickstarts/ClefQuickstart/sample.jpg")

    for candidate in [cwdSample, repoRelativeSample] {
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
    }

    print("""
    ================================================================================
      ⚠️  CONFIGURATION ERROR: SAMPLE IMAGE NOT FOUND
    ================================================================================
      Could not locate default sample image at:
        \(repoRelativeSample.path)

      Remediation:
        swift run EdgeClefVision /path/to/image.jpg
    ================================================================================
    """)
    exit(1)
}

print("=== 06-EdgeClefVision: Multimodal Edge Parcel & Asset Inspection ===")
print("Backend: Cloudflare Clef / Clef-Flash Multimodal Decision Model")
print("Binary footprint: Lean Clef-only trait (Zero Core ML, Jev, or OpenAI targets linked)")

let explicitImageArg = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
let imageURL = resolveImageURL(explicitPath: explicitImageArg)

let accountID = nonEmptyEnv("CLOUDFLARE_ACCOUNT_ID")
let apiToken = nonEmptyEnv("CLOUDFLARE_API_TOKEN")
let customEndpointEnv = nonEmptyEnv("CLEF_ENDPOINT")
let localPortEnv = nonEmptyEnv("CLEF_LOCAL_PORT")

let endpoint: ClefEndpoint
let modeDescription: String

if let customEndpointEnv, let customURL = URL(string: customEndpointEnv) {
    endpoint = .custom(customURL, model: .clefFlash)
    modeDescription = "Custom Clef Endpoint (\(customURL.absoluteString))"
} else if let accountID, let apiToken {
    if let gatewayID = nonEmptyEnv("CLOUDFLARE_GATEWAY_ID") {
        endpoint = .gateway(accountID: accountID, gatewayID: gatewayID, model: .clefFlash)
        modeDescription = "Cloudflare AI Gateway (\(gatewayID))"
    } else {
        endpoint = .workersAI(accountID: accountID, model: .clefFlash)
        modeDescription = "Cloudflare Workers AI Edge (Account: \(accountID.prefix(6))..., Token: \(apiToken.prefix(4))...)"
    }
} else if let localPortEnv, let port = Int(localPortEnv), (1...65535).contains(port) {
    let candidate = ClefEndpoint.local(port: port, model: .clefFlash)
    guard await probeLocalRunner(url: candidate.url) else {
        print("""
        ================================================================================
          ⚠️  CONFIGURATION ERROR: LOCAL CLEF RUNNER UNREACHABLE
        ================================================================================
          CLEF_LOCAL_PORT=\(port) is set, but no Clef runner responded at:
            \(candidate.url.absoluteString)
          Synthetic mock bypasses are not permitted.

          Remediation:
            docker run -p \(port):8000 ghcr.io/typesafe-ai/clef-flash:latest
            # Or evaluate via Cloudflare Workers AI:
            # export CLOUDFLARE_ACCOUNT_ID="your-cloudflare-account-id"
            # export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"
        ================================================================================
        """)
        exit(1)
    }
    endpoint = candidate
    modeDescription = "Local Clef Inference Runner (\(candidate.url.absoluteString))"
} else {
    print("""
    ================================================================================
      ⚠️  CONFIGURATION ERROR: MISSING CLEF CREDENTIALS OR RUNNER
    ================================================================================
      This example application requires either Cloudflare Workers AI credentials
      or a running local Clef inference daemon. Synthetic mock bypasses are not
      permitted.

      Remediation (Cloudflare Workers AI):
        export CLOUDFLARE_ACCOUNT_ID="your-cloudflare-account-id"
        export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"

      Remediation (Local Clef Runner):
        docker run -p 8000:8000 ghcr.io/typesafe-ai/clef-flash:latest
        export CLEF_LOCAL_PORT=8000
    ================================================================================
    """)
    exit(1)
}

print("Mode: \(modeDescription)")
print("Image Asset: \(imageURL.path)\n")

let model = ClefLanguageModel(endpoint: endpoint, apiToken: apiToken)
let session = LanguageModelSession(model: model)

print("Evaluating multimodal parcel inspection decisions via LanguageModelSession...")

// 1. Evaluate damage probability from image attachment
let damageProbability = try await session.probability(
    of: "Does the item or parcel show visible exterior damage, crushing, or safety defects?"
) {
    "Inspect this inbound warehouse parcel image."
    Attachment(imageURL: imageURL)
}

// 2. Select warehouse disposition category from image attachment
let dispositionChoice = try await session.choice(
    "Select the appropriate warehouse receiving disposition for this item",
    from: ParcelDisposition.self
) {
    "Determine receiving workflow routing based on physical appearance."
    Attachment(imageURL: imageURL)
}

let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
let damageJudgement = policy.decide(Probability(clamping: damageProbability))

print("\n=== Clef Multimodal Inspection Decisions ===")
print("• Exterior Damage Probability: \(String(format: "%.1f%%", damageProbability * 100)) (Routing: \(damageJudgement.decision))")
print("• Receiving Disposition: \(dispositionChoice.value.rawValue)")
print("• Disposition Confidence: \(String(format: "%.1f%%", dispositionChoice.confidence * 100))")
print("• Candidate Probabilities:")
for (option, prob) in dispositionChoice.distribution.sorted(by: { $0.value > $1.value }) {
    print("    - \(option.rawValue): \(String(format: "%.1f%%", prob * 100))")
}
print("\nEvaluation successfully completed via Clef Foundation Models.")
