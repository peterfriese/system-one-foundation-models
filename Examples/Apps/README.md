# Native SwiftUI Reference Applications (`Examples/Apps/`) 📱🖥️

`Examples/Apps/` contains **3 production-grade SwiftUI reference applications** built with Swift 6 strict concurrency (`@Observable`, `@MainActor`, actor-isolated services), Apple **Liquid Glass** design, and hot-swappable System One execution backends.

> [!IMPORTANT]
> **Zero Mock Fallbacks (Principle 7)** & **Zero Embedded Secrets**: Reference apps never substitute fake synthetic evaluations when an API key or Core ML model is missing. Credentials are stored exclusively in the Apple Data Protection Keychain or routed through hardware-attested reverse proxies (`ProxyCredential`).

---

## 🧭 Side-by-Side Application Matrix

| Feature / Provider | [**MailTriageApp**](MailTriageApp/README.md) | [**VisionScannerApp**](VisionScannerApp/README.md) | [**NutritionLabelScannerApp**](NutritionLabelScannerApp/README.md) |
| :--- | :---: | :---: | :---: |
| **Platforms** | macOS 27+ & iOS 27+ | macOS 27+ & iOS 27+ (`vision-scanner-app`) | iOS 27+ |
| **Primary Modality** | Text (Inbox & Batch Email Triage) | Live Camera + Photo Vision | Barcode + Vision OCR + Packaging Vision |
| **`LayaOnDevice` (Core ML / ANE)** | ✅ | — *(text-only)* | ✅ *(OCR text mode)* |
| **`LayaFoundationModels` (`laya-serve`)** | ✅ | — *(text-only)* | ✅ *(OCR text mode)* |
| **`JevFoundationModels` (TypeSafe Cloud)** | ✅ | — *(text-only)* | ✅ *(OCR text mode)* |
| **`ClefFoundationModels` (Clef 9B/27B)** | ✅ | ✅ | ✅ *(Vision + OCR)* |
| **`OpenAIFoundationModels` (`gpt-6-luna`)** | ✅ | ✅ | ✅ *(Vision + OCR)* |
| **`GeminiFoundationModels` (`gemini-decision-1`)** | ✅ | ✅ | ✅ *(Vision + OCR)* |
| **Authenticated Proxy (`ProxyCredential`)** | ✅ | ✅ | ✅ |
| **Apple Generative Baseline (`SystemLanguageModel`)** | ✅ *(benchmark comparison)* | — | — |

---

## 📱 Application Summaries & Build Commands

### 1. [`MailTriageApp`](MailTriageApp/README.md) — Multi-Backend Inbox Triage & 500-Email Benchmark Suite
3-pane split-view email client (`AppCore` + `AppUI` modular Swift packages with FactoryKit DI) comparing calibrated System One backends head-to-head against Apple's on-device autoregressive baseline across latency, token usage, and ground-truth accuracy.

```bash
# Build app via FlowDeck:
flowdeck build -w Examples/Apps/MailTriageApp/apps/apple/MailTriageApp.xcodeproj -s MailTriageApp -S "iPhone 18 Pro"

# Run AppCore & AppUI package test suites:
flowdeck test -p Examples/Apps/MailTriageApp/apps/apple/Packages/AppCore -s AppCore-Package -S "iPhone 18 Pro"
flowdeck test -p Examples/Apps/MailTriageApp/apps/apple/Packages/AppUI -s AppUI -S "iPhone 18 Pro"
```

### 2. [`VisionScannerApp`](VisionScannerApp/README.md) — Live Multimodal Camera & Photo Inspector
Real-time AVFoundation camera viewfinder (with native `PhotosPicker` / `.fileImporter` support on Simulator and headless Macs) evaluating `@Generable VisualInspectionDecision` across **Cloudflare Clef**, **OpenAI Decisions (`gpt-6-luna`)**, **Google Gemini Decisions (`gemini-decision-1`)**, and **Authenticated Proxy** gateways with Liquid Glass HUD telemetry.

```bash
# Run macOS executable directly from root Package.swift:
swift run vision-scanner-app

# Or build the Xcode project via FlowDeck:
flowdeck build -w Examples/Apps/VisionScannerApp/VisionScannerApp.xcodeproj -s VisionScannerApp -S "iPhone 18 Pro"
```

### 3. [`NutritionLabelScannerApp`](NutritionLabelScannerApp/README.md) — Dietary Safety & Allergen Triage
Camera-first iOS 27+ app combining live EAN/UPC barcode scanning (Open Food Facts), on-device Apple Vision nutrition label OCR, and multimodal packaging inspection across 5 dietary profiles (Peanut Allergy, Celiac Gluten-Free, Vegan, Low-Sodium, Keto) and all 6 System One providers + Proxy.

```bash
flowdeck build -w Examples/Apps/NutritionLabelScannerApp/NutritionLabelScanner.xcodeproj -s NutritionLabelScanner -S "iPhone 18 Pro"
```
