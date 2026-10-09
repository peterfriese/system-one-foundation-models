# Getting Started with System One for Apple Foundation Models

This guide walks you through integrating System One decision models—including on-device Core ML with **Laya** and cloud-hosted evaluation with **TypeSafe Jev**—into your Apple platform applications using native Swift 6 and Apple's Foundation Models framework.

---

## 🧭 Choose Your Path

System One models evaluate decisions in a single forward pass without autoregressive text generation. Depending on your privacy requirements, infrastructure, and deployment architecture, choose one of three paths:

```
                          ┌───────────────────────────────┐
                          │     Choose Your Path          │
                          └──────────────┬────────────────┘
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         ▼                               ▼                               ▼
 ┌───────────────┐               ┌───────────────┐               ┌───────────────┐
 │    Path A     │               │    Path B     │               │    Path C     │
 │  100% Offline │               │ Zero Secrets  │               │ Cloud Hosted  │
 │  LayaOnDevice │               │ LayaFoundation│               │ JevFoundation │
 └───────┬───────┘               └───────┬───────┘               └───────┬───────┘
         │                               │                               │
         ▼                               ▼                               ▼
 • Core ML on ANE/GPU            • Local `laya-serve` (8000)     • TypeSafe AI Cloud API
 • Zero outbound network         • Docker / Python local         • Managed high availability
 • 0ms external latency          • Zero API key required         • `TYPESAFE_API_KEY` required
 • Zero secrets in bundle        • Ideal for dev & staging       • Resilient retries built-in
```

### Path A: 100% Offline / Zero Secrets (`LayaOnDevice`)
- **Engine**: Apple Neural Engine (ANE) and GPU via Apple Core ML.
- **Privacy & Security**: Zero outbound network requests. No API keys or network credentials required.
- **Best For**: Native iOS/macOS apps handling sensitive data (healthcare, finance, personal communications, edge devices).
- **Target to Import**: `LayaOnDevice`

### Path B: Zero Secrets / Local Docker or Python (`LayaFoundationModels`)
- **Engine**: Self-hosted `laya-serve` instance over local HTTP (`http://127.0.0.1:8000`).
- **Privacy & Security**: All traffic remains on your local workstation or private virtual network. No cloud billing or external API keys needed.
- **Best For**: Rapid local prototyping, offline testing on developer machines, and private enterprise microservices.
- **Target to Import**: `LayaFoundationModels`

### Path C: Cloud-Hosted Managed Infrastructure (`JevFoundationModels`)
- **Engine**: TypeSafe AI cloud API (`api.typesafe.ai`).
- **Privacy & Security**: Encrypted HTTPS transport with built-in exponential backoff and jitter retries.
- **Best For**: Server-side Swift, macOS administrative tools, or mobile apps communicating via an authenticated proxy (see [Mobile Security Guide](mobile-security.md)).
- **Target to Import**: `JevFoundationModels` (requires `TYPESAFE_API_KEY`)

### Path D: Multimodal Visual Decisions (`ClefFoundationModels`)
- **Engine**: Cloudflare Workers AI edge, AI Gateway, or local runner (`Tools/ClefLocalRunner`).
- **Privacy & Security**: Evaluates images, camera frames, and text in a single forward pass.
- **Best For**: Real-time visual inspection, camera scanner apps, and document triage.
- **Target to Import**: `ClefFoundationModels` (optional `CLOUDFLARE_API_TOKEN`)

### Path E: Frontier Non-Autoregressive Decisions (`OpenAIFoundationModels`)
- **Engine**: OpenAI Decisions API (`POST https://api.openai.com/v1/decisions`) via `gpt-6-luna`.
- **Privacy & Security**: Zero output token billing ($0.10/1M input, $0.00 output), enterprise isolation (`OpenAI-Organization`, `OpenAI-Project`).
- **Best For**: High-throughput enterprise ticket routing and frontier classification.
- **Target to Import**: `OpenAIFoundationModels` (requires `OPENAI_API_KEY`)

---

## 📦 Which Target Should I Import?

The package is split into focused, modular targets so you only link the code and dependencies your project needs:

| Target / Library | Primary Capability | Network Required | API Key Required | Dependencies |
| :--- | :--- | :---: | :---: | :--- |
| `LayaOnDevice` | 100% offline inference via Core ML on Apple Neural Engine & GPU | ❌ No | ❌ No | `SystemOneCore` |
| `LayaFoundationModels` | Connect to local (`localhost:8000`) or self-hosted `laya-serve` instances | ✅ Yes (Local/LAN) | ❌ No (Optional token) | `SystemOneCore` |
| `ClefFoundationModels` | Multimodal decisions (Clef 27B & Clef-Flash 9B) via Workers AI or local runner | ✅ Yes (Workers AI or Local) | Optional (`CLOUDFLARE_API_TOKEN`) | `SystemOneCore` |
| `OpenAIFoundationModels` | Non-autoregressive decisions via OpenAI Decisions API (`gpt-6-luna`) | ✅ Yes (Cloud HTTPS) | ✅ Yes (`OPENAI_API_KEY`) | `SystemOneCore` |
| `JevFoundationModels` | Connect to TypeSafe AI cloud API with exponential retries | ✅ Yes (Cloud HTTPS) | ✅ Yes (`TYPESAFE_API_KEY`) | `SystemOneCore` |
| `SystemOneCore` | Core abstractions, `@Generable` schema translation, `RoutingPolicy`, offline mocks | ❌ No | ❌ No | None |
| `SystemOneFoundationModels` | Umbrella module bundling Core ML, Laya HTTP, Clef, OpenAI, and Jev Cloud backends | Varies by backend | Varies by backend | All above |

---

## 🛠️ Installation

### Requirements
- **Xcode**: 27.0+
- **Swift**: 6.0+ (Full Strict Concurrency supported)
- **Deployment Targets**: iOS 27.0+, macOS 27.0+, visionOS 27.0+

### In `Package.swift`
```swift
dependencies: [
    .package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0")
]
```

Add the target corresponding to your chosen path:
```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "LayaOnDevice", package: "SystemOneFoundationModels") // Path A
        // or .product(name: "LayaFoundationModels", package: "SystemOneFoundationModels") // Path B
        // or .product(name: "JevFoundationModels", package: "SystemOneFoundationModels") // Path C
        // or .product(name: "ClefFoundationModels", package: "SystemOneFoundationModels") // Path D
        // or .product(name: "OpenAIFoundationModels", package: "SystemOneFoundationModels") // Path E
        // or .product(name: "SystemOneFoundationModels", package: "SystemOneFoundationModels") // All
    ]
)
```

### In Xcode GUI
1. Open your project in Xcode.
2. Select **File > Add Package Dependencies...**
3. Enter `https://github.com/peterfriese/system-one-foundation-models.git`.
4. Choose version `0.3.0` or later and select your desired library target.

---

## 📝 Define Your Decision Schema

All backends use Apple's standard Foundation Models `@Generable` and `@Guide` macros. Define your output struct as a pure Swift type:

```swift
import FoundationModels

@Generable
struct TicketTriage: Sendable {
    @Guide(description: "Is this ticket urgent, mission-critical, or blocking?")
    var isUrgent: Bool

    @Guide(description: "Which specialized team should handle this request?")
    var department: Department

    @Guide(description: "Customer frustration level from 0 (calm) to 2 (hostile)", .range(0...2))
    var frustration: Int
}

@Generable
enum Department: String, Sendable {
    case billing
    case technical
    case sales
}
```

---

## 🚀 Running Your First Query

### Option 1: On-Device Core ML (`LayaOnDevice`)

Run inference 100% on-device on the Apple Neural Engine with zero API keys and zero network connectivity:

```swift
import FoundationModels
import LayaOnDevice

// 1. Locate compiled .mlmodelc bundle in your app bundle
guard let modelURL = Bundle.main.url(forResource: "LayaModel", withExtension: "mlmodelc") else {
    fatalError("Missing compiled Core ML bundle in application resources")
}

// 2. Initialize native tokenizer and Core ML engine
let engine = try LayaCoreMLEngine(
    modelURL: modelURL,
    tokenizer: ModernBERTTokenizer.defaultTokenizer()
)

// 3. Wrap in Apple-native LanguageModel conforming instance
let model = LayaOnDeviceLanguageModel(engine: engine)

// 4. Create standard Foundation Models session
let session = LanguageModelSession(model: model)

// 5. Evaluate the decision
let ticket = "I was charged twice for my subscription this morning and our CI/CD pipelines are blocked!"
let response = try await session.respond(to: ticket, generating: TicketTriage.self)

// 6. Inspect typed result
let triage = response.content
print("Urgent: \(triage.isUrgent)")               // true
print("Department: \(triage.department)")         // .billing
print("Frustration Score: \(triage.frustration)")   // 2
```

> **Note**: For deterministic offline unit tests without loading physical weights, `LayaCoreMLEngine` supports an offline mock initializer, or you can use `MockSystemOneBackend`.

---

### Option 2: Cloud-Hosted Jev (`JevFoundationModels`)

Connect to TypeSafe AI's hosted cloud service:

```swift
import FoundationModels
import JevFoundationModels

// 1. Read API key securely from environment or Keychain
guard let apiKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] else {
    fatalError("Missing TYPESAFE_API_KEY environment variable")
}

// 2. Initialize the Jev model with optional retry policy
let model = JevLanguageModel(apiKey: apiKey, retryPolicy: .default)

// 3. Create standard Apple FoundationModels session
let session = LanguageModelSession(model: model)

// 4. Evaluate the decision
let ticket = "I was charged twice for my subscription this morning and our CI/CD pipelines are blocked!"
let response = try await session.respond(to: ticket, generating: TicketTriage.self)

// 5. Inspect typed result
let triage = response.content
print("Urgent: \(triage.isUrgent)")               // true
print("Department: \(triage.department)")         // .billing
print("Frustration Score: \(triage.frustration)")   // 2
```

> [!WARNING]
> **Mobile Security Directive**: Never hardcode `TYPESAFE_API_KEY` into iOS, iPadOS, or visionOS client bundles. For client apps, prefer on-device Core ML (`LayaOnDevice`) or route requests through a secure server proxy using Apple App Attest or Firebase App Check (see [Mobile Security Guide](mobile-security.md)).

---

### Option 3: Local HTTP Server (`LayaFoundationModels`)

Connect to a local or internal `laya-serve` instance:

```swift
import FoundationModels
import LayaFoundationModels

// Connects to http://127.0.0.1:8000/v1/systemone by default
let model = LayaLanguageModel(endpoint: .localDefault)
let session = LanguageModelSession(model: model)

let ticket = "I was charged twice for my subscription this morning and our CI/CD pipelines are blocked!"
let response = try await session.respond(to: ticket, generating: TicketTriage.self)
let triage = response.content
```

---

## 🛡️ Configuring Resilience (`RetryPolicy`)

For network-backed transports (`JevFoundationModels` and `LayaFoundationModels`), configure exponential backoff and jitter to withstand transient gateway overload (HTTP 429 / 529):

```swift
let retryPolicy = RetryPolicy(
    maxAttempts: 3,
    initialDelay: .milliseconds(250),
    multiplier: 2.0,
    jitter: 0.15,
    retryableStatuses: [429, 529]
)

let jev = JevLanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)
let session = LanguageModelSession(model: jev)
```

If the API responds with `HTTP 429` and a `Retry-After: 5` header, the transport honors the server directive, sleeps, and retries automatically.

---

## 🎯 Routing Decisions on Calibrated Confidence

In System One models, the answer tells you *what* the model judged, but the calibrated confidence tells you **whether to act on it automatically**:

```swift
let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)

// (a) Categorical routing:
switch response.decision(for: "department", policy: policy) {
case .auto:
    routeTicketDirectly(to: response.content.department)
case .confirm:
    suggestDepartmentToAgent(response.content.department)
case .escalate:
    assignToHumanSupervisor()
}

// (b) Boolean routing with undecided band (0.35...0.65):
let judgement = response.judgement(for: "isUrgent", policy: policy)
switch judgement.decision {
case .auto:
    if judgement.answer == true { dispatchP0Alert() }
case .confirm:
    flagForReview()
case .escalate:
    // Inside 0.35...0.65: model is genuinely undecided, judgement.answer is nil
    assignToHumanSupervisor()
}

// (c) Continuous rubric score inspection:
if let score = response.scoreValue(for: "frustration") {
    print("Weighted: \(score.value) | Discrete Level: \(score.rounded) | Normalized: \(score.normalized ?? 0)")
}
```

---

## 📚 Where to Go Next

- 📱 **Flagship Reference App**: Explore [`Examples/MailTriageApp`](../Examples/MailTriageApp/README.md), a complete macOS and iOS application demonstrating 7 switchable backends and FactoryKit DI.
- 💻 **All Runnable Demos**: Check out [`Examples/README.md`](../Examples/README.md) for CLI tools and apps (`MailTriageApp`, `ClefCameraScanner`, `ClefDemo`, `OpenAIDemo`, `LayaDemo`, `TicketTriageDemo`, `FileOrganizerDemo`, `DuplicateArticleDemo`).
- 🔒 **Mobile Security & App Attest**: Read the [Mobile Security Guide](mobile-security.md) for zero-trust proxying.
- 👁️ **Cloudflare Clef & Multimodal Guide**: Read the [Cloudflare Workers AI & Clef Setup](cloudflare-workers-setup.md).
- 🧠 **On-Device Core ML Guide**: Read the [Laya Mobile & On-Device Guide](laya-mobile-guide.md).
- ⚙️ **CLI & Server Guide**: Read the [Laya CLI & Server Guide](laya-cli-guide.md).
- 📈 **Confidence & Routing**: Read the [Confidence & Noul Routing Guide](confidence-routing.md).
- 🔄 **Resilience & Retries**: Read the [HTTP Resilience & Retries Guide](resilience-and-retries.md).
- 🔍 **Audit & Hardening Report**: Review the [Repository Audit Sweep Report](plans/AUDIT-SWEEP-2026-10-09.md).
