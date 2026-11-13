# `GeminiFoundationModels` ✨⚡

`GeminiFoundationModels` bridges Apple's `FoundationModels` framework (`LanguageModelSession`, `@Generable`, `Attachment`) to Google's high-density multimodal **Gemini Decisions API** (`POST https://generativelanguage.googleapis.com/v1beta/decisions`) powered by **`gemini-decision-1`**—supporting up to **256K input tokens**, **1,000 concurrent questions per pass**, and **`$0.00` output tokens**.

- **Package Trait**: `"Gemini"` (also included in `"Remote"` and default `"All"`)
- **Primary Type**: `GeminiDecisionsLanguageModel` (ergonomic alias: **`GeminiLanguageModel`**)
- **Capabilities**: `LanguageModelCapabilities([.guidedGeneration, .vision])` (Multimodal Vision + Text)
- **Auto-Resolved Environment**: `GEMINI_API_KEY` (fallback: `GOOGLE_API_KEY`) via `x-goog-api-key`

---

## ⚡ Quick Start in 6 Lines

```swift
import FoundationModels
import GeminiFoundationModels

let session = LanguageModelSession(model: GeminiLanguageModel())
let fraudProb = try await session.probability(of: "Transaction requires manual fraud review", state: txLog)
print("Fraud probability: \(fraudProb)")
```

---

## 🧭 Initializer Matrix

| Deployment Mode | Initializer | Notes |
| :--- | :--- | :--- |
| **Env Auto-Resolution** | `GeminiLanguageModel()` | Reads `GEMINI_API_KEY` or `GOOGLE_API_KEY`; targets `gemini-decision-1`. |
| **Explicit Cloud / Custom** | `GeminiLanguageModel(apiKey: key, model: "gemini-decision-1", clientRequestID: id)` | Supports custom `GeminiDecisionsEndpoint` URLs and `x-goog-processing-ms` telemetry. |
| **Mobile Reverse Proxy** | `GeminiLanguageModel(proxyEndpoint: url, credential: .appCheck { ... })` | Hardware-attested proxy via `ProxyCredential` (`.appCheck`, `.bearer`, `.header`, `authorize:`). |
| **Offline Unit Tests** | `GeminiLanguageModel(backend: mockBackend)` | Accepts `MockSystemOneBackend` or `MockGeminiDecisionsBackend`. |

---

## 🔗 Quickstart, Trait Sample & Tests

- **Runnable Quickstart**: [`Examples/Quickstarts/GeminiQuickstart/main.swift`](../../Examples/Quickstarts/GeminiQuickstart/main.swift) (`GEMINI_API_KEY="..." swift run gemini-quickstart`)
- **Trait Sample**: [`08-CloudGeminiDecisions`](../../Examples/TraitSamples/08-CloudGeminiDecisions/README.md) • [**Tech Note 0018**](../../tech-notes/0018-gemini-decisions-api-architecture.md)
- **Offline Tests**: `swift test --filter GeminiFoundationModelsTests` ([`Tests/README.md`](../../Tests/README.md))
- **Agent Skill**: [`skills/gemini-foundation-models/SKILL.md`](../../skills/gemini-foundation-models/SKILL.md)
