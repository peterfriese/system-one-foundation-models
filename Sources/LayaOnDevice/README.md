# `LayaOnDevice` 📱🧠

`LayaOnDevice` runs **Laya** System One decision models (421M English `ModernBERT` and 322M multilingual `mmBERT`) **100% offline on-device** using Apple Core ML and the **Apple Neural Engine (ANE)**—delivering sub-2ms inference with zero network calls and zero API keys.

- **Package Trait**: `"Laya"` / `"OnDevice"` (also included in default `"All"`)
- **Capabilities**: `LanguageModelCapabilities([.guidedGeneration])` (Offline Text)
- **Auto-Resolved Resource**: `LAYA_MODEL_PATH` or bundled `LayaDecisionModel.mlmodelc` + `LAYA_TOKENIZER_PATH` / adjacent `tokenizer.json`

---

## ⚡ Quick Start in 6 Lines

```swift
import FoundationModels
import LayaOnDevice

let session = LanguageModelSession(model: try LayaOnDeviceLanguageModel())
let severity = try await session.score("Rate severity", levels: ["Low", "Medium", "High"], state: logText)
print("Severity: \(severity.mostLikelyLevel) (\(severity.confidence))")
```

---

## 🧭 Initializer Matrix

| Deployment Mode | Initializer | Notes |
| :--- | :--- | :--- |
| **Zero-Arg Auto-Resolve** | `try LayaOnDeviceLanguageModel()` | Checks `LAYA_MODEL_PATH`, `Bundle.main` (`LayaDecisionModel.mlmodelc`), or CWD + adjacent `tokenizer.json`. |
| **Explicit Bundle URL** | `try LayaOnDeviceLanguageModel(modelURL: bundleURL, tokenizer: tok)` | Supports `ModernBERTTokenizer` (WordPiece) and `MMBERTTokenizer` (SentencePiece Unigram). |
| **Shared Core ML Engine** | `LayaOnDeviceLanguageModel(engine: sharedEngine)` | Reuses a pre-warmed `LayaCoreMLEngine` across multiple `LanguageModelSession` instances. |
| **Offline Unit Tests** | `LayaOnDeviceLanguageModel(backend: mockBackend)` | Injects `MockSystemOneBackend` without loading physical Core ML weights in CI. |

---

## 🔗 Conversion Tooling, Quickstart & Tests

- **Model Converter**: [`Tools/CoreMLConverter/`](../../Tools/CoreMLConverter/README.md) (`convert_laya_to_coreml.py` + `xcrun coremlcompiler compile`)
- **Runnable Quickstart**: [`Examples/Quickstarts/LayaOnDeviceQuickstart/main.swift`](../../Examples/Quickstarts/LayaOnDeviceQuickstart/main.swift) (`swift run laya-ondevice-quickstart`)
- **Trait Samples**: [`01-OfflineLayaApp`](../../Examples/TraitSamples/01-OfflineLayaApp/README.md) • [`04-HybridRouter`](../../Examples/TraitSamples/04-HybridRouter/README.md)
- **Offline Tests**: `swift test --filter LayaOnDeviceTests` ([`Tests/README.md`](../../Tests/README.md)) • [**Agent Skill**](../../skills/laya-foundation-models/SKILL.md)
