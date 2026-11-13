# `OpenAIFoundationModels` 🧠⚡

`OpenAIFoundationModels` bridges Apple's `FoundationModels` framework (`LanguageModelSession`, `@Generable`, `Attachment`) to OpenAI's non-autoregressive **Decisions API** (`POST https://api.openai.com/v1/decisions`) powered by **`gpt-6-luna`**—delivering ~35–80ms multimodal evaluation at `$0.10 / 1M` input tokens and **`$0.00` output tokens**.

- **Package Trait**: `"OpenAI"` (also included in `"Remote"` and default `"All"`)
- **Primary Type**: `OpenAIDecisionsLanguageModel` (ergonomic alias: **`OpenAILanguageModel`**)
- **Capabilities**: `LanguageModelCapabilities([.guidedGeneration, .vision])` (Multimodal Vision + Text)
- **Auto-Resolved Environment**: `OPENAI_API_KEY`

---

## ⚡ Quick Start in 6 Lines

```swift
import FoundationModels
import OpenAIFoundationModels

let session = LanguageModelSession(model: OpenAILanguageModel())
let approved = try await session.probability(of: "Receipt complies with meal policy", state: receiptSummary)
print("Approval probability: \(approved)")
```

---

## 🧭 Initializer Matrix

| Deployment Mode | Initializer | Notes |
| :--- | :--- | :--- |
| **Env Auto-Resolution** | `OpenAILanguageModel()` | Reads `OPENAI_API_KEY`; targets `gpt-6-luna` on `/v1/decisions`. |
| **Enterprise Multi-Tenant** | `OpenAILanguageModel(apiKey: key, organization: "org-...", project: "proj-...", clientRequestID: id)` | Attaches `OpenAI-Organization`, `OpenAI-Project`, and `X-Client-Request-Id` headers. |
| **Mobile Reverse Proxy** | `OpenAILanguageModel(proxyEndpoint: url, credential: .appCheck { ... })` | Zero client secrets; refreshes attestation token per attempt inside retry loop. |
| **Offline Unit Tests** | `OpenAILanguageModel(backend: mockBackend)` | Accepts `MockSystemOneBackend` or `MockOpenAIDecisionsBackend`. |

---

## 🔗 Quickstart, Trait Sample & Tests

- **Runnable Quickstart**: [`Examples/Quickstarts/OpenAIQuickstart/main.swift`](../../Examples/Quickstarts/OpenAIQuickstart/main.swift) (`OPENAI_API_KEY="..." swift run openai-quickstart`)
- **Trait Sample**: [`07-CloudOpenAIDecisions`](../../Examples/TraitSamples/07-CloudOpenAIDecisions/README.md) • [**Tech Note 0017**](../../tech-notes/0017-openai-decisions-api-architecture.md)
- **Offline Tests**: `swift test --filter OpenAIFoundationModelsTests` ([`Tests/README.md`](../../Tests/README.md))
- **Agent Skill**: [`skills/openai-foundation-models/SKILL.md`](../../skills/openai-foundation-models/SKILL.md)
