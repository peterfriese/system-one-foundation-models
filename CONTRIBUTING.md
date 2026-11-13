# Contributing to System One for Apple Foundation Models 🤝⚡️

Thank you for your interest in contributing to **System One for Apple Foundation Models**! We welcome community contributions, bug reports, feature proposals, documentation improvements, and architectural feedback.

This guide outlines our development workflow, engineering standards, offline testing philosophy, and contribution protocol.

---

## 🛠️ Prerequisites & Local Setup

### System Requirements
- **macOS**: macOS Sonoma 14.0+ (macOS 15.0+ or 27.0+ recommended for complete Apple Intelligence simulation)
- **Xcode**: Xcode 27.0+ or Swift 6.0+ toolchain
- **Git**: Configured for your GitHub account

### Recommended Optional Tooling
- **[`just`](https://github.com/casey/just)**: Command runner used for standardized build and test tasks.
  ```bash
  brew install just
  ```
- **[`flowdeck`](https://flowdeck.dev)**: Structured CLI for Apple platform builds, simulator orchestration, and automated test execution.
  ```bash
  # Check if flowdeck is available on your PATH
  flowdeck --version
  ```

---

## 🧪 Deterministic Offline-First Testing

We maintain a strict mandate that **all core package unit tests must run 100% offline with zero external network access and zero API keys required**.

Run the complete test suite from your terminal:

```bash
# Standard Swift Package Manager test run (all 7 test targets)
swift test

# Or via just
just test

# Run an individual test target
swift test --filter SystemOneCoreTests
swift test --filter JevFoundationModelsTests
swift test --filter LayaFoundationModelsTests
swift test --filter LayaOnDeviceTests
swift test --filter ClefFoundationModelsTests
swift test --filter OpenAIFoundationModelsTests
swift test --filter GeminiFoundationModelsTests
```

### Core Package Test Targets (7 Suites)
| Test Target | Module Under Test | Coverage Scope |
| :--- | :--- | :--- |
| `SystemOneCoreTests` | `SystemOneCore` | `SchemaTranslator`, `ResponseSynthesizer`, `SystemOneExecutor`, `ProxyCredential`, `ProxyEndpointValidator`, `SystemOneProxyBackend`, `SystemOneImage`, `RoutingPolicy`, `RetryPolicy`, and `.probability` / `.choice` / `.score` shortcuts. |
| `JevFoundationModelsTests` | `JevFoundationModels` | `JevLanguageModel`, `JevEndpoint`, `JevClient`, `URLSessionTransport` & `ProxyTransport` retries/cancellation, and `MockJevTransport` / `MockSystemOneBackend` conformance. |
| `LayaFoundationModelsTests` | `LayaFoundationModels` | `LayaLanguageModel`, `LayaEndpoint` URL validation, `LayaHTTPBackend` retry/error handling, `ProxyCredential`, and `LAYA_SERVE_URL` resolution. |
| `LayaOnDeviceTests` | `LayaOnDevice` | `LayaCoreMLEngine` fixed-shape `[1, 512]` tensor padding, `ModernBERTTokenizer`, `MMBERTTokenizer` (WordPiece & SentencePiece Unigram), and `TemperatureCalibration`. |
| `ClefFoundationModelsTests` | `ClefFoundationModels` | `ClefLanguageModel`, `ClefEndpoint` catalog/body decoupling, Client API v4 dual-decoding, 1024px JPEG attachment scaling, `ProxyCredential`, and multimodal evaluation. |
| `OpenAIFoundationModelsTests` | `OpenAIFoundationModels` | `OpenAIDecisionsLanguageModel` (`OpenAILanguageModel`), `OpenAIDecisionsPayloadAdapter` (`predicate`/`choice`/`score` 0-based & 1-based alignment), enterprise headers, `ProxyCredential`, and multimodal Data URL guardrails. |
| `GeminiFoundationModelsTests` | `GeminiFoundationModels` | `GeminiDecisionsLanguageModel` (`GeminiLanguageModel`), `GeminiDecisionsPayloadAdapter` dictionary-keyed `noul`/`choice`/`score` wire mapping, flat typed multimodal Base64 `input` blocks, `x-goog-api-key` & `ProxyCredential` auth, and `x-goog-processing-ms` timing. |

### Testing Guidelines
- **Use Swift Testing**: Write modern Swift Testing suites (`@Suite`, `@Test`, `#expect(...)`) rather than legacy `XCTest`.
- **Never Depend on Live Network in Core Tests**: Inject `MockSystemOneBackend` (accepted via `init(backend:)` on all 6 providers and `SystemOneLanguageModel`) or `MockJevTransport` to test protocol encoding, error states, and response synthesis offline.
- **Opt-in Live Integration Tests**: Tests that hit live endpoints (such as `api.typesafe.ai`) must conditionally check for environment variables (e.g. `TYPESAFE_API_KEY`) and skip cleanly via `@Test(.enabled(if: ...))` when credentials are absent.

### Running App and UI Tests
To test the reference applications in `Examples/Apps/` (`MailTriageApp`, `VisionScannerApp`, `NutritionLabelScannerApp`) on iOS Simulator (FlowDeck 1.26.5+) or macOS:

```bash
# Build MailTriageApp via FlowDeck
flowdeck build -w Examples/Apps/MailTriageApp/apps/apple/MailTriageApp.xcodeproj -s MailTriageApp -S "iPhone 18 Pro"

# Run AppCore & AppUI package tests on iOS Simulator via FlowDeck 1.26.5+
flowdeck test -p Examples/Apps/MailTriageApp/apps/apple/Packages/AppCore -s AppCore-Package -S "iPhone 18 Pro"
flowdeck test -p Examples/Apps/MailTriageApp/apps/apple/Packages/AppUI -s AppUI -S "iPhone 18 Pro"

# Run fast macOS package unit tests directly via SwiftPM
swift test --package-path Examples/Apps/MailTriageApp/apps/apple/Packages/AppCore
swift test --package-path Examples/Apps/MailTriageApp/apps/apple/Packages/AppUI
```

---

## 🏛️ Architecture & Coding Standards

When authoring or refactoring code in `Sources/` or `Examples/`:

### 1. Apple-Native Foundation Models Ergonomics
- The primary developer experience must use standard Apple Foundation Models APIs:
  ```swift
  let session = LanguageModelSession(model: JevLanguageModel(apiKey: "..."))
  let response = try await session.respond(to: stateText, generating: MyDecision.self)
  ```
- No proprietary wrapper syntax or non-standard session classes. Conformance to Apple's `LanguageModel` and `LanguageModelExecutor` protocols is mandatory.

### 2. Swift 6 Complete Concurrency & Sendability
- The package compiles with `-strict-concurrency=complete`.
- All shared types must naturally conform to `Sendable`.
- Avoid `@unchecked Sendable` unless wrapping proven thread-safe primitives (such as read-only Objective-C Core ML interfaces), and include explicit comments explaining the safety guarantee.
- Mutable state in apps and engines must be isolated to Swift actors (e.g. `MailStore`, `KeychainService`).
- Never introduce blocking operations (`sleep()`, synchronous semaphore waits) into async contexts.

### 3. Zero External Third-Party Runtime Dependencies in Core
- All core library targets (`SystemOneCore`, `SystemOneFoundationModels`, `LayaOnDevice`, `LayaFoundationModels`, `JevFoundationModels`, `ClefFoundationModels`, `OpenAIFoundationModels`, `GeminiFoundationModels`) must remain **zero-dependency**.
- Use native `URLSession`, `JSONDecoder`, and `JSONSerialization` for networking and serialization. Do not introduce third-party HTTP clients.
- If integrating with third-party vendor SDKs (e.g. Firebase App Check), distribute the integration as a standalone example or drop-in file (see `Integrations/FirebaseAppCheckProxy/`).

### 4. SwiftUI Best Practices (for Reference Apps)
- Use SwiftUI's modern `@Observable` macro. Do **not** use legacy `ObservableObject` or `@Published`.
- Use FactoryKit dependency injection (`Container.shared.*`) with `@ObservationIgnored @Injected`.
- Design call-site first with progressive disclosure.

---

## 📝 Tech Note Protocol (`tech-notes/`)

Whenever you discover an Apple Foundation Models SDK quirk, undocumented runtime behavior, serialization nuance, or platform restriction during your contribution, document it in `tech-notes/`:

### 1. File Naming & Numbering
- Assign the next sequential integer (`max + 1`):
  ```text
  tech-notes/NNNN-kebab-cased-title.md
  # Example: tech-notes/0009-dynamic-schema-guidelines.md
  ```

### 2. Standard Structure
Every Tech Note must follow this template:
```markdown
# NNNN — Short Descriptive Title

- **Date**: YYYY-MM-DD
- **Author**: Your Name
- **Framework**: `FoundationModels` / `CoreML` / etc.
- **Upstream**: Link to upstream repo or Apple documentation

---

## Context
Brief explanation of what problem was being solved or explored.

## Findings
Technical explanation, root cause analysis, and code samples.

## Implications
How this affects library design, workarounds implemented, and recommendations.

## Evidence / Sources
Links, test cases, or compiler diagnostics proving the finding.
```

### 3. Index & Cross-Referencing
- Always append the new Tech Note to the table in [`tech-notes/README.md`](tech-notes/README.md).
- Reference the Tech Note in code comments where relevant:
  ```swift
  // See tech-notes/0008-on-device-coreml-decision-engine.md
  ```

---

## 🚀 Submitting a Pull Request

1. **Fork & Branch**: Create a feature branch from `main`:
   ```bash
   git checkout -b feature/my-enhancement
   ```
2. **Verify Tests**: Ensure all tests compile and pass cleanly:
   ```bash
   swift test
   ```
3. **Format & Clean**: Keep git history clean with descriptive commit messages.
4. **Open a PR**: Submit a Pull Request targeting `main`. Describe the motivation, changes made, and any related issues or Tech Notes.

Thank you for helping push the frontier of native System One decision intelligence on Apple platforms! 🚀
