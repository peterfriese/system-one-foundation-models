---
name: clef-foundation-models
license: Apache-2.0
description: >-
  Evaluate Cloudflare Clef (27B) and Clef-Flash (9B) multimodal System One decision models
  natively through Apple's Foundation Models framework in Swift 6. Use when building iOS 27+,
  macOS 27+, or visionOS 27+ apps that evaluate strongly-typed @Generable structs and enums
  over visual attachments (camera frames, photos, screenshots) using LanguageModelSession,
  deploying via Cloudflare Workers AI edge, Cloudflare AI Gateway, or local inference runners,
  implementing visual confidence routing (RoutingPolicy, NoulJudgement, ScoreValue), integrating
  AVFoundation camera pipelines, or writing deterministic offline unit tests with MockClefBackendProtocol.
metadata:
  author: peterfriese
  version: "1.0"
---

# Cloudflare Clef Foundation Models Bridge

> [!TIP]
> **Multi-Backend Architecture**: For projects integrating on-device Core ML (`LayaOnDevice`), self-hosted HTTP daemons (`LayaFoundationModels`), and TypeSafe Jev cloud alongside Cloudflare Clef, refer to the unified `system-one-foundation-models` skill and package target. This skill focuses specifically on Cloudflare Clef & Clef-Flash multimodal decision evaluation, AVFoundation camera integration, and Cloudflare edge gateway infrastructure.

This skill guides the design, implementation, and testing of applications integrating **Cloudflare Clef (27B)** and **Cloudflare Clef-Flash (9B)** multimodal decision models via **Apple's Foundation Models framework** (`FoundationModels`) in Swift 6.

---

## 1. Core Mental Model: Multimodal Decisions, Not Autoregressive Chat

Cloudflare Clef and Clef-Flash are **multimodal System One decision models**, not conversational vision-language models (VLMs). Rather than autoregressively generating textual captions or chat descriptions, Clef evaluates application text and visual attachments in a **single forward pass**, returning calibrated decision primitives in sub-100ms with **zero output tokens** (`output_tokens: 0`).

- **Multimodal State**: Contextual text plus up to 4 image attachments passed inside `Prompt { ... }`.
- **`@Generable` Type $\to$ Decision Questions**: Strongly-typed Swift structs and enums define the questions evaluated over that visual scene.
- **Dual Signal Output**:
  1. **The Typed Content**: *What* the model judged (`response.content` containing enums, booleans, and rubric scores).
  2. **Calibrated Epistemic Uncertainty**: *Whether* to automate the action (`response.judgement(...)`, `response.decision(...)`, `response.scoreValue(...)`).

### Model Family Comparison

| Model | Parameters | Target Workflows | Cold Latency | Key Strengths |
| :--- | :--- | :--- | :--- | :--- |
| **Clef-Flash** | 9B (Qwen3.5 base) | Interactive mobile apps, camera viewfinder triage, real-time scanning | ~80–120ms | Ultra-fast edge execution, low bandwidth overhead, ideal for live iOS camera streams. |
| **Clef** | 27B (Qwen3.8 base) | High-resolution document forensics, multi-page KYC verification, subtle damage audit | ~250–450ms | High discriminative capacity for nuanced enterprise documents, fine print, and micro-defects. |

---

## 2. Pluggable Endpoint Topologies (`ClefEndpoint`)

Configure the target endpoint via the `ClefEndpoint` enum. `ClefLanguageModel` connects to global Cloudflare edge nodes or local inference servers:

```swift
import FoundationModels
import ClefFoundationModels

// 1. Cloudflare Workers AI Edge (Direct Edge REST API)
let workersEndpoint = ClefEndpoint.workersAI(
    accountID: "cloudflare-account-id",
    model: .clefFlash // or .clef
)
let model = ClefLanguageModel(endpoint: workersEndpoint, apiToken: "cloudflare-api-token")
let session = LanguageModelSession(model: model)

// 2. Cloudflare AI Gateway (Centralized caching, analytics, rate limiting)
let gatewayEndpoint = ClefEndpoint.gateway(
    accountID: "cloudflare-account-id",
    gatewayID: "mobile-production",
    model: .clefFlash
)
let gatewayModel = ClefLanguageModel(endpoint: gatewayEndpoint, apiToken: "cloudflare-api-token")

// 3. Local Native Runner (Docker Model Runner, vLLM, Cog, MLX on localhost)
let localEndpoint = ClefEndpoint.local(port: 8000, model: .clefFlash)
let localModel = ClefLanguageModel(endpoint: localEndpoint)

// 4. Custom Fully-Qualified URL
let customEndpoint = ClefEndpoint.custom(
    URL(string: "https://ai.internal.mycompany.com/v1/evaluate")!,
    model: .clef
)
let customModel = ClefLanguageModel(endpoint: customEndpoint, apiToken: "internal-bearer-token")
```

---

## 3. Multimodal Inputs with Apple Foundation Models (`Attachment`)

### Passing Image Attachments via `Prompt`

Visual inputs are attached directly to standard Apple Foundation Models `Prompt` builder blocks using `Attachment(cgImage)` or `Attachment(data:type:)`:

```swift
import FoundationModels
import ClefFoundationModels
import CoreGraphics

let session = LanguageModelSession(
    model: ClefLanguageModel(
        endpoint: .workersAI(accountID: accountID, model: .clefFlash),
        apiToken: apiToken
    )
)

// Construct multimodal prompt
let prompt = Prompt {
    "Examine this manufacturing component for surface defects and dimensional integrity."
    Attachment(capturedCGImage)
    // Or pass raw Data: Attachment(data: jpegData, type: .jpeg)
}

let response = try await session.respond(
    to: prompt,
    generating: DefectInspectionDecision.self
)

let decision: DefectInspectionDecision = response.content
```

### Apple Framework Capability Gating: `LanguageModelCapabilities.Capability.vision`

Apple's `FoundationModels` framework performs client-side capability validation before passing generation requests to an underlying `LanguageModelExecutor`.

If a caller submits a `Prompt` containing visual attachments:
- The session runtime verifies `model.capabilities`.
- The capability set **must include `.vision`** alongside `.guidedGeneration`.
- If `.vision` is missing, `LanguageModelSession` traps immediately with `LanguageModelSession.GenerationError.unsupportedCapability`: *"The selected model does not support image input. Consider trying again with a different model."*
- `ClefLanguageModel` explicitly advertises both capabilities:
  ```swift
  public var capabilities: LanguageModelCapabilities {
      LanguageModelCapabilities([.guidedGeneration, .vision])
  }
  ```
- Supported MIME/UTTypes: PNG (`.png`), JPEG (`.jpeg`), and WebP (`.webP`).

### Image Preprocessing Best Practice: 1024px Downsampling & 0.8 JPEG Compression

Modern Apple mobile hardware captures photos at resolutions up to 48MP. Uploading raw, uncompressed frames or large PNGs leads to severe failure modes (see Tech Note 0015):
1. **BPE Tokenizer Blowout**: Cloudflare's edge gateway serializes images under the `images` array as RFC 2397 Data URLs (`data:image/jpeg;base64,...`). Unrecognized schemas or oversized text blobs fall back to standard Byte-Pair Encoding (BPE) text tokenizers, calculating **700,000+ input tokens** and instantly exceeding the 64k context limit (HTTP 413).
2. **Payload & Patch Inflation**: Uncompressed frames consume 10–30 MB of bandwidth and generate excessive vision transformer patches, degrading latency.

**Production Best Practice**: Always downsample camera frames to a maximum dimension of **1024px** and compress to **JPEG at 0.8 quality**:

```swift
// Utility available in SystemOneCore / CameraManager
if let downsampledData = TranscriptAttachmentExtractor.convertCGImageToJPEG(
    rawCGImage,
    maxDimension: 1024,
    quality: 0.8
) {
    let prompt = Prompt {
        "Verify item condition"
        Attachment(data: downsampledData, type: .jpeg)
    }
}
```

This reduces upload payloads to **100–300 KB**, maps cleanly to **~1,000 vision patch tokens**, and guarantees sub-100ms edge processing.

### Multimodal Guardrails

`SystemOneImage.Guardrails` enforces strict validation prior to wire serialization:
- **Maximum Images**: Up to 4 images per evaluation (`Guardrails.maxImageCount = 4`).
- **Maximum Resolution**: Up to 16 megapixels per image (`Guardrails.maxMegapixels = 16.0`).
- **Maximum Payload Size**: 13 MiB total payload cap (`Guardrails.maxPayloadBytes = 13 * 1024 * 1024`).

---

## 4. `@Generable` Schema Modeling for Visual Decisions

`SchemaTranslator` maps Apple `@Generable` types directly to System One decision primitives:

| Swift Type & Annotations | System One Primitive | Question Key Convention | Output Behavior |
| :--- | :--- | :--- | :--- |
| `Bool` | **`noul`** | Field name (e.g. `"isRecognized"`) | Calibrated probability of truth ($0.0 \dots 1.0$). Decodes to Swift `Bool`. |
| `enum: String` | **`choice`** | Field name (e.g. `"itemCategory"`) | Discrete categorical selection among defined enum cases. |
| `Int` + `@Guide(.range(min...max))` | **`score`** | Field name (e.g. `"conditionScore"`) | Ordinal rubric scoring mapped to integer levels with continuous weighting. |
| `@Guide(description: "...")` | **`instructions`** | N/A | Natural language guidance steering visual judgment. |

### Negative Constraints (Strictly Forbidden)
- ❌ **No unconstrained `String` properties**: Clef models do not generate free-form text. A `String` property without enum choices throws `SystemOneError.invalidSchema`.
- ❌ **No unstructured collections**: Arrays of open-ended values (`[String]`) or dictionaries are unsupported.
- ❌ **No requests without schemas**: Calling `session.respond(to: prompt)` without a `generating:` schema throws `SystemOneError.structuredOutputRequired`.
- ❌ **No tool calling**: `LanguageModelCapabilities` only includes `[.guidedGeneration, .vision]`.

### Production Schema Example

```swift
import FoundationModels
import ClefFoundationModels

@Generable
public enum ItemCategory: String, Sendable, CaseIterable, Codable {
    case snack
    case beverage
    case electronics
    case document
    case household
    case clothing
    case unknown
}

@Generable
public struct VisualInspectionDecision: Sendable, Codable, Equatable {
    @Guide(description: "Is a physical item or subject clearly recognized in the camera view?")
    public var isRecognized: Bool

    @Guide(description: "Primary category classification of the recognized item")
    public var itemCategory: ItemCategory

    @Guide(description: "Physical condition rubric: 0 (unusable/damaged), 1 (worn), 2 (good), 3 (pristine)", .range(0...3))
    public var conditionScore: Int

    @Guide(description: "Safety approval: does the item satisfy safety standards without visible hazards or contamination?")
    public var safetyApproval: Bool
}
```

---

## 5. Visual Confidence Routing with `RoutingPolicy`

Never write naive `if prob > 0.5` checks:
- **`0.50` indicates maximum epistemic uncertainty**, not "half true".
- The **undecided band** ($0.35 \dots 0.65$) indicates the model is genuinely undecided (`answer == nil`).
- A probability of `0.05` is a **confident "no"** ($\text{decisiveness} = \max(p, 1 - p) = 0.95$), which routes to `.auto` with `answer: false`.

Use `RoutingPolicy` to triage visual judgments into operational actions:

```swift
let policy = RoutingPolicy(
    escalateBelow: 0.60,
    autoAtOrAbove: 0.85,
    undecidedBand: 0.35...0.65
)

// 1. Boolean (Noul) Visual Verification
let recognizedJudgement = response.judgement(for: "isRecognized", policy: policy)
switch recognizedJudgement.decision {
case .auto:
    if recognizedJudgement.answer == true {
        print("Item recognized with high confidence:", recognizedJudgement.confidence)
    } else {
        print("Confident rejection: No valid item in viewfinder frame")
    }
case .confirm:
    promptUserToHoldSteady() // Leaning
case .escalate:
    requestManualOverride()  // In undecided band
}

// 2. Categorical Classification (Choice)
let categoryAction = response.decision(for: "itemCategory", policy: policy)
switch categoryAction {
case .auto:     routeToCatalog(decision.itemCategory)
case .confirm:  askUserToConfirmCategory(decision.itemCategory)
case .escalate: routeToUncategorizedQueue()
}

// 3. Rubric Score Telemetry (ScoreValue)
if let conditionScore = response.scoreValue(for: "conditionScore") {
    print("Continuous Weighted Score:", conditionScore.value) // e.g. 2.72
    print("Discrete Rounded Level:", conditionScore.rounded)   // 3 (Pristine)
    print("Score Confidence:", conditionScore.confidence)      // 0.91
}
```

---

## 6. AVFoundation Camera Integration Pipeline

For interactive iOS, iPadOS, and macOS apps, capture live camera frames, downsample using `CIContext`, and evaluate via `LanguageModelSession`:

```swift
import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import CoreGraphics
import Observation
import FoundationModels
import ClefFoundationModels

@Observable
@MainActor
public final class CameraTriageService: NSObject {
    public private(set) var currentFrame: CGImage?
    public private(set) var isInspecting: Bool = false
    public private(set) var latestDecision: VisualInspectionDecision?

    nonisolated(unsafe) public let session = AVCaptureSession()
    private let ciContext = CIContext()
    private let sessionQueue = DispatchQueue(label: "com.clef.camera.session")

    public func captureDownsampledFrame() -> CGImage? {
        guard let frame = currentFrame else { return nil }
        return TranscriptAttachmentExtractor.downsample(image: frame, maxDimension: 1024)
    }

    public func performVisualTriage(endpoint: ClefEndpoint, apiToken: String) async throws {
        guard !isInspecting, let cgImage = captureDownsampledFrame() else { return }
        isInspecting = true
        defer { isInspecting = false }

        let model = ClefLanguageModel(endpoint: endpoint, apiToken: apiToken)
        let lmSession = LanguageModelSession(model: model)

        let prompt = Prompt {
            "Analyze the item in this camera viewfinder frame."
            Attachment(cgImage)
        }

        let response = try await lmSession.respond(
            to: prompt,
            generating: VisualInspectionDecision.self
        )

        self.latestDecision = response.content
    }
}
```

---

## 7. Cloudflare Edge Architecture & Integration Nuances

### A. Decoupled Model Identifiers (Tech Note 0014)

Cloudflare Workers AI enforces two distinct model identification schemas across the HTTP boundary:
1. **Edge URL Path**: Requires the catalog path:
   ```
   POST https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/@cf/cloudflare/clef-flash
   ```
   Omitting `@cf/cloudflare/` causes HTTP 404 (`Model not found`).
2. **Body Schema Validation**: Cloudflare validates the body `/model` parameter against:
   ```regex
   ^\s*(clef|clef-flash)\s*$
   ```
   Passing `@cf/cloudflare/clef-flash` in the request body causes HTTP 400 (`AiError: Bad input`).

`ClefEndpoint` and `ClefModel` automatically decouple `workersAIIdentifier` (URL) from `modelIdentifier` (body slug).

### B. Client API v4 Envelope Unwrapping (Tech Note 0016)

Cloudflare Workers AI edge gateways return HTTP 200 responses wrapped inside Client API v4 envelopes:
```json
{
  "result": {
    "model": "@cf/cloudflare/clef-flash",
    "answers": {
      "isRecognized": { "type": "noul", "noul": 0.98, "confidence": 0.98 }
    },
    "usage": { "input_tokens": 180, "output_tokens": 0 }
  },
  "success": true,
  "errors": [],
  "messages": []
}
```

Local inference runners (Docker, vLLM, MLX) return raw `SystemOneResponse` payloads directly at the JSON root. `ClefHTTPBackend.decodeResponse` implements a dual-decoding fallback pipeline:
- Unwraps `envelope.result` when `result` is present.
- Extracts structured error messages if `success == false`.
- Decodes direct root payloads from local runners seamlessly.

### C. Edge Telemetry & Durations

`ClefHTTPBackend` parses Cloudflare edge latency headers:
- `server-timing`: RFC 7668 headers containing edge durations (e.g. `cfL4;dur=12, inference;dur=45`).
- `x-envoy-upstream-service-time`: Upstream model execution latency in milliseconds.
- Values are exposed directly via `response.serverDurationMs` and `response.transportDurationMs`.

### D. HTTP Resilience & Cooperative Cancellation

`ClefHTTPBackend` integrates `RetryPolicy` with exponential backoff and jitter, retrying transient network errors and HTTP status codes:
- `429` (Rate Limited)
- `529` (Capacity Exhausted)
- `504` / `524` (Cloudflare Gateway Timeout)

Swift 6 task cancellations are respected immediately: `CancellationError` is never converted to a network error.

---

## 8. Deterministic Offline Testing (`MockClefBackendProtocol`)

Always test visual decision workflows deterministically without live Cloudflare credentials or outbound network requests using `MockClefBackendProtocol`:

```swift
import Testing
import Foundation
import CoreGraphics
import FoundationModels
import SystemOneCore
import ClefFoundationModels

// MARK: - Mock URLProtocol for Clef Testing

final class MockClefBackendProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _responseQueue: [Result<(statusCode: Int, headers: [String: String], body: Data), any Error>] = []

    static func reset() {
        lock.withLock { _responseQueue = [] }
    }

    static func enqueue(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        lock.withLock { _responseQueue.append(.success((statusCode, headers, body))) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let nextItem = Self.lock.withLock {
            Self._responseQueue.isEmpty ? nil : Self._responseQueue.removeFirst()
        }

        guard let next = nextItem else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch next {
        case .success(let item):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.cloudflare.com")!,
                statusCode: item.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: item.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: item.body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Suite

@Suite("Clef Multimodal Decision Tests", .serialized)
struct ClefMultimodalDecisionTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockClefBackendProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("Evaluates @Generable visual inspection decision over CGImage attachment")
    func testVisualInspectionEvaluation() async throws {
        let sampleV4JSON = """
        {
          "result": {
            "model": "@cf/cloudflare/clef-flash",
            "answers": {
              "isRecognized": { "type": "noul", "noul": 0.98, "confidence": 0.98 },
              "itemCategory": { "type": "choice", "choice": "electronics", "confidence": 0.94 },
              "conditionScore": { "type": "score", "score": 3.0, "confidence": 0.92 },
              "safetyApproval": { "type": "noul", "noul": 0.99, "confidence": 0.99 }
            },
            "usage": { "input_tokens": 280, "output_tokens": 0 }
          },
          "success": true,
          "errors": [],
          "messages": []
        }
        """.data(using: .utf8)!

        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleV4JSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "test-account", model: .clefFlash),
            apiToken: "test-token",
            session: makeSession()
        )
        let model = ClefLanguageModel(configuration: .init(backend: backend))
        let session = LanguageModelSession(model: model)

        // Synthesize dummy 10x10 CGImage for test attachment
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let testImage = ctx.makeImage()!

        let prompt = Prompt {
            "Inspect camera capture serial #9011"
            Attachment(testImage)
        }

        let response = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)

        // Verify typed content
        #expect(response.content.isRecognized == true)
        #expect(response.content.itemCategory == .electronics)
        #expect(response.content.conditionScore == 3)
        #expect(response.content.safetyApproval == true)

        // Verify calibrated routing
        let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
        let recJudgement = response.judgement(for: "isRecognized", policy: policy)
        #expect(recJudgement.decision == .auto)
        #expect(recJudgement.answer == true)
    }
}
```

---

## 9. Implementation Nuances & Troubleshooting Reference

| Error / Failure Symptom | Underlying Cause | Resolution |
| :--- | :--- | :--- |
| `AiError: '/model' failed test ^\s*(clef\|clef-flash)\s*$ pattern` | Passed full catalog identifier (`@cf/...`) in JSON body. | Use `ClefEndpoint` / `ClefModel`, which automatically sends `model.rawValue` (`clef` or `clef-flash`) in the body (Tech Note 0014). |
| `AiError: The estimated number of tokens (745945) exceeded context limit (65536)` | Uncompressed 12MP–48MP frame or keyed JSON object triggered text BPE fallback. | Downsample to 1024px, compress to 0.8 lossy JPEG, and serialize directly as RFC 2397 Data URL string (Tech Note 0015). |
| `LanguageModelSession.GenerationError.unsupportedCapability` | Model did not declare `.vision` capability when prompt contained an `Attachment`. | Ensure model's `capabilities` includes `[.guidedGeneration, .vision]` (Tech Note 0013). |
| `SystemOneError.decodingError("The data couldn't be read because it is missing.")` | Expected direct root JSON but Cloudflare returned Client API v4 `{ "result": ... }` envelope. | `ClefHTTPBackend.decodeResponse` automatically unwraps `envelope.result` with dual-decoding fallback (Tech Note 0016). |
| `ClefError.imageCountExceeded` | Passed more than 4 images to a single prompt. | Adhere to `SystemOneImage.Guardrails.maxImageCount = 4`. |
| `ClefError.imageResolutionExceeded` | Individual image exceeded 16 megapixels. | Downsample using `TranscriptAttachmentExtractor.convertCGImageToJPEG(_:maxDimension:)` before creating `Attachment`. |
| `SystemOneError.structuredOutputRequired` | Called `session.respond(to: prompt)` without a `generating:` schema. | Always supply a strongly-typed `@Generable` struct or enum. |
| Zero token generation (`output_tokens: 0`) | Expected streaming text tokens from an LLM. | Normal for System One: decisions are computed in a single forward pass without autoregressive text generation. |
