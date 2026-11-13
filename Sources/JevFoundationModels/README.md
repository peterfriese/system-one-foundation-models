# `JevFoundationModels` ☁️

`JevFoundationModels` bridges Apple's `FoundationModels` framework (`LanguageModelSession`, `@Generable`, `@Guide`) to **TypeSafe AI's Jev** System One cloud decision endpoint (`POST https://api.typesafe.ai/v1/systemone`).

- **Package Trait**: `"Jev"` (also included in `"Remote"` and default `"All"`)
- **Capabilities**: `LanguageModelCapabilities([.guidedGeneration])` (Text)
- **Auto-Resolved Environment**: `TYPESAFE_API_KEY`

---

## ⚡ Quick Start in 6 Lines

```swift
import FoundationModels
import JevFoundationModels

let session = LanguageModelSession(model: JevLanguageModel())
let urgent = try await session.probability(of: "Ticket requires immediate escalation", state: ticketText)
print("Urgent probability: \(urgent)")
```

---

## 🧭 Initializer Matrix

| Deployment Mode | Initializer | Notes |
| :--- | :--- | :--- |
| **Env Auto-Resolution** | `JevLanguageModel()` | Reads `TYPESAFE_API_KEY`; targets `JevEndpoint.hosted`. |
| **Explicit Cloud / Custom** | `JevLanguageModel(endpoint: .hosted, apiKey: key, retryPolicy: .default)` | Supports `.hosted` or `.custom(URL)` with configurable `RetryPolicy`. |
| **Mobile Reverse Proxy** | `JevLanguageModel(proxyEndpoint: url, credential: .appCheck { ... })` | Zero client secrets; enforces HTTPS via `ProxyEndpointValidator` (also supports trailing `authorize:`). |
| **Offline Unit Tests** | `JevLanguageModel(backend: mockBackend)` | Accepts `MockSystemOneBackend` (or `MockJevTransport` via `transport:`). |

---

## 🔗 Quickstart, Trait Sample & Tests

- **Runnable Quickstart**: [`Examples/Quickstarts/JevQuickstart/main.swift`](../../Examples/Quickstarts/JevQuickstart/main.swift) (`TYPESAFE_API_KEY="..." swift run jev-quickstart`)
- **Trait Samples**: [`02-CloudJevWorker`](../../Examples/TraitSamples/02-CloudJevWorker/README.md) • [`05-SecureAppCheckApp`](../../Examples/TraitSamples/05-SecureAppCheckApp/README.md)
- **Offline Tests**: `swift test --filter JevFoundationModelsTests` ([`Tests/README.md`](../../Tests/README.md))
- **Agent Skill**: [`skills/jev-foundation-models/SKILL.md`](../../skills/jev-foundation-models/SKILL.md)
