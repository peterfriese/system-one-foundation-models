# Examples & Reference Applications 📱💻

This directory contains reference applications, production examples, and runnable command-line demos showcasing **System One decision models** integrated natively into Apple's **Foundation Models framework** (`LanguageModelSession`, `@Generable`, `@Guide`).

---

## 🧭 Demos & Reference Implementations Comparison

> ⚠️ **Strict Real Execution Mandate**: Example applications and CLI demonstrators are production-representative showcases, **not unit tests**. They **do not use mock fallbacks or synthetic bypasses**. Each application requires real credentials (e.g. `TYPESAFE_API_KEY`), running daemons (e.g. `laya-serve`), or actual emulators (e.g. Firebase Local Emulator). If a prerequisite is missing or unreachable, the application fails fast immediately with a formatted remediation banner directing you how to configure the environment. Offline mocks are strictly reserved for automated test suites in `Tests/`.

| Demo / Application | Format | Target / Backend | Prerequisites / Credentials | Primary Concepts Demonstrated |
| :--- | :--- | :--- | :---: | :--- |
| [**MailTriageApp**](MailTriageApp/README.md) | Full macOS & iOS SwiftUI App | Pluggable (Core ML, Local/Remote Laya, Clef, OpenAI, Jev Cloud, Baseline) | Optional (Keychain managed) | Flagship 3-pane email triage, 7 selectable backends, FactoryKit DI, Liquid Glass UI, urgency priority tokens, batch triage with cancellation. |
| [**LayaDemo**](LayaDemo/README.md) | CLI Executable | `LayaFoundationModels` (`POST /v1/systemone`) | `laya-serve` daemon | 100% free local evaluation against `laya-serve` on `localhost:8000` or custom endpoint. Zero cloud accounts required. |
| [**TicketTriageDemo**](TicketTriageDemo/README.md) | CLI Executable | `JevFoundationModels` | ✅ Yes (`TYPESAFE_API_KEY`) | Customer support ticket routing, RFC 9110 HTTP retry resilience (`RetryPolicy`), multi-primitive `@Generable` schema, confidence routing. |
| [**FileOrganizerDemo**](FileOrganizerDemo/README.md) | CLI Executable | `JevFoundationModels` | ✅ Yes (`TYPESAFE_API_KEY`) | Foundation Models **Dynamic Profiles**, runtime session adaptation (`@SessionPropertyEntry`), turn isolation (`.historyTransform`), sensitive file quarantine. (Requires valid API key; `--demo` generates sample file fixtures). |
| [**DuplicateArticleDemo**](DuplicateArticleDemo/README.md) | CLI Executable | `JevFoundationModels` | ✅ Yes (`TYPESAFE_API_KEY`) | Two-layer content deduplication (exact fast-path + semantic decision), calibrated Noul undecided band ($0.35\dots0.65$), cooperative Swift 6 task cancellation. (Requires valid API key for live semantic evaluation). |
| [**ClefCameraScanner**](ClefCameraScanner/README.md) | Full macOS & iOS SwiftUI App | `ClefFoundationModels` (Workers AI / Local Runner) | Optional (Local runner or `CLOUDFLARE_API_TOKEN`) | Real-time camera viewfinder, `@Observable CameraManager`, `AVCaptureVideoPreviewLayer` bridge, live visual triage, Liquid Glass HUD, simulation fallback feed. |
| [**ClefDemo**](ClefDemo/README.md) | CLI Executable | `ClefFoundationModels` (Workers AI / Local Runner) | Optional (Local runner or `CLOUDFLARE_API_TOKEN`) | Multimodal evaluation on image files or synthetic CoreGraphics visual frames, single forward-pass non-autoregressive triage, latency breakdown. |
| [**OpenAIDemo**](OpenAIDemo/README.md) | CLI Executable | `OpenAIFoundationModels` (`POST /v1/decisions`) | ✅ Yes (`OPENAI_API_KEY`) | Frontier non-autoregressive classification with `gpt-6-luna`, ~150ms latency, zero output token pricing, multi-tenant enterprise headers (`OpenAI-Organization`, `OpenAI-Project`). |
| [**TraitSamples/01-OfflineLayaApp**](TraitSamples/01-OfflineLayaApp/README.md) | Standalone Package | `LayaOnDevice` | ❌ No API key | Pure on-device classification via Apple Neural Engine (`traits: ["Laya"]`). Zero network code linked. |
| [**TraitSamples/02-CloudJevWorker**](TraitSamples/02-CloudJevWorker/README.md) | Standalone Package | `JevFoundationModels` | ✅ Yes (`TYPESAFE_API_KEY`) | Ultra-lean ticket triage worker (`traits: ["Jev"]`). Sub-second build, zero ML linkage. Fails fast if API key is missing. |
| [**TraitSamples/03-PrivateLayaServer**](TraitSamples/03-PrivateLayaServer/README.md) | Standalone Package | `LayaFoundationModels` | `laya-serve` daemon | Internal VPC cluster scoring (`traits: ["LayaServe"]`). Custom DNS, TLS, and bearer auth. Requires reachable `laya-serve`. |
| [**TraitSamples/04-HybridRouter**](TraitSamples/04-HybridRouter/README.md) | Standalone Package | Hybrid (`All`) | ✅ Yes (`TYPESAFE_API_KEY` + Core ML model) | Local-first edge execution with dynamic escalation (`traits: ["All"]`). Escalates to cloud Jev if confidence < 0.80. |
| [**TraitSamples/05-SecureAppCheckApp**](TraitSamples/05-SecureAppCheckApp/README.md) | SwiftUI Mini-App + Cloud Function | `ProxyTransport` (`Jev`) | Firebase Emulator or Cloud Function | Zero-secret hardware attestation using Firebase App Check (Apple App Attest) and `ProxyTransport`. Requires running Firebase emulator or live gateway. |

---

## 🏃 Running Each Example

### 1. MailTriageApp (Flagship Native macOS & iOS App)

A complete native application with multi-window support, Liquid Glass visual hierarchy, and 7 hot-swappable backends:

```bash
# Option A: Open directly in Xcode GUI
open Examples/MailTriageApp/apps/apple/MailTriageApp.xcodeproj

# Option B: Build & test via FlowDeck CLI
cd Examples/MailTriageApp
flowdeck build -w apps/apple/MailTriageApp.xcodeproj -s MailTriageApp
flowdeck test -w apps/apple/MailTriageApp.xcodeproj -s MailTriageApp

# Option C: Build from repository root using just
just mail-build
just mail-test
```

For complete documentation, see [Examples/MailTriageApp/README.md](MailTriageApp/README.md).

---

### 2. LayaDemo (Zero-Key Local Evaluation)

Evaluates customer inquiries against a local or remote `laya-serve` instance:

```bash
# 1. Start laya-serve in background or separate terminal
laya-serve
# (or via Docker: docker run -p 8000:8000 ghcr.io/nandhakishorm/laya:latest)

# 2. Run the demo against default sample inquiry
swift run laya-demo

# 3. Evaluate custom inquiry text from CLI
swift run laya-demo "The app crashes immediately upon opening account settings on iOS 27."

# 4. Point to custom or hosted endpoint
LAYA_ENDPOINT="http://127.0.0.1:8770/v1/systemone" swift run laya-demo "Cancel my subscription"
```

For complete documentation, see [Examples/LayaDemo/README.md](LayaDemo/README.md).

---

### 3. TicketTriageDemo (Network Resilience & Confidence Routing)

Demonstrates production network resilience and calibrated confidence routing against TypeSafe AI:

```bash
# 1. Export your API key
export TYPESAFE_API_KEY="your-api-key"

# 2. Run default billing ticket evaluation
swift run ticket-triage-demo

# 3. Evaluate custom ticket inquiry
swift run ticket-triage-demo "Production database latency spiked to 45 seconds, all checkouts failing."
```

For complete documentation, see [Examples/TicketTriageDemo/README.md](TicketTriageDemo/README.md).

---

### 4. FileOrganizerDemo (Dynamic Profiles & Session Properties)

Classifies and organizes files into semantic directories using Apple Foundation Models dynamic profiles. In strict compliance with Principle 7, real API credentials are required for decision evaluation:

```bash
# 1. Set your TypeSafe AI API key (required)
export TYPESAFE_API_KEY="your-api-key"

# 2. Run sandbox walkthrough (creates sample directory fixtures on disk for demonstration)
swift run file-organizer-demo --demo

# 3. Preview organization of an actual folder in dry-run mode
swift run file-organizer-demo --path ~/Downloads --strategy domain

# 4. Apply changes to disk using live TypeSafe AI API
swift run file-organizer-demo --path ~/Downloads --strategy workflow --apply
```

For complete documentation, see [Examples/FileOrganizerDemo/README.md](FileOrganizerDemo/README.md).

---

### 5. DuplicateArticleDemo (Two-Layer Deduplication & Cancellation)

Demonstrates two-layer content deduplication (deterministic exact-matching layer followed by semantic System One evaluation) and cooperative cancellation. Requires live API credentials:

```bash
# 1. Export your API key (required per Principle 7)
export TYPESAFE_API_KEY="your-api-key"

# 2. Run the walkthrough
swift run duplicate-article-demo
```

For complete documentation, see [Examples/DuplicateArticleDemo/README.md](DuplicateArticleDemo/README.md).

---

### 6. ClefCameraScanner (Real-Time Multimodal Camera Viewfinder App)

A production-representative native SwiftUI camera viewfinder app (iOS & macOS) for holding physical objects up to the camera and performing real-time visual inspection:

```bash
# 1. Run the camera scanner natively on macOS
swift run clef-camera-scanner

# 2. Or run with live Cloudflare Workers AI edge credentials
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_API_TOKEN="your-api-token"
swift run clef-camera-scanner
```

For complete documentation, see [Examples/ClefCameraScanner/README.md](ClefCameraScanner/README.md).

---

### 7. ClefDemo (Multimodal CLI Demonstrator)

Demonstrates single forward-pass multimodal evaluation with visual image attachments or synthetic CoreGraphics test frames:

```bash
# 1. Run against local runner with in-memory synthetic frame:
swift run clef-demo --backend local

# 2. Evaluate a physical image file (PNG, JPEG, WebP):
swift run clef-demo /path/to/product_capture.jpg

# 3. Evaluate against Cloudflare Workers AI edge:
CLOUDFLARE_ACCOUNT_ID="your-id" CLOUDFLARE_API_TOKEN="your-token" swift run clef-demo --backend workers-ai
```

For complete documentation, see [Examples/ClefDemo/README.md](ClefDemo/README.md).

---

### 8. OpenAIDemo (OpenAI Decisions API `gpt-6-luna` Demonstrator)

Demonstrates frontier non-autoregressive decision classification via OpenAI's Decisions API (`POST /v1/decisions`):

```bash
# 1. Export your OpenAI API key
export OPENAI_API_KEY="sk-..."

# 2. Run the demo against default customer ticket
swift run openai-demo

# 3. Evaluate a custom customer inquiry
swift run openai-demo "Customer reported unauthorized charge on their Visa card ending in 4112."
```

For complete documentation, see [Examples/OpenAIDemo/README.md](OpenAIDemo/README.md).

---

### 9. Trait Samples (`Examples/TraitSamples/`)

Five standalone SPM packages demonstrating fine-grained package traits and modularity:

```bash
# 1. 100% Offline ANE Classification (traits: ["Laya"])
cd Examples/TraitSamples/01-OfflineLayaApp && swift run

# 2. Cloud-Only Lean Decision Worker (traits: ["Jev"])
export TYPESAFE_API_KEY="your-api-key"
cd Examples/TraitSamples/02-CloudJevWorker && swift run

# 3. Private VPC Server Scoring (traits: ["LayaServe"])
# Ensure laya-serve daemon is running (default: http://127.0.0.1:8000/v1/systemone)
cd Examples/TraitSamples/03-PrivateLayaServer && swift run

# 4. Local-First Hybrid Confidence Router (traits: ["All"])
export TYPESAFE_API_KEY="your-api-key"
export LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc"
cd Examples/TraitSamples/04-HybridRouter && swift run

# 5. Zero-Secret Hardware-Attested App Check App (ProxyTransport)
# Start emulator first: cd Examples/TraitSamples/05-SecureAppCheckApp/backend && firebase emulators:start --only functions
cd Examples/TraitSamples/05-SecureAppCheckApp && swift run SecureAppCheckApp --cli
```
