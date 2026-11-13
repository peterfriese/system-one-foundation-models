# `SystemOneCore` 🧩

`SystemOneCore` is the zero-dependency foundational module shared by all **6** System One provider targets (`LayaOnDevice`, `LayaFoundationModels`, `JevFoundationModels`, `ClefFoundationModels`, `OpenAIFoundationModels`, and `GeminiFoundationModels`).

It translates Apple `FoundationModels` `@Generable` schemas into canonical `SystemOneRequest` payloads (`noul`, `choice`, `score`), synthesizes single-frame `LanguageModelExecutorGenerationChannel` responses with calibrated metadata, and provides universal mobile reverse-proxy security (`ProxyCredential`, `ProxyEndpointValidator`, `SystemOneProxyBackend`).

---

## ⚡ Vendor-Agnostic Gateway Quick Start (6 Lines)

```swift
import FoundationModels
import SystemOneCore

let model = SystemOneLanguageModel(proxyEndpoint: gatewayURL, credential: .bearer { jwtToken })
let session = LanguageModelSession(model: model)
let urgent = try await session.probability(of: "Ticket blocks production", state: ticketText)
```

---

## 🧭 Key Public Types & Subsystems

| Subsystem | Types / Extensions | Purpose |
| :--- | :--- | :--- |
| **Core Model & Executor** | `SystemOneLanguageModel`, `SystemOneExecutor`, `SystemOneBackend`, `AnySystemOneBackend` | Bridges any `SystemOneBackend` onto Apple's `LanguageModel` & `LanguageModelExecutor` protocols. |
| **Schema & Synthesis** | `SchemaTranslator`, `ResponseSynthesizer`, `DynamicDecisionSchema` | Translates `@Generable` types (`Bool`, `enum`, `.range`) to `noul`/`choice`/`score` and synthesizes typed content + metadata. |
| **Ergonomic Shortcuts** | `.probability(of:)`, `.choice(_:)`, `.score(_:levels:)`, `Choosable`, `Choice`, `ScoreResult` | Zero-boilerplate text & multimodal `@PromptBuilder` overloads on `LanguageModelSession`. |
| **Confidence & Retries** | `RoutingPolicy`, `Decision`, `NoulJudgement`, `Probability`, `ScoreValue`, `RetryPolicy` | Epistemic routing (`.auto`, `.confirm`, `.escalate` across `0.35...0.65` undecided band) and RFC 9110 HTTP backoff. |
| **Mobile Proxy Security** | `ProxyCredential`, `ProxyEndpointValidator`, `SystemOneProxyBackend` | Per-attempt dynamic credential injection (`.appCheck`, `.bearer`, `.header`, `.custom`) and HTTPS endpoint validation. |
| **Multimodal Vision** | `TranscriptAttachmentExtractor`, `SystemOneImage`, `VisualInspectionDecision` | Active-turn `Attachment` extraction, 1024px JPEG downscaling, 4-image/16MP/13MiB guardrails, and shared vision schema. |
| **Offline Testing** | `MockSystemOneBackend`, `SystemOneError` | Deterministic offline unit-testing backend and unified typed error hierarchy. |

---

## 🔗 References

- [**Decision Shortcuts Guide**](../../docs/decision-shortcuts.md) • [**Confidence Routing Guide**](../../docs/confidence-routing.md) • [**Mobile Security Guide**](../../docs/mobile-security.md)
- **Offline Tests**: [`Tests/SystemOneCoreTests/`](../../Tests/README.md) (`swift test --filter SystemOneCoreTests`)
