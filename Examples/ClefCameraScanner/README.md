# Clef Camera Scanner (Real-Time Multimodal Decision App) 📱📷

A production-grade, cross-platform (iOS & macOS) SwiftUI reference application that lets users hold physical objects up to their device's camera for real-time visual inspection, categorization, condition scoring, and safety triage using **Cloudflare Clef (27B)** and **Clef-Flash (9B)** through Apple's **Foundation Models framework**.

---

## 🌟 Architectural Features

### 1. Pure Apple Foundation Models Multimodal Ergonomics
- Evaluates visual frames using standard Apple `FoundationModels` APIs:
  ```swift
  let attachment = Attachment(cgImage)
  let prompt = Prompt {
      "Analyze the item in this camera viewfinder frame."
      attachment
  }
  let response = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)
  ```
- Uses zero proprietary wrappers or custom sessions.
- Ingests image attachments directly through Apple's `Prompt` builder and `Attachment` APIs.

### 2. Thread-Safe `CameraManager`
- Conforms to `@MainActor @Observable` while serializing hardware access on a private serial `sessionQueue` (`com.typesafe.clef.camera.session`), following Apple `photokit` directives.
- Implements balanced `session.beginConfiguration()` with `defer { session.commitConfiguration() }` transactions.
- Zero main-thread hardware blocking.
- Streams real-time frames using `AVCaptureVideoDataOutput` and extracts `CGImage` representations on a high-priority background queue.

### 3. Cross-Platform Viewfinder (`CameraPreviewView`)
- **iOS**: Uses `UIViewRepresentable` overriding `layerClass` with `AVCaptureVideoPreviewLayer`.
- **macOS**: Uses `NSViewRepresentable` hosting `AVCaptureVideoPreviewLayer`.
- **Simulation Fallback**: If running on the iOS Simulator or a Mac without physical camera hardware, activates a synthetic simulation stream cycling between candidate products (snack bar, soda can, electronics device, document) with an animated laser reticle and an explicit simulation notice.

### 4. Interactive HUD with Native Liquid Glass Styling
- Uses Apple's native iOS 26+ / macOS 26+ Liquid Glass APIs (`.glassEffect(.regular, in: ...)` and `.buttonStyle(.glassProminent)`).
- **Calibrated Operational Routing Badge**:
  - `AUTO-ROUTED` (Green / Emerald $\ge 85\%$): Decision executes autonomously.
  - `CONFIRMATION` (Amber $60\%\dots84.9\%$): Suggests answer and prompts operator.
  - `ESCALATE` (Red / Rose $< 60\%$): Escalate to manual review queue.
- **Latency Telemetry Pill**: Surfaces edge forward-pass duration (`serverDurationMs`) and network roundtrip (`transportDurationMs`).
- **Hot-Swappable Backend Switcher**: Toggle dynamically between Cloudflare Workers AI edge (`@cf/cloudflare/clef-flash` or `@cf/cloudflare/clef`) and Local Native Runner (`http://localhost:8000`).

---

## 📋 Strongly-Typed Decision Schema (`VisualInspectionDecision`)

```swift
@Generable
public enum ItemCategory: String, Sendable, CaseIterable {
    case snack
    case beverage
    case electronics
    case document
    case household
    case person
    case clothing
    case plant
    case accessory
    case unknown
}

@Generable
public struct VisualInspectionDecision: Sendable {
    @Guide(description: "Is a physical item or subject clearly recognized in the camera view?")
    public var isRecognized: Bool

    @Guide(description: "Primary category classification of the recognized item")
    public var itemCategory: ItemCategory

    @Guide(description: "Physical condition rubric: 0 (unusable/damaged), 1 (worn), 2 (good), 3 (pristine)", .range(0...3))
    public var conditionScore: Int

    @Guide(description: "Safety approval: does the item satisfy safety standards without visible hazards, damage, or contamination?")
    public var safetyApproval: Bool
}
```

---

## 🏃 Running the Application

### Running on macOS via Swift Package Manager

```bash
# Run the app natively on macOS:
swift run clef-camera-scanner
```

### Running on iOS Simulator or Device via FlowDeck

```bash
# Build the package
flowdeck build

# Run automated tests
flowdeck test
```

### Setting Credentials for Cloudflare Workers AI

To test against Cloudflare's live Workers AI edge infrastructure:
```bash
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_API_TOKEN="your-api-token"
swift run clef-camera-scanner
```

If evaluating offline without cloud credentials, select **Local Runner (localhost:8000)** from the HUD backend menu and run:
```bash
docker run -p 8000:8000 ghcr.io/typesafe-ai/clef-flash:latest
```
