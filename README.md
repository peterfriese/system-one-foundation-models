# System One for Apple Foundation Models 🧠⚡️

[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat&logo=swift)](https://developer.apple.com/swift/)
[![Xcode 27](https://img.shields.io/badge/Xcode-27.0+-blue.svg?style=flat&logo=xcode)](https://developer.apple.com/xcode/)
[![iOS 27.0+](https://img.shields.io/badge/iOS-27.0+-black.svg?style=flat&logo=apple)](https://developer.apple.com/ios/)
[![macOS 27.0+](https://img.shields.io/badge/macOS-27.0+-black.svg?style=flat&logo=apple)](https://developer.apple.com/macos/)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fpeterfriese%2Fsystem-one-foundation-models%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/peterfriese/system-one-foundation-models)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fpeterfriese%2Fsystem-one-foundation-models%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/peterfriese/system-one-foundation-models)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A lightweight, native Swift 6 bridge integrating **System One decision models** into Apple's **Foundation Models** framework (`LanguageModel`, `LanguageModelExecutor`, `@Generable`).

Evaluate strongly typed `@Generable` structs and enums against application state in **15–150ms** with zero hallucinations, calibrated probabilities, and full Apple Intelligence API compatibility across:
- **On-Device Core ML (`LayaOnDevice`)**: Run Laya's 322M (multilingual mmBERT) and 421M (English/typed-decisions ModernBERT) parameter models locally on the Apple Neural Engine and GPU with zero network calls.
- **Self-Hosted HTTP (`LayaFoundationModels`)**: Connect to `laya-serve` (PR #31 merged into `NandhaKishorM/laya`) speaking the Jev-compatible `POST /v1/systemone` protocol with presets for `localhost:8000`, `localhost:8770`, and hosted `api.impossibl.com`.
- **Cloudflare Clef (`ClefFoundationModels`)**: Run open-weight multimodal decision models—**Clef (27B)** and **Clef-Flash (9B)**—running via Cloudflare Workers AI edge, Cloudflare AI Gateway, or local runner (`Tools/ClefLocalRunner`), judging camera frames and image attachments alongside text in a single feed-forward pass.
- **TypeSafe AI Cloud (`JevFoundationModels`)**: Full backwards-compatible support for hosted TypeSafe Jev endpoints with automated HTTP retries (`RetryPolicy`), cooperative cancellation, and confidence routing (`RoutingPolicy`).

> [!WARNING]
> **Security Advisory: Never Embed API Keys in Mobile Apps**
> Cloud API keys (`TYPESAFE_API_KEY`) must **never** be hardcoded or bundled inside client-side iOS, iPadOS, watchOS, or visionOS application binaries. Anyone can inspect or decompile mobile apps to extract embedded secrets.
>
> **Safe Deployment Patterns:**
> - **On-Device Core ML (`LayaOnDevice`)**: Run models locally on hardware with 100% offline privacy and zero secrets required.
> - **Backend / Server / CLI**: Use `LayaLanguageModel` or `JevLanguageModel` directly in server-side Swift services or CLI tools where environment variables remain server-side.
> - **Mobile Applications with Cloud APIs**: Route mobile requests through your own authenticated reverse proxy protected by Apple App Attest and Firebase App Check using the built-in `ProxyTransport` (see [Mobile Security Guide](docs/mobile-security.md) and [Tech Note 0010](tech-notes/0010-proxy-transport-and-dynamic-attestation.md)).

---

## 💡 Why Decision Models in Apple Foundation Models?

Traditional Large Language Models (LLMs) are generative text engines: coercing them into producing deterministic structured decisions requires constrained token sampling or prompt-and-parse pipelines.

**System One decision models** evaluate typed questions directly against state in a single feed-forward pass:

| Apple Foundation Models (`@Generable`) | System One Decision Primitive | Behavior |
| :--- | :--- | :--- |
| `Bool` | **`noul`** | Binary judgment with calibrated probability of truth |
| `enum` / String | **`choice`** | Categorical selection across discrete options |
| `@Guide(description: "...")` | **`instructions`** | Semantic criteria evaluated against state |
| `@Guide(.range(...))` | **`score`** | Bounded ordinal rubric scoring |
| `Response.metadata` | **`confidence` & `probabilities`** | Direct access to model uncertainty |

### Multimodal Visual Decisions

With **Cloudflare Clef (`ClefFoundationModels`)**, System One decision modeling extends natively into visual workflows:
- **Single-Pass Evaluation**: Evaluates camera frames or image attachments (`Attachment(cgImage)`) alongside textual state in a single feed-forward pass—without generative captioning bottlenecks, hallucinations, or multi-stage prompt engineering.
- **Native Apple Foundation Models Vision**: Fully complies with `LanguageModelCapabilities([.guidedGeneration, .vision])`, accepting standard `Prompt` attachments and returning strongly typed `@Generable` outcomes.
- **Calibrated Visual Uncertainty**: Obtains discrete decision outputs (pass/fail, defect categories, priority tiers) alongside continuous probability distributions and confidence scores directly from visual features.

---

## 🚀 Quick Start

### 1. Add Package Dependency & Configure Traits

Add `SystemOneFoundationModels` to your `Package.swift` or via Xcode (**File > Add Package Dependencies...**):

```swift
dependencies: [
    .package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0")
]
```

#### Swift 6.1 Package Traits

Using Swift 6.1 Package Traits ([SE-0402](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0402-package-traits.md)), you can enable precisely the backend capabilities you need, eliminating unnecessary dependencies, cloud secrets, or neural model binaries:

```swift
// Default (TypeSafe Jev hosted cloud API):
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0")

// On-Device only (Core ML + Apple Neural Engine, zero network/cloud code):
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0", traits: ["OnDevice"])

// Remote only (Jev cloud, self-hosted laya-serve HTTP, and Clef; no Core ML binaries):
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0", traits: ["Remote"])

// All backends (Core ML, Laya HTTP, Jev cloud, and Cloudflare Clef):
.package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0", traits: ["All"])
```

| Trait | Type | Description |
| :--- | :--- | :--- |
| `Jev` *(default)* | Model Boundary | Enables TypeSafe Jev hosted cloud API client (`JevFoundationModels`) |
| `Laya` | Model Boundary | Enables on-device Laya decision models via Core ML and Apple Neural Engine (`LayaOnDevice`) |
| `LayaServe` | Model Boundary | Enables HTTP transport for self-hosted `laya-serve` instances (`LayaFoundationModels`) |
| `Clef` | Model Boundary | Enables Cloudflare Clef and Clef-Flash hosted and local multimodal decision models (`ClefFoundationModels`) |
| `OnDevice` | Persona Shorthand | Enables on-device capabilities (activates `["Laya"]`) |
| `Remote` | Persona Shorthand | Enables remote hosted and self-hosted decision model clients (activates `["Jev", "LayaServe", "Clef"]`) |
| `All` | Persona Shorthand | Enables all System One model backends and transports (activates `["Jev", "Laya", "LayaServe", "Clef"]`) |

### Which Target Should I Import?

The package is split into focused, modular targets so you only link the code and dependencies your project needs:

| Target / Library | Primary Capability | Network Required | API Key Required | Dependencies |
| :--- | :--- | :---: | :---: | :--- |
| `LayaOnDevice` | 100% offline inference via Core ML on Apple Neural Engine & GPU | ❌ No | ❌ No | `SystemOneCore` |
| `LayaFoundationModels` | Connect to local (`localhost:8000`) or self-hosted `laya-serve` instances | ✅ Yes (Local/LAN) | ❌ No (Optional token) | `SystemOneCore` |
| `ClefFoundationModels` | Multimodal decisions (Clef 27B & Clef-Flash 9B) via Cloudflare Workers AI or local runner | ✅ Yes (Workers AI or Local) | Optional (`CLOUDFLARE_API_TOKEN` for cloud) | `SystemOneCore` |
| `JevFoundationModels` | Connect to TypeSafe AI cloud API with exponential retries | ✅ Yes (Cloud HTTPS) | ✅ Yes (`TYPESAFE_API_KEY`) | `SystemOneCore` |
| `SystemOneCore` | Core abstractions, `@Generable` schema translation, `RoutingPolicy`, offline mocks | ❌ No | ❌ No | None |
| `SystemOneFoundationModels` | Umbrella module bundling Core ML, Laya HTTP, Clef, and Jev Cloud backends | Varies by backend | Varies by backend | All above |

### 2. Choose Your Execution Backend

#### Option A: On-Device Core ML (Zero Network, Air-Gapped Privacy)
```swift
import FoundationModels
import LayaOnDevice

// 1. Initialize on-device engine with compiled Core ML model
let engine = try LayaCoreMLEngine(
    modelURL: Bundle.main.url(forResource: "LayaModernBERT", withExtension: "mlmodelc")!,
    tokenizer: ModernBERTTokenizer.defaultTokenizer()
)

// 2. Initialize native Apple Foundation Models session
let session = LanguageModelSession(model: LayaOnDeviceLanguageModel(engine: engine))
```

#### Option B: Self-Hosted or Remote Laya HTTP (`laya-serve`)
```swift
import FoundationModels
import LayaFoundationModels

// 1. Connect to local laya-serve (localhost:8000 or localhost:8770) or hosted endpoint
let model = LayaLanguageModel(endpoint: .localDefault) // or .local(port: 8770) or .hosted

// 2. Initialize native Apple Foundation Models session
let session = LanguageModelSession(model: model)
```

#### Option C: TypeSafe AI Jev Cloud with Resilience (Server / CLI)
```swift
import FoundationModels
import JevFoundationModels

// 1. Connect to TypeSafe AI API with automated retry resilience
let retryPolicy = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(250), jitter: 0.15)
let jev = JevLanguageModel(apiKey: ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]!, retryPolicy: retryPolicy)

// 2. Initialize native Apple Foundation Models session
let session = LanguageModelSession(model: jev)
```

#### Option D: Cloudflare Clef & Clef-Flash Multimodal (`ClefFoundationModels`)
```swift
import FoundationModels
import ClefFoundationModels

// 1. Connect to Cloudflare Workers AI edge (or .gateway / .local)
let clef = ClefLanguageModel(
    endpoint: .workersAI(
        accountID: ProcessInfo.processInfo.environment["CLOUDFLARE_ACCOUNT_ID"]!,
        model: .clefFlash // or .clef (27B)
    ),
    apiToken: ProcessInfo.processInfo.environment["CLOUDFLARE_API_TOKEN"]
)

// 2. Initialize native Apple Foundation Models session
let session = LanguageModelSession(model: clef)

// 3. Evaluate multimodal decision with visual Attachment
let prompt = Prompt {
    "Inspect the item presented in this camera frame for physical condition, category, and safety compliance."
    Attachment(cgImage)
}
let response = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)
```

#### Option E: Mobile Reverse Proxy with `ProxyTransport` (Zero Bundled Secrets)
```swift
import FoundationModels
import JevFoundationModels
import FirebaseAppCheck // or Apple App Attest / OAuth 2.0

// 1. Route mobile requests through your reverse proxy with dynamic device attestation
let proxyURL = URL(string: "https://us-central1-myproject.cloudfunctions.net/systemone")!
let transport = ProxyTransport(
    proxyEndpoint: proxyURL,
    credential: .header(name: "X-Firebase-AppCheck") {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
let jev = JevLanguageModel(transport: transport)

// 2. Initialize native Apple Foundation Models session
let session = LanguageModelSession(model: jev)
```

### 3. Define Your Decision Type & Evaluate

```swift
import FoundationModels

@Generable
struct CustomerTriage: Sendable {
    @Guide(description: "Is this inquiry urgent or time-sensitive?")
    var isUrgent: Bool

    @Guide(description: "Which team should handle this request?")
    var department: Department

    @Guide(description: "Customer frustration score", .range(0...2))
    var frustration: Int
}

@Generable
enum Department: String, Sendable {
    case billing
    case technical
    case account
}

// Evaluate state
let ticket = "My account was double charged this morning! Please fix this ASAP."
let response = try await session.respond(to: ticket, generating: CustomerTriage.self)

// Access typed results
let triage = response.content
print("Urgent: \(triage.isUrgent)")             // true
print("Route: \(triage.department)")           // .billing
print("Frustration: \(triage.frustration)")    // 2

// Confidence routing with RoutingPolicy
let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
switch response.decision(for: "department", policy: policy) {
case .auto:     print("Auto-routed to \(triage.department)")
case .confirm:  print("Suggesting \(triage.department) for confirmation")
case .escalate: print("Escalated to human supervisor")
}

let judgement = response.judgement(for: "isUrgent", policy: policy)
if judgement.decision == .auto && judgement.answer == true {
    print("Urgency: Decisive True -> Page on-call engineering P0")
}
```

### 4. Direct Ergonomic Decision Shortcuts (No `@Generable` Boilerplate)

For ad-hoc questions where declaring a composite `@Generable` struct is unnecessary ceremony, `LanguageModelSession` provides direct, calibrated evaluation shortcuts:

#### Binary Probability (`session.probability`)
Evaluate the calibrated truth probability (0.0 to 1.0) of any statement against state:
```swift
// Direct statement evaluation
let isUrgent = try await session.probability(
    of: "Is this inquiry urgent or time-sensitive?",
    state: ticket
)
print("Urgency probability: \(isUrgent)") // e.g. 0.94

// Optional criteria steering
let isSpam = try await session.probability(
    of: "Is this message phishing or malicious?",
    state: emailBody,
    criteria: (
        whenTrue: "requests wire transfers, credentials, or urgent gift cards",
        whenFalse: "routine correspondence from an existing vendor"
    )
)
```

#### Strongly-Typed Categorical Choice (`session.choice` with `Choosable`)
Evaluate discrete categorization across cases of any Swift enum conforming to `Choosable`:
```swift
enum TicketPriority: String, Choosable {
    case critical = "CRITICAL"
    case high = "HIGH"
    case normal = "NORMAL"
    case low = "LOW"

    var optionDescription: String? {
        switch self {
        case .critical: "Complete service outage affecting all users"
        case .high: "Core workflow degraded"
        case .normal: "Standard request or minor bug"
        case .low: "Cosmetic issue or feature request"
        }
    }
}

let choice = try await session.choice(
    "Select the triage priority",
    from: TicketPriority.self,
    state: ticket
)

print("Winning case: \(choice.value)")             // .critical
print("Model confidence: \(choice.confidence)")     // 0.92
print("Distribution: \(choice.distribution)")       // [.critical: 0.92, .high: 0.07, ...]
print("P(critical): \(choice.probability(of: .critical))")
```

#### Dynamic String Options (`session.choice`)
Categorize state among dynamic runtime string options:
```swift
let routing = try await session.choice(
    "Which team should handle this request?",
    options: ["billing", "technical", "account"],
    state: ticket
)
print("Chosen route: \(routing.value)")        // "billing"
print("Confidence: \(routing.confidence)")     // 0.95
```

#### Ordinal Rubric Scoring (`session.score`)
Rate state across ordered rubric levels to obtain both the discrete winner and the probability-weighted continuous mean score:
```swift
let frustration = try await session.score(
    "Rate customer frustration level based on sentiment and phrasing",
    levels: ["Calm", "Mildly Annoyed", "Frustrated", "Extremely Irate"],
    state: ticket
)

print("Continuous mean: \(frustration.value)")              // 2.75 (0...3 scale)
print("Most likely level: \(frustration.mostLikelyLevel)")   // "Extremely Irate"
print("Level index: \(frustration.mostLikelyIndex)")        // 3
print("Probabilities: \(frustration.probabilities)")         // [0.01, 0.04, 0.15, 0.80]
```

---

## 📱 Flagship Reference App: MailTriageApp

Explore [`Examples/MailTriageApp`](Examples/MailTriageApp/README.md), a complete native macOS and iOS reference application showcasing production-grade System One decision models in a modern Apple Mail interface:

- **Intelligent Email Triage**: Automatically categorizes incoming messages, assigns color-coded urgency priority tokens (`P0 Critical`, `P1 High`, `P2 Normal`, `P3 Low`), extracts suggested follow-up actions (Reply, Forward, Compose), and drives batch triage flows.
- **6 Selectable Backends**: Hot-swap backends on the fly in Settings:
  1. **Laya Core ML**: 100% offline inference on the Apple Neural Engine and GPU.
  2. **Laya Local**: Local `laya-serve` instance running on `http://127.0.0.1:8000`.
  3. **Laya Remote**: Hosted Laya instance on `https://api.impossibl.com`.
  4. **Cloudflare Clef**: Serverless Workers AI edge or local runner with multimodal email attachment triage.
  5. **Jev Cloud**: TypeSafe AI hosted service on `https://api.typesafe.ai`.
  6. **Generative Baseline / Offline Mock**: On-device generative baseline or instant deterministic mock evaluation.
- **Pure Native Architecture**: Built with Swift 6 Complete Strict Concurrency, SwiftUI `@Observable`, FactoryKit dependency injection, Liquid Glass design, and multi-window split views.
- **Catalog of Demos**: Browse [`Examples/README.md`](Examples/README.md) for the full list of runnable CLI tools and sample projects.

---

## 🏗️ Architecture

`SystemOneFoundationModels` conforms directly to Apple's public provider protocols (`LanguageModel`, `LanguageModelExecutor`):

```
┌────────────────────────────────────────────────────────────────────────┐
│                        LanguageModelSession                            │
│  session.respond(to: "...", generating: CustomerTriage.self)           │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ passes Request (Transcript + Schema)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        SystemOneExecutor                               │
│  • SchemaTranslator: maps @Generable schema to System One questions    │
│  • SystemOneBackend (Pluggable Execution Engine):                      │
│     ├── LayaOnDeviceBackend: Core ML on Apple Neural Engine / GPU      │
│     ├── LayaHTTPBackend: POST http://localhost:8000/v1/systemone       │
│     ├── ClefHTTPBackend: Cloudflare Workers AI / Gateway / Local       │
│     └── JevBackend: POST https://api.typesafe.ai/v1/systemone          │
│  • ResponseSynthesizer: converts answers into canonical JSON / enums   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ yields via Channel
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│              LanguageModelExecutorGenerationChannel                    │
│  • .appendText(synthesizedJSON) -> decoded into CustomerTriage         │
│  • .updateMetadata(probabilities, confidence, scores, duration)        │
│  • .updateUsage(inputTokens, outputTokens)                             │
└────────────────────────────────────────────────────────────────────────┘
```

For more in-depth documentation, see:
* [Getting Started Guide](docs/getting-started.md)
* [Reference Demos & Examples Directory](Examples/README.md)
* [Flagship Reference App (MailTriageApp)](Examples/MailTriageApp/README.md)
* [Architecture Decision Record (ADR)](docs/architecture/ADR-2026-09-25-mail-triage-system-one-engine.md)
* [Product Requirements Document (PRD)](docs/prd/PRD-2026-09-25-mail-triage-system-one-engine.md)
* [CLI & Server Deployment Guide](docs/laya-cli-guide.md)
* [Mobile Deployment & Core ML Guide](docs/laya-mobile-guide.md)
* [Confidence Routing Guide](docs/confidence-routing.md)
* [Resilience & Retries Guide](docs/resilience-and-retries.md)
* [Mobile Security Guide (ProxyTransport & App Check)](docs/mobile-security.md)
* [Type Mapping Guide](docs/mapping-guide.md)
* [Tech Notes Index](tech-notes/README.md)
* [Contributing Guide](CONTRIBUTING.md)

---

## 📄 License

This project is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
