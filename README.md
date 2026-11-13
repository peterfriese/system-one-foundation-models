# System One for Apple Foundation Models 🧠⚡️

[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-F05138.svg?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2027%2B%20%7C%20macOS%2027%2B%20%7C%20visionOS%2027%2B-007AFF.svg)](https://developer.apple.com)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero-34C759.svg)](Package.swift)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**System One for Apple Foundation Models** bridges Apple's native [`FoundationModels`](https://developer.apple.com/documentation/foundationmodels) framework (`LanguageModelSession`, `@Generable`, `@Guide`, `Attachment`) to **non-autoregressive System One decision models**. Instead of sampling chat tokens one by one, System One models evaluate application state and camera frames in a single forward pass—returning strongly-typed Swift values alongside calibrated probabilities (`0.0...1.0`) in **2–150ms** with **zero output tokens** (`$0.00` output billing).

- **Laya On-Device (`LayaOnDevice`)** — 100% offline Core ML inference on the Apple Neural Engine (< 2ms, zero network egress).
- **Laya HTTP Server (`LayaFoundationModels`)** — Self-hosted `laya-serve` on `localhost` or private enterprise VPCs.
- **TypeSafe AI Jev (`JevFoundationModels`)** — Hosted cloud System One API (`POST /v1/systemone`).
- **Cloudflare Clef (`ClefFoundationModels`)** — Open-weight **Clef 27B** & **Clef-Flash 9B** multimodal models on Workers AI, AI Gateway, or local MPS.
- **OpenAI Decisions (`OpenAIFoundationModels`)** — Frontier **`gpt-6-luna`** multimodal decision API (`POST /v1/decisions`).
- **Google Gemini Decisions (`GeminiFoundationModels`)** — High-density **`gemini-decision-1`** multimodal decision API (256K context, up to 1,000 questions/pass).

> [!WARNING]
> **Mobile Security — Never Ship API Keys in Client Apps**: Upstream keys (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `TYPESAFE_API_KEY`) can be extracted from app binaries. For iOS, macOS, and visionOS client apps, run offline with `LayaOnDevice` or route through an attested proxy via `ProxyCredential` — see the [**Mobile Security Guide**](docs/mobile-security.md).

---

## 🎯 Why Decision Models?

`SchemaTranslator` compiles your Swift `@Generable` types directly into calibrated System One decision primitives, eliminating JSON prompt engineering and hallucinated enum values:

| Apple `FoundationModels` Type | System One Primitive | Returned Signal |
| :--- | :--- | :--- |
| `Bool` | **`noul`** | Calibrated probability of truth ($0.0 \dots 1.0$) + epistemic `NoulJudgement` |
| `enum: String` / `Choosable` | **`choice`** | Categorical distribution across cases + winning `confidence` |
| `Int` / `Double` + `@Guide(.range(min...max))` | **`score`** | Ordinal rubric distribution + probability-weighted mean (`ScoreValue`) |
| `@Guide(description: "...")` | **`instructions`** | Per-question semantic rubric steering model judgment |

For visual workflows, pass native Apple `Attachment(cgImage)` or `Attachment(imageURL:)` values directly inside `Prompt { ... }`. Vision-capable providers (`Clef`, `OpenAI`, `Gemini`, and `SystemOneLanguageModel`) automatically downscale frames to 1024px and evaluate up to 4 images in a single feed-forward pass (`output_tokens: 0`).

---

## ⚡ Quick Start in 6 Lines

Every provider conforms to Apple's `LanguageModel` protocol and supports zero-argument initialization (`init()`):

```swift
import FoundationModels
import GeminiFoundationModels // swap any provider module below

let session = LanguageModelSession(model: GeminiLanguageModel())
let fraudProb = try await session.probability(of: "Transaction requires manual fraud review", state: txLog)
print("Fraud probability: \(fraudProb)")
```

| Provider | 1-Line Initializer | Auto-Resolved Environment / Resource | Vision | `< 10`-Line Quickstart |
| :--- | :--- | :--- | :---: | :--- |
| **TypeSafe Jev** | `JevLanguageModel()` | `TYPESAFE_API_KEY` | Text | `swift run jev-quickstart` |
| **Laya HTTP** | `LayaLanguageModel()` | `LAYA_SERVE_URL` (default `localhost:8000`) + `LAYA_API_KEY` | Text | `swift run laya-quickstart` |
| **Laya On-Device** | `try LayaOnDeviceLanguageModel()` | `LAYA_MODEL_PATH` or bundled `LayaDecisionModel.mlmodelc` | Text | `swift run laya-ondevice-quickstart` |
| **Cloudflare Clef** | `ClefLanguageModel()` | `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN` or `CLEF_LOCAL_PORT` | **Vision** | `swift run clef-quickstart` |
| **OpenAI (`gpt-6-luna`)** | `OpenAILanguageModel()` | `OPENAI_API_KEY` | **Vision** | `swift run openai-quickstart` |
| **Gemini (`gemini-decision-1`)** | `GeminiLanguageModel()` | `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) | **Vision** | `swift run gemini-quickstart` |

---

## 📦 Installation, Targets & Package Traits

Add the package in `Package.swift` (defaults to `traits: ["All"]`; narrow with Swift 6.1 SE-0402 traits to exclude unused SDKs at compile time):

```swift
dependencies: [
    .package(url: "https://github.com/peterfriese/system-one-foundation-models.git", from: "0.3.0")
    // Or isolate specific providers: traits: ["OnDevice"], ["Remote"], ["Gemini"], ["OpenAI"], ["Clef"], ["Jev"]
]
```

| Library Product / Target | Package Trait | Primary Use Case | Network / Key Requirement |
| :--- | :--- | :--- | :--- |
| [`SystemOneFoundationModels`](Sources/SystemOneFoundationModels/README.md) | `All` *(default)*, `OnDevice`, `Remote` | Umbrella module exporting enabled provider traits | Depends on active trait(s) |
| [`LayaOnDevice`](Sources/LayaOnDevice/README.md) | `Laya` / `OnDevice` | Offline Core ML on Apple Neural Engine (ModernBERT / mmBERT) | **None** (100% offline `.mlmodelc`) |
| [`LayaFoundationModels`](Sources/LayaFoundationModels/README.md) | `LayaServe` | Self-hosted `laya-serve` HTTP daemon or private VPC | Localhost or `LAYA_API_KEY` |
| [`JevFoundationModels`](Sources/JevFoundationModels/README.md) | `Jev` | Hosted TypeSafe AI Jev cloud decisions | `TYPESAFE_API_KEY` or Proxy |
| [`ClefFoundationModels`](Sources/ClefFoundationModels/README.md) | `Clef` | Multimodal edge vision on Workers AI, AI Gateway, or local MPS | Cloudflare token, local port, or Proxy |
| [`OpenAIFoundationModels`](Sources/OpenAIFoundationModels/README.md) | `OpenAI` | Multimodal enterprise decisions on OpenAI `gpt-6-luna` | `OPENAI_API_KEY` or Proxy |
| [`GeminiFoundationModels`](Sources/GeminiFoundationModels/README.md) | `Gemini` | High-context (256K) multimodal decisions on `gemini-decision-1` | `GEMINI_API_KEY` or Proxy |
| [`SystemOneCore`](Sources/SystemOneCore/README.md) | *(always linked)* | Shared schemas, `RoutingPolicy`, `RetryPolicy`, `ProxyCredential`, shortcuts | Vendor-agnostic (`SystemOneProxyBackend`) |

---

## 🧩 Core API Highlights

### 1. `@Generable` Schemas & Calibrated `RoutingPolicy`

```swift
@Generable enum Department: String, Sendable { case billing, engineering, security }

@Generable struct TicketTriage: Sendable {
    @Guide(description: "Is this ticket blocking production?") var isUrgent: Bool
    @Guide(description: "Owning support department") var department: Department
    @Guide(description: "Customer frustration from 0 to 3", .range(0...3)) var frustration: Int
}

let response = try await session.respond(to: ticketText, generating: TicketTriage.self)
let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85) // 0.35...0.65 undecided band

switch response.judgement(for: "isUrgent", policy: policy).decision {
case .auto:     response.content.isUrgent ? pageOnCall() : enqueueStandard()
case .confirm:  suggestPriorityInUI(response.content.department)
case .escalate: routeToHumanSupervisor()
}
```

### 2. Zero-Boilerplate Shortcuts & Multimodal Vision (`Attachment`)

Skip `@Generable` boilerplate for single questions—including live `CGImage` or file `Attachment`s via `@PromptBuilder` (see [**Decision Shortcuts**](docs/decision-shortcuts.md)):

```swift
let damaged = try await session.probability(of: "The parcel has visible exterior damage") {
    "Inspect delivery photo for crushed corners or water damage."
    Attachment(parcelCGImage)
}
let route = try await session.choice("Assign team", options: ["claims", "warehouse", "fraud"], state: note)
let condition = try await session.score("Rate packaging", levels: ["Damaged", "Worn", "Pristine"]) {
    Attachment(parcelCGImage)
}
```

### 3. Zero-Secret Mobile Attestation (`ProxyCredential`)

Authenticate client apps through Firebase App Check / Apple App Attest (or custom OAuth/HMAC headers) across every networked provider without adding third-party dependencies to `Package.swift`:

```swift
let model = GeminiLanguageModel(proxyEndpoint: proxyURL, credential: .appCheck {
    try await AppCheck.appCheck().token(forcingRefresh: false).token
})
let session = LanguageModelSession(model: model)
```

### 4. Deterministic Offline Testing (`MockSystemOneBackend`)

Every provider accepts `init(backend:)` so unit tests run 100% offline with Swift Testing (`swift test`) and zero API keys:

```swift
let mock = MockSystemOneBackend { _ in
    SystemOneResponse(
        model: "mock",
        answers: ["isUrgent": SystemOneAnswer(type: "noul", noul: 0.96, confidence: 0.96)]
    )
}
let session = LanguageModelSession(model: GeminiLanguageModel(backend: mock))
```

---

## 🗺️ Examples & Repository Navigation

| Examples Tier | Path | What You'll Find |
| :--- | :--- | :--- |
| **1. Provider Quickstarts** | [`Examples/Quickstarts/`](Examples/Quickstarts/README.md) | 6 single-file `< 10`-line executables (`jev`, `laya`, `laya-ondevice`, `clef`, `openai`, `gemini`). |
| **2. Unified CLI** | [`Examples/CLI/`](Examples/CLI/README.md) | `system-one-cli`: 4 workflows (`ticket-triage`, `duplicate-article`, `file-organizer`, `vision-inspect`) $\times$ 7 provider modes. |
| **3. Package Trait Samples** | [`Examples/TraitSamples/`](Examples/TraitSamples/README.md) | `01`–`09` standalone packages proving binary isolation (`OnDevice`, `Remote`, `Gemini`, `ProxyCredential`, hybrid routing). |
| **4. SwiftUI Reference Apps** | [`Examples/Apps/`](Examples/Apps/README.md) | **MailTriageApp**, **VisionScannerApp**, and **NutritionLabelScannerApp** for iOS 27+ & macOS 27+. |

- **[Documentation Hub (`docs/`)](docs/README.md)** — [Getting Started](docs/getting-started.md), [Decision Shortcuts](docs/decision-shortcuts.md), [Mobile Security](docs/mobile-security.md), [Confidence Routing](docs/confidence-routing.md), [ADRs](docs/architecture/README.md), and [PRDs](docs/prd/README.md).
- **[Examples Catalog (`Examples/`)](Examples/README.md)** • **[Source Modules (`Sources/`)](Sources/README.md)** • **[Offline Test Suites (`Tests/`)](Tests/README.md)**
- **[Proxy Integrations (`Integrations/`)](Integrations/README.md)** • **[Model Tools (`Tools/`)](Tools/README.md)** • **[Agent Skills (`skills/`)](skills/README.md)**
- **[Tech Notes (`tech-notes/`)](tech-notes/README.md)** (0001–0019) • **[Contributing Guide (`CONTRIBUTING.md`)](CONTRIBUTING.md)**

---

## 📄 License

Licensed under the **Apache License, Version 2.0**. See [`LICENSE`](LICENSE) for details.
