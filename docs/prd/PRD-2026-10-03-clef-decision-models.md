# PRD: Cloudflare Clef & Clef-Flash Multimodal Decision Model Support

- **Document ID**: `PRD-2026-10-03-clef-decision-models`
- **Date**: 2026-10-03
- **Status**: Draft / Ready for Architectural Review
- **Owner**: Product Manager Agent
- **Architect**: Senior Architect Agent
- **Target Branch**: `feature/clef-decision-models`
- **Target Release**: SystemOneFoundationModels 1.2.0 (iOS 27.0+, macOS 27.0+, visionOS 27.0+)
- **Upstream / Specs**: Apple Foundation Models Framework, Cloudflare Clef & Clef-Flash Open-Weight Model Family (`Cloudflare/clef`, `Cloudflare/clef-flash`), Cloudflare Workers AI, TypeSafe AI System One Primitives

---

## 1. Problem Statement & Strategic Vision

Modern client applications, autonomous agent pipelines, and enterprise automation workflows are increasingly multimodal. Real-world decision-making rarely relies on raw text alone:
- **Visual Defect & Damage Triage**: Assessing whether a product photo shows physical damage before approving a refund or initiating a warranty claim.
- **Identity & KYC Verification**: Verifying whether an uploaded identity document photo matches biometric requirements and is free of glare, tampering, or cropping.
- **Expense & Receipt Processing**: Classifying merchant categories, currency consistency, and receipt readability directly from mobile camera captures.
- **Autonomous Agent & UI Perception**: Evaluating screenshots to determine whether an error dialog has blocked navigation, whether an accessibility label is missing, or which interactive element must be actuated next.
- **Multimodal Customer Support & Moderation**: Routing inbound user requests containing both explanatory text and screenshot attachments to appropriate human teams or automated workflows.

### The Multimodal Generative LLM Dilemma
Currently, developers building visual routing and classification into Apple applications face severe operational handicaps when relying on generative multimodal Large Language Models (e.g., GPT-4o, Claude 3.5 Sonnet, Gemini 1.5 Pro):
1. **Excessive Latency & Compute Inefficiency**: Generative vision-language models take 1,200ms to 3,500ms to autoregressively decode descriptive text, markdown tables, or JSON strings. For high-volume transactional classification, this latency degrades user experiences and limits real-time mobile throughput.
2. **Absence of Calibrated Probabilities**: Autoregressive decoders output tokens, not calibrated Bayesian probabilities. They cannot natively supply mathematically grounded confidence metrics. Systems are forced to parse ad-hoc confidence ratings or self-reported likelihood scores hallucinated by the model.
3. **High Token Costs**: Processing high-resolution images through generative tokenizers generates hundreds or thousands of vision tokens per image, leading to unsustainable operational expenses for automated triage loops.
4. **Lack of Deployment Flexibility**: Most frontier vision models are proprietary cloud-only APIs. Developers cannot deploy them into zero-egress private clouds, run them offline on local Apple Silicon hardware, or bind them directly to edge worker runtimes.

### The Clef Breakthrough: System One Multimodality
**Cloudflare Clef** (27B) and **Clef-Flash** (9B) represent a landmark advancement: they are the **first multimodal decision models in the System One ecosystem**. 

Rather than generating verbose prose, Clef couples high-capacity backbones (Qwen3.8 for Clef, Qwen3.5 for Clef-Flash) and high-resolution vision encoders with rank-256 Low-Rank Adaptation (LoRA) and a specialized **joint schema routing head**. This architecture enables the model to evaluate text state alongside up to 4 high-resolution images in a single forward pass, directly computing calibrated decision primitives:
- **`noul`**: Calibrated Bayesian probability of truth ($0.0 \dots 1.0$) for boolean propositions.
- **`choice`**: Discrete categorical classification across mutually exclusive candidate labels.
- **`score`**: Bounded ordinal rubric scoring across numeric levels.

### The Pedagogical & Architectural Mission in SystemOneFoundationModels
`SystemOneFoundationModels` bridges System One decision models to Apple's native **Foundation Models** framework (`LanguageModel`, `LanguageModelSession`, `@Generable`, `@Guide`). 

With the introduction of Clef, developers can evaluate multimodal schemas with standard Apple APIs and zero vendor-specific wrappers:
```swift
// 1. Initialize Clef model backed by Cloudflare Workers AI or local runtime
let clef = ClefLanguageModel(endpoint: .workersAI(accountID: "...", apiToken: "..."))
let session = LanguageModelSession(model: clef)

// 2. Prepare multimodal input (Text + Images)
let receiptImage = Transcript.Segment.image(data: receiptData, mimeType: .jpeg)
let prompt = Transcript.Entry.prompt("Evaluate this reimbursement request for compliance.", attachments: [receiptImage])

// 3. Strongly-typed multimodal evaluation in a single forward pass
let response = try await session.respond(to: prompt, generating: ExpenseVerificationDecision.self)

// 4. Access calibrated dual signals:
let decision = response.content               // Struct with isCompliant, merchantCategory, riskScore
let routing = routingPolicy.decide(decision)  // .auto (>=0.85), .confirm (0.60..<0.85), .escalate (<0.60)
```

This PRD formalizes the product requirements, user personas, functional specifications, acceptance criteria, non-functional requirements, edge case behaviors, and engineering boundaries for integrating Cloudflare Clef and Clef-Flash into the `SystemOneFoundationModels` Swift package.

---

## 2. User Personas & User Stories

### User Personas
1. **Elena (Senior iOS / Apple Platform Engineer)**: Builds camera-enabled enterprise and consumer apps for iOS 27 and macOS 27. Values pure Swift 6 ergonomics, strict concurrency compliance, zero external third-party binary dependencies, and native Foundation Models `@Generable` ergonomics with Apple `UTType` attachments.
2. **Kiran (ML Engineer / Edge AI Infrastructure Lead)**: Deploys edge-accelerated decision engines across distributed teams. Requires first-class support for Cloudflare Workers AI and Cloudflare AI Gateway (with analytics, caching, and rate limiting), alongside self-hosted inference in private Kubernetes clusters via vLLM or Docker Model Runner.
3. **Marcus (Autonomous Agent & Systems Architect)**: Develops autonomous desktop and mobile workflow agents. Needs sub-150ms visual state verification (e.g., verifying form completion, error popups, visual layout states) with mathematically calibrated confidence to trigger reliable automated rollbacks and branch transitions.
4. **Siddharth (Enterprise Privacy & Compliance Officer)**: Enforces strict data privacy. Demands options for 100% on-device or local network inference (via MLX, GGUF, or local Docker runner on Apple Silicon) where user images never leave enterprise hardware boundaries.

### User Stories

- **US-1 (Multimodal `@Generable` Evaluation)**:
  - **As an** Apple platform engineer,
  - **I want to** pass image data attachments (PNG, JPEG, WebP) directly into a `LanguageModelSession` evaluating a `@Generable` schema,
  - **So that** I can extract structured boolean, categorical, and rubric decisions from visual and textual context simultaneously without manual image pre-processing.

- **US-2 (Model Family Selection: Clef 27B vs. Clef-Flash 9B)**:
  - **As a** developer optimizing latency versus cognitive depth,
  - **I want to** configure whether my `ClefLanguageModel` evaluates against Clef (27B) or Clef-Flash (9B),
  - **So that** I can choose Clef-Flash for ultra-low latency mobile interactions (~35ms) or Clef for complex multi-image document reasoning.

- **US-3 (Cloudflare Workers AI & AI Gateway Integration)**:
  - **As an** edge computing developer,
  - **I want to** route Clef decision requests through Cloudflare Workers AI (`@cf/cloudflare/clef`, `@cf/cloudflare/clef-flash`) and Cloudflare AI Gateway,
  - **So that** I can leverage Cloudflare's global edge network, unified authentication, centralized request caching, and observability.

- **US-4 (Local & Self-Hosted Execution Support)**:
  - **As an** enterprise privacy engineer or offline developer,
  - **I want to** target locally hosted Clef endpoints running via Docker Model Runner (`docker model run hf.co/Cloudflare/clef`), vLLM, SGLang, or Apple Silicon MLX/GGUF servers,
  - **So that** visual decisions can be evaluated completely offline or within private air-gapped corporate networks.

- **US-5 (Calibrated Visual Confidence & Routing Policy)**:
  - **As an** autonomous agent architect,
  - **I want** Clef visual evaluations to produce calibrated Bayesian confidence scores that plug into `SystemOneCore`'s `RoutingPolicy`,
  - **So that** visual actions with confidence $\ge 85\%$ execute autonomously, mid-confidence results ($60\%\dots84.9\%$) trigger user confirmation, and ambiguous images escalate to human review.

- **US-6 (SPM Trait & Dependency Hygiene)**:
  - **As an** app developer mindful of binary size and dependency footprint,
  - **I want** Clef support packaged cleanly under an optional SPM trait or dedicated target (`ClefFoundationModels`),
  - **So that** projects only needing on-device Laya or TypeSafe Jev are not forced to compile unneeded Clef networking or configuration code.

---

## 3. Model Architecture & Ecosystem Context

### 3.1 Model Specifications

| Attribute | Cloudflare Clef (`Cloudflare/clef`) | Cloudflare Clef-Flash (`Cloudflare/clef-flash`) |
| :--- | :--- | :--- |
| **Parameter Scale** | 27 Billion parameters | 9 Billion parameters |
| **Language Backbone** | Qwen3.8 Base | Qwen3.5 Base |
| **Vision Encoder** | High-resolution multimodal vision transformer | High-resolution multimodal vision transformer |
| **Fine-Tuning Architecture** | Rank-256 LoRA + Joint Schema Routing Head | Rank-256 LoRA + Joint Schema Routing Head |
| **Forward Pass Semantics** | Single joint pass (Text + Vision + Routing Head) | Single joint pass (Text + Vision + Routing Head) |
| **License** | Open-weight Apache 2.0 (Hugging Face) | Open-weight Apache 2.0 (Hugging Face) |
| **Hugging Face Hub** | `hf.co/Cloudflare/clef` | `hf.co/Cloudflare/clef-flash` |
| **Workers AI Identifier** | `@cf/cloudflare/clef` | `@cf/cloudflare/clef-flash` |
| **Image Capacity** | Up to 4 images per evaluation | Up to 4 images per evaluation |
| **Supported Image Formats** | PNG, JPEG, WebP | PNG, JPEG, WebP |
| **Maximum Image Resolution** | Up to 16 Megapixels (16MP) per image | Up to 16 Megapixels (16MP) per image |
| **Primary Use Cases** | Complex document analysis, multi-image comparison, subtle defect inspection, high-stakes verification | Real-time UI inspection, fast receipt triage, edge mobile perception, autonomous agent micro-decisions |

### 3.2 Joint Schema Routing Head Mechanics
Traditional multimodal LLMs concatenate visual tokens to text tokens and auto-regressively generate output characters one token at a time. In contrast, Clef projects the final hidden representations of the joint text-vision prompt directly into a specialized multi-head classifier:
1. **Noul Head**: Predicts the log-odds of boolean proposition truth, passed through a temperature-calibrated sigmoid function to produce an exact probability $p \in [0.0, 1.0]$.
2. **Choice Head**: Computes normalized softmax probabilities over candidate category criteria keys, returning the top-ranked label and categorical distribution.
3. **Score Head**: Evaluates cumulative ordinal logistic distributions across defined rubric levels, outputting expected rubric values and rubric bin probabilities.

---

## 4. Functional Requirements

### FR-1: Multimodal Data Attachment Support in Foundation Models
1. **Capability Reporting**:
   - `ClefLanguageModel` and `SystemOneLanguageModel` (when configured with a multimodal backend) shall implement `LanguageModel.supportsDataAttachmentType(_ type: UTType)` to declare native support for:
     - `UTType.png` (`public.png`)
     - `UTType.jpeg` (`public.jpeg`)
     - `UTType.webP` (`org.webmproject.webp`)
   - All other attachment types (e.g., audio, video, arbitrary binary blobs) shall return `false`.
2. **Transcript Attachment Ingestion**:
   - The executor shall inspect entries within the Foundation Models `Transcript`.
   - The executor shall extract data attachment segments containing supported image MIME types, converting them into structured image representations (`ClefImageAttachment`).
3. **Image Constraints & Guardrails**:
   - **Maximum Image Count**: The system shall support a maximum of 4 images per evaluation request. If more than 4 images are supplied in the transcript, the executor shall throw `ClefError.imageCountExceeded(count: Int, maximum: 4)`.
   - **Maximum Image Resolution**: Up to 16 Megapixels (16MP) per image. The client library shall inspect image metadata (headers) without full bitmap decompression where possible; if an image exceeds 16MP, the client shall provide an automatic opt-in downscaling utility or throw `ClefError.imageResolutionExceeded(megapixels: Double, maximum: 16.0)`.
   - **Supported Payload Formats**: The backend transport shall format images either as RFC 2397 base64 data URLs (`data:image/{format};base64,...`) or as structured JSON objects `{ "type": "image", "data": "...", "mime_type": "..." }` conforming to the Cloudflare API schema.

### FR-2: Schema Translation & Bounded Decision Evaluation
1. **Mapping to System One Primitives**:
   - The schema translation engine (`SchemaTranslator`) shall map `@Generable` properties to Clef questions identical to existing System One rules:
     - `Bool` $\to$ `noul` question with `@Guide(description:)` instructions.
     - `enum` / `anyOf` $\to$ `choice` question with case names and `@Guide(description:)` criteria.
     - Numeric types with `@Guide(.range(A...B))` $\to$ `score` question with ordinal rubric levels.
2. **Structured Output Enforcement**:
   - Requests without a valid `@Generable` schema must throw `SystemOneError.structuredOutputRequired`. Unstructured generative prose chat completion is strictly rejected.
3. **Dual-Signal Response Synthesis**:
   - The engine shall synthesize both:
     - The strongly-typed `@Generable` Swift struct instance (`response.content`).
     - Calibrated confidence and probability metadata (`response.metadata["probabilities"]`, `response.metadata["confidence"]`, `response.metadata["scores"]`).

### FR-3: Backend & Transport Architecture
The library shall provide dedicated, highly configurable backends conforming to `SystemOneBackend`:

```
                           +---------------------------+
                           | LanguageModelSession      |
                           +-------------+-------------+
                                         |
                           +-------------v-------------+
                           | ClefLanguageModel         |
                           +-------------+-------------+
                                         |
                           +-------------v-------------+
                           | ClefBackend (Protocol)    |
                           +-------------+-------------+
                                         |
         +-------------------------------+-------------------------------+
         |                               |                               |
+--------v--------------+     +----------v------------+     +------------v------------+
| ClefWorkersAIBackend  |     | ClefLocalBackend      |     | MockClefBackend         |
| (Cloudflare Edge &    |     | (Docker Model Runner, |     | (Deterministic Offline  |
|  AI Gateway)          |     |  vLLM, SGLang, MLX)   |     |  Unit Testing)          |
+-----------------------+     +-----------------------+     +-------------------------+
```

1. **`ClefWorkersAIBackend` (Cloudflare Hosted Edge)**:
   - **Target Endpoints**:
     - Direct Workers AI REST API: `https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/{model}`
     - Cloudflare AI Gateway: `https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/workers-ai/{model}`
   - **Authentication**:
     - Cloudflare API Token via HTTP header `Authorization: Bearer {api_token}`.
   - **Model Identifiers**:
     - `@cf/cloudflare/clef` (27B)
     - `@cf/cloudflare/clef-flash` (9B)
   - **AI Gateway Features**:
     - Caching control via `cf-aig-cache-key` or standard gateway headers.
     - Centralized rate limiting, request logging, and telemetry tracking.
   - **Worker Binding Emulation**:
     - Documentation and payload alignment for edge developers deploying Workers with `env.AI.run("@cf/cloudflare/clef", ...)`.
2. **`ClefLocalBackend` (Self-Hosted & Local Inference)**:
   - **Target Configurations**:
     - Docker Model Runner: `http://localhost:8080/v1` (running `docker model run hf.co/Cloudflare/clef`).
     - vLLM / SGLang / Python `joint_schema_model.py` HTTP servers.
     - Apple Silicon MLX / GGUF local quantization servers.
   - **Authentication**: Optional Bearer token or API key (default: none).
   - **Configurable Endpoints**: Custom URL schemes, ports, and base paths.
3. **`MockClefBackend` (Deterministic Offline Testing)**:
   - Pre-canned multimodal responses, schema verification, and latency simulation.
   - Zero network access required; executable in hermetic CI pipelines without Cloudflare credentials.

### FR-4: First-Class Swift Ergonomics
1. **Public Types & Initialization**:
   ```swift
   // Initializing with Workers AI
   let model = ClefLanguageModel(
       model: .clefFlash, // or .clef
       endpoint: .workersAI(accountID: "cf_acc_123", apiToken: "cf_tok_abc", gatewayID: "my-gateway")
   )

   // Initializing with local Docker runner
   let localModel = ClefLanguageModel(
       model: .clef,
       endpoint: .localDocker(port: 8080)
   )
   ```
2. **Convenience Extensions for Apple Images**:
   - Native Swift helpers to construct multimodal `Transcript` prompts from:
     - `Data` (with explicit MIME type: `.png`, `.jpeg`, `.webP`)
     - Apple `UTType` validation
     - Cross-platform image helpers (`UIImage` on iOS/visionOS, `NSImage` on macOS) via optional extension modules or core Foundation `Data` abstractions.
3. **Confidence Routing Integration**:
   - Full compatibility with `RoutingPolicy` from `SystemOneCore`.
   - Automatic calculation of decisiveness metrics for visual triage (`.auto`, `.confirm`, `.escalate`).

### FR-5: Package Architecture & Trait Configuration
1. **Target Structure in `Package.swift`**:
   - Introduce a new target `ClefFoundationModels` depending on `SystemOneCore`.
   - Maintain zero external third-party package dependencies (pure native `URLSession`, `JSONDecoder`, `Foundation`, `UniformTypeIdentifiers`).
2. **Package Trait Integration**:
   - Add `.trait(name: "Clef", description: "Enables Cloudflare Clef and Clef-Flash multimodal decision models")`.
   - Add `.trait(name: "All", enabledTraits: ["Jev", "Laya", "LayaServe", "Clef"])`.
   - Ensure the library compiles cleanly when only `Clef` is enabled, or when combined with `Laya` and `Jev`.

---

## 5. Acceptance Criteria

### AC-1: Multimodal Schema Evaluation with Images
- **Scenario 1.1**: Single Image Attachment Processing
  - **Given** an open `LanguageModelSession` configured with `ClefLanguageModel(model: .clefFlash)`,
  - **When** the caller submits a prompt containing text and a valid 2MB JPEG image attachment, generating a `@Generable` decision struct `DamagedPackageDecision`,
  - **Then** the request payload to the Clef backend shall contain the state text, the translated System One questions, and the base64-encoded JPEG image attachment, returning an evaluated decision with calibrated probabilities.
- **Scenario 1.2**: Multi-Image Comparison (Up to 4 Images)
  - **Given** a prompt comparing 3 distinct PNG screenshots of a user interface,
  - **When** the session responds against `ClefLanguageModel(model: .clef)`,
  - **Then** all 3 images are serialized in order, the backend executes a single joint forward pass, and the resulting enum choice is decoded accurately.
- **Scenario 1.3**: Excessive Image Count Rejection
  - **Given** a prompt containing 5 image attachments,
  - **When** `session.respond(...)` is called,
  - **Then** the executor immediately throws `ClefError.imageCountExceeded(count: 5, maximum: 4)` before making any network request.

### AC-2: Schema Translation & Primitive Mapping
- **Scenario 2.1**: Translating Mixed Multimodal Decision Schemas
  - **Given** a `@Generable` struct containing `isSuspicious: Bool`, `fraudCategory: FraudCategory`, and `riskLevel: Int` with `@Guide(.range(1...5))`,
  - **When** translated by `SchemaTranslator`,
  - **Then** the generated request contains exactly one `noul`, one `choice`, and one `score` question with rubric range $[1, 5]$.
- **Scenario 2.2**: Rejecting Unstructured Text Generation
  - **Given** a request to `ClefLanguageModel` invoked without a `@Generable` schema (plain string chat completion),
  - **When** `executor.respond(...)` executes,
  - **Then** it throws `SystemOneError.structuredOutputRequired`.

### AC-3: Cloudflare Workers AI & AI Gateway Connectivity
- **Scenario 3.1**: Successful Direct Workers AI Dispatch
  - **Given** valid Cloudflare credentials (`accountID` and `apiToken`),
  - **When** evaluating against `ClefLanguageModel.Endpoint.workersAI(...)` with model `.clefFlash`,
  - **Then** an HTTP POST is issued to `https://api.cloudflare.com/client/v4/accounts/{accountID}/ai/run/@cf/cloudflare/clef-flash` with header `Authorization: Bearer {apiToken}` and `Content-Type: application/json`.
- **Scenario 3.2**: AI Gateway Routing & Cache Headers
  - **Given** an endpoint configured with `gatewayID: "enterprise-gateway"`,
  - **When** a decision request is dispatched,
  - **Then** the HTTP request routes to `https://gateway.ai.cloudflare.com/v1/{accountID}/enterprise-gateway/workers-ai/@cf/cloudflare/clef` and includes appropriate gateway headers.
- **Scenario 3.3**: RFC 9110 Rate Limit Handling
  - **Given** Cloudflare Workers AI responds with HTTP status 429 and `Retry-After: 3`,
  - **When** `RetryPolicy` is active,
  - **Then** the backend waits the indicated duration with jitter and retries up to configured retry limits before surfacing an error.

### AC-4: Local Runner & MLX Inference
- **Scenario 4.1**: Local Docker Model Runner Execution
  - **Given** a local Docker container running `docker model run hf.co/Cloudflare/clef` on `http://127.0.0.1:8080`,
  - **When** configured with `ClefLanguageModel(endpoint: .localDocker(port: 8080))`,
  - **Then** requests dispatch to `http://127.0.0.1:8080/v1/evaluate` without authorization headers, returning valid `SystemOneResponse` payloads.
- **Scenario 4.2**: Graceful Offline Error Reporting
  - **Given** a local endpoint where the runner is not booted,
  - **When** a decision evaluation is attempted,
  - **Then** the library catches the socket connection refusal and returns a typed, human-actionable `ClefError.localRunnerUnreachable(endpoint:port:remediation:)`.

### AC-5: Visual Confidence Routing & Guardrails
- **Scenario 5.1**: High-Confidence Visual Automation
  - **Given** an image of a clean receipt evaluated with `isReceipt: true` at probability $0.96$,
  - **When** evaluated by `RoutingPolicy.default`,
  - **Then** `decision.routing` resolves to `.auto`, enabling zero-click automated processing.
- **Scenario 5.2**: Ambiguous Image Escalation
  - **Given** a blurry or corrupted photo where the model returns `noul: 0.51` (within the $0.35\dots0.65$ epistemic indecision band),
  - **When** passed to `RoutingPolicy.default`,
  - **Then** the routing resolves to `.escalate`, flagging the visual item for manual review.

### AC-6: Swift 6 Strict Concurrency & Multiplatform Build
- **Scenario 6.1**: Strict Concurrency Compilation
  - **Given** the `ClefFoundationModels` target compiled with `-strict-concurrency=complete` in Swift 6.1,
  - **When** building on macOS 27, iOS 27, and visionOS 27,
  - **Then** the build completes with zero concurrency warnings, zero data race hazards, and all public types conforming to `Sendable`.
- **Scenario 6.2**: Offline Deterministic Testing
  - **Given** the test suite executed with no internet connection and no API keys,
  - **When** running `swift test`,
  - **Then** all unit tests using `MockClefBackend` pass deterministically in $<2$ seconds.

---

## 6. Non-Functional Requirements

### 6.1 Performance & Latency Budgets
- **Workers AI Hosted Inference Latency**:
  - `Clef-Flash` (9B multimodal): $\le 90$ ms server-side inference latency for single-image requests; $< 250$ ms total client round-trip over broadband.
  - `Clef` (27B multimodal): $\le 280$ ms server-side inference latency for complex/multi-image requests; $< 550$ ms total client round-trip.
- **Local Apple Silicon Inference (MLX / Docker Runner)**:
  - `Clef-Flash` 4-bit/8-bit quantized on M3/M4/M5 Max/Ultra: $\le 60$ ms forward pass.
- **Client-Side Image Pre-processing**:
  - Base64 encoding and format validation for a 4MB image must complete in $< 15$ ms on modern Apple Silicon without blocking the main actor.
- **Memory Footprint**:
  - The client networking and schema synthesis layer must allocate $< 35$ MB of transient RAM during multi-image base64 encoding.

### 6.2 Concurrency & Architectural Standards (Stratos Compliance)
- **Call-Site First Design**: The developer API must feel native to Apple Foundation Models. A developer familiar with Apple's `LanguageModelSession` should need zero new conceptual learning to use Clef.
- **Strict Concurrency**:
  - Compiled with `-strict-concurrency=complete`.
  - All configuration structs, endpoints, backends, attachments, and answers must conform to `Sendable`.
  - All asynchronous network calls must properly support task cancellation (`withTaskCancellationHandler` / `Task.isCancelled`).
- **Zero Third-Party Runtime Dependencies**:
  - Pure native standard library and Apple system frameworks: `Foundation`, `FoundationModels`, `UniformTypeIdentifiers`.
  - Zero Alamofire, zero external JSON parsers, zero third-party base64 packages.

### 6.3 Security, Privacy & Compliance
- **Zero Data Ingress/Egress on Local Backends**: When using local Docker runner, vLLM, or MLX backends, zero network packets shall leave the local subnet.
- **Secure Credential Handling**:
  - Cloudflare API tokens and account IDs must never be hardcoded in client source code.
  - The library must support injection via environment variables (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`), Apple Keychain references, or dependency injection containers (FactoryKit).
- **Redaction of Image Payloads in Logs**:
  - Debug logging and diagnostics must never dump raw base64 image strings into system logs (`os_log` / `Logger`). Image attachments must be summarized by format, byte size, and dimensions (e.g., `[Image: JPEG, 1920x1080, 1.4 MB]`).

---

## 7. Edge Cases & Error Handling

1. **Unsupported Image Formats**:
   - If an attachment with an unsupported MIME type (e.g., GIF, TIFF, BMP, HEIC, PDF) is supplied:
   - *Behavior*: If the platform provides built-in conversion capabilities, the system may optionally transcode HEIC to JPEG; otherwise, the executor shall throw a typed error `ClefError.unsupportedImageFormat(mimeType: String, supported: ["image/png", "image/jpeg", "image/webp"])`.
2. **Corrupted or Truncated Image Data**:
   - If image data is empty (0 bytes) or corrupted so that image dimensions cannot be parsed:
   - *Behavior*: Throw `ClefError.invalidImageData(reason: "Payload is empty or header is corrupted")`.
3. **Image Exceeding 16 Megapixels**:
   - Clef vision encoders support up to 16MP per image.
   - *Behavior*: If an uncompressed 48MP camera photo is supplied and auto-downscaling is disabled, throw `ClefError.imageResolutionExceeded(megapixels: Double, maximum: 16.0)`. If auto-downscaling is enabled, downscale proportionally using native Apple image I/O to fit within 16MP before encoding.
4. **Cloudflare Edge Gateway Timeouts (504 / 524)**:
   - If Cloudflare Workers AI edge execution times out:
   - *Behavior*: Return `SystemOneError.networkError("Cloudflare Workers AI gateway timeout (524). Model may be cold-starting.")` with retry eligibility under `RetryPolicy`.
5. **Partial Model Outputs & Missing Schema Keys**:
   - If the model's routing head fails to return an answer for one of the translated schema questions:
   - *Behavior*: Synthesizer must detect the missing key and throw `SystemOneError.synthesisError("Missing answer for key '\(key)' in Clef model response")`, triggering safe escalation under `RoutingPolicy`.

---

## 8. Out of Scope

1. **Free-Form Generative Image Captioning or Chat**:
   - Clef is a **System One decision model**, not a conversational chat bot. Producing paragraphs of descriptive visual prose or multi-turn conversational chat completion is out of scope.
2. **On-Device Core ML Port of Clef 27B / Clef-Flash 9B Weights**:
   - While on-device Laya models run directly via Core ML (`.mlmodelc`) on the Apple Neural Engine, porting the full 9B/27B Clef transformer weights to native Core ML is out of scope for this release. Local execution on Apple hardware is supported via local HTTP runtimes (MLX, GGUF, Docker Model Runner). Core ML conversion is deferred to future feasibility studies.
3. **Video and Audio Streaming Ingestion**:
   - Processing live video streams (HLS, RTSP) or continuous audio transcripts is out of scope. Only static image attachments (up to 4 images per evaluation) are supported in this release.
4. **Cloudflare Account Provisioning & Billing UI**:
   - In-app management of Cloudflare subscriptions, billing, or worker script deployment is out of scope. Users configure their own Cloudflare Workers AI credentials.

---

## 9. Handoff & Technical Dependencies

### Implementation Phasing
- **Phase 1 (Core Schema & DTO Expansion)**: Update `SystemOneCore` to support multimodal image attachments in `SystemOneRequest` and `SystemOneLanguageModel`.
- **Phase 2 (ClefFoundationModels Target)**: Implement `ClefLanguageModel`, `ClefConfiguration`, `ClefWorkersAIBackend`, and `ClefLocalBackend`.
- **Phase 3 (Testing & Offline Harness)**: Build `MockClefBackend` and comprehensive unit tests with single-image, multi-image, and boundary cases.
- **Phase 4 (Documentation & Tech Notes)**: Author `tech-notes/0012-cloudflare-clef-multimodal-decision-models.md` and update `tech-notes/README.md`.

### Handoff Gate
This PRD is submitted for Phase 2 of the Spec-Driven Pipeline.
- **Assigned Architect**: Senior Architect Agent (`@senior-architect`)
- **Next Deliverable**: Architectural Decision Record (`docs/architecture/ADR-2026-10-03-clef-decision-models.md`) detailing multimodal DTO representations, `Transcript` image segment parsing, and Workers AI / AI Gateway HTTP payload contracts.