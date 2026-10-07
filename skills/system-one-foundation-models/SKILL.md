---
name: system-one-foundation-models
license: Apache-2.0
description: >-
  Evaluate System One decision models (Laya On-Device Core ML, Laya HTTP server, TypeSafe Jev,
  and Cloudflare Clef & Clef-Flash multimodal decision models) natively through Apple's Foundation
  Models framework in Swift 6. Use when building iOS 27+, macOS 27+, or visionOS 27+ apps that
  evaluate strongly-typed @Generable structs and enums using LanguageModelSession, running models
  on-device via Core ML (Apple Neural Engine), connecting to self-hosted laya-serve, deploying
  multimodal visual triage via Cloudflare Workers AI and AI Gateway, implementing confidence
  routing (RoutingPolicy, NoulJudgement, ScoreValue), configuring resilient network retries (RetryPolicy),
  or writing deterministic offline unit tests with MockSystemOneBackend and MockClefBackendProtocol.
metadata:
  author: peterfriese
  version: "2.1"
---

# System One Foundation Models Bridge

This skill guides the design, implementation, and testing of applications integrating **System One decision models** (**Laya On-Device Core ML**, **Laya HTTP Server**, **TypeSafe Jev**, and **Cloudflare Clef & Clef-Flash multimodal decision models**) via **Apple's Foundation Models framework** (`FoundationModels`) in Swift 6.

---

## 1. Core Mental Model: Decisions, Not Chat

System One models are **non-autoregressive decision models**, not text-generating LLMs. They evaluate application state against a set of typed questions in a single forward pass, returning calibrated probabilities and discrete categorical decisions in 15–150ms.

- **Prompt $\to$ Application State**: The text passed to `session.respond(to:)` represents current application context (support tickets, sensor readings, transaction logs, user inputs, or parsed documents).
- **`@Generable` Type $\to$ Decision Questions**: The struct or enum defines the typed questions being asked over that state.
- **Dual Signal Output**:
  1. **The Answer**: *What* the model judged (`response.content` containing typed enum choices, booleans, or rubric scores).
  2. **The Calibrated Confidence / Probability**: *Whether* to automate the action (`response.judgement(...)`, `response.decision(...)`, `response.scoreValue(...)`).

---

## 2. Pluggable Backends

Developers choose between four primary execution backends by passing the appropriate model to `LanguageModelSession`:

### Option A: On-Device Core ML (`LayaOnDevice`)
Runs Laya's 322M (multilingual mmBERT) or 421M (ModernBERT) model directly on the **Apple Neural Engine (ANE)** and GPU. 100% offline, zero network requests, zero secrets:

```swift
import FoundationModels
import LayaOnDevice

let modelURL = Bundle.main.url(forResource: "LayaModernBERT", withExtension: "mlmodelc")!
let engine = try LayaCoreMLEngine(
    modelURL: modelURL,
    tokenizer: ModernBERTTokenizer.defaultTokenizer()
)

let model = LayaOnDeviceLanguageModel(engine: engine)
let session = LanguageModelSession(model: model)
```

### Option B: Self-Hosted or Remote Laya HTTP (`LayaFoundationModels`)
Connects to `laya-serve` (speaking the Jev-compatible `POST /v1/systemone` protocol):

```swift
import FoundationModels
import LayaFoundationModels

// Local server (localhost:8000 or localhost:8770) or hosted endpoint
let model = LayaLanguageModel(endpoint: .localDefault) // or .local(port: 8770) or .hosted
let session = LanguageModelSession(model: model)
```

### Option C: TypeSafe AI Jev Cloud (`JevFoundationModels`)
Connects to TypeSafe AI's hosted decision API with automated HTTP retry resilience and backoff:

```swift
import FoundationModels
import JevFoundationModels

let retryPolicy = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(250), jitter: 0.15)
let model = JevLanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)
let session = LanguageModelSession(model: model)
```

### Option D: Cloudflare Clef & Clef-Flash (`ClefFoundationModels`)
Connects to Cloudflare's **Clef** (27B) or **Clef-Flash** (9B) multimodal decision models for visual item inspection, damage assessment, KYC document verification, or mobile camera triage:

```swift
import FoundationModels
import ClefFoundationModels

// 1. Direct Cloudflare Workers AI Edge
let workersEndpoint = ClefEndpoint.workersAI(accountID: "cf-account-id", model: .clefFlash)
let workersModel = ClefLanguageModel(endpoint: workersEndpoint, apiToken: "cf-api-token")
let session = LanguageModelSession(model: workersModel)

// 2. Cloudflare AI Gateway (with edge caching, analytics, and rate limiting)
let gatewayEndpoint = ClefEndpoint.gateway(
    accountID: "cf-account-id",
    gatewayID: "production-gateway",
    model: .clef
)
let gatewayModel = ClefLanguageModel(endpoint: gatewayEndpoint, apiToken: "cf-api-token")

// 3. Local Native Runner (Docker Model Runner, vLLM, Cog, MLX on port 8000)
let localEndpoint = ClefEndpoint.local(port: 8000, model: .clefFlash)
let localModel = ClefLanguageModel(endpoint: localEndpoint)
```

---

## 3. Multimodal Decision Evaluation

Unlike autoregressive vision-language models that generate text captions or verbose descriptions, **Clef** and **Clef-Flash** evaluate multimodal inputs (contextual text + image attachments) in a **single forward pass**, computing calibrated decision primitives with **zero output tokens** (`output_tokens: 0`).

### Passing Image Attachments via `Prompt`

Visual inputs are attached to standard Apple Foundation Models `Prompt` builder blocks using `Attachment(cgImage)` or `Attachment(data:type:)`:

```swift
import FoundationModels
import ClefFoundationModels
import CoreGraphics

let session = LanguageModelSession(
    model: ClefLanguageModel(
        endpoint: .workersAI(accountID: accountID, model: .clefFlash),
        apiToken: token
    )
)

// Attach CGImage or raw Data
let prompt = Prompt {
    "Inspect the physical condition of this returned merchandise item."
    Attachment(capturedCGImage)
    // Or pass raw Data: Attachment(data: jpegData, type: .jpeg)
}

let response = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)
let decision: VisualInspectionDecision = response.content
```

### Apple Framework Capability Gating: `LanguageModelCapabilities.Capability.vision`

Apple's `FoundationModels` framework performs client-side capability validation before dispatching generation requests. If a `Prompt` contains an `Attachment` with visual data:
- The session runtime inspects `model.capabilities`.
- The capability set **must include `.vision`** alongside `.guidedGeneration`.
- If `.vision` is missing (as in text-only models like `JevLanguageModel` or `LayaLanguageModel`), `LanguageModelSession` traps immediately with `LanguageModelSession.GenerationError.unsupportedCapability`: *"The selected model does not support image input. Consider trying again with a different model."*
- `ClefLanguageModel` explicitly advertises both capabilities:
  ```swift
  public var capabilities: LanguageModelCapabilities {
      LanguageModelCapabilities([.guidedGeneration, .vision])
  }
  ```

### Image Preprocessing Best Practice: 1024px Downsampling & 0.8 JPEG Compression

High-resolution mobile camera hardware (such as 12MP to 48MP iPhone sensors) creates two critical problems if uploaded uncompressed or as raw PNGs (see Tech Note 0015):
1. **BPE Text Tokenizer Fallback**: Cloudflare's edge gateway serializes images under the `images` array as RFC 2397 Data URLs (`data:image/jpeg;base64,...`). If non-standard objects or oversized base64 blobs are parsed as text, standard BPE tokenization expands the string into **700,000+ tokens**, instantly exceeding the 64k context limit (HTTP 413).
2. **Payload & Patch Blowout**: High-resolution PNGs consume 10–30 MB of bandwidth and generate tens of thousands of vision patches, dramatically slowing inference.

**Best Practice**: Downsample all camera frames so the maximum dimension does not exceed **1024px**, and compress using lossy **JPEG at 0.8 quality**:
```swift
// See TranscriptAttachmentExtractor / CameraManager
let downsampledJPEG = TranscriptAttachmentExtractor.convertCGImageToJPEG(
    rawCGImage,
    maxDimension: 1024,
    quality: 0.8
)
```
This reduces the image payload to 100–300 KB, maps to **~1,000 vision patch tokens**, and executes in sub-100ms.

### Multimodal Guardrails

`SystemOneImage.Guardrails` enforces strict runtime validation before network serialization:
- **Maximum Images**: Up to 4 images per evaluation (`Guardrails.maxImageCount = 4`).
- **Maximum Resolution**: Up to 16 megapixels per image (`Guardrails.maxMegapixels = 16.0`).
- **Maximum Payload Size**: 13 MiB total payload cap (`Guardrails.maxPayloadBytes = 13 * 1024 * 1024`).

```swift
try SystemOneImage.validate(images: extractedImages)
```

---

## 4. `@Generable` Schema Modeling Rules

`SchemaTranslator` maps Apple `@Generable` types directly to System One decision primitives. Follow these mapping rules strictly:

| Swift Type & Annotations | System One Primitive | Question Key Convention | Behavior / Output |
| :--- | :--- | :--- | :--- |
| `Bool` | **`noul`** | Field name (e.g. `"isUrgent"`) or `"root"` | Calibrated probability of truth ($0.0 \dots 1.0$). Decodes to Swift `Bool`. |
| `enum: String` | **`choice`** | Field name (e.g. `"department"`) or `"choice"` | Discrete categorical selection among defined enum cases. |
| `Int` or `Double` + `@Guide(.range(min...max))` | **`score`** | Field name (e.g. `"frustrationLevel"`) or `"root"` | Ordinal rubric scoring mapped to integer/numeric levels with continuous weighting. |
| `@Guide(description: "...")` | **`instructions`** | N/A | Natural language instructions steering judgment. |
| Nested `@Generable struct` | **`nested questions`** | Dot-notation (e.g. `"metadata.priority"`) | Evaluates hierarchical sub-properties concurrently. |

### Negative Constraints (Strictly Forbidden)
- ❌ **No unconstrained `String` properties**: Decision models do not generate free-form text. A `String` property without enum choices throws an invalid schema error.
- ❌ **No unstructured collections**: Arrays of open-ended values (`[String]`) or dictionaries are not supported.
- ❌ **No text generation requests without schemas**: Calling `session.respond(to: "Hello")` without a `generating:` argument throws a structured output required error.
- ❌ **No tool calling**: `LanguageModelCapabilities` for System One only includes `[.guidedGeneration]`.

### Correct Schema Example

```swift
import FoundationModels

@Generable
enum SupportDepartment: String, Sendable {
    case billing
    case technicalSupport
    case sales
}

@Generable
struct TriageDecision: Sendable {
    @Guide(description: "Is this customer inquiry urgent or blocking critical business?")
    var isUrgent: Bool

    @Guide(description: "Which department is best suited to resolve this issue?")
    var department: SupportDepartment

    @Guide(description: "Customer frustration rating on a 0 to 3 scale", .range(0...3))
    var frustrationLevel: Int
}
```

---

## 5. Confidence Routing with `RoutingPolicy`

Never write naive `if prob > 0.5` checks:
- **`0.50` indicates maximum epistemic uncertainty**, not "half true".
- The **undecided band** ($0.35 \dots 0.65$) indicates the model is genuinely undecided (`answer == nil`).
- A probability of `0.05` is a **confident "no"** ($\text{decisiveness} = \max(p, 1 - p) = 0.95$), which routes to `.auto` with `answer: false`.

Use `RoutingPolicy` to map calibrated signals into operational actions (`.auto`, `.confirm`, `.escalate`):

```swift
let policy = RoutingPolicy(
    escalateBelow: 0.60,
    autoAtOrAbove: 0.85,
    undecidedBand: 0.35...0.65
)

// Categorical or Scored Decision (.auto, .confirm, .escalate)
let deptAction = response.decision(for: "department", policy: policy)
switch deptAction {
case .auto:     routeToDepartment(decision.department)
case .confirm:  suggestDepartment(decision.department)
case .escalate: routeToGeneralQueue()
}

// Boolean (Noul) Judgement
let urgencyJudgement = response.judgement(for: "isUrgent", policy: policy)
switch urgencyJudgement.decision {
case .auto:
    if urgencyJudgement.answer == true {
        pageOnCallLead()       // Confident Yes (p >= 0.85)
    } else {
        markStandardPriority() // Confident No (p <= 0.15)
    }
case .confirm:  promptAgentToConfirm() // Leaning
case .escalate: assignManualReview()   // Undecided band (answer is nil)
}
```

---

## 6. Cloudflare Edge Integration Nuances

Deploying decision models to Cloudflare Workers AI introduces two critical edge architectural nuances:

### A. Decoupled Model Identifiers (Tech Note 0014)

Cloudflare Workers AI enforces two distinct model identification schemas across the HTTP boundary:
1. **Edge URL Routing Identifier**: The REST endpoint URL path requires the full catalog prefix:
   ```
   POST https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/@cf/cloudflare/clef-flash
   ```
   Omitting the `@cf/cloudflare/` catalog prefix triggers an HTTP 404 (`Model not found`).
2. **Payload Body Schema Validation**: The underlying inference container validates the request body's `"model"` field against a strict regex:
   ```regex
   ^\s*(clef|clef-flash)\s*$
   ```
   If the request body passes the full catalog URI `@cf/cloudflare/clef-flash`, schema validation fails with `AiError: Bad input: Error: '/model' failed test ^\s*(clef|clef-flash)\s*$ pattern`.

**Resolution**: `ClefEndpoint` and `ClefModel` cleanly decouple the edge URL catalog path (`model.workersAIIdentifier`) from the payload body model slug (`model.rawValue` / `modelIdentifier`):
```swift
// ClefEndpoint.url -> ".../run/@cf/cloudflare/clef-flash"
// ClefEndpoint.modelIdentifier -> "clef-flash"
```

### B. Client API v4 Envelope Unwrapping & Dual Decoding Fallback (Tech Note 0016)

Cloudflare Workers AI sits behind Cloudflare's Client API v4 gateway, which wraps successful responses in a canonical envelope:
```json
{
  "result": {
    "model": "@cf/cloudflare/clef-flash",
    "answers": { ... },
    "usage": { "input_tokens": 240, "output_tokens": 0 }
  },
  "success": true,
  "errors": [],
  "messages": []
}
```
In contrast, local runners (Docker Model Runner, MLX, `laya-serve`) return raw `SystemOneResponse` payloads directly at the JSON root:
```json
{
  "model": "clef-flash",
  "answers": { ... },
  "usage": { "input_tokens": 240, "output_tokens": 0 }
}
```

**Resolution**: `ClefHTTPBackend.decodeResponse` implements a dual-decoding fallback pipeline:
1. First attempts to decode `SystemOneResponse` directly at the root.
2. If root keys are missing, decodes `CloudflareAPIEnvelope` and extracts `envelope.result`.
3. If `envelope.success == false`, extracts structured errors and throws `SystemOneError.apiError`.

---

## 7. Package Traits Architecture (Swift 6.1 / SE-0402)

`SystemOneFoundationModels` adopts Swift 6.1 Package Traits (SE-0402) to maintain zero runtime bloat. Traits are partitioned along **model boundaries** so consumers link only the dependencies and platforms they require:

| Trait | Category | Included Capabilities | Intended Deployment |
| :--- | :--- | :--- | :--- |
| `Jev` | Model Boundary | `JevFoundationModels`, hosted TypeSafe Jev API client | Cloud / hosted decision services |
| `Laya` | Model Boundary | `LayaOnDevice`, Core ML engine, Apple Neural Engine | Offline mobile, air-gapped apps |
| `LayaServe` | Model Boundary | `LayaFoundationModels`, local/remote HTTP client | Self-hosted daemons, private VPCs |
| `Clef` | Model Boundary | `ClefFoundationModels`, Cloudflare Workers AI, AI Gateway & local Clef runners | Multimodal vision & mobile camera inspection |
| `OnDevice` | Persona / Shorthand | Enables `["Laya"]` | Zero-network mobile applications |
| `Remote` | Persona / Shorthand | Enables `["Jev", "LayaServe", "Clef"]` | Client/server apps using networked models |
| `All` | Persona / Shorthand | Enables `["Jev", "Laya", "LayaServe", "Clef"]` | Multi-backend reference apps (e.g. MailTriageApp) |
| *default* | Default Trait | Enables `["Jev"]` | Backward compatibility |

### Consumer Configuration in `Package.swift`

```swift
// 1. Only Clef multimodal decision models
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.2.0", traits: ["Clef"])

// 2. All remote models (Jev, LayaServe, Clef)
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.2.0", traits: ["Remote"])

// 3. Complete suite (On-device Core ML + all remote backends)
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.2.0", traits: ["All"])
```

---

## 8. Deterministic Offline Testing

Always test decision workflows deterministically without live network access, Cloudflare credentials, or GPU model loading.

### A. Testing Core System One Workflows (`MockSystemOneBackend`)

```swift
import Testing
import FoundationModels
import SystemOneCore

@Suite("Triage Decision Tests")
struct TriageWorkflowTests {

    @Test("Verifies triage routing and high-probability escalation")
    func testUrgentBillingTriage() async throws {
        let mockBackend = MockSystemOneBackend { request in
            #expect(request.questions.count == 3)
            #expect(request.state.contains("charged $500 twice"))

            return SystemOneResponse(
                model: "mock",
                answers: [
                    "isUrgent": SystemOneAnswer(type: "noul", noul: 0.97, confidence: 0.95),
                    "department": SystemOneAnswer(type: "choice", choice: "billing", confidence: 0.98),
                    "frustrationLevel": SystemOneAnswer(type: "score", score: 2.8, confidence: 0.90)
                ],
                usage: SystemOneUsage(inputTokens: 85, outputTokens: 0)
            )
        }

        let model = SystemOneLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(
            to: "charged $500 twice",
            generating: TriageDecision.self
        )

        #expect(response.content.isUrgent == true)
        #expect(response.content.department == .billing)
        #expect(response.content.frustrationLevel == 3)
    }
}
```

### B. Testing Clef Cloudflare Envelopes Offline (`MockClefBackendProtocol`)

Use an ephemeral `URLSession` backed by `MockClefBackendProtocol` to simulate Cloudflare Workers AI edge responses without outbound traffic:

```swift
import Testing
import Foundation
import FoundationModels
import ClefFoundationModels

@Suite("Clef Backend Offline Tests", .serialized)
struct ClefBackendTests {

    @Test("Verifies unwrap of Cloudflare Client API v4 envelope")
    func testCloudflareEnvelopeEvaluation() async throws {
        let envelopeJSON = """
        {
          "result": {
            "model": "@cf/cloudflare/clef-flash",
            "answers": {
              "hasDefect": { "type": "noul", "noul": 0.93, "confidence": 0.93 },
              "category": { "type": "choice", "choice": "scratch", "confidence": 0.89 },
              "severity": { "type": "score", "score": 2.0, "confidence": 0.85 }
            },
            "usage": { "input_tokens": 120, "output_tokens": 0 }
          },
          "success": true,
          "errors": [],
          "messages": []
        }
        """.data(using: .utf8)!

        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 200, body: envelopeJSON)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockClefBackendProtocol.self]
        let session = URLSession(configuration: config)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "mock-account", model: .clefFlash),
            apiToken: "mock-token",
            session: session
        )
        let model = ClefLanguageModel(configuration: .init(backend: backend))
        let lmSession = LanguageModelSession(model: model)

        let response = try await lmSession.respond(
            to: "Inspecting surface finish",
            generating: DefectInspectionDecision.self
        )

        #expect(response.content.hasDefect == true)
        #expect(response.content.category == .scratch)
        #expect(response.content.severity == 2)
    }
}
```
