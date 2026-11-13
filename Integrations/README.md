# Production Proxy & Gateway Integrations (`Integrations/`) 🔒☁️

Because client-side Apple binaries (iOS, iPadOS, macOS, visionOS) can be inspected or network-proxied, **upstream API keys (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `TYPESAFE_API_KEY`) must never be embedded in shipped client apps**.

Meanwhile, the core `SystemOneFoundationModels` Swift package maintains **zero external third-party runtime dependencies** ([Tech Note 0005](../tech-notes/0005-spm-dependency-isolation-and-vendor-transports.md)). To give developers turnkey security without bloating `Package.swift`, `SystemOneCore` provides closure-injected **`ProxyCredential`** & **`SystemOneProxyBackend`**, while `Integrations/` hosts ready-to-deploy multi-provider server gateway templates and optional vendor helpers.

---

## 🗂️ Available Integrations

| Directory | Stack | Purpose |
| :--- | :--- | :--- |
| [**`FirebaseAppCheckProxy/`**](FirebaseAppCheckProxy/README.md) | Firebase Cloud Functions (2nd Gen, TypeScript) + Apple App Attest | SSRF-safe multi-provider reverse proxy supporting **all 5 networked providers** (`jev`, `laya`, `clef`, `openai`, `gemini`) across **Pattern A** (native wire passthrough) and **Pattern B** (`SystemOneRequest` canonical wire adaptation + Cloudflare `{ result }` unwrapping), replay-protected `limitedUseToken()` consumption, configurable `ENABLED_SECRETS`, automated `node --test` unit tests, and drop-in [`FirebaseAppCheckTransport.swift`](FirebaseAppCheckProxy/FirebaseAppCheckTransport.swift) (`ProxyCredential.firebaseAppCheck(strategy:)`). |

---

## ⚡ Recommended Swift Client Pattern (`ProxyCredential`)

All **5** networked providers (`GeminiLanguageModel`, `OpenAILanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, `JevLanguageModel`) plus vendor-agnostic `SystemOneLanguageModel` natively accept `ProxyCredential`:

```swift
import FirebaseAppCheck
import FoundationModels
import GeminiFoundationModels // or OpenAI / Clef / Laya / Jev / SystemOneCore

let proxyBase = URL(string: "https://us-central1-my-project.cloudfunctions.net/systemone")!

// Zero-dependency closure from SystemOneCore (or .firebaseAppCheck(strategy:) if copying FirebaseAppCheckTransport.swift):
let model = GeminiLanguageModel(
    proxyEndpoint: proxyBase.appending(path: "gemini"),
    credential: .appCheck {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
let session = LanguageModelSession(model: model)
```

---

## 🔗 Related Guides & End-to-End Samples

- [**Mobile Security Guide (`docs/mobile-security.md`)**](../docs/mobile-security.md) — Threat model, multi-provider Cloud Function routing, replay protection (`alreadyConsumed` + `limitedUseToken()`), rate-limiting best practices, and latency profiles.
- [**`05-SecureAppCheckApp` (`Examples/TraitSamples/05-SecureAppCheckApp/`)**](../Examples/TraitSamples/05-SecureAppCheckApp/README.md) — Runnable multi-provider SwiftUI + CLI showcase (`--provider jev|laya|clef|openai|gemini|gateway`) with automated local Firebase Emulator scripts (`./run-emulator-and-cli.sh`).
- [**ADR-2026-11-12-01**](../docs/architecture/ADR-2026-11-12-01-universal-proxy-credentials.md) & [**Tech Note 0010**](../tech-notes/0010-proxy-transport-and-dynamic-attestation.md).
