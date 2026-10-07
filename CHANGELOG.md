# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.3.0] - 2026-10-07

### Added

- **Cloudflare Clef & Clef-Flash Multimodal Decision Models (`ClefFoundationModels`)**:
  - Added native Apple Foundation Models integration for Cloudflare's open-weight multimodal decision models: **Clef (27B)** and **Clef-Flash (9B)**.
  - Implements `ClefLanguageModel` conforming to `LanguageModel` with `LanguageModelCapabilities([.guidedGeneration, .vision])`, accepting Apple `Prompt` attachments (`Attachment(cgImage)`).
  - Supports multiple deployment topologies via `ClefEndpoint`: Cloudflare Workers AI edge (`.workersAI(accountID:model:)`), Cloudflare AI Gateway (`.gateway(accountID:gatewayID:model:)`), local inference runners (`.local(port:model:)`), and custom HTTP/HTTPS endpoints (`.custom(url:model:)`).
  - Wire protocol parity for System One decision primitives (`noul`, `choice`, `score`) evaluated in a single non-autoregressive feed-forward pass.
  - Added dual-decoding fallback in `ClefHTTPBackend` supporting both raw JSON payloads and Cloudflare Client API v4 envelopes (`{ result, success, errors }`).
  - Decoupled Cloudflare Workers AI routing catalog paths (`@cf/cloudflare/clef-flash`) from JSON payload model identifiers (`clef-flash`) to satisfy Cloudflare schema regex rules.

- **Core Multimodal Primitives (`SystemOneCore`)**:
  - Introduced `SystemOneImage` supporting zero-allocation binary dimension sniffing for PNG, JPEG, and WebP formats without decoding pixel buffers.
  - Implemented RFC 2397 Data URL streaming serialization for lightweight wire transport.
  - Enforces Clef multimodal guardrails: maximum 4 images per turn, 16.0 megapixels maximum resolution, and 13 MiB payload limit.
  - Added visual transcript extraction supporting both `Attachment(cgImage)` and raw image data payloads.

- **`ClefCameraScanner` Reference Application (`Examples/ClefCameraScanner/`)**:
  - Added complete cross-platform SwiftUI reference application for macOS and iOS featuring live camera capture and real-time visual decision modeling.
  - Built with modern Apple platform patterns: SwiftUI `@Observable`, Liquid Glass HUD overlays (`InspectionHUDView`), dynamic device selection, and AVFoundation capture pipelines.
  - Evaluates strongly-typed `VisualInspectionDecision` models judging item category, physical condition, defect severity, and safety compliance directly from live camera frames.

- **`ClefDemo` CLI Demonstrator (`Examples/ClefDemo/`)**:
  - Added standalone command-line executable demonstrating multimodal visual inspection with Cloudflare Clef and Clef-Flash.
  - Supports reading local image files (PNG, JPEG, WebP) or auto-generating synthetic CoreGraphics bitmap frames in-memory.
  - Configurable backend targeting (`workers-ai` edge vs. `local` runner), model selection (`clef-flash` vs. `clef`), and custom endpoints.

- **`MailTriageApp` 6th Backend Integration (`Examples/MailTriageApp/`)**:
  - Integrated Cloudflare Clef as the 6th runtime deployment topology (`TriageBackend.cloudflareClef`), hot-swappable in Settings alongside Core ML, local/remote Laya, Jev Cloud, and generative baselines.
  - Implemented multimodal email attachment triage, inspecting image attachments alongside message body text for triage classification and urgency priority scoring.
  - Added dedicated health probe checks, latency tracking, and edge token configuration.

- **Pure Apple Data Protection Keychain Architecture (`Examples/MailTriageApp/`)**:
  - Implemented `@KeychainStorage` SwiftUI dynamic property wrapper providing reactive `@Binding` support for sensitive credentials.
  - Introduced type-safe `KeychainKey` enum (`.cloudflareAccountId`, `.cloudflareApiToken`, `.typesafeApiKey`, `.hostedVpcToken`) enforcing isolated, keyed storage.
  - Fully adopted `kSecUseDataProtectionKeychain` to prevent legacy macOS authorization dialogs during automated tests, CLI workflows, and development builds.

- **Local Apple Silicon MPS Runner Recipe (`Tools/ClefLocalRunner/`)**:
  - Added local Python inference runner recipe in `Tools/ClefLocalRunner/` for running quantized Clef and Clef-Flash weights on Apple Silicon Metal Performance Shaders (MPS).
  - Compatible with standard System One wire protocols on `http://localhost:8000/v1/evaluate`.

- **Technical Notes Expansion (Tech Notes 0012 through 0016)**:
  - Documented multimodal architecture discoveries, SDK quirks, and edge integration nuances in `tech-notes/`:
    - **Tech Note 0012** (`tech-notes/0012-clef-multimodal-decision-models.md`): Cloudflare Clef & Clef-Flash Multimodal Decision Model Architecture (Qwen-based joint routing head, single-pass feed-forward evaluation, and Workers AI vs local serving topologies).
    - **Tech Note 0013** (`tech-notes/0013-foundationmodels-vision-capability.md`): Foundation Models Vision Capability & Multimodal Attachment Gating (`LanguageModelCapabilities.Capability.vision` requirements for `Attachment(cgImage)`).
    - **Tech Note 0014** (`tech-notes/0014-cloudflare-workers-ai-model-schema-nuance.md`): Cloudflare Workers AI Model Schema Validation Nuance & Identifier Decoupling (resolving `AiError: Bad input` via catalog path vs body ID decoupling).
    - **Tech Note 0015** (`tech-notes/0015-clef-multimodal-token-estimation-and-data-url-encoding.md`): Clef Multimodal Token Estimation, Data URL Wire Encoding & Camera Frame Downscaling (preventing HTTP 413 token overflow).
    - **Tech Note 0016** (`tech-notes/0016-cloudflare-workers-ai-v4-response-envelope.md`): Cloudflare Workers AI Client API v4 Response Envelope & Dual-Decoding Fallback (handling root JSON and `{ result, success, errors }` wrappers).

- **Architectural Learnings Deep-Dive Article**:
  - Published comprehensive engineering article: `docs/learnings/2026-10-05-bridging-cloudflare-clef-to-apple-foundation-models.md` detailing the design, implementation, and lessons learned while bridging Cloudflare Clef into Apple Foundation Models.

---

## [0.2.0] - 2026-09-30

### Added

- **Repository and Package Rename (`SystemOneFoundationModels`)**:
  - Renamed the repository from `jev-foundation-models` to `system-one-foundation-models` and the core SPM package and umbrella library product to `SystemOneFoundationModels`.
  - Reflects multi-model decision support across **Laya on-device Core ML** (Apple Neural Engine), **Laya self-hosted HTTP** (`laya-serve`), and hosted **TypeSafe Jev** cloud endpoints.
  - Modularized targets into focused libraries: `SystemOneCore`, `LayaOnDevice`, `LayaFoundationModels`, `JevFoundationModels`, and the umbrella `SystemOneFoundationModels`.
  - Updated all package dependency manifests, documentation, and Swift Package Index links.

- **`NutritionLabelScanner` Reference iOS Application (`Examples/NutritionLabelScannerApp/`)**:
  - Added native iOS reference application showcasing real-time camera scanning and multi-backend decision modeling for nutrition safety.
  - Implemented live Vision OCR text recognition with spatial 2D row-clustering tolerance (`NutritionLabelParser`) to accurately reconstruct horizontal lines across multi-column tables.
  - Supports multilingual label parsing for European / DACH (`Nährwertdeklaration`, `Brennwert`, `Zutaten`), French, and FDA / US (`Nutrition Facts`, `Serving Size`, `Ingredients`) standards.
  - Strongly-typed dietary safety evaluation via `@Generable` `DietarySafetyDecision` and `DietaryFlag` models, computing allergen risk (0–3) and NOVA food processing classification (0–3).
  - Configurable dietary restriction profiles (vegan, gluten-free, lactose-free, seed-oil-free, low sodium, sugar limits).
  - Features OpenFoodFacts barcode fallback resolution, dynamic bounding box viewfinder overlays, and accessible haptic/audio feedback.

- **Ergonomic Decision Shortcuts on `LanguageModelSession` (`SystemOneCore/Ergonomics`)**:
  - Implemented high-level ergonomic extensions on Apple's `LanguageModelSession` enabling ad-hoc queries without declaring boilerplate `@Generable` schema types:
    - `session.probability(of:state:criteria:)`: Direct truth probability evaluation ($0.0 \dots 1.0$) for statements against state with optional criteria guidance.
    - `session.choice(_:from:state:)`: Strongly-typed categorical selection across cases of any Swift enum conforming to `Choosable`.
    - `session.choice(_:options:state:)`: Categorical selection among dynamic runtime string arrays.
    - `session.score(_:levels:state:)`: Ordinal rubric scoring returning discrete winner indices and continuous probability-weighted mean scores.
  - Introduced the `Choosable` protocol (`CaseIterable & Hashable & Sendable`) with automatic default identifiers and optional natural-language option descriptions.
  - Introduced `Choice<Option>` container encapsulating winning value, calibrated confidence score, and candidate probability distribution.
  - Introduced `ScoreResult` container encapsulating continuous expected value, winning level index, level label, and complete rubric probability distribution.
  - Implemented `DynamicDecisionSchema` for runtime generation of `GenerationSchema` instances, ensuring ad-hoc queries undergo standard schema translation and retain backend parity across `LayaCoreMLEngine`, `LayaHTTPBackend`, `JevBackend`, and `MockSystemOneBackend`.

- **Swift 6.1 Package Traits Partitioned by Model Boundaries (SE-0402 / SE-0450)**:
  - Upgraded `Package.swift` to `swift-tools-version: 6.1` and adopted package traits.
  - Partitioned traits strictly along **model boundaries** matching developer intent:
    - `Jev`: Enables hosted TypeSafe Jev cloud decision API client (`JevFoundationModels`).
    - `Laya`: Enables on-device Core ML and Apple Neural Engine execution (`LayaOnDevice`).
    - `LayaServe`: Enables HTTP client for self-hosted private `laya-serve` instances (`LayaFoundationModels`).
  - Added convenient persona shorthands:
    - `OnDevice`: Activates `["Laya"]` for zero-network, zero-secret local edge deployments.
    - `Remote`: Activates `["Jev", "LayaServe"]` for networked clients without Core ML neural binaries.
    - `All`: Activates `["Jev", "Laya", "LayaServe"]` for multi-backend showcase applications.
  - Configured `.default(enabledTraits: ["Jev"])` for seamless backwards compatibility.

- **Zero-Dependency `ProxyTransport` for Mobile Reverse Proxies (`JevFoundationModels`)**:
  - Added `ProxyTransport` conforming to `JevTransport` and `Sendable` in `Sources/JevFoundationModels/Transport/ProxyTransport.swift`.
  - Supports zero-trust mobile architectures routing through reverse proxies (e.g., Firebase Cloud Functions, Cloudflare Workers, AWS API Gateway) without embedding API keys in Mach-O binaries.
  - Provides dynamic closure-based `Credential` resolution:
    - `.bearer`: Dynamic OAuth 2.0 / OIDC / Firebase Auth token injection.
    - `.header`: Named header injection (e.g., `X-Firebase-AppCheck` with Apple App Attest / DeviceCheck).
    - `.custom`: In-place request mutations for dynamic HMAC signatures and replay nonces.
  - Evaluates credential resolution **per attempt inside the retry loop**, guaranteeing fresh tokens on retries for consumable single-use or rotating credentials.
  - Features jittered exponential backoff respecting RFC 9110 `Retry-After` headers and latency telemetry via `x-envoy-upstream-service-time`.

- **Standalone Trait Sample Applications (`Examples/TraitSamples/`)**:
  - `01-OfflineLayaApp`: 100% offline document classifier using `LayaOnDevice` and `Choosable` enum categories (`traits: ["Laya"]`).
  - `02-CloudJevWorker`: Lean ticket triage worker querying hosted Jev API with zero ML linkage (`traits: ["Jev"]`).
  - `03-PrivateLayaServer`: Internal VPC cluster ordinal vulnerability scoring (`ScoreResult`) over private HTTP (`traits: ["LayaServe"]`).
  - `04-HybridRouter`: Local-first edge execution escalating to cloud Jev when confidence falls below 0.80 (`traits: ["All"]`).
  - `05-SecureAppCheckApp`: SwiftUI and CLI application utilizing `ProxyTransport` with hardware-backed Firebase App Check (Apple App Attest). Includes production Cloud Function reference, automated deployment wizard `setup-firebase-project.sh`, and `SETUP-PRODUCTION.md`.

- **Technical Notes Expansion (0003 through 0011)**:
  - Documented deep SDK findings, architectural designs, and platform nuances in `tech-notes/`:
    - **Tech Note 0003** (`tech-notes/0003-foundationmodels-dynamic-profiles.md`): Declarative dynamic profiles and session adaptation in Apple Foundation Models (`LanguageModelSession.DynamicProfile`, `DynamicProfileBuilder`, `@SessionPropertyEntry`, turn isolation).
    - **Tech Note 0004** (`tech-notes/0004-secure-mobile-transport-appcheck.md`): Production mobile architecture securing TypeSafe credentials using Apple App Attest / DeviceCheck hardware attestation, Firebase Cloud Functions proxy, and `JevTransport`.
    - **Tech Note 0005** (`tech-notes/0005-spm-dependency-isolation-and-vendor-transports.md`): SPM dependency isolation and decoupling vendor-specific transports from core targets to prevent dependency creep.
    - **Tech Note 0006** (`tech-notes/0006-http-resilience-and-confidence-routing.md`): HTTP resilience, RFC 9110 `Retry-After` parsing, exponential backoff, cooperative cancellation safety, and calibrated confidence routing for the undecided band (`0.35...0.65`).
    - **Tech Note 0007** (`tech-notes/0007-pluggable-system-one-backends-and-laya-serve.md`): Pluggable `SystemOneBackend` protocol architecture, wire protocol parity between TypeSafe Jev `/v1/systemone` and self-hosted `laya-serve`, and dynamic header injection.
    - **Tech Note 0008** (`tech-notes/0008-on-device-coreml-decision-engine.md`): On-device decision models via Core ML and Apple Neural Engine (ANE), ModernBERT/mmBERT compilation, option marker gathering, 8-bit quantization, and zero-dependency Swift tokenization.
    - **Tech Note 0009** (`tech-notes/0009-package-traits-and-ergonomic-shortcuts.md`): Architectural analysis of `AnyDecisionModel`, runtime dynamic schema synthesis (`DynamicDecisionSchema`), ergonomic shortcuts (`.probability()`, `.choice()`, `.score()`), `Choosable` protocol, and model-bounded package traits.
    - **Tech Note 0010** (`tech-notes/0010-proxy-transport-and-dynamic-attestation.md`): Zero-dependency reverse proxy transport architecture, dynamic `Credential` enum (`.bearer`, `.header`, `.custom`), per-attempt token acquisition inside retry loops, and secret-free mobile binaries.
    - **Tech Note 0011** (`tech-notes/0011-xcode-27-2-json-xcproj-format.md`): Adoption of Xcode 27.2+ native JSON project format (`project.xcproj`) replacing legacy OpenStep `.pbxproj` for human and AI agent ergonomics.

### Fixed

- **macOS Keychain Password Prompts in `KeychainService.swift`**:
  - Eliminated legacy macOS keychain queries (`SecItemCopyMatching` / `SecItemAdd` without `kSecUseDataProtectionKeychain`).
  - Prevents system password authorization dialogs when running un-entitled environments (CLI runners, test runners, Xcode previews, un-provisioned dev builds).
  - Adopted shared in-memory fallback store with thread-safe access and reset facilities for clean, isolated test runs.

---

## [0.1.0] - 2026-09-21

### Added

- Initial release of the native Apple Foundation Models bridge for TypeSafe Jev.
- Direct integration with `LanguageModel`, `LanguageModelExecutor`, and `@Generable`.
- Decision primitive mapping for boolean statements (`noul`), categorical enums (`choice`), and ordinal rubrics (`score`).
- CLI demonstration tools: `ticket-triage-demo`, `duplicate-article-demo`, and `file-organizer-demo`.
- Technical notes 0001 (`tech-notes/0001-afm-decision-model-bridging.md`) and 0002 (`tech-notes/0002-foundationmodels-generation-quirks.md`).

[0.3.0]: https://github.com/peterfriese/system-one-foundation-models/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/peterfriese/system-one-foundation-models/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/peterfriese/system-one-foundation-models/releases/tag/0.1.0
