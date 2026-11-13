# Ergonomic Decision Shortcuts (`.probability`, `.choice`, `.score`) ⚡️

While `@Generable` structs shine when evaluating multi-property composite decisions in a single forward pass, defining a dedicated struct for a single boolean check, routing choice, or rubric rating adds unnecessary boilerplate.

`SystemOneCore` extends Apple's `LanguageModelSession` with three progressive-disclosure shortcuts—**`.probability`**, **`.choice`**, and **`.score`**—that synthesize dynamic `GenerationSchema` definitions under the hood (`DynamicDecisionSchema`) and work identically across **all 6 System One providers** (`Jev`, `LayaServe`, `LayaOnDevice`, `Clef`, `OpenAI`, `Gemini`) and `SystemOneLanguageModel`.

---

## 1. Binary Truth Probability — `session.probability(of:)`

Evaluates a `noul` proposition and returns its calibrated posterior probability of truth as a `Double` in `0.0...1.0`.

### Text State Overload

```swift
import FoundationModels
import JevFoundationModels

let session = LanguageModelSession(model: JevLanguageModel())

let urgentProb = try await session.probability(
    of: "This support ticket requires immediate on-call engineering escalation",
    state: "Production checkout returning HTTP 502 across us-east-1 for 14 minutes."
)
```

### Explicit Disambiguation Rubric (`criteria:`)

Supply optional `(whenTrue:whenFalse:)` criteria to sharpen boundary cases between positive and negative judgments:

```swift
let duplicateProb = try await session.probability(
    of: "Candidate article reports the exact same underlying news event as the primary story",
    state: comparisonPayload,
    criteria: (
        whenTrue: "Same event, entities, and core facts—even if syndicated under a rewritten headline.",
        whenFalse: "Merely shares a broad industry topic or mentions a competing product."
    )
)
```

### Epistemic Routing with `Probability` & `RoutingPolicy`

Remember that `0.50` represents **maximum epistemic uncertainty**, whereas `0.04` is a **96% decisive "no"**. Wrap raw `Double` results in `Probability` and evaluate with `RoutingPolicy`:

```swift
let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85, undecidedBand: 0.35...0.65)
let judgement: NoulJudgement = policy.decide(Probability(clamping: urgentProb))

switch judgement.decision {
case .auto:
    if judgement.answer == true {
        pageOnCallEngineer() // p >= 0.85
    } else {
        archiveAsRoutine()   // p <= 0.15 (decisiveness >= 0.85)
    }
case .confirm:
    flagForOneClickConfirmation()
case .escalate:
    routeToHumanTriage()     // Inside 0.35...0.65 undecided band (judgement.answer == nil)
}
```

---

## 2. Categorical Selection — `session.choice(_:)`

Evaluates a discrete `choice` question and returns a typed `Choice<Option>` containing the winning `value`, calibrated `confidence` (`0.0...1.0`), full probability `distribution: [Option: Double]`, and `probability(of:)`.

### A. Strongly-Typed `Choosable` Enums

Conform any `CaseIterable & Hashable & Sendable` enum to `Choosable`. Provide optional per-case `optionDescription` guidance so the model understands subtle domain distinctions:

```swift
import FoundationModels
import GeminiFoundationModels

enum ModerationAction: String, Choosable, CaseIterable, Sendable {
    case publish = "publish"
    case holdForReview = "hold_for_review"
    case quarantine = "quarantine"

    var optionDescription: String? {
        switch self {
        case .publish: return "Benign community post complying with platform rules"
        case .holdForReview: return "Borderline claim or ambiguous context needing moderator eyes"
        case .quarantine: return "Credential phishing, malware link, or clear safety violation"
        }
    }
}

let session = LanguageModelSession(model: GeminiLanguageModel())
let result: Choice<ModerationAction> = try await session.choice(
    "Select the moderation enforcement action for this post",
    from: ModerationAction.self,
    state: postBody
)

print("Selected: \(result.value) (confidence: \(result.confidence))")
print("Phishing quarantine prob: \(result.probability(of: .quarantine))")
```

### B. Dynamic Runtime String Options (`options: [String]`)

When candidate buckets come from user configuration, database folders, or runtime state rather than a compile-time enum, pass `options: [String]`:

```swift
let folderChoice: Choice<String> = try await session.choice(
    "Choose the best destination folder for this invoice",
    options: ["Tax_2026", "Client_Reimbursements", "SaaS_Subscriptions", "Personal"],
    state: extractedPDFText
)

if folderChoice.confidence >= 0.85 {
    moveFile(to: folderChoice.value)
}
```

> [!NOTE]
> `choice` validates options before dispatch: empty arrays, blank/whitespace-only identifiers, or duplicate option names throw `SystemOneError.invalidSchema`.

---

## 3. Ordinal Rubric Scoring — `session.score(_:levels:)`

Evaluates an ordered rubric from index `0` to `levels.count - 1` (up to 32 levels) and returns a `ScoreResult`:

| `ScoreResult` Property | Type | Meaning |
| :--- | :--- | :--- |
| `value` | `Double` | Probability-weighted continuous mean across `0...(levels.count - 1)` (e.g. `2.74`). |
| `mostLikelyIndex` | `Int` | Zero-based index of the highest-probability rubric level. |
| `mostLikelyLevel` | `String` | Label string at `levels[mostLikelyIndex]`. |
| `probabilities` | `[Double]` | Calibrated probability for each rubric level in index order. |
| `confidence` | `Double` | Calibrated model confidence (`0.0...1.0`). |
| `levels` | `[String]` | The ordered rubric labels evaluated. |

```swift
import FoundationModels
import LayaOnDevice

let session = LanguageModelSession(model: try LayaOnDeviceLanguageModel())

let severity: ScoreResult = try await session.score(
    "Rate operational incident severity",
    levels: ["Low", "Medium", "High", "Critical"],
    state: "Primary database connection pool exhausted; 40% of checkout requests timing out."
)

print("Level: \(severity.mostLikelyLevel) (#\(severity.mostLikelyIndex))")
print("Continuous weighted score: \(String(format: "%.2f", severity.value)) / 3.00")
print("Confidence: \(severity.confidence)")
```

---

## 4. Multimodal `@PromptBuilder` & `Prompt` Overloads (`Attachment`)

All three shortcuts (`.probability`, `.choice`, `.score`) provide both explicit `prompt: Prompt` and trailing `@PromptBuilder` closure overloads. On vision-capable providers (**`ClefLanguageModel`**, **`OpenAILanguageModel`**, **`GeminiLanguageModel`**, and **`SystemOneLanguageModel(supportsVision: true)`**), attach `CGImage`, local image URLs, or `JPEG`/`PNG`/`WebP` data directly:

```swift
import CoreGraphics
import FoundationModels
import OpenAIFoundationModels

let session = LanguageModelSession(model: OpenAILanguageModel())

// 1. Multimodal .probability with trailing @PromptBuilder
let isDamaged = try await session.probability(
    of: "The outer shipping carton has crushed corners, punctures, or water staining",
    criteria: (
        whenTrue: "Visible structural dents, torn cardboard, or moisture rings.",
        whenFalse: "Intact seams and clean surfaces; normal shipping labels only."
    )
) {
    "Inspect inbound warehouse parcel #9042."
    Attachment(cameraCGImage)
}

// 2. Multimodal .choice with Choosable enum or dynamic [String] options
let department = try await session.choice(
    "Route this returned item photo to the right warehouse station",
    options: ["restock_new", "refurbish_bench", "hazmat_disposal"]
) {
    Attachment(imageURL: localPhotoURL)
}

// 3. Multimodal .score across ordered visual rubric levels
let condition = try await session.score(
    "Rate physical surface condition of the device",
    levels: ["Unusable / Cracked", "Heavy Wear", "Light Scuffs", "Pristine"]
) {
    "Evaluate front and back enclosure photos."
    Attachment(frontCGImage)
    Attachment(backCGImage)
}
```

### Multimodal Guardrails & Automatic Downscaling

- **Capability Check**: Calling a multimodal overload on a text-only model (`Jev`, `LayaServe`, `LayaOnDevice`) fails fast with `LanguageModelSession.GenerationError.unsupportedCapability`.
- **Automatic Downscaling**: `TranscriptAttachmentExtractor` automatically scales `Attachment(cgImage)` and oversized image files down to a **1024px** max dimension (`0.8` JPEG for opaque frames, lossless PNG for alpha images).
- **Wire Guardrails (`SystemOneImage.Guardrails`)**: Up to **4 images** per evaluation turn, **16 MP** max per image, and **13 MiB** max combined payload.

---

## 5. Complete Signature Summary

```swift
extension LanguageModelSession {
    // Binary Noul (0.0...1.0)
    func probability(of instructions: String, state: String, criteria: (whenTrue: String, whenFalse: String)? = nil) async throws -> Double
    func probability(of instructions: String, prompt: Prompt, criteria: (whenTrue: String, whenFalse: String)? = nil) async throws -> Double
    func probability(of instructions: String, criteria: (whenTrue: String, whenFalse: String)? = nil, @PromptBuilder prompt: () throws -> Prompt) async throws -> Double

    // Typed Enum Choice
    func choice<Option: Choosable>(_ instructions: String, from type: Option.Type = Option.self, state: String) async throws -> Choice<Option>
    func choice<Option: Choosable>(_ instructions: String, from type: Option.Type = Option.self, prompt: Prompt) async throws -> Choice<Option>
    func choice<Option: Choosable>(_ instructions: String, from type: Option.Type = Option.self, @PromptBuilder prompt: () throws -> Prompt) async throws -> Choice<Option>

    // Dynamic String Choice
    func choice(_ instructions: String, options: [String], state: String) async throws -> Choice<String>
    func choice(_ instructions: String, options: [String], prompt: Prompt) async throws -> Choice<String>
    func choice(_ instructions: String, options: [String], @PromptBuilder prompt: () throws -> Prompt) async throws -> Choice<String>

    // Ordinal Rubric Score
    func score(_ instructions: String, levels: [String], state: String) async throws -> ScoreResult
    func score(_ instructions: String, levels: [String], prompt: Prompt) async throws -> ScoreResult
    func score(_ instructions: String, levels: [String], @PromptBuilder prompt: () throws -> Prompt) async throws -> ScoreResult
}
```
