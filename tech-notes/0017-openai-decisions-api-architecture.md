# 0017 — OpenAI Decisions API (GPT-6 Luna) System One Model Architecture

- **Date**: 2026-10-08
- **Author**: Peter Friese
- **Framework**: `FoundationModels` (iOS 27.0+, macOS 27.0+, visionOS 27.0+), `SystemOneCore`, `OpenAIFoundationModels`
- **Upstream**: OpenAI Decisions API (`POST /v1/decisions`), `gpt-6-luna`

---

## Context

Mobile and enterprise applications evaluating structured state require rapid, deterministic classification, triage, and scoring. Historically, integrating foundation models into transactional pipelines has relied on autoregressive generative models (e.g. GPT-4o, Claude 3.5 Sonnet, or GPT-5) paired with JSON schema enforcement.

### The Autoregressive Evaluation Problem

Using generative large language models for discrete, bounded operational decisions presents severe structural drawbacks:

1. **Decoding Latency Overhead**: Autoregressive token-by-token generation incurs 600ms–2,500ms of latency per call, precluding real-time interactive UI updates and sub-100ms mobile batch triage.
2. **Asymmetric Economics**: Developers are billed for both input prompt tokens and generated output tokens. Output tokens are priced 3x–10x higher than input tokens, despite producing only repetitive JSON formatting boilerplate.
3. **Uncalibrated Confidence**: Generative sampling estimates sequential word distributions rather than true Bayesian posterior probabilities of propositions. Models report arbitrary confidence scores when prompted, leading to hallucinations and brittle escalation rules.
4. **Schema Fragility**: Even with constrained decoding, generative outputs risk malformed syntax, truncation, or token limit timeouts on edge or mobile networks.

### The System One Ecosystem & GPT-6 Luna

The System One paradigm solves this by evaluating decisions via a single forward pass without autoregressive text decoding:
- **Laya**: On-device Core ML (ANE/GPU) and self-hosted `laya-serve` instances running ModernBERT and mmBERT backbones.
- **TypeSafe Jev**: Managed cloud API providing Bayesian confidence-calibrated decision primitives (`noul`, `choice`, `score`).
- **Cloudflare Clef & Clef-Flash**: Edge-hosted Workers AI multimodal decision models (9B / 27B) with native vision attachment support.

OpenAI has entered the dedicated decision model ecosystem with the **OpenAI Decisions API** (`POST /v1/decisions`) and the **`gpt-6-luna`** model architecture. `gpt-6-luna` is a purpose-built discriminative model optimized for ultra-low latency, multimodal understanding, and mathematically calibrated proposition probabilities at extreme efficiency ($0.10 per 1M input tokens, with $0.00 output token billing).

This tech note documents the architecture of the OpenAI Decisions API, its integration into Apple's `FoundationModels` framework via `OpenAIFoundationModels`, wire schema translation mechanics, RFC 2397 multimodal Data URL ingestion, zero-output-token economics, and confidence calibration dynamics.

---

## Findings

### 1. Model Topology & API Characteristics

The `gpt-6-luna` model operates as a discriminative classification and judgment engine rather than an autoregressive text generator:

| Metric / Dimension | OpenAI `gpt-6-luna` | TypeSafe Jev Cloud | Cloudflare Clef-Flash | Apple Intelligence (Baseline) |
| :--- | :--- | :--- | :--- | :--- |
| **Endpoint** | `POST /v1/decisions` | `POST /v1/systemone` | `POST .../ai/run/...` | On-Device ANE / Metal |
| **Model Type** | Non-autoregressive decision model | Non-autoregressive decision model | Non-autoregressive multimodal | Autoregressive generative LLM |
| **Parameter Scale** | Undisclosed (~12B equivalent) | 421M / 1.2B | ~9B (Qwen3.5 backbone) | ~3B |
| **Typical Latency** | 35ms – 80ms | 60ms – 90ms | 45ms – 85ms | 800ms – 1,500ms |
| **Output Tokens** | **0** (`output_tokens: 0`) | **0** | **0** | Variable (50–300 tokens) |
| **Input Pricing** | **$0.10 / 1M tokens** | $0.20 / 1M tokens | $0.05 / 1M tokens | $0.00 (On-Device) |
| **Output Pricing** | **$0.00** | $0.00 | $0.00 | $0.00 (On-Device) |
| **Multimodal Inputs** | Yes (PNG, JPEG, WebP) | No (Text only) | Yes (PNG, JPEG, WebP) | Text only |
| **Safety Refusals** | Explicit refusal envelope | Error code / flag | Null score | Refusal string |

### 2. Execution Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│              OpenAI Decisions API (GPT-6 Luna) Pipeline                 │
│                                                                         │
│   Prompt Text         Visual Attachments (Data URL)   Question Schemas  │
│        │                          │                           │         │
│        ▼                          ▼                           ▼         │
│ ┌─────────────────────────────────────────────────────────────────────┐ │
│ │                  OpenAI Decisions Request Payload                   │ │
│ │  - model: "gpt-6-luna"                                              │ │
│ │  - input: .text(...) OR .multimodal([Message...])                   │ │
│ │  - questions: [predicate, choice, score]                            │ │
│ └──────────────────────────────────┬──────────────────────────────────┘ │
│                                    │                                    │
│                                    ▼                                    │
│                     POST https://api.openai.com/v1/decisions            │
│                     Authorization: Bearer sk-...                        │
│                     OpenAI-Organization: org-...                        │
│                     OpenAI-Project: proj-...                            │
│                     X-Client-Request-Id: req-...                        │
│                                    │                                    │
│                                    ▼                                    │
│ ┌─────────────────────────────────────────────────────────────────────┐ │
│ │               Single Forward Pass (ANE / Edge Cluster)              │ │
│ │                 NO AUTOREGRESSIVE TOKEN DECODING                    │ │
│ └──────────────────────────────────┬──────────────────────────────────┘ │
│                                    │                                    │
│                                    ▼                                    │
│ ┌─────────────────────────────────────────────────────────────────────┐ │
│ │                      Response Wire Payload                          │ │
│ │  - answers: [                                                       │ │
│ │      { name: "isUrgent", type: "predicate", probability: 0.94 },    │ │
│ │      { name: "category", type: "choice", choice: "billing" },       │ │
│ │      { name: "tier", type: "score", score: 2.0, confidence: 0.91 }  │ │
│ │    ]                                                                │ │
│ │  - usage: { input_tokens: 342, output_tokens: 0 }                   │ │
│ └─────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Wire Schema Translation Mechanics

The `OpenAIFoundationModels` package bridges Apple's `FoundationModels` `@Generable` structured generation macros into the wire format expected by `POST /v1/decisions`.

### 1. Primitive Mapping

`OpenAIDecisionsPayloadAdapter` translates System One question specifications to OpenAI Decisions primitives:

| System One Primitive | OpenAI Wire `type` | Wire Payload Fields | Response Mapping |
| :--- | :--- | :--- | :--- |
| **`noul`** | `"predicate"` | `name`, `instructions` | `answer.probability` $\to$ `Answer.noul(probability:)` |
| **`choice`** | `"choice"` | `name`, `instructions`, `choices: [{value, description}]` | `answer.choice`, `answer.probabilities` $\to$ `Answer.choice(...)` |
| **`score`** | `"score"` | `name`, `instructions`, `levels: [{label, description}]` | `answer.score`, `answer.probabilities` $\to$ `Answer.score(...)` |

### 2. Request Translation

```swift
public static func adaptRequest(_ request: SystemOneRequest) throws -> OpenAIDecisionsRequest {
    let inputPayload: OpenAIDecisionsRequest.InputPayload
    if request.hasImages {
        var contentBlocks: [OpenAIDecisionsRequest.InputPayload.ContentBlock] = []
        if !request.state.isEmpty {
            contentBlocks.append(.inputText(request.state))
        }
        for image in request.images {
            contentBlocks.append(.inputImage(dataURL: image.dataURLString))
        }
        inputPayload = .multimodal([
            OpenAIDecisionsRequest.InputPayload.Message(role: "user", content: contentBlocks)
        ])
    } else {
        inputPayload = .text(request.state)
    }

    let questions = request.questions.map { (name, spec) in
        adaptQuestion(name: name, spec: spec)
    }

    return OpenAIDecisionsRequest(
        model: request.model,
        input: inputPayload,
        questions: questions
    )
}
```

### 3. Response Synthesis & Safety Refusals

If the Decisions API refuses to evaluate an assertion due to content safety or policy triggers, the `answers` array contains a non-nil `refusal` string. The payload adapter immediately catches this and surfaces a typed `OpenAIError.refusal`:

```swift
if let refusal = answer.refusal, !refusal.isEmpty {
    throw OpenAIError.refusal(question: answer.name, message: refusal)
}
```

Otherwise, answers are converted into the canonical `SystemOneResponse.Answer` types, which are subsequently channeled into Apple Foundation Models' `LanguageModelExecutorGenerationChannel` for macro decoding into strongly-typed `@Generable` structs.

---

## Multimodal RFC 2397 Data URL Encoding

When an email or ticket contains visual assets (screenshots, server logs, receipts, invoice scans), Apple's `FoundationModels` provides them via `Attachment(data, type:)`.

### 1. Ingestion via `Transcript` & Capabilities

`OpenAIDecisionsLanguageModel` advertises native multimodal vision capabilities to the system runtime:

```swift
public var capabilities: LanguageModelCapabilities {
    LanguageModelCapabilities([.guidedGeneration, .vision])
}

public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
    type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .webP)
}
```

### 2. RFC 2397 Serialization

Visual attachments extracted from the prompt are converted to canonical base64 Data URLs:

```
data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...
```

This format guarantees zero-dependency serialization over standard JSON transport and prevents text tokenizer byte-fallback corruption.

---

## Zero Output Tokens Economics

Standard autoregressive language models incur quadratic or linear decode costs proportional to generated output length. For structured operational workloads, this leads to severe economic waste:

### Cost Comparison on 1,000,000 Email Triage Operations

Assuming an average email length of 450 prompt tokens and a 90-token structured JSON decision output:

| Model / Architecture | Input Cost | Output Cost | Total Cost per 1M Emails | Relative Spend |
| :--- | :--- | :--- | :--- | :--- |
| **OpenAI GPT-4o** | $2.50 / 1M ($1.125) | $10.00 / 1M ($0.900) | **$2,025.00** | **20.25x** |
| **OpenAI GPT-5 mini** | $0.30 / 1M ($0.135) | $1.20 / 1M ($0.108) | **$243.00** | **2.43x** |
| **OpenAI Decisions (GPT-6 Luna)** | **$0.10 / 1M ($0.045)** | **$0.00 (0 tokens)** | **$45.00** | **0.45x** |
| **TypeSafe Jev Cloud** | $0.20 / 1M ($0.090) | $0.00 (0 tokens) | **$90.00** | **0.90x** |
| **Cloudflare Clef-Flash** | $0.05 / 1M ($0.0225) | $0.00 (0 tokens) | **$22.50** | **0.225x** |
| **On-Device Core ML (Laya)** | $0.00 (ANE) | $0.00 (ANE) | **$0.00** | **0.00x** |

At $0.10 / 1M input tokens with zero output tokens, `gpt-6-luna` enables continuous, line-rate evaluation of high-volume customer service streams, log monitoring, and financial triage at an order of magnitude lower cost than any conventional autoregressive model.

---

## Confidence Calibration Analysis: Luna vs. Jev & Laya

A critical requirement for automated triage is **epistemic calibration**: if a model assigns a probability $P = 0.90$ to an event across 1,000 evaluations, exactly ~900 of those instances must be objectively true.

### 1. Calibration Methodologies

- **TypeSafe Jev**: Employs deep Bayesian ensemble scoring over token representations, outputting explicit epistemic variance alongside probability.
- **Laya On-Device (ModernBERT)**: Uses temperature-scaled Platt scaling calibrated during supervised fine-tuning on domain-specific corpora.
- **OpenAI GPT-6 Luna**: Applies multi-task temperature-scaled softmax cross-entropy over discrete classification heads trained directly on decision corpora.

### 2. Reliability in the Undecided Band ($[0.35, 0.65]$)

When evaluating ambiguous or borderline emails:
- Autoregressive models forced into JSON generation frequently overcommit (reporting $0.99$ or $0.01$ confidence) due to mode collapse in token generation.
- `gpt-6-luna` produces smooth, well-dispersed posterior distributions. Probabilities in the undecided range $[0.35, 0.65]$ naturally trigger the **`.escalate`** or **`.confirm`** routing policy in `MailTriageApp`, routing the message to human supervisors rather than taking autonomous action.

```swift
let decisiveness: Double? = p.map { max($0, 1.0 - $0) } ?? conf
let routingTier = RoutingPolicy.evaluate(confidence: decisiveness, probability: p)
```

---

## Implications

1. **Unification Under Apple Foundation Models**: By implementing `LanguageModel` and `LanguageModelExecutor`, developers interact with `OpenAIDecisionsLanguageModel` using canonical Apple APIs:
   ```swift
   let model = OpenAIDecisionsLanguageModel(endpoint: .hosted(model: "gpt-6-luna"), apiKey: key)
   let session = LanguageModelSession(model: model)
   let decision = try await session.respond(to: prompt, generating: EmailTriageDecision.self)
   ```
2. **Seamless Fallback in `MailTriageApp`**: MailTriage now provides a unified seven-architecture spectrum spanning offline privacy (On-Device Core ML), localhost development (laya-serve), private cloud (Hosted VPC), managed cloud (Jev Cloud), edge multimodal (Cloudflare Clef), global hyperscaler (OpenAI Decisions), and on-device generative baseline (Apple Intelligence).
3. **Resilience & Governance**: Built-in support for `OpenAI-Organization` and `OpenAI-Project` headers enables strict enterprise cost allocation and audit tracking directly from mobile and macOS endpoints.

---

## Evidence / Sources

- OpenAI Decisions API Specification: `POST /v1/decisions` (2026-10-08).
- `Sources/OpenAIFoundationModels/OpenAIDecisionsLanguageModel.swift`.
- `Sources/OpenAIFoundationModels/OpenAIDecisionsHTTPBackend.swift`.
- `Sources/OpenAIFoundationModels/OpenAIDecisionsPayloadAdapter.swift`.
- `Sources/OpenAIFoundationModels/OpenAIDecisionsWireDTOs.swift`.
- `Examples/MailTriageApp/apps/apple/Packages/AppCore/Sources/AppCore/Services/TriageEngine.swift`.
- `Examples/MailTriageApp/apps/apple/Packages/AppCore/Sources/AppCore/Models/TriageBackend.swift`.
