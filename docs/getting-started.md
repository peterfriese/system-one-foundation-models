# Getting Started with System One for Apple Foundation Models 🚀

This guide walks you through integrating **all 6 System One decision model providers**—plus universal **`ProxyCredential` / `SystemOneProxyBackend`** mobile reverse proxies—into your Apple platform apps and Swift services using native Swift 6 and Apple's `FoundationModels` framework.

---

## 🧭 Choose Your Provider

System One models evaluate typed propositions in a single forward pass (`output_tokens: 0`). Pick the topology that matches your privacy, latency, and multimodal requirements:

| Provider | Target | Capabilities | Latency | Best For |
| :--- | :--- | :--- | :---: | :--- |
| **Laya On-Device** | `LayaOnDevice` | Text (`.guidedGeneration`) | **< 2ms** | 100% offline iOS/macOS/visionOS apps on Apple Neural Engine; zero secrets. |
| **Laya HTTP (`laya-serve`)** | `LayaFoundationModels` | Text (`.guidedGeneration`) | **5–30ms** | Local workstation development (`localhost:8000`) & private enterprise VPCs. |
| **TypeSafe AI Jev** | `JevFoundationModels` | Text (`.guidedGeneration`) | **30–120ms** | Managed TypeSafe AI cloud decisions (`POST /v1/systemone`). |
| **Cloudflare Clef** | `ClefFoundationModels` | **Vision + Text** | **50–250ms** | Edge camera inspection & document triage on Clef-Flash (9B) / Clef (27B). |
| **OpenAI Decisions** | `OpenAIFoundationModels` | **Vision + Text** | **35–80ms** | Enterprise multi-tenant decisions on `gpt-6-luna` ($0.10/1M input, $0 output). |
| **Google Gemini Decisions** | `GeminiFoundationModels` | **Vision + Text** | **35–90ms** | Long-context (256K) & high-batch (1,000 questions/pass) on `gemini-decision-1`. |
| **Vendor-Agnostic Gateway** | `SystemOneCore` | **Vision + Text** | **Varies** | Client apps routing canonical `SystemOneRequest` via `SystemOneProxyBackend`. |

---

## 🛠️ Installation & Package Traits

### Requirements
- **Xcode**: 27.0+ • **Swift**: 6.1+ (`-strict-concurrency=complete`)
- **Platforms**: iOS 27.0+, macOS 27.0+, visionOS 27.0+

### Swift Package Manager (`Package.swift`)

By default, `SystemOneFoundationModels` enables `traits: ["All"]`. Use Swift 6.1 Package Traits (SE-0402) to compile **only** the provider SDKs your binary needs:

```swift
dependencies: [
    // Default ("All" — links all 6 providers):
    .package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0"),

    // Or narrow by persona / model boundary:
    // .package(url: "...", from: "0.3.0", traits: ["OnDevice"]) // LayaOnDevice only (zero HTTP code)
    // .package(url: "...", from: "0.3.0", traits: ["Remote"])   // All 5 networked providers, zero Core ML
    // .package(url: "...", from: "0.3.0", traits: ["Gemini"])   // GeminiFoundationModels only
]
```

Or link an individual target product directly:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "GeminiFoundationModels", package: "SystemOneFoundationModels")
    ]
)
```

---

## 📝 Step 1: Define Your `@Generable` Decision Schema

All 6 providers evaluate the exact same Apple `@Generable` structs and enums (or zero-boilerplate [`.probability` / `.choice` / `.score` shortcuts](decision-shortcuts.md)):

```swift
import FoundationModels

@Generable
enum Department: String, Sendable {
    case billing
    case engineering
    case security
}

@Generable
struct TicketTriage: Sendable {
    @Guide(description: "Is this ticket urgent, mission-critical, or blocking production?")
    var isUrgent: Bool

    @Guide(description: "Which specialized team should own this request?")
    var department: Department

    @Guide(description: "Customer frustration level from 0 (calm) to 2 (hostile)", .range(0...2))
    var frustration: Int
}
```

---

## ⚡ Step 2: Configure Your Provider

Every provider offers **progressive disclosure**: start with zero-argument `init()` (auto-resolving standard environment variables), customize explicit endpoints/headers for enterprise deployments, or pass `ProxyCredential` for client mobile apps.

### 1. On-Device Core ML (`LayaOnDevice`)

Convert Hugging Face Laya weights (`convaiinnovations/laya` ModernBERT 421M or multilingual mmBERT 322M) once using [`Tools/CoreMLConverter/`](../Tools/CoreMLConverter/README.md) and compile to `.mlmodelc`:

```bash
python3 Tools/CoreMLConverter/convert_laya_to_coreml.py \
    --model convaiinnovations/laya \
    --output LayaDecisionModel.mlpackage \
    --quantize fp16
xcrun coremlcompiler compile LayaDecisionModel.mlpackage .
```

Initialize in Swift:

```swift
import FoundationModels
import LayaOnDevice

// 1a. Zero-arg: resolves LAYA_MODEL_PATH or bundled LayaDecisionModel.mlmodelc + adjacent tokenizer.json
let session = LanguageModelSession(model: try LayaOnDeviceLanguageModel())

// 1b. Explicit Core ML bundle & tokenizer
let modelURL = Bundle.main.url(forResource: "LayaDecisionModel", withExtension: "mlmodelc")!
let engine = try LayaCoreMLEngine(
    modelURL: modelURL,
    tokenizer: ModernBERTTokenizer.defaultTokenizer() // or try MMBERTTokenizer(jsonURL: ...)
)
let customSession = LanguageModelSession(model: LayaOnDeviceLanguageModel(engine: engine))
```

### 2. Self-Hosted Laya HTTP / Private VPC (`LayaFoundationModels`)

Connects to `laya-serve` over `POST /v1/systemone`:

```swift
import FoundationModels
import LayaFoundationModels

// 2a. Zero-arg: reads LAYA_SERVE_URL / LAYA_ENDPOINT (defaults to http://127.0.0.1:8000/v1/systemone) + LAYA_API_KEY
let session = LanguageModelSession(model: LayaLanguageModel())

// 2b. Explicit custom port or internal VPC endpoint
let vpcModel = LayaLanguageModel(
    endpoint: .custom(URL(string: "https://laya.internal.mycompany.com/v1/systemone")!),
    apiKey: ProcessInfo.processInfo.environment["LAYA_API_KEY"],
    retryPolicy: .default
)
```

### 3. TypeSafe AI Jev Cloud (`JevFoundationModels`)

Connects to `https://api.typesafe.ai/v1/systemone`:

```swift
import FoundationModels
import JevFoundationModels

// 3a. Zero-arg: reads TYPESAFE_API_KEY
let session = LanguageModelSession(model: JevLanguageModel())

// 3b. Explicit endpoint & custom RetryPolicy
let explicitModel = JevLanguageModel(
    endpoint: .hosted, // or .custom(enterpriseURL)
    apiKey: apiKey,
    retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(250), jitter: 0.15)
)
```

### 4. Cloudflare Clef & Clef-Flash Multimodal (`ClefFoundationModels`)

Supports Workers AI Direct Edge, **Cloudflare AI Gateway** (caching, analytics, rate limiting), and zero-egress local Apple Silicon MPS runners ([`Tools/ClefLocalRunner/`](../Tools/ClefLocalRunner/README.md)):

```swift
import FoundationModels
import ClefFoundationModels

// 4a. Zero-arg: resolves CLEF_ENDPOINT, CLOUDFLARE_ACCOUNT_ID (+ CLOUDFLARE_GATEWAY_ID) + CLOUDFLARE_API_TOKEN, or CLEF_LOCAL_PORT
let autoSession = LanguageModelSession(model: ClefLanguageModel())

// 4b. Direct Cloudflare Workers AI Edge (.clefFlash 9B or .clef 27B)
let edgeModel = ClefLanguageModel(
    endpoint: .workersAI(accountID: accountID, model: .clefFlash),
    apiToken: apiToken
)

// 4c. Cloudflare AI Gateway
let gatewayModel = ClefLanguageModel(
    endpoint: .gateway(accountID: accountID, gatewayID: "prod-mobile-gw", model: .clef),
    apiToken: apiToken
)

// 4d. Local Runner on localhost:8000 (zero network egress)
let localModel = ClefLanguageModel(endpoint: .local(port: 8000, model: .clefFlash))
```

### 5. OpenAI Decisions API — `gpt-6-luna` (`OpenAIFoundationModels`)

Targets `POST https://api.openai.com/v1/decisions` (`OpenAILanguageModel` is a convenience `typealias` for `OpenAIDecisionsLanguageModel`):

```swift
import FoundationModels
import OpenAIFoundationModels

// 5a. Zero-arg: resolves OPENAI_API_KEY on gpt-6-luna
let session = LanguageModelSession(model: OpenAILanguageModel())

// 5b. Enterprise multi-tenant headers (OpenAI-Organization, OpenAI-Project, X-Client-Request-Id)
let enterpriseModel = OpenAILanguageModel(
    apiKey: apiKey,
    organization: "org-acme-prod",
    project: "proj-support-triage",
    clientRequestID: UUID().uuidString,
    retryPolicy: .default
)
```

### 6. Google Gemini Decisions API — `gemini-decision-1` (`GeminiFoundationModels`)

Targets `POST https://generativelanguage.googleapis.com/v1beta/decisions` using `x-goog-api-key` authentication (`GeminiLanguageModel` is a convenience `typealias` for `GeminiDecisionsLanguageModel`):

```swift
import FoundationModels
import GeminiFoundationModels

// 6a. Zero-arg: resolves GEMINI_API_KEY (or fallback GOOGLE_API_KEY)
let session = LanguageModelSession(model: GeminiLanguageModel())

// 6b. Explicit API key, custom gateway URL, or X-Client-Request-Id tracing
let customGemini = GeminiLanguageModel(
    endpoint: GeminiDecisionsEndpoint(model: "gemini-decision-1"),
    apiKey: apiKey,
    clientRequestID: UUID().uuidString
)
```

### 7. Zero-Secret Mobile Reverse Proxy (`ProxyCredential` & `SystemOneProxyBackend`)

> [!WARNING]
> Never embed upstream cloud keys inside iOS, macOS, or visionOS client binaries. Use `ProxyCredential` on any networked provider (or `SystemOneLanguageModel` for vendor-agnostic gateways) — see the [**Mobile Security Guide**](mobile-security.md).

```swift
import FirebaseAppCheck
import FoundationModels
import GeminiFoundationModels

let model = GeminiLanguageModel(
    proxyEndpoint: URL(string: "https://us-central1-my-app.cloudfunctions.net/geminiDecisions")!,
    credential: .appCheck {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
let session = LanguageModelSession(model: model)
```

---

## 🎯 Step 3: Evaluate & Route on Calibrated Confidence

In System One models, `response.content` gives *what* the model judged, while `RoutingPolicy` determines **whether to automate**:

```swift
let response = try await session.respond(to: ticketText, generating: TicketTriage.self)
let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85, undecidedBand: 0.35...0.65)

// 1. Categorical choice routing (.auto, .confirm, .escalate)
switch response.decision(for: "department", policy: policy) {
case .auto:     routeDirectly(to: response.content.department)
case .confirm:  suggestInUI(response.content.department)
case .escalate: assignToSupervisor()
}

// 2. Epistemic boolean (noul) routing
let urgent = response.judgement(for: "isUrgent", policy: policy)
switch urgent.decision {
case .auto:     urgent.answer == true ? pageOnCall() : enqueueRoutine()
case .confirm:  promptAgentConfirmation()
case .escalate: assignToSupervisor() // Inside 0.35...0.65 undecided band
}

// 3. Continuous rubric score inspection
if let score = response.scoreValue(for: "frustration") {
    print("Weighted: \(score.value) | Level: \(score.rounded) | Confidence: \(score.confidence)")
}
```

---

## 📚 Next Steps

- ⚡ [**`< 10`-Line Provider Quickstarts (`Examples/Quickstarts/`)**](../Examples/Quickstarts/README.md) — Run any provider from your terminal in 10 seconds.
- 💻 [**Unified Multi-Provider CLI (`Examples/CLI/`)**](../Examples/CLI/README.md) — Try `ticket-triage`, `duplicate-article`, `file-organizer`, and `vision-inspect` across all 7 modes.
- 🧩 [**Swift 6.1 Trait Samples (`Examples/TraitSamples/`)**](../Examples/TraitSamples/README.md) — Explore `01-OfflineLayaApp` through `09-RemotePersonaRouter`.
- 📱 [**SwiftUI Reference Apps (`Examples/Apps/`)**](../Examples/Apps/README.md) — Inspect `MailTriageApp`, `VisionScannerApp`, and `NutritionLabelScannerApp`.
- 🎛️ [**Decision Shortcuts Reference**](decision-shortcuts.md) — Deep dive into `.probability`, `.choice`, `.score`, and multimodal `@PromptBuilder` attachments.
- 🔒 [**Mobile Security Guide**](mobile-security.md) — Production Firebase App Check + Apple App Attest deployment recipes.
