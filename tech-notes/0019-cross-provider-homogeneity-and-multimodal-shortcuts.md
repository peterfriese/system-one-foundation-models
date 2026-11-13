# 0019 — Cross-Provider Homogeneity, Unified Multimodal Execution, and `@PromptBuilder` Shortcuts

- **Date**: 2026-11-13
- **Author**: Peter Friese
- **Framework**: `FoundationModels` (iOS 27.0+, macOS 27.0+, visionOS 27.0+), `SystemOneCore`, Swift 6.1 Package Traits (SE-0402)
- **Upstream**: `SystemOneFoundationModels` (`JevFoundationModels`, `LayaFoundationModels`, `LayaOnDevice`, `ClefFoundationModels`, `OpenAIFoundationModels`, `GeminiFoundationModels`)

---

## Context

As `SystemOneFoundationModels` expanded from a single-provider TypeSafe Jev bridge into a six-provider ecosystem (`JevFoundationModels`, `LayaFoundationModels`, `LayaOnDevice`, `ClefFoundationModels`, `OpenAIFoundationModels`, and `GeminiFoundationModels`), sequential feature additions introduced structural asymmetries across providers:

1. **Duplicated `LanguageModelExecutor` Pipelines**: `JevExecutor`, `ClefExecutor`, `OpenAIDecisionsExecutor`, and `GeminiDecisionsExecutor` each maintained ~125–135 lines of duplicated transcript extraction, schema translation, channel synthesis, metadata emission, and token usage accounting, while `SystemOneExecutor` in `SystemOneCore` lacked multimodal vision support.
2. **Multi-Turn Transcript Attachment Accumulation**: `TranscriptAttachmentExtractor.extractImages(from:)` scanned the entire `Transcript` from index `0` on every turn, re-sending Turn 1 images on subsequent turns and tripping `SystemOneImage.Guardrails.maxImageCount = 4` by Turn 5.
3. **Asymmetric Initialization & Test Seams**: Newer cloud providers auto-resolved API keys with zero arguments (`init()`), whereas `JevLanguageModel`, `ClefLanguageModel`, and `LayaOnDeviceLanguageModel` required multi-step configuration ceremony (preventing `< 10`-line provider quickstarts), and `JevLanguageModel` lacked `init(backend: any SystemOneBackend)` for uniform `MockSystemOneBackend` injection.
4. **Siloed Mobile Proxy Credentials**: Dynamic attestation needed a shared zero-dependency `SystemOneCore` contract (`ProxyCredential`, `ProxyEndpointValidator`, `SystemOneProxyBackend`) so all 5 networked providers (`Jev`, `LayaServe`, `Clef`, `OpenAI`, `Gemini`) expose identical `init(proxyEndpoint:credential:)` and trailing `authorize:` initializers.
5. **Text-Only Ergonomic Shortcuts & Trait Scanner Warnings**: `LanguageModelSession` shortcuts (`.probability`, `.choice`, `.score`) only accepted `state: String` (forcing `@Generable` boilerplate for single-question vision checks), and `SystemOneFoundationModels.swift` used `#if canImport(...)` without trait guards, triggering Swift 6.1 dependency scanner warnings under `--disable-default-traits --traits <Trait>`.

---

## Findings

### 1. Unified Vision-Capable `SystemOneExecutor` & Active-Turn Attachment Scoping

`SystemOneLanguageModel.Configuration` and `SystemOneExecutor` in `SystemOneCore` natively model provider-specific invariants (`supportsVision`, `defaultOutputTokenCount`, `emitsOutputTokensMetadata`, `alwaysEmitUsage`, `requiresAllAnswers`, and `emptyStateFallback`):

```swift
// Sources/SystemOneCore/SystemOneExecutor.swift
let images: [SystemOneImage]?
if configuration.supportsVision {
    let extracted = try TranscriptAttachmentExtractor.extractImages(from: request.transcript)
    images = extracted.isEmpty ? nil : extracted
} else {
    images = nil
}
```

Simultaneously, `TranscriptAttachmentExtractor.extractImages(from:)` slices the `Transcript` starting strictly **after the most recent `.response` entry**:

```swift
let entries = Array(transcript)
let activeStartIndex = entries.lastIndex(where: {
    if case .response = $0 { return true }
    return false
}).map { entries.index(after: $0) } ?? entries.startIndex
```

- **Impact**: All six provider executors (`JevExecutor`, `LayaExecutor`, `LayaOnDeviceExecutor`, `ClefExecutor`, `OpenAIDecisionsExecutor`, `GeminiDecisionsExecutor`) collapse into thin ~35–60 line adapters delegating to `SystemOneExecutor`. `SystemOneLanguageModel(backend: ..., supportsVision: true)` advertises `LanguageModelCapabilities([.guidedGeneration, .vision])` and supports PNG/JPEG/WebP attachments directly in core unit tests, while `Jev` automatically gains `transportDurationMs` metadata telemetry.

### 2. Universal `ProxyCredential`, `ProxyEndpointValidator` & `SystemOneProxyBackend`

`SystemOneCore` centralizes zero-secret mobile reverse-proxy security via `ProxyCredential` (`.appCheck`, `.bearer`, `.header`, `.custom`), `ProxyEndpointValidator`, and `SystemOneProxyBackend` (see Tech Note 0010):

- **Per-Attempt Refresh & Header Safety**: Credentials resolve on every retry attempt inside the backoff loop while rejecting empty tokens and CR/LF/NUL header-injection bytes with `SystemOneError.authenticationFailed`.
- **HTTPS Enforcement**: `ProxyEndpointValidator.validate(_:)` enforces `https://` for all remote hosts (`localhost`, `127.0.0.1`, `::1`, `[::1]` allowed over `http://` for local Firebase / Cloudflare emulators) and forbids embedded URL userinfo credentials.
- **Dual Proxy Topologies**: Every networked provider supports Pattern A passthrough (`GeminiLanguageModel(proxyEndpoint:credential:)`, etc.), while `SystemOneLanguageModel(proxyEndpoint:credential:)` provides Pattern B vendor-agnostic routing via `SystemOneProxyBackend`.

### 3. Homogeneous Zero-Argument `init()` & Uniform `init(backend:)`

Every `LanguageModel` provider follows an identical progressive-disclosure initialization contract:

| Provider | Zero-Arg Initializer | Environment / Bundle Resolution Chain | Endpoint Type |
| :--- | :--- | :--- | :--- |
| `JevLanguageModel` | `JevLanguageModel()` | `TYPESAFE_API_KEY` | `JevEndpoint` (`.hosted`, `.custom`) |
| `LayaLanguageModel` | `LayaLanguageModel()` | `LAYA_SERVE_URL` / `LAYA_ENDPOINT` $\to$ `localhost:8000` + `LAYA_API_KEY` | `LayaEndpoint` |
| `LayaOnDeviceLanguageModel` | `try LayaOnDeviceLanguageModel()` | `LAYA_MODEL_PATH` $\to$ `Bundle.main` $\to$ `./LayaDecisionModel.mlmodelc` + `LAYA_TOKENIZER_PATH` / adjacent `tokenizer.json` | Local `file://` URL |
| `ClefLanguageModel` | `ClefLanguageModel()` | `CLEF_ENDPOINT` $\to$ `CLOUDFLARE_ACCOUNT_ID` (+ `CLOUDFLARE_GATEWAY_ID`) + `CLOUDFLARE_API_TOKEN` $\to$ `CLEF_LOCAL_PORT` | `ClefEndpoint` |
| `OpenAILanguageModel` (`OpenAIDecisionsLanguageModel`) | `OpenAILanguageModel()` | `OPENAI_API_KEY` | `OpenAIDecisionsEndpoint` |
| `GeminiLanguageModel` (`GeminiDecisionsLanguageModel`) | `GeminiLanguageModel()` | `GEMINI_API_KEY` / `GOOGLE_API_KEY` | `GeminiDecisionsEndpoint` |

Every provider also exposes `public init(backend: any SystemOneBackend, ...)` (and `JevClient` conforms directly to `SystemOneBackend`), allowing any test suite to inject `MockSystemOneBackend` without custom `URLProtocol` boilerplate.

### 4. Swift 6.1 Package Trait Scanner Hygiene (`#if <Trait> && canImport(...)`)

When compiling `SystemOneFoundationModels` with selective traits (`swift build --disable-default-traits --traits OnDevice`), Swift 6.1's dependency scanner inspects `#if canImport(ModuleName)` blocks before target graph pruning and emits warnings for conditionally excluded sibling targets.

Gating each re-export in `Sources/SystemOneFoundationModels/SystemOneFoundationModels.swift` with **both** the package trait condition (`Jev`, `LayaServe`, `Laya`, `Clef`, `OpenAI`, `Gemini`) and `canImport(...)` silences all scanner diagnostics cleanly.

### 5. Multimodal `@PromptBuilder` Ergonomic Shortcuts

`LanguageModelSession+SystemOne.swift` extends `.probability`, `.choice` (both `Choosable` and `[String]`), and `.score` with `prompt: Prompt` and trailing `@PromptBuilder` overloads:

```swift
let damaged = try await session.probability(of: "The parcel has visible exterior damage") {
    "Inspect delivery photo for crushed corners."
    Attachment(imageURL: url)
}
```

Additionally, missing confidence metadata in shortcut decoding safely defaults to `0.0` rather than `1.0`, ensuring `RoutingPolicy.default.decide(confidence:)` routes uncalibrated fallback answers to `.escalate` instead of `.auto`.

---

## Implications

1. **True `< 10`-Line Call Sites Across All 6 Providers**: Every provider in `Examples/Quickstarts/` (`jev-quickstart`, `laya-quickstart`, `laya-ondevice-quickstart`, `clef-quickstart`, `openai-quickstart`, `gemini-quickstart`) runs a real, non-mocked System One evaluation in 8–9 lines of idiomatic Swift 6.
2. **Single Point of Maintenance for Execution Semantics**: Improvements to attachment downscaling (1024px JPEG conversion), active-turn scoping, missing-answer validation, or metadata formatting in `SystemOneExecutor` automatically apply across every provider.
3. **Provider-Agnostic Mobile Security**: iOS, macOS, and visionOS apps share a single `ProxyCredential` definition across `Gemini`, `OpenAI`, `Clef`, `LayaServe`, `Jev`, and `SystemOneLanguageModel`.

---

## Evidence / Sources

- [`Sources/SystemOneCore/SystemOneExecutor.swift`](../Sources/SystemOneCore/SystemOneExecutor.swift) — Unified text + multimodal executor pipeline.
- [`Sources/SystemOneCore/Backend/ProxyCredential.swift`](../Sources/SystemOneCore/Backend/ProxyCredential.swift) & [`SystemOneProxyBackend.swift`](../Sources/SystemOneCore/Backend/SystemOneProxyBackend.swift) — Universal zero-dependency proxy security.
- [`Sources/SystemOneCore/Attachment/TranscriptAttachmentExtractor.swift`](../Sources/SystemOneCore/Attachment/TranscriptAttachmentExtractor.swift) — Active-turn attachment slicing and 1024px JPEG downscaling.
- [`Sources/SystemOneCore/Ergonomics/LanguageModelSession+SystemOne.swift`](../Sources/SystemOneCore/Ergonomics/LanguageModelSession+SystemOne.swift) — `Prompt` and `@PromptBuilder` overloads on `.probability`, `.choice`, and `.score`.
- [`Sources/SystemOneFoundationModels/SystemOneFoundationModels.swift`](../Sources/SystemOneFoundationModels/SystemOneFoundationModels.swift) — `#if <Trait> && canImport(...)` conditional exports.
- [`Examples/Quickstarts/`](../Examples/Quickstarts/README.md) — 6 `< 10`-line executable provider samples.
- [`Tests/SystemOneCoreTests/ErgonomicShortcutTests.swift`](../Tests/SystemOneCoreTests/ErgonomicShortcutTests.swift) — Unit tests verifying multimodal `@PromptBuilder` shortcuts and `0.0` confidence fallback safety.
