import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import FoundationModels
import SystemOneCore
import ClefFoundationModels

#if canImport(ImageIO)
import ImageIO
#endif

// MARK: - Helper Functions & Argument Parsing

struct DemoConfiguration {
    var imagePath: String?
    var backendType: String
    var model: ClefModel
    var accountID: String?
    var apiToken: String?
    var port: Int
    var customURL: URL?
}

func parseArguments() -> DemoConfiguration {
    let args = CommandLine.arguments.dropFirst()
    var config = DemoConfiguration(
        imagePath: nil,
        backendType: "auto",
        model: .clefFlash,
        accountID: ProcessInfo.processInfo.environment["CLOUDFLARE_ACCOUNT_ID"],
        apiToken: ProcessInfo.processInfo.environment["CLOUDFLARE_API_TOKEN"],
        port: Int(ProcessInfo.processInfo.environment["CLEF_LOCAL_PORT"] ?? "8000") ?? 8000,
        customURL: nil
    )

    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--image", "-i":
            config.imagePath = iterator.next()
        case "--backend", "-b":
            if let val = iterator.next()?.lowercased() {
                config.backendType = val
            }
        case "--model", "-m":
            if let val = iterator.next()?.lowercased() {
                if val == "clef" || val.contains("27b") {
                    config.model = .clef
                } else {
                    config.model = .clefFlash
                }
            }
        case "--account-id":
            config.accountID = iterator.next()
        case "--token":
            config.apiToken = iterator.next()
        case "--port", "-p":
            if let val = iterator.next(), let p = Int(val) {
                config.port = p
            }
        case "--url", "-u":
            if let val = iterator.next(), let url = URL(string: val) {
                config.customURL = url
            }
        case "--help", "-h":
            printUsageAndExit()
        default:
            if !arg.hasPrefix("-") && config.imagePath == nil {
                config.imagePath = arg
            }
        }
    }

    if config.backendType == "auto" {
        if config.accountID != nil && config.apiToken != nil {
            config.backendType = "workers-ai"
        } else {
            config.backendType = "local"
        }
    }

    return config
}

func printUsageAndExit() -> Never {
    print("""
    Clef Multimodal Decision Model Demonstrator 👁️⚡️

    USAGE:
      clef-demo [OPTIONS] [IMAGE_PATH]

    ARGUMENTS:
      <IMAGE_PATH>               Optional path to PNG, JPEG, or WebP image.
                                 If omitted, a synthetic sample frame is generated in-memory.

    OPTIONS:
      -b, --backend <type>       Backend topology: 'workers-ai' or 'local' (default: auto)
      -m, --model <variant>      Model: 'clef-flash' (9B) or 'clef' (27B) (default: clef-flash)
      --account-id <id>          Cloudflare Account ID (or env CLOUDFLARE_ACCOUNT_ID)
      --token <token>            Cloudflare API Token (or env CLOUDFLARE_API_TOKEN)
      -p, --port <port>          Local inference runner port (default: 8000)
      -u, --url <url>            Direct custom endpoint URL
      -h, --help                 Display this help information

    EXAMPLES:
      # Run against local runner with auto-generated frame:
      swift run clef-demo --backend local

      # Run against local runner with an image file:
      swift run clef-demo /path/to/product_scan.jpg

      # Run against Cloudflare Workers AI edge:
      CLOUDFLARE_ACCOUNT_ID="abc" CLOUDFLARE_API_TOKEN="xyz" swift run clef-demo --backend workers-ai
    """)
    exit(0)
}

// MARK: - Synthetic Visual Frame Generator

func generateSampleCGImage() -> (cgImage: CGImage, description: String) {
    let width = 640
    let height = 480
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Failed to allocate CoreGraphics bitmap context for synthetic frame")
    }

    // 1. Dark background
    context.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // 2. Draw inspection frame reticle
    context.setStrokeColor(CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.8))
    context.setLineWidth(3.0)
    let reticleRect = CGRect(x: 80, y: 60, width: 480, height: 360)
    context.stroke(reticleRect)

    // 3. Draw simulated product item: Portable Electronics Device
    let itemRect = CGRect(x: 160, y: 120, width: 320, height: 240)
    context.setFillColor(CGColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1.0))
    context.fill(itemRect)
    context.setStrokeColor(CGColor(red: 0.35, green: 0.75, blue: 0.50, alpha: 1.0))
    context.setLineWidth(2.0)
    context.stroke(itemRect)

    // 4. Draw screen / display area
    let displayRect = CGRect(x: 180, y: 160, width: 280, height: 160)
    context.setFillColor(CGColor(red: 0.04, green: 0.45, blue: 0.85, alpha: 0.9))
    context.fill(displayRect)

    // 5. Draw simulated barcode lines
    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
    for i in 0..<18 {
        let barX = 200 + (i * 14)
        let barW = (i % 3 == 0) ? 6 : 3
        context.fill(CGRect(x: barX, y: 130, width: barW, height: 20))
    }

    guard let cgImage = context.makeImage() else {
        fatalError("Failed to finalize synthetic CGImage")
    }

    return (cgImage, "640x480 RGB Synthetic Electronics Component (Serial #SN-9281-OK)")
}

func loadCGImage(from path: String) throws -> CGImage {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        throw SystemOneError.modelExecutionError("Image file not found at path: \(path)")
    }

    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw SystemOneError.modelExecutionError("Failed to decode image at path: \(path). Ensure format is PNG, JPEG, or WebP.")
    }

    return cgImage
}

func formatPercentage(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}

// MARK: - Main Execution Flow

let config = parseArguments()

// 1. Resolve Endpoint & Verify Prerequisites
let endpoint: ClefEndpoint
switch config.backendType {
case "workers-ai":
    guard let accountID = config.accountID, !accountID.isEmpty,
          let token = config.apiToken, !token.isEmpty else {
        print("""
        ==============================================================
        🛑 CONFIGURATION REQUIRED: Cloudflare Credentials Missing
        ==============================================================
        Cloudflare Workers AI requires your Account ID and API Token.

        To remediate, export your credentials:
          export CLOUDFLARE_ACCOUNT_ID="your-cloudflare-account-id"
          export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"

        Or evaluate against a local native runner without credentials:
          swift run clef-demo --backend local
        ==============================================================
        """)
        exit(1)
    }
    endpoint = .workersAI(accountID: accountID, model: config.model)

case "local":
    endpoint = .local(port: config.port, model: config.model)

default:
    if let url = config.customURL {
        endpoint = .custom(url, model: config.model)
    } else {
        endpoint = .local(port: config.port, model: config.model)
    }
}

// 2. Load or Synthesize Visual Frame
let cgImage: CGImage
let imageDescription: String
if let path = config.imagePath {
    do {
        cgImage = try loadCGImage(from: path)
        imageDescription = "\(cgImage.width)x\(cgImage.height) Image File: \(path)"
    } catch {
        print("""
        ==============================================================
        ❌ IMAGE LOAD ERROR
        ==============================================================
        \(error.localizedDescription)
        ==============================================================
        """)
        exit(1)
    }
} else {
    let synthetic = generateSampleCGImage()
    cgImage = synthetic.cgImage
    imageDescription = "\(synthetic.description) [Generated in-memory]"
}

// 3. Print Banner
print("""
==============================================================
  System One Foundation Models — Clef Multimodal Demo 👁️⚡️
==============================================================
Target Endpoint:  \(endpoint.url.absoluteString)
Model:            \(config.model.displayName)
Image Attachment: \(imageDescription)

Evaluating multimodal decision via Apple LanguageModelSession...
""")

// 4. Initialize Apple Foundation Models Session
let clefModel = ClefLanguageModel(
    endpoint: endpoint,
    apiToken: config.apiToken
)
let session = LanguageModelSession(model: clefModel)

// Construct multimodal prompt with standard FoundationModels Attachment
let attachment = Attachment(cgImage)
let prompt = Prompt {
    "Analyze the item presented in this camera capture for identification, categorization, physical condition, and safety compliance."
    attachment
}

let startTime = CFAbsoluteTimeGetCurrent()

do {
    let response = try await session.respond(
        to: prompt,
        generating: VisualInspectionDecision.self
    )

    let totalDurationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
    let decision = response.content

    print("""

    Evaluation Complete in \(String(format: "%.1f", totalDurationMs))ms!
    ==============================================================
      Structured Decision Result (@Generable VisualInspectionDecision)
    ==============================================================
      • isRecognized:     \(decision.isRecognized)
      • itemCategory:     \(decision.itemCategory.displayName) (\(decision.itemCategory.rawValue))
      • conditionScore:   Level \(decision.conditionScore) — \(VisualInspectionDecision.conditionLabel(for: decision.conditionScore))
      • safetyApproval:   \(decision.safetyApproval ? "APPROVED ✅" : "REJECTED ❌")
    """)

    // 5. Operational Confidence Routing
    let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
    print("Operational Confidence Routing (Policy: auto ≥ \(formatPercentage(policy.autoAtOrAbove)), escalate < \(formatPercentage(policy.escalateBelow))):")
    print("--------------------------------------------------------------")

    // Boolean Recognition Judgement
    let recognizedJudgement = response.recognizedJudgement(policy: policy)
    let recognizedProb = response.probability(for: "isRecognized")
    let recognizedProbStr = recognizedProb.map(formatPercentage) ?? "n/a"
    switch recognizedJudgement.decision {
    case .auto:
        if recognizedJudgement.answer == true {
            print("  • Item Recognition: [AUTO-CONFIRMED] ──► Confidently recognized (Prob: \(recognizedProbStr))")
        } else {
            print("  • Item Recognition: [AUTO-REJECT]    ──► Confidently unidentifiable (Prob: \(recognizedProbStr))")
        }
    case .confirm:
        print("  • Item Recognition: [CONFIRM ITEM]   ──► Leaning recognized; prompt operator (Prob: \(recognizedProbStr))")
    case .escalate:
        print("  • Item Recognition: [ESCALATE REVIEW] ──► Low confidence / ambiguous visual data (Prob: \(recognizedProbStr))")
    }

    // Categorical Item Category
    let categoryDecision = response.categoryDecision(policy: policy)
    let catConfidence = response.confidence(for: "itemCategory")
    let catConfStr = catConfidence.map(formatPercentage) ?? "n/a"
    switch categoryDecision {
    case .auto:
        print("  • Item Category:    [AUTO-ROUTE]     ──► Routed to \(decision.itemCategory.rawValue) pipeline (Conf: \(catConfStr))")
    case .confirm:
        print("  • Item Category:    [CONFIRM CHOICE] ──► Suggests \(decision.itemCategory.rawValue); prompt operator (Conf: \(catConfStr))")
    case .escalate:
        print("  • Item Category:    [ESCALATE MANUAL] ──► Low certainty; manual categorization queue (Conf: \(catConfStr))")
    }

    // Rubric Condition Score
    if let conditionScoreVal = response.conditionScoreValue {
        let normStr = conditionScoreVal.normalized.map { String(format: "%.2f", $0) } ?? "n/a"
        let confStr = formatPercentage(conditionScoreVal.confidence)
        print("  • Condition Rubric: Weighted: \(String(format: "%.2f", conditionScoreVal.value)) | Rounded: Level \(conditionScoreVal.rounded) | Normalized: \(normStr) (Confidence: \(confStr))")
    }

    // Boolean Safety Approval
    let safetyJudgement = response.safetyJudgement(policy: policy)
    let safetyProb = response.probability(for: "safetyApproval")
    let safetyProbStr = safetyProb.map(formatPercentage) ?? "n/a"
    switch safetyJudgement.decision {
    case .auto:
        if safetyJudgement.answer == true {
            print("  • Safety Approval:  [AUTO-PASS]      ──► Passed safety verification (Prob: \(safetyProbStr))")
        } else {
            print("  • Safety Approval:  [AUTO-QUARANTINE] ──► Flagged unsafe item; trigger containment (Prob: \(safetyProbStr))")
        }
    case .confirm:
        print("  • Safety Approval:  [CONFIRM SAFETY] ──► Borderline safety status; prompt inspection (Prob: \(safetyProbStr))")
    case .escalate:
        print("  • Safety Approval:  [ESCALATE SAFETY] ──► Ambiguous hazard; escalate to safety officer (Prob: \(safetyProbStr))")
    }

    // 6. Usage & Telemetry Breakdown
    print("""

    Usage & Telemetry:
    --------------------------------------------------------------
      • Input Tokens:     \(response.usage.input.totalTokenCount)
      • Output Tokens:    \(response.usage.output.totalTokenCount) (Non-autoregressive forward pass)
    """)

    if let serverMs = response.serverDurationMs {
        print(String(format: "  • Server Duration:  %.1fms (Forward pass inference on edge)", serverMs))
    }
    if let transportMs = response.transportDurationMs {
        print(String(format: "  • Transport Time:   %.1fms (HTTP roundtrip + inference)", transportMs))
    }
    print(String(format: "  • Total Client:     %.1fms (Swift session wall time)", totalDurationMs))
    print("==============================================================\n")

} catch let error as SystemOneError {
    print("""

    ==============================================================
    ❌ SYSTEM ONE ERROR
    ==============================================================
    \(error.localizedDescription)

    💡 Troubleshooting Tip:
    """)
    if case .local = endpoint {
        print("""
        Make sure your local Clef inference runner is active on \(endpoint.url.absoluteString):
          docker run -p 8000:8000 ghcr.io/typesafe-ai/clef-flash:latest
        """)
    } else {
        print("""
        Check your Cloudflare account ID and API token:
          export CLOUDFLARE_ACCOUNT_ID="your-id"
          export CLOUDFLARE_API_TOKEN="your-token"
        """)
    }
    print("==============================================================\n")
    exit(1)
} catch {
    print("""

    ==============================================================
    ❌ CONNECTION ERROR
    ==============================================================
    \(error.localizedDescription)

    💡 Could not connect to \(endpoint.url.absoluteString).
    """)
    if case .local = endpoint {
        print("""
        Start a local Clef runner via Docker:
          docker run -p \(config.port):8000 ghcr.io/typesafe-ai/clef-flash:latest
        """)
    } else {
        print("""
        Verify your network connection and Cloudflare API token permissions.
        """)
    }
    print("==============================================================\n")
    exit(1)
}
