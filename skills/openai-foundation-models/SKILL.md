---
name: openai-foundation-models
license: Apache-2.0
description: >-
  Evaluate OpenAI Decisions API (`gpt-6-luna`) non-autoregressive System One decision models
  natively through Apple's Foundation Models framework in Swift 6. Use when building iOS 27+,
  macOS 27+, or visionOS 27+ apps and services that evaluate strongly-typed @Generable structs,
  enums, or `.probability`/`.choice`/`.score` shortcuts over text and multimodal image attachments
  via `POST /v1/decisions` with zero output token billing, enterprise multi-tenant headers
  (`OpenAI-Organization`, `OpenAI-Project`), confidence routing (`RoutingPolicy`), zero-secret
  mobile reverse proxies (`ProxyCredential`), or offline unit tests (`MockSystemOneBackend`).
metadata:
  author: peterfriese
  version: "1.1"
---

# OpenAI Decisions (`gpt-6-luna`) Foundation Models Bridge

> [!TIP]
> **Multi-Backend Architecture**: For projects combining OpenAI Decisions (`OpenAIFoundationModels`) with on-device Core ML (`LayaOnDevice`), self-hosted `laya-serve` (`LayaFoundationModels`), TypeSafe Jev (`JevFoundationModels`), Cloudflare Clef (`ClefFoundationModels`), Google Gemini Decisions (`GeminiFoundationModels`), or vendor-agnostic gateways (`SystemOneLanguageModel`), refer to the unified `system-one-foundation-models` skill. This skill focuses specifically on `OpenAILanguageModel` (`OpenAIDecisionsLanguageModel`), `gpt-6-luna` wire translation, zero-output-token economics, enterprise headers, and multimodal guardrails.

This skill guides the design, implementation, and testing of Swift 6 applications integrating **OpenAI's Decisions API** (`POST https://api.openai.com/v1/decisions`) powered by **`gpt-6-luna`** via **Apple's Foundation Models framework** (`FoundationModels`).

---

## 1. Core Mental Model & Zero-Output-Token Economics

`gpt-6-luna` is a purpose-built **non-autoregressive System One decision model**, not a conversational chat model. Instead of sampling JSON tokens one by one, it evaluates application state and visual inputs against typed propositions in a **single forward pass**:

- **Sub-100ms Typical Latency**: ~35–80ms server processing (`openai-processing-ms` header exposed via `response.serverDurationMs`).
- **Zero Output Token Billing**: Every evaluation emits `output_tokens: 0`. Pricing is **$0.10 / 1M input tokens** and **$0.00 / 1M output tokens**, eliminating the 3x–10x output token tax of autoregressive LLMs.
- **Dual Signal Output**:
  1. **Typed Decision Content**: `response.content` decoded directly into your Swift `@Generable` struct or enum.
  2. **Calibrated Epistemic Probabilities**: Posterior proposition probabilities (`predicate`), categorical distributions (`choice`), and rubric distributions (`score`) accessible via `response.judgement(for:policy:)`, `response.decision(for:policy:)`, and `response.scoreValue(for:)`.

---

## 2. Progressive-Disclosure Initialization & Enterprise Headers

`OpenAIDecisionsLanguageModel` supports zero-argument initialization (automatically resolving `OPENAI_API_KEY` from the process environment), multi-tenant enterprise isolation headers, custom gateways (`OpenAIDecisionsEndpoint`), and uniform `SystemOneBackend` injection:

```swift
import FoundationModels
import OpenAIFoundationModels

// 1. Zero-Argument Progressive Disclosure (reads OPENAI_API_KEY, targets gpt-6-luna)
let session = LanguageModelSession(model: OpenAIDecisionsLanguageModel())

// 2. Enterprise Multi-Tenant Configuration
// Sends `OpenAI-Organization`, `OpenAI-Project`, and `X-Client-Request-Id` headers
let enterpriseModel = OpenAIDecisionsLanguageModel(
    apiKey: apiKey,
    organization: "org-acme-prod",
    project: "proj-claims-triage",
    clientRequestID: UUID().uuidString,
    retryPolicy: .default
)
let enterpriseSession = LanguageModelSession(model: enterpriseModel)

// 3. Explicit Endpoint Enum (.hosted or .custom enterprise gateway)
let gatewayEndpoint = OpenAIDecisionsEndpoint.custom(
    URL(string: "https://ai-gateway.internal.example.com/v1/decisions")!,
    model: OpenAIDecisionsEndpoint.defaultModel, // "gpt-6-luna"
    organization: "org-acme-prod",
    project: "proj-claims-triage"
)
let gatewayModel = OpenAIDecisionsLanguageModel(endpoint: gatewayEndpoint, apiKey: gatewayToken)
```

### Zero-Secret Mobile Deployment (`ProxyCredential`)
Never bundle `OPENAI_API_KEY` inside client iOS, iPadOS, macOS, or visionOS binaries. Route mobile traffic through an HTTPS reverse proxy (validated by `ProxyEndpointValidator.validate(_:)`) using `SystemOneCore.ProxyCredential`:

```swift
import FirebaseAppCheck
import FoundationModels
import OpenAIFoundationModels

let mobileModel = OpenAILanguageModel(
    proxyEndpoint: URL(string: "https://us-central1-my-app.cloudfunctions.net/openaiDecisions")!,
    credential: .appCheck {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
let mobileSession = LanguageModelSession(model: mobileModel)
```

---

## 3. `@Generable` Schema Mapping & Wire Translation

`OpenAIDecisionsPayloadAdapter` bridges Apple `@Generable` schemas and `SystemOneRequest` primitives cleanly onto OpenAI's `/v1/decisions` wire format:

| Swift Type & Annotation | System One Primitive | OpenAI `/v1/decisions` Wire Type | Behavior |
| :--- | :--- | :--- | :--- |
| `Bool` | `noul` | **`predicate`** | Calibrated truth probability ($0.0\dots1.0$). |
| `enum: String` | `choice` | **`choice`** | Categorical selection across `choices: [{ value, description }]`. |
| `Int` / `Double` + `@Guide(.range(min...max))` | `score` | **`score`** | Bounded ordinal rubric across `levels: [{ label, description }]` (up to 32 discrete levels; handles both 0-based and non-zero-based ranges like `1...5`). |
| `@Guide(description: "...")` | `instructions` | **`instructions`** | Semantic rubric instructions for that question. |

### Canonical `@Generable` Evaluation & Epistemic Routing

```swift
import FoundationModels
import OpenAIFoundationModels

@Generable
enum ClaimQueue: String, Sendable {
    case autoApprove
    case fraudInvestigation
    case manualAdjuster
}

@Generable
struct ExpenseDecision: Sendable {
    @Guide(description: "Does this receipt comply with corporate travel & meal policy?")
    var isApproved: Bool

    @Guide(description: "Target claims processing queue")
    var queue: ClaimQueue

    @Guide(description: "Audit risk score from 1 (minimal) to 5 (severe)", .range(1...5))
    var riskScore: Int
}

let session = LanguageModelSession(model: OpenAIDecisionsLanguageModel())
let response = try await session.respond(
    to: "Team dinner receipt $142.50 with itemized merchant invoice attached.",
    generating: ExpenseDecision.self
)

let decision = response.content
let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85, undecidedBand: 0.35...0.65)

// Epistemic Noul routing (never use raw `p < policy.escalateBelow`!)
let approvalJudgement = response.judgement(for: "isApproved", policy: policy)
switch approvalJudgement.decision {
case .auto:
    if approvalJudgement.answer == true {
        reimburseAutomatically() // Confident Yes (p >= 0.85)
    } else {
        rejectAutomatically()    // Confident No (p <= 0.15, decisiveness >= 0.85)
    }
case .confirm:
    flagForManagerOneClickReview()
case .escalate:
    routeToHumanAuditor()        // Probability inside undecided band (0.35...0.65)
}
```

---

## 4. Multimodal Vision Evaluation & Guardrails

`OpenAIDecisionsLanguageModel` advertises `LanguageModelCapabilities([.guidedGeneration, .vision])` and accepts PNG, JPEG, and WebP attachments in both `session.respond(to:generating:)` and `.probability` / `.choice` / `.score` `@PromptBuilder` shortcuts:

```swift
import FoundationModels
import OpenAIFoundationModels

let session = LanguageModelSession(model: OpenAIDecisionsLanguageModel())

// 1. One-line multimodal @PromptBuilder shortcut
let receiptTampered = try await session.probability(
    of: "The uploaded receipt image shows signs of digital alteration or font mismatch"
) {
    "Audit receipt #4410 against submitted total of $980.00"
    Attachment(receiptCGImage)
}

// 2. Full @Generable multimodal evaluation
let prompt = Prompt {
    "Evaluate itemized receipt image for policy compliance and audit risk."
    Attachment(imageURL: localReceiptJPEGURL)
}
let response = try await session.respond(to: prompt, generating: ExpenseDecision.self)
```

### Multimodal Wire Rules (`OpenAIDecisionsAttachmentValidator`)
1. **Inline RFC 2397 Data URLs Only**: `OpenAIDecisionsPayloadAdapter` encodes active-turn attachments as inline `input_image` blocks (`data:image/jpeg;base64,...`). Remote HTTPS image URLs and OpenAI Files API `file_id` references are not supported by `/v1/decisions`.
2. **Guardrails (`SystemOneImage.Guardrails`)**:
   - Maximum **4 images** per active evaluation turn (`maxImageCount = 4`).
   - Maximum **16.0 megapixels** per image (`maxMegapixels = 16.0`).
   - Maximum **13 MiB** combined image payload (`maxPayloadBytes = 13 * 1024 * 1024`).
3. **Downscaling**: `TranscriptAttachmentExtractor` automatically downscales `Attachment(cgImage)` and oversized local `Attachment(imageURL:)` inputs exceeding `1024px` to 0.8-quality JPEG (`TranscriptAttachmentExtractor.convertCGImageToJPEG(_:maxDimension:quality:)`).

---

## 5. Error Semantics & Resilience

`OpenAIDecisionsHTTPBackend` maps HTTP and domain errors onto typed `SystemOneError` cases while preserving Swift 6 cooperative cancellation (`CancellationError` is never wrapped):

| Condition | Thrown `SystemOneError` | Retry Behavior |
| :--- | :--- | :--- |
| Unset `OPENAI_API_KEY` | `.missingAPIKey` | Fails immediately |
| HTTP `401` / `403` | `.authenticationFailed(message)` | Fails immediately |
| HTTP `429` with `insufficient_quota` | `.quotaExceeded(message)` | Fails immediately (does not waste retries) |
| HTTP `429` (rate limit) / `503` / `529` | `.apiError(statusCode:message:)` | Retries with `Retry-After` (RFC 9110) or jittered backoff |
| Policy refusal (`answer.refusal != nil`) | `.safetyRefusal(reason:questionName:)` | Fails immediately |
| Missing `generating:` schema | `.structuredOutputRequired` | Fails immediately |

---

## 6. Deterministic Offline Testing (`MockSystemOneBackend`)

Never call `api.openai.com` in unit tests. Inject `MockSystemOneBackend` directly via `OpenAIDecisionsLanguageModel(backend:)`:

```swift
import Testing
import FoundationModels
import SystemOneCore
import OpenAIFoundationModels

@Suite("OpenAI Decisions Offline Tests")
struct OpenAIDecisionsWorkflowTests {

    @Test("Evaluates ExpenseDecision and normalizes zero output tokens")
    func testExpenseEvaluation() async throws {
        let mockBackend = MockSystemOneBackend { request in
            #expect(request.model == "gpt-6-luna")
            #expect(request.questions.count == 3)

            return SystemOneResponse(
                model: "gpt-6-luna",
                answers: [
                    "isApproved": SystemOneAnswer(
                        type: "noul",
                        noul: 0.94,
                        confidence: 0.94,
                        probabilities: ["true": 0.94, "false": 0.06]
                    ),
                    "queue": SystemOneAnswer(
                        type: "choice",
                        choice: "autoApprove",
                        confidence: 0.92,
                        probabilities: ["autoApprove": 0.92, "manualAdjuster": 0.06, "fraudInvestigation": 0.02]
                    ),
                    "riskScore": SystemOneAnswer(
                        type: "score",
                        score: 1.0,
                        confidence: 0.90,
                        probabilities: ["1": 0.90, "2": 0.08, "3": 0.02, "4": 0.0, "5": 0.0]
                    )
                ],
                usage: SystemOneUsage(inputTokens: 128, outputTokens: 0),
                serverDurationMs: 42.5,
                transportDurationMs: 58.0
            )
        }

        let model = OpenAIDecisionsLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(
            to: "Team dinner receipt $142.50 with itemized invoice",
            generating: ExpenseDecision.self
        )

        #expect(response.content.isApproved == true)
        #expect(response.content.queue == .autoApprove)
        #expect(response.content.riskScore == 1)
        #expect(response.usage.output.totalTokenCount == 0)
        #expect(response.serverDurationMs == 42.5)
    }
}
```
