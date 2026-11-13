# Developer Guide: Deploying Laya on iOS, visionOS, and macOS

This guide covers building production-grade mobile applications evaluating System One decision models locally via **Core ML** on the **Apple Neural Engine (ANE)**, as well as handling development-time tooling, SwiftUI Canvas rendering, and Xcode On-Demand Resources (ODR).

---

## 1. Development Workflow: Simulator & SwiftUI Previews

### Simulator to Local Mac Bridge
When running in the **iOS Simulator**, network requests to `http://127.0.0.1:8000` automatically map to your host Mac's loopback interface. You can run `laya-serve` on your Mac and test your iOS app in the simulator without compiling Core ML weights:

```swift
#if DEBUG && targetEnvironment(simulator)
// iOS Simulator connects directly to Mac's local laya-serve instance
let devModel = LayaLanguageModel(endpoint: .localDefault)
#else
// Physical device or production release: use on-device Core ML engine
let prodModel = LayaOnDeviceLanguageModel(engine: sharedOnDeviceEngine)
#endif
```

### Instant SwiftUI Canvas Previews
Waiting for Core ML compilation or network sockets slows down Xcode Canvas previews. Use `LayaCoreMLEngine`'s mock predictor for instantaneous `#Preview` rendering:

```swift
#Preview("Urgent Billing Ticket") {
    let mockEngine = LayaCoreMLEngine(tokenizer: ModernBERTTokenizer.defaultTokenizer()) { _ in
        // Instant simulated logits for UI preview
        return [4.0, -1.0, -1.0]
    }
    let session = LanguageModelSession(model: LayaOnDeviceLanguageModel(engine: mockEngine))
    TriageDetailView(session: session)
}
```

---

## 2. Model Preparation & Size Optimization

Laya ships two primary models:
1. **`laya-multilingual` (322M)**: mmBERT-base backbone covering 100+ languages.
2. **`laya` (421M)**: ModernBERT-large backbone covering English and specialized decision workflows.

### Quantization Matrix

| Model | Parameters | Uncompressed FP32 | Core ML FP16 (ANE Native) | Core ML 8-bit Quantized | Accuracy Impact |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`laya-multilingual`** | 322M | ~1.28 GB | ~644 MB | **~160 MB** | $< 0.005$ Brier score |
| **`laya` (English)** | 421M | ~1.68 GB | ~842 MB | **~210 MB** | $< 0.008$ Brier score |

### Converting & Compiling
Run the conversion tool with 8-bit quantization:

```bash
# 1. Convert to .mlpackage
python Tools/CoreMLConverter/convert_laya_to_coreml.py \
    --model convaiinnovations/laya-multilingual \
    --output LayaMultilingual.mlpackage \
    --quantize 8bit

# 2. Compile to .mlmodelc bundle
xcrun coremlcompiler compile LayaMultilingual.mlpackage .
```

---

## 3. Deployment: Xcode On-Demand Resources (ODR)

To keep initial App Store cellular download sizes small (< 30 MB), use Apple's **On-Demand Resources (ODR)** to download `LayaMultilingual.mlmodelc` (~160 MB) in the background.

### Step 1: Tag the Asset in Xcode
1. In Xcode, select `LayaMultilingual.mlmodelc`.
2. In the **File Inspector**, add an On-Demand Resource tag: `laya-multilingual-v1`.
3. In **Target Settings > Resource Tags**, assign it to:
   - **Prefetched**: Downloads immediately after initial app installation in the background.
   - **On Demand**: Downloads only when the user first opens the smart feature.

### Step 2: Download & Load with `NSBundleResourceRequest`

```swift
import Foundation
import FoundationModels
import LayaOnDevice

@Observable
@MainActor
final class DecisionService {
    private var engine: LayaCoreMLEngine?

    func ensureModelAvailable() async throws -> LanguageModelSession {
        if let engine {
            return LanguageModelSession(model: LayaOnDeviceLanguageModel(engine: engine))
        }

        // 1. Request resource tag from Apple CDN / Local Cache
        let resourceRequest = NSBundleResourceRequest(tags: ["laya-multilingual-v1"])
        resourceRequest.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent

        // Track download progress if needed
        let _ = resourceRequest.progress

        try await resourceRequest.beginAccessingResources()

        // 2. Locate compiled bundle in app sandbox
        guard let modelURL = Bundle.main.url(forResource: "LayaMultilingual", withExtension: "mlmodelc") else {
            throw NSError(domain: "DecisionService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model resource not found"])
        }

        // 3. Initialize Core ML engine on Neural Engine
        let engine = try LayaCoreMLEngine(
            modelURL: modelURL,
            tokenizer: MMBERTTokenizer.defaultTokenizer()
        )
        self.engine = engine

        return LanguageModelSession(model: LayaOnDeviceLanguageModel(engine: engine))
    }

    func evaluateTriage(state: String) async throws -> TriageDecision {
        let session = try await ensureModelAvailable()
        let response = try await session.respond(to: state, generating: TriageDecision.self)
        return response.content
    }
}
```

---

## 4. Hybrid Device Memory Gating

For older devices with 4 GB of RAM (e.g. iPhone 11/12), keeping a ~160 MB model resident in memory during intense UI tasks can lead to memory pressure jetsams.

Implement a runtime memory check to route requests intelligently:

```swift
func resolveSystemOneModel() -> any LanguageModel {
    let physicalRAM = ProcessInfo.processInfo.physicalMemory
    let sixGigabytes: UInt64 = 6 * 1024 * 1024 * 1024

    if physicalRAM >= sixGigabytes {
        // High-memory devices (iPhone 15 Pro, iPad Air M2, Macs): Run 100% on-device
        return LayaOnDeviceLanguageModel(engine: sharedOnDeviceEngine)
    } else {
        // Lower-memory devices: Route via hardware-attested App Check proxy
        let transport = ProxyTransport(
            proxyEndpoint: cloudProxyURL,
            credential: .header(name: "X-Firebase-AppCheck") {
                try await AppCheck.appCheck().token(forcingRefresh: false).token
            }
        )
        return JevLanguageModel(transport: transport)
    }
}
```
