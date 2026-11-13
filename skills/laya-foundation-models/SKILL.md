---
name: laya-foundation-models
license: Apache-2.0
description: >-
  Evaluate Laya System One decision models 100% offline on-device via Core ML & Apple Neural
  Engine (`LayaOnDevice` / `LayaOnDeviceLanguageModel`) or against self-hosted / private-VPC
  `laya-serve` HTTP servers (`LayaFoundationModels` / `LayaLanguageModel`) natively through
  Apple's Foundation Models framework in Swift 6. Use when building air-gapped iOS 27+,
  macOS 27+, or visionOS 27+ apps, compiling ModernBERT (421M) or multilingual mmBERT (322M)
  `.mlmodelc` bundles, configuring native Swift tokenizers (`ModernBERTTokenizer`,
  `MMBERTTokenizer`), implementing local-first hybrid ANE-to-cloud confidence routing, securing
  remote `laya-serve` gateways via `ProxyCredential`, or writing deterministic offline tests.
metadata:
  author: peterfriese
  version: "1.0"
---

# Laya On-Device Core ML & Self-Hosted HTTP Bridge (`LayaOnDevice` + `LayaFoundationModels`)

> [!TIP]
> **Multi-Backend Architecture**: For projects combining Laya with TypeSafe Jev (`JevFoundationModels`), Cloudflare Clef (`ClefFoundationModels`), OpenAI Decisions (`OpenAIFoundationModels`), or Google Gemini Decisions (`GeminiFoundationModels`), refer to the unified `system-one-foundation-models` skill. This skill focuses specifically on **Laya On-Device Core ML** (`LayaOnDevice`) and **Self-Hosted `laya-serve` HTTP** (`LayaFoundationModels`).

This skill guides the design, Core ML model preparation, tokenization, and deployment of **Laya System One decision models** across two complementary Swift 6 targets:

| Module | Swift `LanguageModel` Type | Package Trait | Execution Topology | Latency |
| :--- | :--- | :--- | :--- | :---: |
| **`LayaOnDevice`** | `LayaOnDeviceLanguageModel` | `"Laya"` / `"OnDevice"` | 100% offline Core ML on Apple Neural Engine (ANE) & GPU | **< 2ms** |
| **`LayaFoundationModels`** | `LayaLanguageModel` | `"LayaServe"` | Self-hosted `laya-serve` HTTP daemon (`localhost:8000` or private VPC) | **5–30ms** |

---

## 1. Part A — On-Device Core ML (`LayaOnDevice`)

### Converting Checkpoints to `.mlmodelc`

Convert Hugging Face Laya checkpoints (`convaiinnovations/laya` English ModernBERT 421M or multilingual mmBERT 322M) using `Tools/CoreMLConverter/convert_laya_to_coreml.py` (see Tech Note 0008):

```bash
# 1. Convert ModernBERT (421M, FP16) or multilingual mmBERT (322M, 8-bit)
python3 Tools/CoreMLConverter/convert_laya_to_coreml.py \
    --model convaiinnovations/laya \
    --output LayaDecisionModel.mlpackage \
    --seq-len 512 \
    --max-options 32 \
    --quantize fp16

# 2. Compile into an Xcode-embeddable .mlmodelc directory
xcrun coremlcompiler compile LayaDecisionModel.mlpackage .
```

### Progressive-Disclosure Initialization (`LayaOnDeviceLanguageModel`)

`try LayaOnDeviceLanguageModel()` resolves the model URL in order:
1. Explicit `modelURL:` parameter (if supplied).
2. `LAYA_MODEL_PATH` environment variable (`~` expanded).
3. `Bundle.main.url(forResource: "LayaDecisionModel", withExtension: "mlmodelc")` (or `.mlpackage`).
4. Current working directory `LayaDecisionModel.mlmodelc` / `.mlpackage`.

And resolves the tokenizer in order:
1. Explicit `tokenizer:` parameter (`ModernBERTTokenizer` WordPiece or `MMBERTTokenizer` SentencePiece Unigram).
2. `LAYA_TOKENIZER_PATH` environment variable.
3. Adjacent `tokenizer.json` next to `modelURL`.
4. Built-in `ModernBERTTokenizer.defaultTokenizer()`.

```swift
import FoundationModels
import LayaOnDevice

// 1. Zero-argument initialization (auto-resolves LAYA_MODEL_PATH or bundled LayaDecisionModel.mlmodelc)
let session = LanguageModelSession(model: try LayaOnDeviceLanguageModel())

let severity = try await session.score(
    "Rate operational incident severity",
    levels: ["Low", "Medium", "High", "Critical"],
    state: "Primary database connection pool exhausted; checkout queries timing out."
)

// 2. Shared pre-warmed engine across multiple sessions (recommended for SwiftUI apps)
let modelURL = Bundle.main.url(forResource: "LayaDecisionModel", withExtension: "mlmodelc")!
let engine = try LayaCoreMLEngine(
    modelURL: modelURL,
    tokenizer: ModernBERTTokenizer.defaultTokenizer(), // or try MMBERTTokenizer(jsonURL: ...)
    maxOptions: 32
)
let sharedModel = LayaOnDeviceLanguageModel(engine: engine)
```

### Core ML Architectural Constraints
- **Text-Only Capability**: `LayaOnDeviceLanguageModel` advertises `LanguageModelCapabilities([.guidedGeneration])`. Passing image `Attachment`s throws `LanguageModelSession.GenerationError.unsupportedCapability`—route visual tasks to `ClefLanguageModel`, `OpenAILanguageModel`, or `GeminiLanguageModel`.
- **Max Options (`maxOptions = 32`)**: Each `choice` or `score` question supports up to 32 option markers gathered on the ANE (`[1, 512]` / `[1, 1024]` fixed-shape tensors prevent ANE graph recompilation stalls).
- **Non-Blocking Execution**: `LayaCoreMLEngine.predict(request:)` pre-tokenizes state once across batched questions, checks `Task.checkCancellation()` before every question, and dispatches synchronous `MLModel.prediction` inside a detached task so `@MainActor` UI threads never stall.

---

## 2. Part B — Self-Hosted `laya-serve` HTTP (`LayaFoundationModels`)

`LayaLanguageModel` speaks the canonical `POST /v1/systemone` JSON wire protocol against local workstation daemons (`laya-serve`), private Kubernetes/VPC clusters, or reverse proxies.

```swift
import FoundationModels
import LayaFoundationModels

// 1. Zero-arg: resolves LAYA_SERVE_URL / LAYA_ENDPOINT or defaults to http://127.0.0.1:8000/v1/systemone
//    Also auto-attaches LAYA_API_KEY as Bearer token when present
let localSession = LanguageModelSession(model: LayaLanguageModel())

// 2. Explicit LayaEndpoint (.localDefault, .localAlt [8770], .local(port:), .hosted, .custom(URL))
let vpcModel = LayaLanguageModel(
    endpoint: .custom(URL(string: "https://laya.internal.mycompany.com/v1/systemone")!),
    modelID: "english", // or "multilingual"
    apiKey: vpcBearerToken,
    retryPolicy: .default
)

// 3. Mobile Reverse Proxy with ProxyCredential (.appCheck, .bearer, .header, or trailing authorize:)
let mobileModel = LayaLanguageModel(
    proxyEndpoint: URL(string: "https://gateway.mycompany.com/layaDecisions")!,
    credential: .appCheck {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
```

---

## 3. Local-First Hybrid ANE $\to$ Cloud Routing Pattern

Combine `LayaOnDevice` with any cloud System One provider (`Gemini`, `OpenAI`, `Jev`, `Clef`) using `RoutingPolicy` so 80–90% of clear-cut decisions resolve locally in `< 2ms` at `$0` cost, escalating only ambiguous inputs (`confidence < 0.80`) to a larger cloud model (see `Examples/TraitSamples/04-HybridRouter`):

```swift
import FoundationModels
import SystemOneFoundationModels

actor HybridTriageRouter {
    private let localSession: LanguageModelSession
    private let cloudSession: LanguageModelSession
    private let policy = RoutingPolicy(escalateBelow: 0.80, autoAtOrAbove: 0.80)

    init(engine: LayaCoreMLEngine, cloudModel: GeminiLanguageModel) {
        self.localSession = LanguageModelSession(model: LayaOnDeviceLanguageModel(engine: engine))
        self.cloudSession = LanguageModelSession(model: cloudModel)
    }

    func routePriority(for text: String) async throws -> Choice<String> {
        let local = try await localSession.choice(
            "Determine incident priority",
            options: ["routine", "elevated", "urgent"],
            state: text
        )
        if policy.decide(confidence: local.confidence) == .auto {
            return local // Resolved offline on ANE (< 2ms)
        }
        return try await cloudSession.choice(
            "Determine incident priority",
            options: ["routine", "elevated", "urgent"],
            state: text
        )
    }
}
```

---

## 4. Deterministic Offline Testing

Both `LayaOnDeviceLanguageModel` and `LayaLanguageModel` accept `init(backend: MockSystemOneBackend)`—and `LayaCoreMLEngine` additionally provides `init(tokenizer:maxOptions:mockPredictor:)` to test tokenization and logit temperature calibration without loading `.mlmodelc` weights:

```swift
import FoundationModels
import LayaFoundationModels
import LayaOnDevice
import SystemOneCore
import Testing

@Suite("Laya Offline Tests")
struct LayaOfflineTests {

    @Test("Tests LayaOnDeviceLanguageModel via MockSystemOneBackend without .mlmodelc file")
    func testOnDeviceMockBackend() async throws {
        let mock = MockSystemOneBackend { _ in
            SystemOneResponse(
                model: "laya-ondevice",
                answers: ["decision": SystemOneAnswer(type: "noul", noul: 0.93, confidence: 0.93)]
            )
        }
        let session = LanguageModelSession(model: LayaOnDeviceLanguageModel(backend: mock))
        let p = try await session.probability(of: "Alert is critical", state: "Kernel panic on node-04")
        #expect(p == 0.93)
    }
}
```
