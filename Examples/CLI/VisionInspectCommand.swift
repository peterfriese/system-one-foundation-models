import Foundation
import CoreGraphics
import FoundationModels
import SystemOneCore
#if canImport(ImageIO)
import ImageIO
#endif

enum VisionInspectCommand {
    private static let defaultSampleImagePath = "Examples/Quickstarts/ClefQuickstart/sample.jpg"

    static func run(provider: ConfiguredProvider, arguments: [String]) async {
        provider.requireVisionSupport(forCommand: "vision-inspect")

        var imagePath: String?
        var idx = 0
        while idx < arguments.count {
            let arg = arguments[idx]
            if (arg == "--image" || arg == "-i"), idx + 1 < arguments.count {
                imagePath = arguments[idx + 1]
                idx += 2
                continue
            } else if !arg.hasPrefix("-"), imagePath == nil {
                imagePath = arg
            }
            idx += 1
        }

        let resolvedPath = imagePath ?? defaultSampleImagePath
        let cgImage: CGImage
        do {
            cgImage = try loadCGImage(from: resolvedPath)
        } catch {
            print("""
            ================================================================================
              🛑 IMAGE LOAD ERROR: Real Image Asset Required
            ================================================================================
              \(error.localizedDescription)

              Per AGENTS.md Principle 7, synthetic test frames are never substituted.

              Remediation — pass an existing PNG, JPEG, or WebP file:
                swift run system-one-cli --provider \(provider.provider.rawValue) vision-inspect /path/to/image.jpg
                # Or run from repository root to use \(defaultSampleImagePath):
                swift run system-one-cli --provider \(provider.provider.rawValue) vision-inspect
            ================================================================================
            """)
            exit(1)
        }

        print("""
        ==============================================================
          System One CLI — Multimodal Vision Inspection 👁️⚡️
        ==============================================================
        Provider:         \(provider.provider.displayName)
        Endpoint:         \(provider.endpointSummary)
        Image Attachment: \(cgImage.width)x\(cgImage.height) (\(resolvedPath))

        Evaluating multimodal decision via Apple LanguageModelSession...
        """)

        let session = provider.makeSession()
        let attachment = Attachment(cgImage)
        let prompt = Prompt {
            "Analyze the item presented in this image for identification, categorization, physical condition, and safety compliance."
            attachment
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await session.respond(
                to: prompt,
                generating: VisualInspectionDecision.self
            )
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let decision = response.content

            print("""

            Evaluation Complete in \(String(format: "%.1f", durationMs))ms!
            ==============================================================
              Structured Decision Result (@Generable VisualInspectionDecision)
            ==============================================================
              • isRecognized:     \(decision.isRecognized)
              • itemCategory:     \(decision.itemCategory.displayName) (\(decision.itemCategory.rawValue))
              • conditionScore:   Level \(decision.conditionScore) — \(VisualInspectionDecision.conditionLabel(for: decision.conditionScore))
              • safetyApproval:   \(decision.safetyApproval ? "APPROVED ✅" : "REJECTED ❌")
            """)

            let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
            print("Operational Confidence Routing:")
            print("--------------------------------------------------------------")

            let recJudgement = response.recognizedJudgement(policy: policy)
            let recProb = response.probability(for: "isRecognized").map(formatPercentage) ?? "n/a"
            print("  • Item Recognition: [\(recJudgement.decision.rawValue.uppercased())] (Prob: \(recProb))")

            let catDecision = response.categoryDecision(policy: policy)
            let catConf = response.confidence(for: "itemCategory").map(formatPercentage) ?? "n/a"
            print("  • Item Category:    [\(catDecision.rawValue.uppercased())] -> \(decision.itemCategory.rawValue) (Conf: \(catConf))")

            if let scoreVal = response.conditionScoreValue {
                let normStr = scoreVal.normalized.map { String(format: "%.2f", $0) } ?? "n/a"
                print("  • Condition Rubric: Weighted \(String(format: "%.2f", scoreVal.value)) | Level \(scoreVal.rounded) | Normalized \(normStr)")
            }

            let safetyJudgement = response.safetyJudgement(policy: policy)
            let safetyProb = response.probability(for: "safetyApproval").map(formatPercentage) ?? "n/a"
            print("  • Safety Approval:  [\(safetyJudgement.decision.rawValue.uppercased())] (Prob: \(safetyProb))")

            print("\nUsage & Telemetry:")
            print("--------------------------------------------------------------")
            print("  • Input Tokens:     \(response.usage.input.totalTokenCount)")
            print("  • Output Tokens:    \(response.usage.output.totalTokenCount)")
            if let serverMs = response.serverDurationMs {
                print(String(format: "  • Server Duration:  %.1fms", serverMs))
            }
            if let transportMs = response.transportDurationMs {
                print(String(format: "  • Transport Time:   %.1fms", transportMs))
            }
            print("==============================================================\n")
        } catch {
            provider.failFastOnError(error)
        }
    }

    private static func loadCGImage(from path: String) throws -> CGImage {
        let expandedPath = (path as NSString).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SystemOneError.modelExecutionError("Image file not found at path: \(fileURL.path)")
        }
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SystemOneError.modelExecutionError("Failed to decode image at path: \(fileURL.path). Ensure format is PNG, JPEG, or WebP.")
        }
        return cgImage
        #else
        throw SystemOneError.modelExecutionError("ImageIO is unavailable on this platform.")
        #endif
    }
}
