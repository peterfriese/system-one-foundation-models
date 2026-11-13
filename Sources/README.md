# Source Modules (`Sources/`) 📦

`SystemOneFoundationModels` is organized into 8 modular Swift 6 targets—one SE-0402 trait-gated umbrella library, one shared zero-dependency core module, and 6 System One decision model providers conforming to Apple's `LanguageModel` and `LanguageModelExecutor` protocols.

## Module Overview

| Module | SPM Trait | Primary Types | Capabilities & Transport |
| :--- | :--- | :--- | :--- |
| [**`SystemOneFoundationModels`**](SystemOneFoundationModels/README.md) | `All` *(default)*, `OnDevice`, `Remote` | `@_exported` umbrella module | Re-exports `SystemOneCore` + whichever provider modules are enabled via SE-0402 package traits. |
| [**`SystemOneCore`**](SystemOneCore/README.md) | *(always linked)* | `SystemOneLanguageModel`, `SystemOneExecutor`, `SystemOneProxyBackend`, `ProxyCredential`, `RoutingPolicy`, `RetryPolicy` | Shared `@Generable` schema translator (`noul`, `choice`, `score`), multimodal `Attachment` extraction, `.probability` / `.choice` / `.score` shortcuts, and vendor-agnostic proxy gateway. |
| [**`LayaOnDevice`**](LayaOnDevice/README.md) | `Laya` / `OnDevice` | `LayaOnDeviceLanguageModel`, `LayaCoreMLEngine` | 100% offline on-device Core ML inference on Apple Neural Engine (ModernBERT / mmBERT); zero network stack. |
| [**`LayaFoundationModels`**](LayaFoundationModels/README.md) | `LayaServe` | `LayaLanguageModel`, `LayaHTTPBackend` | Self-hosted `laya-serve` HTTP daemon (`localhost:8000`) or private VPC deployment (`LAYA_SERVE_URL`, `LAYA_API_KEY`, or `ProxyCredential`). |
| [**`JevFoundationModels`**](JevFoundationModels/README.md) | `Jev` | `JevLanguageModel`, `JevHTTPBackend` | Hosted TypeSafe AI Cloud (`jev-latest`) over `POST /v1/systemone` (`TYPESAFE_API_KEY` or `ProxyCredential`). |
| [**`ClefFoundationModels`**](ClefFoundationModels/README.md) | `Clef` | `ClefLanguageModel`, `ClefHTTPBackend` | Multimodal vision + text decisions on Cloudflare Workers AI (`clef` 27B / `clef-flash` 9B), AI Gateway, or local runner (`CLOUDFLARE_API_TOKEN` or `ProxyCredential`). |
| [**`OpenAIFoundationModels`**](OpenAIFoundationModels/README.md) | `OpenAI` | `OpenAIDecisionsLanguageModel` (`OpenAILanguageModel`) | Multimodal vision + text enterprise decisions on OpenAI `gpt-6-luna` via `POST /v1/decisions` (`OPENAI_API_KEY` or `ProxyCredential`). |
| [**`GeminiFoundationModels`**](GeminiFoundationModels/README.md) | `Gemini` | `GeminiDecisionsLanguageModel` (`GeminiLanguageModel`) | High-context (256K tokens, up to 1,000 questions/pass) multimodal vision + text decisions on Google `gemini-decision-1` (`GEMINI_API_KEY` / `GOOGLE_API_KEY` or `ProxyCredential`). |

## Design Invariants Across All Modules

- **Apple-Native Call Sites**: Every provider plugs directly into `LanguageModelSession(model:)`—no proprietary session wrappers.
- **Complete Swift 6 Concurrency**: Every target compiles with `.enableUpcomingFeature("StrictConcurrency")` and full `Sendable` conformance.
- **Zero External Runtime Dependencies**: Built strictly on Apple's `Foundation`, `FoundationModels`, `CoreML`, `ImageIO`, and `UniformTypeIdentifiers`.
- **Deterministic Offline Testing**: Every provider accepts `init(backend:)` for hermetic offline testing via [`Tests/`](../Tests/README.md).

## Related Links

- [**Root Overview (`README.md`)**](../README.md) • [**Documentation Hub (`docs/`)**](../docs/README.md) • [**Examples Catalog (`Examples/`)**](../Examples/README.md)
- [**Offline Test Suites (`Tests/`)**](../Tests/README.md) • [**Architecture Decision Records (`docs/architecture/`)**](../docs/architecture/README.md) • [**Tech Notes (`tech-notes/`)**](../tech-notes/README.md)
