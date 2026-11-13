---
name: gemini-foundation-models
license: Apache-2.0
description: >-
  Evaluate Google Gemini Decisions API (`gemini-decision-1`) non-autoregressive System One
  decision models natively through Apple's Foundation Models framework in Swift 6. Use when
  building iOS 27+, macOS 27+, or visionOS 27+ apps and services that evaluate strongly-typed
  @Generable structs, enums, or `.probability`/`.choice`/`.score` shortcuts over long-context
  text (up to 256K tokens), high-density question batches (up to 1,000 questions/pass), and
  multimodal image attachments via `POST /v1beta/decisions` with zero output token billing,
  confidence routing (`RoutingPolicy`), zero-secret mobile reverse proxies (`ProxyCredential`),
  or offline unit tests (`MockSystemOneBackend` / `MockGeminiDecisionsBackend`).
metadata:
  author: peterfriese
  version: "1.0"
---

# Google Gemini Decisions (`gemini-decision-1`) Foundation Models Bridge

> [!TIP]
> **Multi-Backend Architecture**: For projects combining Google Gemini Decisions (`GeminiFoundationModels`) with on-device Core ML (`LayaOnDevice`), self-hosted `laya-serve` (`LayaFoundationModels`), TypeSafe Jev (`JevFoundationModels`), Cloudflare Clef (`ClefFoundationModels`), OpenAI Decisions (`OpenAIFoundationModels`), or vendor-agnostic gateways (`SystemOneLanguageModel`), refer to the unified `system-one-foundation-models` skill. This skill focuses specifically on `GeminiLanguageModel` (`GeminiDecisionsLanguageModel`), `POST /v1beta/decisions` wire semantics, high-batch evaluation, multimodal Base64 segments, and `ProxyCredential` mobile attestation.

This skill guides the design, implementation, and testing of Swift 6 applications integrating **Google's Gemini Decisions API** (`POST https://generativelanguage.googleapis.com/v1beta/decisions`) powered by **`gemini-decision-1`** via **Apple's Foundation Models framework** (`FoundationModels`).

---

## 1. Core Mental Model & High-Density Economics

`gemini-decision-1` is a purpose-built **non-autoregressive System One decision model**, not an autoregressive chat generator. It evaluates long-context state and visual inputs against dictionary-keyed propositions in a **single forward pass**:

- **Zero Output Token Billing**: Every evaluation emits `output_tokens: 0` (`$0.00` output tokens).
- **256K Context & 1,000 Questions per Pass**: Evaluates between **1 and 1,000 concurrent questions** in a single HTTP request (`GeminiDecisionsPayloadAdapter` validates `(1...1_000).contains(request.questions.count)`).
- **Sub-100ms Server Telemetry**: Parses `x-goog-processing-ms`, `x-envoy-upstream-service-time`, and `server-timing` headers into `response.serverDurationMs`.
- **Dual Signal Output**:
  1. **Typed Decision Content**: `response.content` decoded directly into your Swift `@Generable` struct or enum.
  2. **Calibrated Epistemic Probabilities**: Posterior `noul` probabilities, categorical `choice` distributions, and ordinal `score` distributions accessible via `response.judgement(for:policy:)`, `response.decision(for:policy:)`, and `response.scoreValue(for:)`.

---

## 2. Progressive-Disclosure Initialization & Mobile `ProxyCredential`

`GeminiLanguageModel` (`public typealias` for `GeminiDecisionsLanguageModel`) supports zero-argument initialization (`GEMINI_API_KEY` or fallback `GOOGLE_API_KEY` sent via `x-goog-api-key`), explicit custom endpoints, zero-secret mobile `ProxyCredential` gateways, and uniform `init(backend:)` injection:

```swift
import FoundationModels
import GeminiFoundationModels

// 1. Zero-Argument Progressive Disclosure (reads GEMINI_API_KEY or GOOGLE_API_KEY)
let session = LanguageModelSession(model: GeminiLanguageModel())

// 2. Explicit API Key & Distributed Tracing Header (`X-Client-Request-Id`)
let tracedModel = GeminiLanguageModel(
    apiKey: apiKey,
    model: GeminiDecisionsEndpoint.defaultModel, // "gemini-decision-1"
    clientRequestID: UUID().uuidString,
    retryPolicy: .default
)

// 3. Custom Enterprise Gateway Endpoint
let customEndpoint = GeminiDecisionsEndpoint.custom(
    URL(string: "https://gemini-gateway.internal.example.com/v1beta/decisions")!,
    model: "gemini-decision-1"
)
let enterpriseModel = GeminiLanguageModel(endpoint: customEndpoint, apiKey: internalKey)
```

### Zero-Secret Mobile Deployment (`ProxyCredential`)

**Never ship `GEMINI_API_KEY` or `GOOGLE_API_KEY` inside client iOS, macOS, or visionOS binaries.** Route mobile requests through an HTTPS reverse proxy (validated by `ProxyEndpointValidator.validate(_:)`) using `ProxyCredential` (`.appCheck`, `.bearer`, `.header`, `.custom`, or trailing `authorize:`):

```swift
import FirebaseAppCheck
import FirebaseCore
import FoundationModels
import GeminiFoundationModels

let proxyURL = URL(string: "https://us-central1-my-app.cloudfunctions.net/geminiDecisions")!

let mobileModel = GeminiLanguageModel(
    proxyEndpoint: proxyURL,
    credential: .appCheck {
        guard FirebaseApp.app() != nil else {
            throw SystemOneError.authenticationFailed("FirebaseApp is not configured.")
        }
        return try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
let mobileSession = LanguageModelSession(model: mobileModel)
```

---

## 3. `@Generable` Schema Mapping & Wire Translation

`GeminiDecisionsPayloadAdapter` maps Apple `@Generable` schemas onto Google's dictionary-keyed `/v1beta/decisions` wire format (see Tech Note 0018):

| Swift Type & Annotation | System One Primitive | Gemini `/v1beta/decisions` Wire Question | Behavior |
| :--- | :--- | :--- | :--- |
| `Bool` | `noul` | `{ "type": "noul", "instructions": "..." }` | Calibrated truth probability ($0.0\dots1.0$). |
| `enum: String` / `Choosable` | `choice` | `{ "type": "choice", "instructions": "...", "criteria": { ... } }` | Categorical distribution across enum cases. |
| `Int` / `Double` + `@Guide(.range(min...max))` | `score` | `{ "type": "score", "instructions": "...", "criteria": [...] }` | Ordinal rubric levels with continuous weighted mean. |

> [!IMPORTANT]
> **Self-Identifying Batched Questions**: When evaluating multiple questions in a single `@Generable` struct (up to 1,000 questions), ensure each `@Guide(description:)` names the specific entity or attribute it evaluates. Identical instruction strings collapse batch discrimination toward `0.5`.

### Canonical Call Site & Epistemic Routing

```swift
import FoundationModels
import GeminiFoundationModels

@Generable
enum ModerationAction: String, Sendable {
    case publish
    case holdForReview
    case quarantine
}

@Generable
struct TrustSafetyDecision: Sendable {
    @Guide(description: "Does this submission attempt credential phishing or admin impersonation?")
    var isPhishing: Bool

    @Guide(description: "Recommended moderation queue action")
    var action: ModerationAction

    @Guide(description: "Threat severity from 0 (benign) to 3 (critical threat)", .range(0...3))
    var severity: Int
}

let session = LanguageModelSession(model: GeminiLanguageModel())
let response = try await session.respond(to: postSubmission, generating: TrustSafetyDecision.self)

let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85, undecidedBand: 0.35...0.65)
let phishing = response.judgement(for: "isPhishing", policy: policy)

switch phishing.decision {
case .auto:
    phishing.answer == true ? quarantinePost() : publishImmediately()
case .confirm:
    flagModeratorOneClickReview()
case .escalate:
    assignTrustSafetySpecialist() // Inside 0.35...0.65 undecided band
}
```

---

## 4. Multimodal Vision Evaluation & Flat Typed `input` Array

`GeminiLanguageModel` declares `LanguageModelCapabilities([.guidedGeneration, .vision])` and accepts PNG, JPEG, and WebP `Attachment`s in both `session.respond(to:generating:)` and `.probability` / `.choice` / `.score` `@PromptBuilder` shortcuts:

```swift
import FoundationModels
import GeminiFoundationModels

let session = LanguageModelSession(model: GeminiLanguageModel())

// 1. Direct @PromptBuilder multimodal shortcut
let damaged = try await session.probability(of: "The parcel has visible exterior damage") {
    "Inspect inbound delivery photo #8812."
    Attachment(parcelCGImage)
}

// 2. Full @Generable visual inspection schema
let prompt = Prompt {
    "Analyze item category, physical condition, and safety compliance."
    Attachment(imageURL: localPhotoURL)
}
let inspection = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)
```

### Multimodal Wire Nuances (`GeminiDecisionsPayloadAdapter`)
- **Flat Typed `input` Array**: When images are attached, `input` serializes as `[ { "type": "text", "text": "..." }, { "type": "image", "mime_type": "image/jpeg", "data": "<raw-base64>" } ]` using **raw Base64** (not `data:...` URL prefixes), while also supporting legacy `parts`/`inline_data` decode compatibility.
- **Automatic Downscaling & Guardrails**: `TranscriptAttachmentExtractor` downscales `Attachment(cgImage)` above `1024px` to `0.8` JPEG; `GeminiDecisionsAttachmentValidator` / `SystemOneImage.Guardrails` enforce max **4 images**, **16.0 MP** per image, and **13 MiB** total payload.

---

## 5. Error Semantics & Google RPC Status Mapping

`GeminiDecisionsHTTPBackend` parses Google RPC error envelopes (`{ "error": { "code", "message", "status" } }`) onto typed `SystemOneError` cases while never wrapping Swift 6 `CancellationError`:

| Condition | Thrown `SystemOneError` | Retry Behavior |
| :--- | :--- | :--- |
| Unset `GEMINI_API_KEY` & `GOOGLE_API_KEY` | `.missingAPIKey` | Fails immediately |
| HTTP `401` / `403` (`UNAUTHENTICATED` / `PERMISSION_DENIED`) | `.authenticationFailed(message)` | Fails immediately |
| `RESOURCE_EXHAUSTED` quota depletion | `.quotaExceeded(message)` | Fails immediately |
| Transient HTTP `429` / `503` / `529` | `.apiError(statusCode:message:)` | Retries with `Retry-After` (RFC 9110) or jittered backoff |
| Safety policy block (`type == "refusal"` / `ans.refusal != nil`) | `.safetyRefusal(reason:questionName:)` | Fails immediately |
| Missing `generating:` schema | `.structuredOutputRequired` | Fails immediately |

---

## 6. Deterministic Offline Testing (`MockSystemOneBackend` / `MockGeminiDecisionsBackend`)

Never call `generativelanguage.googleapis.com` in unit tests. Inject `MockSystemOneBackend` (or wire-level `MockGeminiDecisionsBackend`) via `GeminiLanguageModel(backend:)`:

```swift
import FoundationModels
import GeminiFoundationModels
import SystemOneCore
import Testing

@Suite("Gemini Decisions Offline Tests")
struct GeminiDecisionsWorkflowTests {

    @Test("Evaluates TrustSafetyDecision offline with zero output tokens")
    func testPhishingDetection() async throws {
        let mock = MockSystemOneBackend { request in
            #expect(request.model == "gemini-decision-1")
            #expect(request.questions.count == 3)
            return SystemOneResponse(
                model: "gemini-decision-1",
                answers: [
                    "isPhishing": SystemOneAnswer(type: "noul", noul: 0.98, confidence: 0.98),
                    "action": SystemOneAnswer(type: "choice", choice: "quarantine", confidence: 0.96),
                    "severity": SystemOneAnswer(type: "score", score: 3.0, confidence: 0.95)
                ],
                usage: SystemOneUsage(inputTokens: 94, outputTokens: 0),
                serverDurationMs: 38.0
            )
        }

        let session = LanguageModelSession(model: GeminiLanguageModel(backend: mock))
        let response = try await session.respond(to: "Verify your SSO password now!", generating: TrustSafetyDecision.self)

        #expect(response.content.isPhishing == true)
        #expect(response.content.action == .quarantine)
        #expect(response.content.severity == 3)
        #expect(response.usage.output.totalTokenCount == 0)
    }
}
```
