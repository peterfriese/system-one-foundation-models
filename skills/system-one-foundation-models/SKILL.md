---
name: system-one-foundation-models
license: Apache-2.0
description: >-
  Evaluate System One decision models (Laya On-Device Core ML, Laya HTTP server, TypeSafe Jev,
  Cloudflare Clef & Clef-Flash, OpenAI Decisions gpt-6-luna, Google Gemini Decisions
  gemini-decision-1, and vendor-agnostic SystemOneProxyBackend gateways) natively through
  Apple's Foundation Models framework in Swift 6. Use when building iOS 27+, macOS 27+, or
  visionOS 27+ apps that evaluate strongly-typed @Generable structs, enums, or
  `.probability`/`.choice`/`.score` shortcuts using LanguageModelSession, running models
  on-device via Core ML (Apple Neural Engine), deploying multimodal visual triage, securing
  mobile proxies via zero-dependency ProxyCredential and Firebase App Check, implementing
  confidence routing (RoutingPolicy, NoulJudgement, ScoreValue), configuring resilient network
  retries (RetryPolicy), or writing deterministic offline unit tests with MockSystemOneBackend.
metadata:
  author: peterfriese
  version: "2.2"
---

# System One Foundation Models Bridge

This skill guides the design, implementation, and testing of applications integrating **System One decision models** (**Laya On-Device Core ML**, **Laya HTTP Server**, **TypeSafe Jev**, **Cloudflare Clef & Clef-Flash**, **OpenAI Decisions (`gpt-6-luna`)**, **Google Gemini Decisions (`gemini-decision-1`)**, and vendor-agnostic **`SystemOneProxyBackend` gateways**) via **Apple's Foundation Models framework** (`FoundationModels`) in Swift 6.

---

## 1. Core Mental Model: Decisions, Not Chat

System One models are **non-autoregressive decision models**, not text-generating LLMs. They evaluate application state against a set of typed questions in a single forward pass, returning calibrated probabilities and discrete categorical decisions in 15–250ms with zero output tokens.

- **Prompt $\to$ Application State**: The text (and optional image attachments on multimodal backends) passed to `session.respond(to:)` represents current application context (support tickets, sensor readings, transaction logs, camera frames, or parsed documents).
- **`@Generable` Type $\to$ Decision Questions**: The struct or enum defines the typed questions being asked over that state.
- **Dual Signal Output**:
  1. **The Answer**: *What* the model judged (`response.content` containing typed enum choices, booleans, or rubric scores). For `Bool` fields this decode is a hard `0.5` cutoff (`noul >= 0.5`) — see §5; decisions must consume `response.probability(for:)` / `response.judgement(for:policy:)`.
  2. **The Calibrated Confidence / Probability**: *Whether* to automate the action (`response.judgement(...)`, `response.decision(...)`, `response.scoreValue(...)`).

---

## 2. Pluggable Backends & Homogeneous Initialization

All **6** providers support progressive-disclosure **zero-argument initialization (`init()`)** with automatic environment-variable / bundle resolution, uniform **`init(backend: any SystemOneBackend)`**, and universal **`init(proxyEndpoint:credential:)`** across networked models:

| Provider | Zero-Arg Call Site | Auto-Resolved Environment / Resource |
| :--- | :--- | :--- |
| `LayaOnDeviceLanguageModel` | `try LayaOnDeviceLanguageModel()` | `LAYA_MODEL_PATH` or bundled `LayaDecisionModel.mlmodelc` + `LAYA_TOKENIZER_PATH` / adjacent `tokenizer.json` |
| `LayaLanguageModel` | `LayaLanguageModel()` | `LAYA_SERVE_URL` / `LAYA_ENDPOINT` (defaults to `http://127.0.0.1:8000/v1/systemone`) + optional `LAYA_API_KEY` |
| `JevLanguageModel` | `JevLanguageModel()` | `TYPESAFE_API_KEY` on `JevEndpoint.hosted` (`https://api.typesafe.ai/v1/systemone`) |
| `ClefLanguageModel` | `ClefLanguageModel()` | `CLEF_ENDPOINT`, `CLOUDFLARE_ACCOUNT_ID` (+ `CLOUDFLARE_GATEWAY_ID`) + `CLOUDFLARE_API_TOKEN`, or `CLEF_LOCAL_PORT` |
| `OpenAIDecisionsLanguageModel` (`OpenAILanguageModel`) | `OpenAILanguageModel()` | `OPENAI_API_KEY` on `OpenAIDecisionsEndpoint.hosted()` (`https://api.openai.com/v1/decisions`, `gpt-6-luna`) |
| `GeminiDecisionsLanguageModel` (`GeminiLanguageModel`) | `GeminiLanguageModel()` | `GEMINI_API_KEY` (fallback `GOOGLE_API_KEY`) on `GeminiDecisionsEndpoint.hosted()` (`gemini-decision-1`) |

### Option A: On-Device Core ML (`LayaOnDevice`)
Runs Laya's 322M (multilingual mmBERT) or 421M (ModernBERT) model directly on the **Apple Neural Engine (ANE)** and GPU. 100% offline, zero network requests, zero secrets:

```swift
import FoundationModels
import LayaOnDevice

// Progressive disclosure: auto-resolves LAYA_MODEL_PATH or bundled LayaDecisionModel.mlmodelc
let session = LanguageModelSession(model: try LayaOnDeviceLanguageModel())

// Or explicit Core ML engine configuration:
let modelURL = Bundle.main.url(forResource: "LayaModernBERT", withExtension: "mlmodelc")!
let engine = try LayaCoreMLEngine(
    modelURL: modelURL,
    tokenizer: ModernBERTTokenizer.defaultTokenizer()
)
let customSession = LanguageModelSession(model: LayaOnDeviceLanguageModel(engine: engine))
```

### Option B: Self-Hosted or Remote Laya HTTP (`LayaFoundationModels`)
Connects to `laya-serve` (speaking the Jev-compatible `POST /v1/systemone` protocol) with `RetryPolicy` resilience:

```swift
import FoundationModels
import LayaFoundationModels

// Auto-resolves LAYA_SERVE_URL / LAYA_API_KEY or defaults to localhost:8000
let session = LanguageModelSession(model: LayaLanguageModel())

// Or explicit endpoint (.localDefault, .local(port: 8770), .hosted, or .custom(url))
let explicitModel = LayaLanguageModel(endpoint: .local(port: 8770), retryPolicy: .default)
```

### Option C: TypeSafe AI Jev Cloud (`JevFoundationModels`)
Connects to TypeSafe AI's hosted decision API (`JevEndpoint.hosted` or `.custom(url)`) with automated HTTP retry resilience and backoff:

```swift
import FoundationModels
import JevFoundationModels

// Auto-resolves TYPESAFE_API_KEY
let session = LanguageModelSession(model: JevLanguageModel())

// Or explicit configuration
let retryPolicy = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(250), jitter: 0.15)
let explicitModel = JevLanguageModel(endpoint: .hosted, apiKey: apiKey, retryPolicy: retryPolicy)
```

### Option D: Cloudflare Clef & Clef-Flash Multimodal (`ClefFoundationModels`)
Connects to Cloudflare's **Clef** (27B) or **Clef-Flash** (9B) multimodal decision models for visual item inspection, damage assessment, KYC document verification, or mobile camera triage:

```swift
import FoundationModels
import ClefFoundationModels

// Auto-resolves CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN, CLEF_ENDPOINT, or CLEF_LOCAL_PORT
let autoSession = LanguageModelSession(model: ClefLanguageModel())

// 1. Direct Cloudflare Workers AI Edge
let workersEndpoint = ClefEndpoint.workersAI(accountID: "cf-account-id", model: .clefFlash)
let workersModel = ClefLanguageModel(endpoint: workersEndpoint, apiToken: "cf-api-token")

// 2. Cloudflare AI Gateway (with edge caching, analytics, and rate limiting)
let gatewayEndpoint = ClefEndpoint.gateway(
    accountID: "cf-account-id",
    gatewayID: "production-gateway",
    model: .clef
)
let gatewayModel = ClefLanguageModel(endpoint: gatewayEndpoint, apiToken: "cf-api-token")

// 3. Local Native Runner (Tools/ClefLocalRunner/server.py, vLLM, MLX on port 8000)
let localModel = ClefLanguageModel(endpoint: .local(port: 8000, model: .clefFlash))
```

### Option E: OpenAI Decisions API — `gpt-6-luna` (`OpenAIFoundationModels`)
Connects to OpenAI's purpose-built non-autoregressive Decisions API (`POST https://api.openai.com/v1/decisions`) powered by **`gpt-6-luna`** (~35–80ms latency, multimodal vision support, $0.10/1M input tokens, and **$0.00 output tokens**):

```swift
import FoundationModels
import OpenAIFoundationModels

// Auto-resolves OPENAI_API_KEY
let session = LanguageModelSession(model: OpenAIDecisionsLanguageModel())

// Or configure enterprise multi-tenant headers (OpenAI-Organization, OpenAI-Project, X-Client-Request-Id)
let enterpriseModel = OpenAIDecisionsLanguageModel(
    apiKey: apiKey,
    organization: "org-...",
    project: "proj-..."
)
```

### Option F: Google Gemini Decisions API (`GeminiFoundationModels`)
Connects to Google's high-density multimodal Gemini Decisions API (`POST https://generativelanguage.googleapis.com/v1beta/decisions`, default model `"gemini-decision-1"`), supporting `GeminiLanguageModel` (`typealias` for `GeminiDecisionsLanguageModel`), up to 256K-token context, and up to 1,000 concurrent questions per forward pass:

```swift
import FoundationModels
import GeminiFoundationModels

// Auto-resolves GEMINI_API_KEY or GOOGLE_API_KEY
let session = LanguageModelSession(model: GeminiLanguageModel())

// Or explicit API key
let explicitModel = GeminiLanguageModel(apiKey: apiKey)
```

### Option G: Vendor-Agnostic Proxy Gateway (`SystemOneCore`)
Dispatches canonical `SystemOneRequest` JSON via `SystemOneProxyBackend` (with `ProxyCredential`) so your backend gateway can route, A/B test, or fail over between Gemini, OpenAI, Clef, Jev, and Laya server-side with zero client code changes (see §6):

```swift
import FoundationModels
import SystemOneCore

let model = SystemOneLanguageModel(
    proxyEndpoint: gatewayURL,
    credential: appCheckCredential,
    modelID: "gemini-decision-1" // supportsVision defaults to true on proxy initializers
)
let session = LanguageModelSession(model: model)
```

---

## 3. Multimodal Decision Evaluation (`Clef`, `OpenAI` & `Gemini`)

Unlike autoregressive vision-language models that generate text captions or verbose descriptions, multimodal System One backends — **Cloudflare Clef (`ClefLanguageModel`)**, **OpenAI Decisions (`OpenAILanguageModel`)**, **Google Gemini Decisions (`GeminiLanguageModel`)**, and **`SystemOneLanguageModel(supportsVision: true)`** — evaluate contextual text + image attachments (`PNG`, `JPEG`, `WebP`) in a **single forward pass**, computing calibrated decision primitives with **zero output tokens** (`output_tokens: 0`).

### Passing Image Attachments via `Prompt` & Ergonomic Shortcuts

Visual inputs are attached to standard Apple Foundation Models `Prompt` builder blocks using `Attachment(cgImage)`, `Attachment(imageURL: url)`, or failable `Attachment(jpegData, type: .jpeg)`:

```swift
import FoundationModels
import GeminiFoundationModels // or ClefFoundationModels / OpenAIFoundationModels
import CoreGraphics

let session = LanguageModelSession(model: GeminiLanguageModel())

// 1. Composite @Generable decision with Prompt
let prompt = Prompt {
    "Inspect the physical condition of this returned merchandise item."
    Attachment(capturedCGImage)
}
let response = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)
let decision: VisualInspectionDecision = response.content

// 2. Direct @PromptBuilder ergonomic shortcuts (.probability, .choice, .score)
let damagedProb = try await session.probability(of: "The parcel has visible exterior damage") {
    "Inspect delivery photo for crushed corners or water damage."
    Attachment(capturedCGImage)
}
```

### Apple Framework Capability Gating: `LanguageModelCapabilities.Capability.vision`

Apple's `FoundationModels` framework performs client-side capability validation before dispatching generation requests. If a `Prompt` contains an `Attachment` with visual data:
- The session runtime inspects `model.capabilities`.
- The capability set **must include `.vision`** alongside `.guidedGeneration`.
- If `.vision` is missing (as in text-only models like `JevLanguageModel`, `LayaLanguageModel`, or `LayaOnDeviceLanguageModel`), `LanguageModelSession` fails immediately with `LanguageModelSession.GenerationError.unsupportedCapability`: *"The selected model does not support image input. Consider trying again with a different model."*
- `ClefLanguageModel`, `OpenAIDecisionsLanguageModel`, `GeminiDecisionsLanguageModel`, and `SystemOneLanguageModel(supportsVision: true)` explicitly advertise both capabilities:
  ```swift
  public var capabilities: LanguageModelCapabilities {
      LanguageModelCapabilities([.guidedGeneration, .vision])
  }
  ```

### Image Preprocessing Best Practice: 1024px Downsampling & 0.8 JPEG Compression

High-resolution mobile camera hardware (such as 12MP to 48MP iPhone sensors) creates two critical problems if uploaded uncompressed or as raw PNGs (see Tech Note 0015):
1. **BPE Text Tokenizer Fallback**: Edge gateways serialize images as RFC 2397 Data URLs (`data:image/jpeg;base64,...`). If oversized base64 blobs are parsed as text, standard BPE tokenization expands the string into **700,000+ tokens**, exceeding context limits (HTTP 413).
2. **Payload & Patch Blowout**: High-resolution PNGs consume 10–30 MB of bandwidth and generate tens of thousands of vision patches, slowing inference.

**Best Practice**: `TranscriptAttachmentExtractor` automatically downscales `Attachment(cgImage)` inputs to a **1024px** maximum dimension (encoding opaque frames as `0.8` JPEG and alpha-bearing images as PNG). When constructing raw `Attachment(data:type:)` segments manually, pre-downsample so the maximum dimension does not exceed **1024px** at **0.8 JPEG quality**:
```swift
let downsampledJPEG = TranscriptAttachmentExtractor.convertCGImageToJPEG(
    rawCGImage,
    maxDimension: 1024,
    quality: 0.8
)
```
This reduces the image payload to 100–300 KB, maps to **~1,000 vision patch tokens**, and executes in sub-250ms.

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
- ❌ **No unconstrained `String` properties**: Decision models do not generate free-form text. A `String` property without enum choices throws `SystemOneError.invalidSchema`.
- ❌ **No unstructured collections**: Arrays of open-ended values (`[String]`) or dictionaries are not supported.
- ❌ **No text generation requests without schemas**: Calling `session.respond(to: "Hello")` without a `generating:` argument throws `SystemOneError.structuredOutputRequired`.
- ❌ **No tool calling**: `LanguageModelCapabilities` includes `[.guidedGeneration]` (plus `.vision` on multimodal backends) — `Tool` execution is not supported.

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

### Batched Questions Must Self-Identify

When a single `@Generable` type emits **multiple questions in one call** (e.g. two `Bool` fields → two batched nouls), each question's `@Guide(description:)` MUST self-identify its target entity ("Candidate A", "transaction #8491"). Observably **identical instruction text collapses the batch** and answers land near `0.5` (observed live: `0.77`/`0.79` before naming candidates → `0.94`/`0.01` after). **Applies to every backend — Jev, Laya, LayaOnDevice, Clef, OpenAI, Gemini, and `SystemOneProxyBackend`**: prefer one call with self-identifying guides, or fall back to one question per request.

---

## 5. Confidence Routing (`RoutingPolicy`) & HTTP Resilience (`RetryPolicy`)

> [!WARNING]
> **`response.content` is a hard 0.5 cutoff for `Bool` fields.** `ResponseSynthesizer` decodes a noul probability to `Bool` via `noul >= 0.5` — `p = 0.55` decodes `true` and `p = 0.45` decodes `false` regardless of decisiveness. Treat `response.content` `Bool` fields as display/fallback values only; gate automation on `response.probability(for:)` and `response.judgement(for:policy:)` through a `RoutingPolicy`.

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

### Network Retries & Cooperative Cancellation
All networked backends accept `RetryPolicy` (`RetryPolicy.defaultRetryableStatuses = [408, 429, 500, 502, 503, 504, 524, 529]`, `maxAttempts = 3`, honoring RFC 9110 `Retry-After` headers). HTTP `401`/`403` and non-cancellation `ProxyCredential` failures fail fast immediately with `SystemOneError.authenticationFailed`, while `CancellationError` and `URLError(.cancelled)` propagate directly without being wrapped in `SystemOneError`.

---

## 6. Mobile Security: Universal `ProxyCredential` & `SystemOneProxyBackend`

**Never bundle upstream API keys (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `TYPESAFE_API_KEY`) inside client-side iOS, macOS, or visionOS binaries.**

Either run offline on-device via `LayaOnDevice`, or route client requests through an authenticated reverse proxy (e.g. Firebase Cloud Functions 2nd Gen `onRequest` + Apple App Attest / Firebase App Check) using `SystemOneCore`'s zero-dependency **`ProxyCredential`** (`.appCheck`, `.header`, `.bearer`, `.custom`, or trailing-closure `authorize:`):

```swift
import Foundation
import FirebaseCore
import FirebaseAppCheck
import GeminiFoundationModels // or OpenAIFoundationModels / ClefFoundationModels / LayaFoundationModels / JevFoundationModels
import SystemOneCore

let proxyBaseURL = URL(string: "https://us-central1-your-project.cloudfunctions.net")!

// Shared zero-dependency App Check credential (re-evaluated per attempt inside the retry loop)
let appCheck = ProxyCredential.appCheck {
    guard FirebaseApp.app() != nil else {
        #if DEBUG
        return "dev-monitor-placeholder"
        #else
        throw SystemOneError.authenticationFailed("FirebaseApp is not configured.")
        #endif
    }
    return try await AppCheck.appCheck().token(forcingRefresh: false).token
}

// Pattern A: Provider Passthrough Proxy (available on Gemini, OpenAI, Clef, Laya, and Jev models)
let gemini = GeminiLanguageModel(
    proxyEndpoint: proxyBaseURL.appending(path: "geminiDecisions"),
    credential: appCheck
)

// Pattern B: Vendor-Agnostic Gateway (canonical SystemOneRequest routed server-side)
let gateway = SystemOneLanguageModel(
    proxyEndpoint: proxyBaseURL.appending(path: "systemone"),
    credential: appCheck,
    modelID: "gemini-decision-1"
)
```

### Critical Proxy & Attestation Rules
- **Guard `FirebaseApp.app() != nil`**: Calling `AppCheck.appCheck()` before `FirebaseApp.configure()` throws an uncaught Objective-C exception that Swift `try?` cannot catch. Guard initialization and run proxies in **Monitor mode** until client attestation rollout completes.
- **Replay Protection (`alreadyConsumed` + `limitedUseToken()`)**: In `firebase-admin/app-check`, `verifyToken(token, { consume: true })` **does not throw** on replayed tokens — it resolves `{ alreadyConsumed: true }`. Always check `if (verified.alreadyConsumed) return res.status(401)...` on the server, and pair `{ consume: true }` strictly with client `AppCheck.appCheck().limitedUseToken()` (never cached `token(forcingRefresh: false)`, which has a 1-hour TTL and would fail every subsequent call with `401`). Apple **App Attest** supports single-use consumption; legacy **DeviceCheck** does not.
- **Rate-Limit Identity**: Never key per-caller rate limits on App Check `verified.appId` alone — `appId` is shared by every user and device of your app. Key per-user limits on verified Firebase Auth `uid`, or pair a per-client IP limit (from trusted `X-Forwarded-For`) beneath a global `appId` ceiling.
- **Pre-Populated Body & SwiftUI Lifecycle**: Backends populate `request.httpBody` *before* invoking `.custom` / `authorize:` (enabling HMAC body signatures) and reject empty or CR/LF/NUL header tokens with `SystemOneError.authenticationFailed`. Because each `ProxyCredential` factory mints a `UUID` identity unless `id:` is supplied, hold your credential/model/session in `@State`, an `@Observable` ViewModel, or DI rather than recreating it inside `View.body`.

---

## 7. Cloudflare Edge Integration Nuances

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

## 8. Package Traits Architecture (Swift 6.1 / SE-0402)

`SystemOneFoundationModels` adopts Swift 6.1 Package Traits (SE-0402) to maintain zero runtime bloat. By default, `Package.swift` sets `.default(enabledTraits: ["All"])` for seamless out-of-the-box access, while allowing consumers to narrow along **model boundaries**:

| Trait | Category | Included Capabilities | Intended Deployment |
| :--- | :--- | :--- | :--- |
| `Jev` | Model Boundary | `JevFoundationModels`, hosted TypeSafe Jev API client | Cloud / hosted decision services |
| `Laya` | Model Boundary | `LayaOnDevice`, Core ML engine, Apple Neural Engine | Offline mobile, air-gapped apps |
| `LayaServe` | Model Boundary | `LayaFoundationModels`, local/remote HTTP client | Self-hosted daemons, private VPCs |
| `Clef` | Model Boundary | `ClefFoundationModels`, Cloudflare Workers AI, AI Gateway & local Clef runners | Multimodal vision & mobile camera inspection |
| `OpenAI` | Model Boundary | `OpenAIFoundationModels`, OpenAI Decisions API client (`gpt-6-luna`) | Enterprise & multimodal cloud decisions |
| `Gemini` | Model Boundary | `GeminiFoundationModels`, Google Gemini Decisions API client (`gemini-decision-1`) | High-context (256K) & multimodal cloud decisions |
| `OnDevice` | Persona / Shorthand | Enables `["Laya"]` | Zero-network mobile applications |
| `Remote` | Persona / Shorthand | Enables `["Jev", "LayaServe", "Clef", "OpenAI", "Gemini"]` | Client/server apps using networked models |
| `All` *(default)* | Persona / Shorthand | Enables `["Jev", "Laya", "LayaServe", "Clef", "OpenAI", "Gemini"]` | Multi-backend apps & default ergonomics |

### Consumer Configuration in `Package.swift`

```swift
// 1. Default: enables ["All"] (Core ML + Jev + LayaServe + Clef + OpenAI + Gemini)
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0")

// 2. Air-gapped on-device Core ML only (zero network client targets)
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0", traits: ["OnDevice"])

// 3. Single hosted provider (e.g. Google Gemini Decisions, OpenAI, or Cloudflare Clef)
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0", traits: ["Gemini"])

// 4. All networked backends without Core ML (`Jev`, `LayaServe`, `Clef`, `OpenAI`, `Gemini`)
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0", traits: ["Remote"])
```

---

## 9. Deterministic Offline Testing

Always test decision workflows deterministically without live network access, API credentials, or GPU model loading using `MockSystemOneBackend`, `MockOpenAIDecisionsBackend`, `MockGeminiDecisionsBackend`, or an ephemeral `URLSession` protocol stub.

### A. Testing Core & Provider Workflows (`MockSystemOneBackend` / `MockGeminiDecisionsBackend` / `MockOpenAIDecisionsBackend`)

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

        // Works identically with GeminiLanguageModel(backend: MockGeminiDecisionsBackend(...))
        // or OpenAILanguageModel(backend: MockOpenAIDecisionsBackend(...))
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

---

## 10. Reference Examples Hierarchy (`Examples/`)

When looking for runnable reference implementations in the repository, follow the 4-tier `Examples/` layout:
- **`Examples/Quickstarts/`**: 6 `< 10`-line single-file executables (`jev-quickstart`, `laya-quickstart`, `laya-ondevice-quickstart`, `clef-quickstart`, `openai-quickstart`, `gemini-quickstart`).
- **`Examples/CLI/`**: Unified `system-one-cli` (`ticket-triage`, `duplicate-article`, `file-organizer`, `vision-inspect`) across `--provider jev|laya|laya-ondevice|clef|openai|gemini|proxy`.
- **`Examples/TraitSamples/`**: `01-OfflineLayaApp` through `09-RemotePersonaRouter` verifying SE-0402 trait isolation and `ProxyCredential` (`05-SecureAppCheckApp`).
- **`Examples/Apps/`**: Production SwiftUI apps — `MailTriageApp`, `VisionScannerApp`, and `NutritionLabelScannerApp`.

