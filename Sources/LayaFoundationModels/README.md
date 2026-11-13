# `LayaFoundationModels` 🖥️

`LayaFoundationModels` bridges Apple's `FoundationModels` framework (`LanguageModelSession`, `@Generable`, `@Guide`) to self-hosted or private-VPC **`laya-serve`** HTTP decision servers speaking the canonical `POST /v1/systemone` wire protocol.

- **Package Trait**: `"LayaServe"` (also included in `"Remote"` and default `"All"`)
- **Capabilities**: `LanguageModelCapabilities([.guidedGeneration])` (Text)
- **Auto-Resolved Environment**: `LAYA_SERVE_URL` / `LAYA_ENDPOINT` (defaults to `http://127.0.0.1:8000/v1/systemone`) + optional `LAYA_API_KEY`

---

## ⚡ Quick Start in 6 Lines

```swift
import FoundationModels
import LayaFoundationModels

let session = LanguageModelSession(model: LayaLanguageModel())
let route = try await session.choice("Select owning team", options: ["billing", "eng", "sec"], state: ticket)
print("Routed to \(route.value) (confidence: \(route.confidence))")
```

---

## 🧭 Initializer Matrix

| Deployment Mode | Initializer | Notes |
| :--- | :--- | :--- |
| **Zero-Arg Local / Env** | `LayaLanguageModel()` | Resolves `LAYA_SERVE_URL` / `LAYA_ENDPOINT` or defaults to `localhost:8000` + `LAYA_API_KEY`. |
| **Explicit Port / VPC** | `LayaLanguageModel(endpoint: .local(port: 8770), modelID: "english", apiKey: key)` | Supports `.localDefault`, `.local(port:)`, `.hosted`, or `.custom(URL)`. |
| **Mobile Reverse Proxy** | `LayaLanguageModel(proxyEndpoint: url, credential: .bearer { ... })` | Dynamic per-attempt auth via `ProxyCredential` (`.appCheck`, `.bearer`, `.header`, `authorize:`). |
| **Offline Unit Tests** | `LayaLanguageModel(backend: mockBackend)` | Injects `MockSystemOneBackend` with zero sockets or running daemons. |

---

## 🔗 Quickstart, Trait Sample & Tests

- **Runnable Quickstart**: [`Examples/Quickstarts/LayaServeQuickstart/main.swift`](../../Examples/Quickstarts/LayaServeQuickstart/main.swift) (`swift run laya-quickstart`)
- **Trait Sample**: [`03-PrivateLayaServer`](../../Examples/TraitSamples/03-PrivateLayaServer/README.md) • [**CLI & Server Guide**](../../docs/laya-cli-guide.md)
- **Offline Tests**: `swift test --filter LayaFoundationModelsTests` ([`Tests/README.md`](../../Tests/README.md))
- **Agent Skill**: [`skills/laya-foundation-models/SKILL.md`](../../skills/laya-foundation-models/SKILL.md)
