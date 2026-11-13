# VisionScannerApp (Multi-Provider Multimodal Decision Scanner) 📱📷

A cross-platform (iOS 27+ & macOS 27+) SwiftUI reference application that evaluates live camera frames and real imported photographs across **all vision-capable System One providers** and **authenticated reverse proxies** through Apple's **Foundation Models framework** (`LanguageModelSession`, `Prompt`, `Attachment`, `@Generable`).

---

## 🌟 Supported Multimodal Vision Backends

Switch live in the HUD picker to compare latency, calibrated probabilities, and ordinal condition scores on the **exact same camera frame or imported photo**:

1. **Cloudflare Clef-Flash (9B)** (`ClefLanguageModel`, Workers AI / AI Gateway)
2. **Cloudflare Clef (27B)** (`ClefLanguageModel`, Workers AI / AI Gateway)
3. **Local Clef Runner (`localhost:8000`)** (`ClefLanguageModel`, local server / Docker / MLX)
4. **OpenAI Decisions (`gpt-6-luna`)** (`OpenAIDecisionsLanguageModel`, native multimodal decisions)
5. **Google Gemini Decisions (`gemini-decision-1`)** (`GeminiDecisionsLanguageModel`, native multimodal decisions)
6. **Authenticated Reverse Proxy** (`SystemOneLanguageModel(proxyEndpoint:credential:supportsVision: true)`, App Check / Bearer zero-secret gateway)

---

## 🏛️ Architectural Highlights

### 1. Pure Apple Foundation Models Multimodal Ergonomics
Evaluates live `CGImage` attachments across every vision provider using standard `FoundationModels` APIs and `VisualInspectionDecision` from `SystemOneCore`:

```swift
let attachment = Attachment(cgImage)
let prompt = Prompt {
    "Analyze the item in this camera viewfinder frame for identification, categorization, physical condition, and safety compliance."
    attachment
}
let session = LanguageModelSession(model: resolvedModel)
let response = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)
```

### 2. Zero-Churn `CameraManager` & Real Photo Import (Principle 7)
- Live preview renders directly on `AVCaptureVideoPreviewLayer` while storing only the latest `CVPixelBuffer` under a lock on `sampleQueue` — converting to a downsampled `CGImage` strictly on demand inside `captureFrame()`.
- When running on the iOS Simulator or a headless Mac without camera hardware, displays `CameraUnavailableView` with native `PhotosPicker` and `.fileImporter` buttons — **zero synthetic frames, zero mock fallbacks**.

### 3. Secure Keychain Storage + CLI Compatibility
- API tokens (`CLOUDFLARE_API_TOKEN`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, proxy Bearer / App Check tokens) are persisted via `@KeychainStorage` (`Services/KeychainStorage.swift`), with graceful handling for unentitled `swift run vision-scanner-app` executions on macOS (`OSStatus -34018`).

---

## 🔐 Configuring Providers

Configure credentials in the in-app **Settings** sheet (gear icon) or via environment variables:

```bash
# 1 & 2. Cloudflare Clef-Flash (9B) / Clef (27B)
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_API_TOKEN="your-workers-ai-token"
# Optional Cloudflare AI Gateway:
export CLOUDFLARE_GATEWAY_ID="your-gateway-slug"

# 3. Local Clef Runner
export LOCAL_RUNNER_URL="http://127.0.0.1:8000"

# 4. OpenAI Decisions (gpt-6-luna)
export OPENAI_API_KEY="sk-..."

# 5. Google Gemini Decisions (gemini-decision-1)
export GEMINI_API_KEY="AIza..."   # or GOOGLE_API_KEY

# 6. Authenticated Reverse Proxy (Production Recommended)
export SYSTEM_ONE_PROXY_URL="https://your-gateway.example.com/v1/systemone"
export SYSTEM_ONE_PROXY_TOKEN="optional-bearer-token"
# OR Firebase App Check attestation header:
export FIREBASE_APPCHECK_TOKEN="optional-appcheck-token"
```

---

## 🛠️ Building & Running

### macOS via Swift Package Manager
```bash
swift build --target VisionScannerApp
swift run vision-scanner-app
```

### iOS Simulator / macOS via FlowDeck CLI & Xcode 27+
```bash
flowdeck build \
  -w Examples/Apps/VisionScannerApp/VisionScannerApp.xcodeproj \
  -s VisionScannerApp \
  -S "iPhone 18 Pro Max" \
  --show-warnings
```
