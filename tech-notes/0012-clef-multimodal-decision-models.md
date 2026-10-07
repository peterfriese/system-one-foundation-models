# 0012 — Cloudflare Clef & Clef-Flash Multimodal Decision Model Architecture

- **Date**: 2026-10-03
- **Author**: Peter Friese
- **Framework**: `FoundationModels` (iOS 27.0+, macOS 27.0+, visionOS 27.0+), `SystemOneCore`, `ClefFoundationModels`
- **Upstream**: Cloudflare Clef (27B), Cloudflare Clef-Flash (9B), Cloudflare Workers AI

---

## Context

Client applications and autonomous agents operating on Apple platforms are increasingly multimodal. Routine operational tasks require evaluating visual evidence in conjunction with textual state:
- **Visual Defect & Damage Triage**: Assessing whether camera captures of a returned parcel show transit damage prior to issuing an automated refund.
- **Identity & KYC Document Verification**: Validating whether an uploaded identity card satisfies framing, anti-glare, and legibility criteria.
- **Expense & Receipt Processing**: Categorizing merchant line items, detecting tax compliance, and identifying currency discrepancies from mobile camera scans.
- **Autonomous Agent UI Perception**: Inspecting application screenshots to detect modal alerts, interactive UI barriers, and accessibility defects during workflow automation.

### The Generative Vision-Language Model Dilemma

When developers implement visual decision-making using autoregressive multimodal generative models (e.g., GPT-4o, Claude 3.5 Sonnet, Gemini 1.5 Pro, or Llama 3.2 Vision), they encounter severe architectural handicaps:

1. **Autoregressive Latency Penalties**: Decoding prose descriptions or serialized JSON strings token-by-token introduces 1,200ms to 3,500ms of end-to-end latency. This overhead prohibits interactive sub-second mobile flows.
2. **Uncalibrated Hallucinated Confidence**: Generative decoders sample tokens based on conditional next-token probability distributions rather than calibrated Bayesian probabilities for propositions. Models hallucinate self-reported confidence or require secondary prompting passes, compromising automated escalation rules.
3. **Severe Token Overhead**: High-resolution image patching generates hundreds to thousands of vision tokens per image, inflating operational cloud spend on high-throughput batch workloads.
4. **Cloud Monoculture & Privacy Constraints**: Frontier vision models are predominantly closed cloud services. Developers cannot run them on local developer workstations, zero-egress corporate clouds, or edge worker environments.

### The Clef Breakthrough: System One Multimodality

Cloudflare has released **Clef** (27B, based on Qwen3.8) and **Clef-Flash** (9B, based on Qwen3.5)—the first dedicated multimodal decision models in the System One ecosystem. Rather than autoregressively generating text:
- Clef couples high-resolution multimodal vision transformers with rank-256 Low-Rank Adaptation (LoRA) and a specialized **joint schema routing head**.
- Clef evaluates contextual text and up to 4 high-resolution images ($\le 16\text{MP}$ each) in a **single forward pass**.
- Clef emits zero autoregressive content tokens (`output_tokens: 0`), computing calibrated decision primitives directly:
  - **`noul`**: Bayesian probability of truth ($0.0 \dots 1.0$) for boolean assertions.
  - **`choice`**: Discrete categorical classification across candidate options.
  - **`score`**: Bounded ordinal rubric scoring across numeric levels.

This tech note documents the architectural characteristics of Clef and Clef-Flash, the mechanics of its non-autoregressive decision pipeline, wire schema parity with Jev and Laya, multimodal attachment extraction from Apple Foundation Models transcripts, and deployment topologies spanning Cloudflare Workers AI to local inference engines.

---

## Findings

### 1. Architectural Discoveries: Clef (27B) & Clef-Flash (9B)

The Clef family is engineered specifically for fast, deterministic decision evaluation over visual and textual context:

| Metric / Attribute | Cloudflare Clef-Flash | Cloudflare Clef |
| :--- | :--- | :--- |
| **Backbone Architecture** | Qwen3.5 Multimodal Backbone | Qwen3.8 Multimodal Backbone |
| **Parameter Footprint** | ~9 Billion Parameters | ~27 Billion Parameters |
| **Target Deployment** | Ultra-low latency edge & local workstations | Complex multi-document reasoning |
| **Inference Time (Edge)** | ~35ms – 90ms (Workers AI edge GPU) | ~180ms – 320ms (Workers AI edge GPU) |
| **Inference Time (Local)** | ~45ms – 65ms (Apple Silicon M4 Max) | ~210ms – 280ms (Apple Silicon M4 Max) |
| **Maximum Visual Inputs** | 4 image attachments | 4 image attachments |
| **Resolution Boundary** | $\le 16$ Megapixels per image | $\le 16$ Megapixels per image |
| **Supported Image Types** | PNG, JPEG, WebP | PNG, JPEG, WebP |
| **Adapter Architecture** | Rank-256 LoRA + Joint Routing Head | Rank-256 LoRA + Joint Routing Head |
| **Autoregressive Decode** | None (`output_tokens: 0`) | None (`output_tokens: 0`) |

#### Latency vs. Reasoning Trade-offs
- **Clef-Flash (9B)** is optimized for interactive mobile workflows: responsive UI verification, instant receipt triage, and real-time camera framing checks. Its lightweight parameter count delivers sub-100ms cold evaluations on edge nodes.
- **Clef (27B)** delivers higher discriminative capacity for nuanced enterprise documents: multi-page PDF renders, subtle tampering in KYC credentials, and fine-grained legal or regulatory compliance checks.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Cloudflare Clef Execution Pipeline                   │
│                                                                         │
│  Context Text + Prompt      Image Attachments (1..4, <=16MP)            │
│         │                               │                               │
│         ▼                               ▼                               │
│  Text Tokenizer              Vision Patch Grid Encoder                  │
│         │                               │                               │
│         └───────────────┬───────────────┘                               │
│                         ▼                                               │
│       Qwen3.8 / Qwen3.5 Multimodal Backbone                             │
│       [Prefill Only — Bidirectional / Causal Hidden States]             │
│                         │                                               │
│                         ▼                                               │
│       Rank-256 LoRA Adaptation Layers                                   │
│                         │                                               │
│                         ▼                                               │
│       Joint Schema Routing Head                                         │
│       ┌────────────────────────────────────────────────────────┐        │
│       │ - Cross-attention pooling over text & visual patches   │        │
│       │ - Parallel projection to question type schema heads    │        │
│       └────────────────────────────────────────────────────────┘        │
│           │                     │                     │                 │
│           ▼                     ▼                     ▼                 │
│     noul Head              choice Head            score Head            │
│  (0.0...1.0 Prob)      (Normalized Probs)     (Rubric Levels)           │
│                                                                         │
│  Total Tokens Generated: 0      Latency: 35ms - 90ms (Prefill Only)     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 2. Single Forward-Pass Non-Autoregressive Decision Mechanism

Standard Large Language Models generate output autoregressively: given input tokens $x_{1 \dots n}$, they calculate $P(x_{n+1} \mid x_{1 \dots n})$, sample a token, append it to the sequence, and repeat until an end-of-sequence token is reached. This produces an $O(N)$ sequential delay proportional to the length of the generated response.

Clef discards autoregressive generation entirely. Decision synthesis is formulated as a single-pass classification and scoring task across prefill hidden states:

1. **Multimodal Prefill Ingestion**:
   - Text state and instructions are tokenized into standard text embedding vectors $E_{\text{text}}$.
   - Input images (1 to 4) are split into spatial patch grids and projected through the vision encoder into visual embedding vectors $E_{\text{vis}}$.
   - The concatenated sequence $[E_{\text{text}} ; E_{\text{vis}}]$ passes through the Qwen3.8/3.5 transformer backbone in a single forward pass.
2. **Rank-256 Low-Rank Adaptation (LoRA)**:
   - To adapt the base multimodal LLM without corrupting general semantic representations, high-rank LoRA matrices ($r=256, \alpha=512$) are applied to attention query, key, value, and output projection layers:
     $$W = W_0 + \frac{\alpha}{r} (B \cdot A)$$
   - The high rank ($r=256$) preserves subtle perceptual signals from image patches while steering hidden states toward decision boundaries.
3. **Joint Schema Routing Head**:
   - Hidden representations from the final transformer layer are pooled via cross-attention with schema question queries.
   - The routing head branches into three parallel classification heads corresponding to System One primitives:
     - **`noul` head**: A sigmoid classification head outputting a calibrated Bayesian probability $p \in [0.0, 1.0]$.
     - **`choice` head**: A linear projection to candidate option indices followed by temperature-scaled softmax normalization:
       $$P(\text{option}_i) = \frac{e^{z_i / T}}{\sum_{j=1}^K e^{z_j / T}}$$
     - **`score` head**: An ordinal projection computing discrete level probabilities and an expected continuous score:
       $$\mathbb{E}[\text{score}] = \sum_{l=1}^L \text{val}(l) \cdot P(l)$$
4. **Zero Output Tokens (`output_tokens: 0`)**:
   - Because all question logits are computed simultaneously from the prefill activations, the model emits no textual generation tokens.
   - HTTP responses return `output_tokens: 0` in the usage block, drastically minimizing compute costs and network transmission size.

---

### 3. Comparison of Decision Primitives and Wire Envelopes

The TypeSafe System One specification defines three core primitives: `noul`, `choice`, and `score`. Cloudflare Clef maintains complete semantic compatibility with these primitives while introducing support for visual context.

#### Primitives Comparison Across System One Backends

| Primitive | Semantic Meaning | Output Data Structure | Jev / Laya Parity | Clef Multimodal Parity |
| :--- | :--- | :--- | :--- | :--- |
| **`noul`** | Probability of truth for a boolean proposition | `{"noul": 0.94}` | Calibrated probability in $[0.0, 1.0]$ | Supported; evaluates visual evidence against assertion |
| **`choice`** | Categorical selection among discrete options | `{"choice": "valid", "probabilities": {"valid": 0.88, "fraud": 0.12}}` | Mutually exclusive categorical labels | Supported; assigns visual evidence across discrete categories |
| **`score`** | Ordinal rating on an explicit rubric scale | `{"score": 4.2, "levels": {"1": 0.05, "2": 0.05, "3": 0.10, "4": 0.80}}` | Expected score + level distribution | Supported; scores visual quality or compliance against rubric |

#### Wire Request Envelope Comparison

Text-only backends (TypeSafe Jev, local `laya-serve`) accept text context in `state`. Clef extends this structure with an optional `images` collection:

##### Jev / Laya Request Payload (`POST /v1/systemone`):
```json
{
  "state": "The user reported an unauthorized transaction of $450 at 02:30 AM.",
  "model": "jev-default",
  "questions": {
    "is_fraud": {
      "type": "noul",
      "instructions": "Determine if the transaction exhibits fraudulent characteristics."
    }
  }
}
```

##### Clef Request Payload (`POST /v1/evaluate` or Workers AI):
```json
{
  "state": "Inspect this physical receipt for reimbursement compliance.",
  "model": "@cf/cloudflare/clef-flash",
  "questions": {
    "is_compliant": {
      "type": "noul",
      "instructions": "Is the receipt intact with visible date and line items?"
    },
    "expense_category": {
      "type": "choice",
      "instructions": "Select the merchant expense category.",
      "options": ["meals", "lodging", "travel", "supplies"]
    }
  },
  "images": [
    {
      "format": "image/jpeg",
      "data_url": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQE...",
      "identifier": "camera_capture_01.jpg"
    }
  ]
}
```

##### Unified Response Envelope:
```json
{
  "id": "clef_resp_01jb9w1q",
  "model": "@cf/cloudflare/clef-flash",
  "questions": {
    "is_compliant": {
      "type": "noul",
      "noul": 0.965
    },
    "expense_category": {
      "type": "choice",
      "choice": "meals",
      "probabilities": {
        "meals": 0.92,
        "lodging": 0.04,
        "travel": 0.03,
        "supplies": 0.01
      }
    }
  },
  "usage": {
    "input_tokens": 1420,
    "output_tokens": 0
  }
}
```

Notice the crucial characteristic: `output_tokens` is strictly `0`, reflecting the non-autoregressive forward-pass nature of the inference.

---

### 4. Multimodal Data Attachment Mapping in Apple Foundation Models Framework

Apple's Foundation Models framework (`FoundationModels`) models conversational turns through `Transcript` entries and segments. The bridge extracts visual data segments cleanly without requiring proprietary session wrappers.

#### Supported UTTypes and Extraction Pipeline

In `ClefFoundationModels`, `ClefLanguageModel` declares explicit support for standard image uniform type identifiers:

```swift
import FoundationModels
import UniformTypeIdentifiers

extension UTType {
    public static let supportedClefImageTypes: Set<UTType> = [
        .png,
        .jpeg,
        .webP
    ]
}
```

When evaluating a `@Generable` schema with `session.respond(to:generating:)`, the caller passes image segments inside the `Transcript`:

```swift
let imageSegment = Transcript.Segment.data(imageData, type: .jpeg)
let prompt = Transcript.Entry.prompt(
    "Verify the authenticity of this photo ID.",
    attachments: [imageSegment]
)
let response = try await session.respond(to: prompt, generating: IdentityVerificationDecision.self)
```

#### Transcript Ingestion & Guardrail Enforcement

The `TranscriptAttachmentExtractor` inspects incoming transcript entries, extracts valid data segments, maps `UTType` to `SystemOneImage.Format`, and enforces model boundaries:

```swift
public enum TranscriptAttachmentExtractor {
    public static let maximumImageCount: Int = 4
    public static let maximumMegapixels: Double = 16.0

    public static func extractImages(from transcript: Transcript) throws -> [SystemOneImage] {
        var images: [SystemOneImage] = []

        for entry in transcript {
            switch entry {
            case .prompt(let prompt):
                for segment in prompt.segments {
                    if case .data(let data, let type) = segment {
                        guard let format = mapUTTypeToFormat(type) else {
                            throw ClefError.unsupportedAttachmentType(type.identifier)
                        }
                        try validateImageResolution(data: data, format: format)
                        images.append(SystemOneImage(data: data, format: format))
                    }
                }
            default:
                break
            }
        }

        if images.count > maximumImageCount {
            throw ClefError.imageCountExceeded(count: images.count, maximum: maximumImageCount)
        }

        return images
    }
}
```

#### Low-Overhead Dimension Parsing
To prevent memory exhaustion on mobile devices when handling multiple 16MP images, `validateImageResolution` reads image dimensions directly from the file header (e.g., JPEG `SOF0` marker or PNG `IHDR` chunk) rather than decompressing full bitmaps into memory.

---

### 5. Edge Workers AI vs. Local Serving Topologies

Clef evaluations can be routed to Cloudflare's global edge infrastructure or hosted locally for privacy-critical offline execution. The `ClefEndpoint` enum abstracts these deployment targets:

```swift
public enum ClefEndpoint: Sendable, Hashable {
    /// Cloudflare Workers AI edge execution across 330+ edge data centers.
    case workersAI(accountID: String, apiToken: String, model: ClefModel = .clefFlash)

    /// Cloudflare AI Gateway with centralized caching, rate limiting, and analytics.
    case aiGateway(accountID: String, gatewayID: String, apiToken: String, model: ClefModel = .clefFlash)

    /// Self-hosted local or private container runtime (vLLM, Cog, MLX, Docker Model Runner).
    case local(url: URL = URL(string: "http://localhost:8000/v1/evaluate")!, apiKey: String? = nil, model: String = "clef-flash")
}
```

#### Serving Topology Comparison

```
┌────────────────────────────────────────────────────────────────────────┐
│                      Clef Serving Topology Matrix                      │
├───────────────────────┬──────────────────────┬─────────────────────────┤
│ Characteristic        │ Cloudflare Workers AI│ Local / Self-Hosted     │
├───────────────────────┼──────────────────────┼─────────────────────────┤
│ Runtimes Supported    │ Workers AI Edge,     │ vLLM, Cog, MLX Server,  │
│                       │ Cloudflare AI Gateway│ Docker Model Runner     │
│ Hardware              │ Multi-tenant Cloud   │ Apple Silicon M4 /      │
│                       │ GPU infrastructure   │ NVIDIA Private Clusters │
│ Latency (Flash 9B)    │ 35ms – 90ms          │ 45ms – 65ms (Apple M4)  │
│ Cold Start Overhead   │ 150ms – 400ms        │ 0ms (pre-loaded daemon) │
│ Data Privacy          │ Transit encryption   │ Zero-egress / Air-gap   │
│ Auth Mechanism        │ Cloudflare API Token │ None / Static API Key   │
│ Telemetry Headers     │ cf-ray, server-timing│ x-envoy-service-time    │
└───────────────────────┴──────────────────────┴─────────────────────────┘
```

#### Telemetry Extraction and Resilience
1. **Edge Tracing**: `ClefHTTPBackend` parses Cloudflare's `cf-ray` header to enable distributed tracing and edge support correlation.
2. **RFC 7668 `server-timing` Parsing**: Metrics like `cfL4;dur=12` (edge network transit) and `inference;dur=45` (pure model forward pass) are extracted into `LanguageModelSession.Response` metadata.
3. **Resilience & Backoff**: Edge environments occasionally surface transient status codes:
   - `429 Too Many Requests`: Cloudflare rate limiting.
   - `504 Gateway Timeout` / `524 A Timeout Occurred`: Edge routing cold-start delays.
   - `529 Site Overloaded`: Edge GPU queue saturation.
   The integrated `RetryPolicy` adheres strictly to RFC 9110, backing off exponentially with full jitter and respecting incoming `Retry-After` headers.

---

## Implications

1. **Native Apple Ergonomics for Multimodal Decisions**:
   Developers write standard Apple Swift code without learning proprietary SDK surfaces:
   ```swift
   let clef = ClefLanguageModel(endpoint: .workersAI(accountID: "...", apiToken: "..."))
   let session = LanguageModelSession(model: clef)
   let response = try await session.respond(to: prompt, generating: DamageInspectionDecision.self)
   ```
2. **Dual-Signal Confidence Routing**:
   Every visual decision produces strongly-typed values alongside calibrated probabilities that feed directly into `SystemOneCore`'s `RoutingPolicy`:
   - High confidence ($\ge 0.85$): Proceed autonomously (e.g., auto-approve refund).
   - Medium confidence ($0.60 \dots 0.849$): Prompt user for confirmation.
   - Low confidence / Ambiguous visual evidence ($< 0.60$): Escalate to human operator.
3. **SPM Trait Sandboxing**:
   Following the trait architecture introduced in Tech Note 0009, Clef support is isolated behind the `Clef` trait and `ClefFoundationModels` target. Applications that only require on-device Core ML (`LayaOnDevice`) do not compile or bundle image parsing and Cloudflare network routines.
4. **Deterministic Offline CI Testing**:
   Because `ClefHTTPBackend` adheres to the `SystemOneBackend` protocol, unit and integration tests simulate image classification using `MockClefBackend` or `MockSystemOneBackend` with zero external network connectivity or Cloudflare tokens.

---

## Sources & References

- Cloudflare Workers AI: [Clef Multimodal Decision Model Documentation](https://developers.cloudflare.com/workers-ai/models/)
- Apple Developer Documentation: [Foundation Models Framework (iOS 27.0+, macOS 27.0+)](https://developer.apple.com/documentation/foundationmodels)
- Apple Developer Documentation: [UniformTypeIdentifiers](https://developer.apple.com/documentation/uniformtypeidentifiers)
- SystemOneFoundationModels ADR: [ADR-2026-10-03-01: Cloudflare Clef & Clef-Flash Integration](../docs/architecture/ADR-2026-10-03-01-clef-foundation-models-integration.md)
- SystemOneFoundationModels PRD: [PRD-2026-10-03: Cloudflare Clef Decision Models](../docs/prd/PRD-2026-10-03-clef-decision-models.md)
- RFC 2397: [The "data" URL Scheme](https://datatracker.ietf.org/doc/html/rfc2397)
- RFC 7668 / W3C: [Server Timing](https://www.w3.org/TR/server-timing/)
- RFC 9110: [HTTP Semantics & Retry-After Guidelines](https://datatracker.ietf.org/doc/html/rfc9110)
- Tech Note 0001: [Bridging Decision Models into Apple Foundation Models via Channel Synthesis](0001-afm-decision-model-bridging.md)
- Tech Note 0007: [Pluggable System One Backends & Wire Compatibility with Laya HTTP Serving](0007-pluggable-system-one-backends-and-laya-serve.md)
- Tech Note 0008: [On-Device Decision Models via Core ML, Apple Neural Engine, and Native Tokenization](0008-on-device-coreml-decision-engine.md)
- Tech Note 0009: [Package Traits & Ergonomic Decision Shortcuts in System One Foundation Models](0009-package-traits-and-ergonomic-shortcuts.md)
- Tech Note 0010: [Dynamic Credential Resolution & Reverse Proxying with ProxyTransport](0010-proxy-transport-and-dynamic-attestation.md)
