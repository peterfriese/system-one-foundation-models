# ⚡ `< 10`-Line Provider Quickstarts

Every System One model provider in this repository conforms directly to Apple's native `LanguageModel` protocol and supports progressive-disclosure zero-argument initialization (`init()`), automatically resolving its standard environment variable or local daemon endpoint at runtime.

Each quickstart below is **8–9 lines of pure Swift 6** using standard Apple `FoundationModels` APIs (`LanguageModelSession`, `@Generable`, `Attachment`, and calibrated `.probability` / `.choice` / `.score` shortcuts) — **zero wrapper classes, zero mock fallbacks**.

> [!IMPORTANT]
> **Strict Real Execution (Principle 7)**: Quickstart executables do not embed mock fallbacks or synthetic offline responses. If a required API key, Core ML model bundle, or local daemon is missing or unreachable, evaluation fails fast with an explicit error explaining how to configure the environment.

---

## 🧭 All 6 Providers at a Glance

| Executable (`swift run <name>`) | Source File | Lines | Provider Type | Environment Variable / Prerequisite |
| :--- | :--- | :---: | :--- | :--- |
| **`jev-quickstart`** | [`JevQuickstart/main.swift`](JevQuickstart/main.swift) | **9** | `JevLanguageModel()` | `TYPESAFE_API_KEY` |
| **`laya-quickstart`** | [`LayaServeQuickstart/main.swift`](LayaServeQuickstart/main.swift) | **9** | `LayaLanguageModel()` | Running `laya-serve` (`localhost:8000` or `LAYA_SERVE_URL` + optional `LAYA_API_KEY`) |
| **`laya-ondevice-quickstart`** | [`LayaOnDeviceQuickstart/main.swift`](LayaOnDeviceQuickstart/main.swift) | **9** | `try LayaOnDeviceLanguageModel()` | `LAYA_MODEL_PATH` (`.mlmodelc` / `.mlpackage`) + optional `LAYA_TOKENIZER_PATH` |
| **`clef-quickstart`** | [`ClefQuickstart/main.swift`](ClefQuickstart/main.swift) | **8** | `ClefLanguageModel()` | `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`, `CLEF_ENDPOINT`, or `CLEF_LOCAL_PORT` |
| **`openai-quickstart`** | [`OpenAIQuickstart/main.swift`](OpenAIQuickstart/main.swift) | **9** | `OpenAILanguageModel()` (`OpenAIDecisionsLanguageModel`) | `OPENAI_API_KEY` |
| **`gemini-quickstart`** | [`GeminiQuickstart/main.swift`](GeminiQuickstart/main.swift) | **9** | `GeminiLanguageModel()` | `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) |

---

## 1. TypeSafe AI Jev Cloud (`jev-quickstart`)

Evaluates calibrated binary truth probability (`noul`) over an operational incident ticket using TypeSafe AI's hosted Jev System One endpoint (`https://api.typesafe.ai/v1/systemone`).

```swift
import FoundationModels
import JevFoundationModels

let session = LanguageModelSession(model: JevLanguageModel())
let urgent = try await session.probability(
    of: "This support ticket requires immediate on-call escalation",
    state: "Production checkout returning HTTP 502 across us-east-1 for 14 minutes."
)
print("Urgent escalation probability: \(urgent)")
```

**Run from repository root:**

```bash
export TYPESAFE_API_KEY="your-typesafe-api-key"
swift run jev-quickstart
```

---

## 2. Self-Hosted Laya HTTP Server (`laya-quickstart`)

Evaluates a discrete categorical routing decision (`choice`) with calibrated confidence against a local or remote `laya-serve` instance (`http://127.0.0.1:8000/v1/systemone` by default, or overridden via `LAYA_SERVE_URL`).

```swift
import FoundationModels
import LayaFoundationModels

let route = try await LanguageModelSession(model: LayaLanguageModel()).choice(
    "Select the team responsible for handling this request",
    options: ["billing", "engineering", "security"],
    state: "Customer charged twice on invoice #9920 after card retry."
)
print("Routed to \(route.value) (confidence: \(route.confidence))")
```

**Run from repository root:**

```bash
# Terminal 1: Start laya-serve locally (or set LAYA_SERVE_URL for a remote instance)
laya-serve

# Terminal 2: Run the 9-line quickstart
swift run laya-quickstart
```

---

## 3. On-Device Laya Core ML (`laya-ondevice-quickstart`)

Evaluates an ordinal rubric score (`score`) 100% offline on the Apple Neural Engine (ANE) and GPU with zero network calls and zero API keys. `LayaOnDeviceLanguageModel()` resolves `LAYA_MODEL_PATH` (or a bundled/working-directory `LayaDecisionModel.mlmodelc`) alongside an adjacent `tokenizer.json` (or `LAYA_TOKENIZER_PATH`).

```swift
import FoundationModels
import LayaOnDevice

let severity = try await LanguageModelSession(model: LayaOnDeviceLanguageModel()).score(
    "Rate incident severity",
    levels: ["Low", "Medium", "High", "Critical"],
    state: "Database connection pool exhausted; queries timing out on checkout."
)
print("Severity: \(severity.mostLikelyLevel) (confidence: \(severity.confidence))")
```

**Run from repository root:**

```bash
# Convert Hugging Face weights once if you don't already have a compiled .mlmodelc:
# uv run Tools/CoreMLConverter/convert_laya_to_coreml.py --output ./LayaDecisionModel.mlpackage

export LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc"
swift run laya-ondevice-quickstart
```

---

## 4. Cloudflare Clef Multimodal Vision (`clef-quickstart`)

Evaluates a visual decision in a single feed-forward pass (`output_tokens: 0`) using `ClefLanguageModel()` and the `@PromptBuilder` multimodal `.probability(of:) { ... }` shortcut. Automatically uses the bundled [`ClefQuickstart/sample.jpg`](ClefQuickstart/sample.jpg) fixture or accepts any local `.jpg`, `.png`, or `.webp` path as a CLI argument.

```swift
import ClefFoundationModels
import Foundation
import FoundationModels

let url = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Examples/Quickstarts/ClefQuickstart/sample.jpg")
let session = LanguageModelSession(model: ClefLanguageModel())
let damaged = try await session.probability(of: "The parcel has visible exterior damage") { Attachment(imageURL: url) }
print("Damage probability: \(damaged)")
```

**Run against Cloudflare Workers AI edge:**

```bash
export CLOUDFLARE_ACCOUNT_ID="your-32-char-account-id"
export CLOUDFLARE_API_TOKEN="your-workers-ai-token"
swift run clef-quickstart
# Or pass a custom image path:
swift run clef-quickstart /path/to/parcel_photo.jpg
```

**Or run against the local Clef runner (`Tools/ClefLocalRunner/server.py`):**

```bash
# Terminal 1: Start local runner on port 8000
python3 Tools/ClefLocalRunner/server.py --port 8000

# Terminal 2: Point ClefLanguageModel() at localhost:8000
CLEF_LOCAL_PORT=8000 swift run clef-quickstart
```

---

## 5. OpenAI Decisions API — `gpt-6-luna` (`openai-quickstart`)

Evaluates a multi-property `@Generable` decision struct (`Bool` predicate + bounded `1...5` rubric score) in a single non-autoregressive pass against `POST https://api.openai.com/v1/decisions` with zero output token billing (`$0.00` output tokens).

```swift
import FoundationModels
import OpenAIFoundationModels

@Generable struct ExpenseDecision {
    var isApproved: Bool
    @Guide(.range(1...5)) var riskScore: Int
}
let session = LanguageModelSession(model: OpenAIDecisionsLanguageModel())
print(try await session.respond(to: "Team dinner receipt $142.50 with itemized invoice", generating: ExpenseDecision.self).content)
```

**Run from repository root:**

```bash
export OPENAI_API_KEY="sk-..."
swift run openai-quickstart
```

---

## 6. Google Gemini Decisions API — `gemini-decision-1` (`gemini-quickstart`)

Evaluates a calibrated fraud-review binary truth probability (`noul`) in a single non-autoregressive pass against Google's Gemini Decisions API with zero output token billing (`$0.00` output tokens).

```swift
import FoundationModels
import GeminiFoundationModels

let session = LanguageModelSession(model: GeminiLanguageModel())
let fraudProb = try await session.probability(
    of: "This transaction requires manual fraud review",
    state: "New account purchased $4,800 in gift cards from 3 mismatched IPs in 90 seconds."
)
print("Fraud review probability: \(fraudProb.formatted(.percent.precision(.fractionLength(1))))")
```

**Run from repository root:**

```bash
export GEMINI_API_KEY="AIza..."
swift run gemini-quickstart
```
