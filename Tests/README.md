# Deterministic Offline Test Suites (`Tests/`) 🧪

In accordance with **Principle 5 (Deterministic, Offline-First Automated Testing)**, every unit test across all **7** Swift Testing suites in `Tests/` executes **100% offline** with **zero external network traffic**, **zero live API keys**, and **zero GPU/ANE model downloads**.

---

## 🚀 Running the Test Suites

```bash
# Run all 7 offline test suites in parallel via Swift Package Manager:
swift test

# Or run an isolated provider test target:
swift test --filter SystemOneCoreTests
swift test --filter JevFoundationModelsTests
swift test --filter LayaFoundationModelsTests
swift test --filter LayaOnDeviceTests
swift test --filter ClefFoundationModelsTests
swift test --filter OpenAIFoundationModelsTests
swift test --filter GeminiFoundationModelsTests
```

---

## 🧭 All 7 Offline Test Targets

| Test Target | Module Under Test | Coverage Scope |
| :--- | :--- | :--- |
| **`SystemOneCoreTests`** | [`SystemOneCore`](../Sources/SystemOneCore/README.md) | `SchemaTranslator`, `ResponseSynthesizer`, `SystemOneExecutor`, `ProxyCredential` & `ProxyEndpointValidator`, `SystemOneProxyBackend`, `SystemOneImage` guardrails, `RoutingPolicy`, `RetryPolicy`, and `.probability` / `.choice` / `.score` shortcuts. |
| **`JevFoundationModelsTests`** | [`JevFoundationModels`](../Sources/JevFoundationModels/README.md) | `JevLanguageModel`, `JevEndpoint`, `JevClient`, `URLSessionTransport` & `ProxyTransport` backoff/cancellation, and `MockJevTransport` / `MockSystemOneBackend` conformance. |
| **`LayaFoundationModelsTests`** | [`LayaFoundationModels`](../Sources/LayaFoundationModels/README.md) | `LayaLanguageModel`, `LayaEndpoint` URL validation, `LayaHTTPBackend` retry/auth/cancellation handling, `ProxyCredential` headers, and `LAYA_SERVE_URL` resolution. |
| **`LayaOnDeviceTests`** | [`LayaOnDevice`](../Sources/LayaOnDevice/README.md) | `LayaCoreMLEngine` fixed-shape `[1, 512]` tensor padding, `ModernBERTTokenizer` (WordPiece), `MMBERTTokenizer` (SentencePiece Unigram), and `TemperatureCalibration`. |
| **`ClefFoundationModelsTests`** | [`ClefFoundationModels`](../Sources/ClefFoundationModels/README.md) | `ClefLanguageModel`, `ClefEndpoint` URL/body model slug decoupling, Client API v4 dual-decoding, 1024px JPEG downscaling, `ProxyCredential`, and multimodal vision evaluation. |
| **`OpenAIFoundationModelsTests`** | [`OpenAIFoundationModels`](../Sources/OpenAIFoundationModels/README.md) | `OpenAIDecisionsLanguageModel` (`OpenAILanguageModel`), `OpenAIDecisionsPayloadAdapter` (`predicate`/`choice`/`score` 0-based & 1-based alignment), enterprise headers, `ProxyCredential`, and multimodal Data URL guardrails. |
| **`GeminiFoundationModelsTests`** | [`GeminiFoundationModels`](../Sources/GeminiFoundationModels/README.md) | `GeminiDecisionsLanguageModel` (`GeminiLanguageModel`), `GeminiDecisionsPayloadAdapter` dictionary-keyed `noul`/`choice`/`score` wire mapping, flat typed multimodal Base64 `input` blocks, `x-goog-api-key` & `ProxyCredential` auth, and `x-goog-processing-ms` timing. |

---

## 🏗️ Offline Mock Architecture

1. **Application & Schema Level (`MockSystemOneBackend`)**: Every provider (`JevLanguageModel`, `LayaLanguageModel`, `LayaOnDeviceLanguageModel`, `ClefLanguageModel`, `OpenAILanguageModel`, `GeminiLanguageModel`, and `SystemOneLanguageModel`) exposes `init(backend: any SystemOneBackend)`, allowing tests to inspect translated `SystemOneRequest` payloads and return deterministic `SystemOneResponse` fixtures.
2. **HTTP Wire & Retry Level (`URLProtocol` Stubs & Provider Mock Backends)**: Networked provider suites pair ephemeral `URLSessionConfiguration.ephemeral` protocol stubs with `RetryPolicy` tests to verify HTTP `401`/`403` fail-fast behavior, RFC 9110 `Retry-After` backoff, per-attempt `ProxyCredential` refresh, and cooperative Swift 6 `CancellationError` propagation without opening real sockets.
3. **Strict Boundary (Principle 7)**: Mocks exist exclusively for automated testing in `Tests/` and SwiftUI `#Preview` blocks—never as silent fallbacks in [`Examples/`](../Examples/README.md).
