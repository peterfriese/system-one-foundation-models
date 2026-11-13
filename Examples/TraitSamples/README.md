# Swift 6.1 Package Trait Samples (`Examples/TraitSamples/`) 🧩

`SystemOneFoundationModels` uses **Swift 6.1 Package Traits ([SE-0402](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0402-extension-macros.md))** so downstream apps, microservices, and CLI tools compile **only** the System One provider targets they actually deploy—eliminating unused Core ML engines from cloud workers and stripping HTTP client code from air-gapped on-device apps.

Each directory below (`01` through `09`) is a standalone Swift package with its own `Package.swift` and `#if canImport(...)` compile-time assertions verifying exact target isolation.

---

## 🧭 All 9 Trait Samples at a Glance

| # | Sample Package | `traits:` in `Package.swift` | Compiled Provider Target(s) | Excluded Targets | Required Runtime Prerequisite |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **01** | [**`01-OfflineLayaApp`**](01-OfflineLayaApp/README.md) | `["Laya"]` *(or `["OnDevice"]`)* | `LayaOnDevice` | All 5 HTTP providers | `LAYA_MODEL_PATH` (`.mlmodelc`) |
| **02** | [**`02-CloudJevWorker`**](02-CloudJevWorker/README.md) | `["Jev"]` | `JevFoundationModels` | `LayaOnDevice` + 4 other cloud SDKs | `TYPESAFE_API_KEY` |
| **03** | [**`03-PrivateLayaServer`**](03-PrivateLayaServer/README.md) | `["LayaServe"]` | `LayaFoundationModels` | `LayaOnDevice` + 4 other cloud SDKs | `laya-serve` (`LAYA_SERVE_URL`) |
| **04** | [**`04-HybridRouter`**](04-HybridRouter/README.md) | `["All"]` | All 6 Providers | None | `LAYA_MODEL_PATH` + any 1 cloud credential |
| **05** | [**`05-SecureAppCheckApp`**](05-SecureAppCheckApp/README.md) | `["Remote"]` | All 5 Remote Providers + `ProxyCredential` | `LayaOnDevice` (zero Core ML weight) | Firebase Local Emulator (`./run-emulator-and-cli.sh --provider <name>`) or Cloud Function |
| **06** | [**`06-EdgeClefVision`**](06-EdgeClefVision/README.md) | `["Clef"]` | `ClefFoundationModels` | `LayaOnDevice` + 4 other cloud SDKs | `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN` or local runner |
| **07** | [**`07-CloudOpenAIDecisions`**](07-CloudOpenAIDecisions/README.md) | `["OpenAI"]` | `OpenAIFoundationModels` | `LayaOnDevice` + 4 other cloud SDKs | `OPENAI_API_KEY` |
| **08** | [**`08-CloudGeminiDecisions`**](08-CloudGeminiDecisions/README.md) | `["Gemini"]` | `GeminiFoundationModels` | `LayaOnDevice` + 4 other cloud SDKs | `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) |
| **09** | [**`09-RemotePersonaRouter`**](09-RemotePersonaRouter/README.md) | `["Remote"]` | `Jev`, `LayaServe`, `Clef`, `OpenAI`, `Gemini` | `LayaOnDevice` (zero Core ML weight) | Any 1 remote provider key or `SYSTEM_ONE_PROXY_URL` |

---

## 🔬 How Trait Isolation Is Verified

Every sample includes compile-time `#if canImport(...)` guards in `Sources/main.swift`. For example, `09-RemotePersonaRouter` proves at compile time that `LayaOnDevice` is excluded while all 5 networked modules are exported:

```swift
#if canImport(LayaOnDevice)
#error("LayaOnDevice must NOT be compiled when building with the 'Remote' persona trait!")
#endif

#if !(canImport(JevFoundationModels) && canImport(LayaFoundationModels) && canImport(ClefFoundationModels) && canImport(OpenAIFoundationModels) && canImport(GeminiFoundationModels))
#error("Expected all 5 remote System One providers under 'Remote' trait!")
#endif
```

---

## 🚀 Building & Running Any Trait Sample

Build any sample offline to verify isolated compilation, or export its prerequisite environment variable to run live evaluation:

```bash
# Compile-check isolated binary graph (zero credentials required to build):
swift build --package-path Examples/TraitSamples/08-CloudGeminiDecisions
swift build --package-path Examples/TraitSamples/09-RemotePersonaRouter

# Run live evaluation:
GEMINI_API_KEY="AIza..." swift run --package-path Examples/TraitSamples/08-CloudGeminiDecisions
```

> [!IMPORTANT]
> **Principle 7 (Zero Mock Fallbacks)**: Running a sample without its required model or credential prints a clear remediation banner and exits immediately with status `1`.
