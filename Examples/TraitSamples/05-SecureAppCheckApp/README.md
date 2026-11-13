# 05-SecureAppCheckApp: Multi-Provider Hardware-Attested Gateway (`traits: ["Remote"]`)

This sample demonstrates securing mobile and desktop System One evaluations across **all 5 remote providers** (`jev`, `laya`, `clef`, `openai`, `gemini`) plus the **Provider-Agnostic Gateway** (`SystemOneLanguageModel`) using **`ProxyCredential.appCheck`**, **`ProxyEndpointValidator`**, **Firebase App Check (Apple App Attest)**, and a multi-provider **Firebase 2nd Gen Cloud Function** reverse proxy.

Upstream API keys (`TYPESAFE_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `LAYA_API_KEY`) are **never bundled in client binaries**; requests attach a per-attempt `X-Firebase-AppCheck` header and are verified by the gateway before forwarding or adapting upstream.

---

## 📦 SPM Trait Configuration & Client Call Sites

Links `traits: ["Remote"]` (`JevFoundationModels`, `LayaFoundationModels`, `ClefFoundationModels`, `OpenAIFoundationModels`, `GeminiFoundationModels`, and `SystemOneCore` — zero Core ML weight and zero Firebase SDK dependency in package core):

```swift
// Pattern A: Provider-native wire passthrough (/systemone/<jev|laya|clef|openai|gemini>)
let geminiEndpoint = try environment.endpoint(projectID: projectID, provider: .gemini)
let geminiModel = GeminiLanguageModel(
    proxyEndpoint: geminiEndpoint,
    credential: .appCheck { appCheckToken }
)

// Pattern B: Provider-agnostic canonical gateway (/systemone -> server adapts to DEFAULT_PROVIDER)
let gatewayEndpoint = try environment.endpoint(projectID: projectID, provider: .gateway)
let gatewayModel = SystemOneLanguageModel(
    proxyEndpoint: gatewayEndpoint,
    credential: .appCheck { appCheckToken }
)

let session = LanguageModelSession(model: geminiModel)
let choice = try await session.choice(
    "Classify the incoming alert to determine response protocol",
    from: SecureTriageCategory.self,
    state: inputText
)
```

```text
┌───────────────────────────────────────────────────────────┐
│  SwiftUI / CLI Client (SecureTriageView / App.swift)      │
│  • Pattern A: <Provider>LanguageModel(.../systemone/<id>) │
│  • Pattern B: SystemOneLanguageModel(.../systemone)       │
└─────────────────────────────┬─────────────────────────────┘
                              │ HTTPS POST + X-Firebase-AppCheck
                              ▼
┌───────────────────────────────────────────────────────────┐
│  Firebase 2nd Gen Cloud Function (systemone / jevProxy)   │
│  1. Verifies X-Firebase-AppCheck token                    │
│  2. SSRF-safe routing (jev | laya | clef | openai | gemini│
│  3. Passthrough (Pattern A) or wire adapter (Pattern B)   │
│  4. Injects server secret from env / Secret Manager       │
└─────────────────────────────┬─────────────────────────────┘
                              │
                              ▼
┌───────────────────────────────────────────────────────────┐
│  Allowlisted Upstream Decision API                        │
│  TypeSafe Jev • Laya • Cloudflare Clef • OpenAI • Gemini  │
└───────────────────────────────────────────────────────────┘
```

---

## 🚀 Quickstart: Local Firebase Emulator Suite

Per Principle 7, synthetic mock bypasses are prohibited; if the local Firebase Emulator is unreachable on port `5001` or the selected provider's upstream secret is unconfigured, CLI execution prints a remediation banner and exits with code `1`.

### Option A: Single Command (Start Emulator, Run CLI & Tear Down)

```bash
cd Examples/TraitSamples/05-SecureAppCheckApp

# Evaluate via TypeSafe Jev (default), Google Gemini, OpenAI, Clef, Laya, or Pattern B Gateway:
TYPESAFE_API_KEY="ts_..."  ./run-emulator-and-cli.sh --provider jev
GEMINI_API_KEY="AIza..."   ./run-emulator-and-cli.sh --provider gemini
OPENAI_API_KEY="sk-..."    ./run-emulator-and-cli.sh --provider openai
DEFAULT_PROVIDER="gemini" GEMINI_API_KEY="AIza..." ./run-emulator-and-cli.sh --provider gateway
```

### Option B: Interactive SwiftUI App + Running Emulator

```bash
# Terminal 1: Start Firebase Functions & App Check emulators (ports 5001 & 9099)
cd Examples/TraitSamples/05-SecureAppCheckApp/backend
firebase emulators:start --only functions,appCheck

# Terminal 2: Launch the SwiftUI macOS app (pick any provider in the UI) or run --cli
cd Examples/TraitSamples/05-SecureAppCheckApp
swift run SecureAppCheckApp
# Or CLI mode:
swift run SecureAppCheckApp --cli --emulator --provider gemini
```

### Option C: Build Native Xcode 27.2 JSON Project (`.xcproj`) via FlowDeck

```bash
flowdeck build -w Examples/TraitSamples/05-SecureAppCheckApp/SecureAppCheckApp.xcodeproj -s SecureAppCheckApp -S "iPhone 18 Pro" --show-warnings
```

---

## 🌐 Production Cloud Deployment

1. Run the setup script in `backend/` or configure only the secrets your deployment uses (`ENABLED_SECRETS` in `backend/functions/.env`):
   ```bash
   cd Examples/TraitSamples/05-SecureAppCheckApp/backend
   ./setup-firebase-project.sh
   ```
2. Register your Apple Team ID and App Attest provider following [`backend/SETUP-PRODUCTION.md`](backend/SETUP-PRODUCTION.md), [`Integrations/FirebaseAppCheckProxy/README.md`](../../../Integrations/FirebaseAppCheckProxy/README.md), and the [**Mobile Security Guide**](../../../docs/mobile-security.md).
3. Switch **Target Environment** to **Production Cloud Functions** (or pass `--cli --live --provider <name>`).
