# 09-RemotePersonaRouter: Multi-Cloud `'Remote'` Persona (`traits: ["Remote"]`)

Demonstrates the aggregate **`Remote`** persona trait in `SystemOneFoundationModels`—purpose-built for server-side Swift services, thin iOS/macOS clients, and multi-cloud routers that want **every networked System One provider** (`Jev`, `LayaServe`, `Clef`, `OpenAI`, `Gemini`, plus `SystemOneProxyBackend`) while **excluding Core ML (`LayaOnDevice`)** at compile time.

---

## 📦 Package Manifest & Compile-Time Proofs

```swift
dependencies: [
    .package(name: "SystemOneFoundationModels", path: "../../..", traits: ["Remote"])
]
```

`Sources/main.swift` enforces two compile-time assertions:
1. `#if canImport(LayaOnDevice)` triggers `#error(...)` — proving zero Core ML / ANE binary weight is linked.
2. `#if !(canImport(JevFoundationModels) && canImport(LayaFoundationModels) && canImport(ClefFoundationModels) && canImport(OpenAIFoundationModels) && canImport(GeminiFoundationModels))` verifies all 5 networked provider modules are active.

---

## ⚙️ Supported Remote Backends (Auto-Resolved)

Evaluates `@Generable struct IncidentRoutingDecision` (`isProductionIncident: Bool`, `queue: EscalationQueue`, `severityLevel: Int` in `0...3`) against whichever remote backend you configure:

| Environment Variable(s) | Selected Provider |
| :--- | :--- |
| `SYSTEM_ONE_PROXY_URL` (+ optional `SYSTEM_ONE_PROXY_TOKEN`) | `SystemOneLanguageModel` (`SystemOneProxyBackend` + `ProxyCredential`) |
| `TYPESAFE_API_KEY` | `JevLanguageModel` (TypeSafe Cloud) |
| `GEMINI_API_KEY` / `GOOGLE_API_KEY` | `GeminiLanguageModel` (`gemini-decision-1`) |
| `OPENAI_API_KEY` | `OpenAILanguageModel` (`gpt-6-luna`) |
| `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN` | `ClefLanguageModel` (`clef-flash`) |
| `LAYA_SERVE_URL` (+ optional `LAYA_API_KEY`) | `LayaLanguageModel` (`laya-serve`) |

---

## 🚀 Running the Sample

```bash
export GEMINI_API_KEY="AIza..."   # or any credential from the table above
swift run --package-path Examples/TraitSamples/09-RemotePersonaRouter
```
