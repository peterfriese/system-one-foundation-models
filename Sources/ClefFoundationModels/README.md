# `ClefFoundationModels` 👁️⚡

`ClefFoundationModels` bridges Apple's `FoundationModels` framework (`LanguageModelSession`, `@Generable`, `Attachment`) to **Cloudflare Clef (27B)** and **Clef-Flash (9B)** open-weight multimodal decision models across Cloudflare Workers AI, Cloudflare AI Gateway, and local Apple Silicon MPS runners (`output_tokens: 0`).

- **Package Trait**: `"Clef"` (also included in `"Remote"` and default `"All"`)
- **Capabilities**: `LanguageModelCapabilities([.guidedGeneration, .vision])` (Multimodal Vision + Text)
- **Auto-Resolved Environment**: `CLEF_ENDPOINT`, `CLOUDFLARE_ACCOUNT_ID` (+ optional `CLOUDFLARE_GATEWAY_ID`) + `CLOUDFLARE_API_TOKEN`, or `CLEF_LOCAL_PORT`

---

## ⚡ Multimodal Quick Start in 6 Lines

```swift
import ClefFoundationModels
import FoundationModels

let session = LanguageModelSession(model: ClefLanguageModel())
let damaged = try await session.probability(of: "The parcel has visible exterior damage") { Attachment(cgImage) }
print("Damage probability: \(damaged)")
```

---

## 🧭 Initializer Matrix

| Deployment Mode | Initializer | Notes |
| :--- | :--- | :--- |
| **Env Auto-Resolution** | `ClefLanguageModel(model: .clefFlash)` | Resolves `CLEF_ENDPOINT`, `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`, or `CLEF_LOCAL_PORT`. |
| **Workers AI / AI Gateway** | `ClefLanguageModel(endpoint: .workersAI(accountID: id, model: .clefFlash), apiToken: tok)` | Also supports `.gateway(accountID:gatewayID:model:)`, `.local(port:model:)`, and `.custom(url, model:)`. |
| **Mobile Reverse Proxy** | `ClefLanguageModel(proxyEndpoint: url, model: .clefFlash, credential: .appCheck { ... })` | Hardware-attested mobile proxy without shipping `CLOUDFLARE_API_TOKEN` on device. |
| **Offline Unit Tests** | `ClefLanguageModel(backend: mockBackend)` | Injects `MockSystemOneBackend` (or ephemeral `URLSession` on `ClefHTTPBackend`). |

---

## 🔗 Quickstart, Local Runner & Tests

- **Runnable Quickstart**: [`Examples/Quickstarts/ClefQuickstart/main.swift`](../../Examples/Quickstarts/ClefQuickstart/main.swift) (`swift run clef-quickstart`)
- **Local MPS Runner**: [`Tools/ClefLocalRunner/`](../../Tools/ClefLocalRunner/README.md) • **Trait Sample**: [`06-EdgeClefVision`](../../Examples/TraitSamples/06-EdgeClefVision/README.md)
- **Offline Tests**: `swift test --filter ClefFoundationModelsTests` ([`Tests/README.md`](../../Tests/README.md))
- **Agent Skill**: [`skills/clef-foundation-models/SKILL.md`](../../skills/clef-foundation-models/SKILL.md)
