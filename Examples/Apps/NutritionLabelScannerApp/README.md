# NutritionLabelScannerApp 🥗📷⚡️

`NutritionLabelScannerApp` is a native iOS 27+ SwiftUI application that combines **AVFoundation** live camera scanning, **Apple Vision** barcode + on-device Nutrition Facts OCR, **Open Food Facts** barcode lookup, and **all 6 System One providers + Authenticated Reverse Proxy** through Apple's **Foundation Models framework** (`LanguageModelSession`, `Prompt`, `Attachment`, `@Generable`, `@Guide`).

Point your iPhone camera at any packaged grocery barcode or Nutrition Facts / ingredient panel (or pick a label photo via `PhotosPicker`) to evaluate allergen risk, NOVA ultra-processing tier, and dietary compliance with calibrated probabilities.

---

## 🌟 All 7 Supported System One Modes

Switch providers live from the camera viewfinder pill, the Nutrition Sheet header, or the **System One Providers** settings sheet:

1. **On-Device Laya Core ML (Offline)** (`LayaOnDeviceLanguageModel` via `LAYA_MODEL_PATH`, imported `.mlmodelc` / `.mlpackage`, or bundled `LayaDecisionModel.mlmodelc`)
2. **Local Laya Server (`laya-serve`)** (`LayaLanguageModel` via `LAYA_SERVE_URL` / `http://127.0.0.1:8000`)
3. **TypeSafe Jev Cloud** (`JevLanguageModel` via `TYPESAFE_API_KEY`)
4. **Cloudflare Clef (Vision)** (`ClefLanguageModel` via `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN` or `CLEF_LOCAL_PORT`)
5. **OpenAI Decisions (`gpt-6-luna`, Vision)** (`OpenAIDecisionsLanguageModel` via `OPENAI_API_KEY`)
6. **Google Gemini Decisions (`gemini-decision-1`, Vision)** (`GeminiDecisionsLanguageModel` via `GEMINI_API_KEY` / `GOOGLE_API_KEY`)
7. **Authenticated Reverse Proxy** (`SystemOneLanguageModel(proxyEndpoint:credential:supportsVision:)` via `SYSTEM_ONE_PROXY_URL` / `TYPESAFE_PROXY_URL`)

### Multimodal Vision Enhancement
When a vision-capable provider (`Clef`, `OpenAI`, `Gemini`, or vision-enabled `Reverse Proxy`) is active and a nutrition label photo or camera frame (`CGImage`) was captured, `ScannerViewModel` automatically builds a multimodal `Prompt`:

```swift
let attachment = Attachment(cgImage)
let prompt = Prompt {
    state
    attachment
}
let response = try await session.respond(to: prompt, generating: DietarySafetyDecision.self)
```

---

## 🔐 Configuring Credentials & Models (Principle 7)

> [!WARNING]
> **Never Embed Cloud API Keys in Shipping Mobile Binaries**
> Use API keys only during local Xcode Simulator or personal device debugging. For TestFlight and App Store builds, use **On-Device Laya Core ML** or **Authenticated Reverse Proxy** (`SYSTEM_ONE_PROXY_URL` + Firebase App Check / Bearer token).

```bash
# 1. On-Device Laya Core ML (Offline)
LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc"

# 2. Local Laya Server (laya-serve)
LAYA_SERVE_URL="http://127.0.0.1:8000"

# 3. TypeSafe Jev Cloud
TYPESAFE_API_KEY="ts-..."

# 4. Cloudflare Clef
CLOUDFLARE_ACCOUNT_ID="your-account-id"
CLOUDFLARE_API_TOKEN="your-workers-ai-token"

# 5. OpenAI Decisions (gpt-6-luna)
OPENAI_API_KEY="sk-..."

# 6. Google Gemini Decisions (gemini-decision-1)
GEMINI_API_KEY="AIza..."

# 7. Authenticated Reverse Proxy (Zero-Secret Production)
SYSTEM_ONE_PROXY_URL="https://your-gateway.example.com/v1/systemone"
FIREBASE_APPCHECK_TOKEN="optional-appcheck-token"
# or SYSTEM_ONE_PROXY_TOKEN="optional-bearer-token"
```

---

## 🏛️ Architecture & Code Layout

```text
Examples/Apps/NutritionLabelScannerApp/
├── NutritionLabelScanner.xcodeproj         # Native iOS 27.0+ Xcode project (Swift 6)
└── Sources/
    ├── NutritionLabelScannerApp.swift      # @main SwiftUI App entrypoint
    ├── Models/
    │   ├── DietaryProfile.swift            # 5 dietary restriction personas & prompt guidance
    │   ├── DietarySafetyDecision.swift     # @Generable DietarySafetyDecision & DietaryFlag
    │   └── FoodProduct.swift               # NutritionFacts & formatted System One state builder
    ├── Services/
    │   ├── AudioFeedback.swift             # Haptic & system audio scan feedback
    │   ├── CameraScannerService.swift      # AVFoundation capture + Vision OCR + CGImage frame snapshot
    │   ├── KeychainStorage.swift           # Secure Keychain storage for in-app provider API keys
    │   ├── NutritionLabelParser.swift      # Spatial Vision parser for Nutrition Facts & allergens
    │   ├── OpenFoodFactsClient.swift       # Async barcode metadata lookup via URLSession
    │   ├── ProviderResolution.swift        # All 7 System One modes + Principle 7 fail-fast validation
    │   └── ScannerViewModel.swift          # @MainActor @Observable coordinator & multimodal LanguageModelSession
    └── Views/
        ├── NutritionScannerAppView.swift
        ├── CameraViewfinderView.swift
        ├── CameraPreviewView.swift
        ├── ProviderSettingsSheetView.swift
        ├── SafetyIndicatorBanner.swift
        ├── NutritionSheetView.swift
        └── NutritionTableView.swift
```

---

## 🛠️ Building & Running via FlowDeck CLI

```bash
flowdeck build \
  -w Examples/Apps/NutritionLabelScannerApp/NutritionLabelScanner.xcodeproj \
  -s NutritionLabelScanner \
  -S "iPhone 18 Pro Max" \
  --show-warnings
```
