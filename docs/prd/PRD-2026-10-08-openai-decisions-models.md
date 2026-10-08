# PRD: OpenAI Decisions API (GPT-6 Luna) Model Support

- **Document ID**: `PRD-2026-10-08-openai-decisions-models`
- **Date**: 2026-10-08
- **Status**: Draft / Ready for Architectural Review
- **Owner**: Product Manager Agent
- **Architect**: Senior Architect Agent
- **Target Branch**: `feature/openai-decisions-models`
- **Target Release**: SystemOneFoundationModels 1.3.0 (iOS 27.0+, macOS 27.0+, visionOS 27.0+)
- **Upstream / Specs**: Apple Foundation Models Framework (`LanguageModel`, `LanguageModelSession`, `@Generable`), OpenAI Decisions API (`POST https://api.openai.com/v1/decisions`), `gpt-6-luna`, TypeSafe AI System One Primitives

---

## 1. Problem Statement & Strategic Vision

Modern client applications, reactive user interfaces, and autonomous agent systems require constant, high-frequency micro-decisions:
- **Inbound Content & Email Triage**: Classifying urgency, identifying customer sentiment, categorizing intent, and routing tickets to specialized escalation queues.
- **Multimodal Visual Verification**: Verifying whether a captured photo is blurry, whether an uploaded driver's license shows signs of glare or tampering, or whether a physical package arrived damaged.
- **Agent Action Selection & Guardrails**: Evaluating whether a proposed tool call violates security parameters, choosing the next state transition in an automated workflow, or determining whether a human confirmation dialog is mandated.
- **Form Validation & Smart Field Auto-Fill**: Determining data consistency, detecting anomalies across multi-field submissions, and selecting contextual fallback values.

### The Generative LLM Dilemma in System One Workflows
Historically, developers implementing these decision and routing pipelines have been forced to repurpose autoregressive generative Large Language Models (such as GPT-4o, GPT-5, Claude 3.5 Sonnet, or Gemini 1.5 Pro) via standard chat or response endpoints. This mismatch introduces severe operational liabilities:

1. **Excessive Autoregressive Latency**: Standard conversational endpoints take 1,200ms to 2,500ms end-to-end to autoregressively decode descriptive text, markdown delimiters, or structured JSON strings. In mobile applications and multi-step agent loops, this latency makes real-time interactivity impossible.
2. **Fragility of Output Generation**: Forcing a generative model to produce structured JSON requires complex prompt engineering or constrained decoding grammars. Models can still hallucinate explanatory prose, generate malformed syntax, or wrap answers in unwanted markdown code blocks.
3. **Absence of Calibrated Probabilities**: Autoregressive decoders output token sequences, not mathematically grounded probabilities. They cannot natively provide true Bayesian confidence scores for a boolean proposition or a normalized probability distribution over candidate categories. Systems are forced to parse subjective self-assessments (e.g., `"confidence": "high"` or `"confidence": 0.95`) hallucinated by the model.
4. **Asymmetric Token Pricing**: Generating conversational JSON payloads incurs both input token charges and steep output token pricing. For high-volume automated decision pipelines, paying per output token for repetitive structural boilerplate is economically inefficient.

### The OpenAI Decisions Breakthrough: GPT-6 Luna
At DevDay 2026 (September 29, 2026), OpenAI announced the **Decisions API**, which graduated to Public Beta on October 6, 2026. Powered by **`gpt-6-luna`**—the low-latency, hyper-efficient tier of OpenAI's GPT-6 generation—the Decisions API represents OpenAI's official entry into non-autoregressive, System One decision computing.

Key characteristics of the Decisions API:
- **Dedicated Endpoint**: `POST https://api.openai.com/v1/decisions`.
- **Purpose-Built Objective**: High-speed triage, classification, routing, and next-action selection without generating conversational text, markdown, or unstructured prose.
- **Unprecedented Latency Profile**: Benchmarked at ~150ms end-to-end round-trip latency—roughly **10x faster** than standard autoregressive generation via the OpenAI Responses API (~1.6s).
- **Disruptive Pricing Structure**: **$0.10 per 1M input tokens** and **$0.00 for output tokens**. Zero output token billing eliminates financial penalties for large, multi-field schemas. Furthermore, there are no cache-read or cache-write surcharges.
- **Multimodal Ingestion**: Evaluates both text state and visual evidence. Visual inputs are accepted strictly as inline Base64 Data URLs (`data:image/png;base64,...`, JPEG, WebP). Hosted URLs and OpenAI `file_id` references are explicitly unsupported on this endpoint, enforcing zero external network fetch latency on the server.

### The Architectural & Pedagogical Mission in SystemOneFoundationModels
`SystemOneFoundationModels` is the authoritative Apple platform framework bridging System One decision engines (TypeSafe Jev, on-device Laya Core ML, self-hosted Laya, and Cloudflare Clef) to Apple's native **Foundation Models** framework (`LanguageModel`, `LanguageModelSession`, `@Generable`, `@Guide`).

With the introduction of OpenAI Decisions API support, Apple developers gain access to OpenAI's frontier classification infrastructure while preserving 100% native Apple SDK ergonomics:

```swift
// 1. Initialize OpenAI Decisions model with standard API credentials
let model = OpenAIDecisionsLanguageModel(
    apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
    organization: "org-apple-dev",
    project: "proj-triage-v1"
)
let session = LanguageModelSession(model: model)

// 2. Prepare prompt (supporting optional inline visual attachments)
let prompt = Transcript.Entry.prompt("Evaluate incoming customer reimbursement ticket.", attachments: [receiptAttachment])

// 3. Strongly-typed decision evaluation in a single ~150ms forward pass
let response = try await session.respond(to: prompt, generating: ReimbursementTriageDecision.self)

// 4. Access dual signals: strongly-typed struct + calibrated confidence
let decision = response.content               // Struct with isApproved, category, priorityScore
let routing = routingPolicy.decide(decision)  // .auto (>=0.85), .confirm (0.60..<0.85), .escalate (<0.60)
```

This PRD formalizes the product requirements, user personas, functional specifications, wire schema translation mechanics, acceptance criteria, non-functional requirements, edge case behaviors, and engineering boundaries for integrating OpenAI's Decisions API (`gpt-6-luna`) into the `SystemOneFoundationModels` Swift package.

---

## 2. User Personas & User Stories

### User Personas
1. **Elena (Senior iOS / Apple Platform Engineer)**: Builds mission-critical consumer and enterprise applications for iOS 27 and macOS 27. Insists on pure Swift 6 strict concurrency, Apple Foundation Models ergonomics, zero third-party binary dependencies, and clean SPM trait modularity.
2. **Kiran (Enterprise AI Platform Architect)**: Manages cloud and AI infrastructure across large organizations. Requires multi-tenant credential isolation (OpenAI Organization and Project headers), deterministic rate limit handling under RFC 9110 (`Retry-After`), and verifiable token cost metrics.
3. **Marcus (Autonomous Agent & Workflow Engineer)**: Builds low-latency agent loops on macOS and iOS. Needs sub-200ms decision cycles with calibrated confidence scores to evaluate branch transitions, tool execution permissions, and automated rollbacks without risking autoregressive hallucinations.
4. **Chloe (Mobile Product & Operations Lead)**: Focuses on unit economics and operational scalability. Demands predictable zero-cost output token pricing and transparent tracking of input token budgets across high-throughput production features.

### User Stories

- **US-1 (Native Foundation Models Ergonomics)**:
  - **As an** Apple platform engineer,
  - **I want to** evaluate strongly-typed `@Generable` decision schemas through a standard `LanguageModelSession` backed by `OpenAIDecisionsLanguageModel`,
  - **So that** I can write idiomatic Swift 6 code using Apple's official API without learning vendor-specific client wrappers.

- **US-2 (Multimodal Inline Image Evaluation)**:
  - **As an** iOS developer building visual inspection workflows,
  - **I want to** pass image attachments (`PNG`, `JPEG`, `WebP`) inside a Foundation Models `Transcript`,
  - **So that** `gpt-6-luna` can evaluate visual evidence alongside text instructions in a single forward pass without external hosting.

- **US-3 (Protocol & Wire Schema Translation)**:
  - **As an** SDK consumer,
  - **I want** the framework to seamlessly adapt Apple Foundation Models schemas and System One decision primitives (`noul`, `choice`, `score`) into OpenAI's array-based wire format (`predicate`, `choice`, `score`) and decode the results back into my native Swift struct,
  - **So that** I never have to manually construct raw JSON dictionaries or parse untyped arrays.

- **US-4 (Multi-Tenant Enterprise Headers)**:
  - **As an** enterprise systems engineer,
  - **I want to** configure optional `organization` and `project` identifiers on `OpenAIDecisionsLanguageModel`,
  - **So that** requests are properly billed and isolated within our corporate OpenAI workspace using standard `OpenAI-Organization` and `OpenAI-Project` HTTP headers.

- **US-5 (Calibrated Epistemic Routing & Dual Signals)**:
  - **As an** autonomous agent engineer,
  - **I want** OpenAI Decision responses to yield calibrated probabilities and confidence values compatible with `RoutingPolicy`,
  - **So that** ambiguous decisions (confidence $< 0.60$) are escalated to human review, while decisive evaluations ($\ge 0.85$) execute autonomously.

- **US-6 (Resilient Network Handling & RFC 9110 Backoff)**:
  - **As a** mobile developer dealing with intermittent cellular networks and API rate limits,
  - **I want** the transport layer to respect HTTP 429 `Retry-After` headers and apply exponential jitter backoff,
  - **So that** transient network hiccups and quota spikes do not disrupt user workflows.

- **US-7 (SPM Trait Isolation & Hermetic Testing)**:
  - **As a** developer focused on modularity and CI reliability,
  - **I want** OpenAI support packaged under an optional SPM trait (`OpenAI`) in a decoupled target (`OpenAIFoundationModels`), accompanied by a `MockOpenAIDecisionsBackend`,
  - **So that** my automated unit tests run completely offline without requiring live OpenAI API keys or incurring token charges.

---

## 3. Model Architecture, API Contracts & Ecosystem Context

### 3.1 Model Specifications & Operational Comparison

| Attribute | OpenAI Decisions (`gpt-6-luna`) | OpenAI Responses API (`gpt-5` / `gpt-4o`) | TypeSafe Jev (`jev-latest`) | Cloudflare Clef (`clef` / `clef-flash`) |
| :--- | :--- | :--- | :--- | :--- |
| **Model ID** | `gpt-6-luna` | `gpt-5`, `gpt-4o` | `jev-latest` | `clef` (27B), `clef-flash` (9B) |
| **Endpoint** | `POST https://api.openai.com/v1/decisions` | `POST https://api.openai.com/v1/responses` | `POST https://api.typesafe.ai/v1/systemone` | `POST /client/v4/accounts/{id}/ai/run/{model}` |
| **Execution Paradigm** | Non-autoregressive decision classification | Autoregressive token generation | Non-autoregressive decision classification | Non-autoregressive decision classification |
| **P50 Latency (Broadband)** | **~150 ms** | 1,200 ms – 2,500 ms | ~90 ms | 90 ms – 280 ms |
| **Input Token Pricing** | **$0.10 / 1M tokens** | $2.50 – $5.00 / 1M tokens | Billed by plan | Free / Workers AI pricing |
| **Output Token Pricing** | **$0.00 / 1M tokens** (Free) | $10.00 – $15.00 / 1M tokens | $0.00 (Output tokens = 0) | $0.00 (Output tokens = 0) |
| **Cache Surcharges** | None ($0.00 read/write) | Tiered caching fees | None | None (AI Gateway optional) |
| **Multimodal Inputs** | Yes (Inline Base64 Data URL only) | Yes (Hosted URLs, Files, Base64) | Text only (v1) | Yes (Inline Base64 / Raw Data) |
| **Output Token Count** | Always `0` | Autoregressive count | Always `0` | Always `0` |
| **Confidence Calibration** | Native probabilities & confidence | Uncalibrated / token logprobs | Calibrated Bayesian probabilities | Calibrated Bayesian probabilities |

### 3.2 Wire Schema & Protocol Differences Matrix

While TypeSafe Jev and Cloudflare Clef utilize dictionary-keyed question and answer structures, OpenAI's Decisions API specifies an **ordered array of question objects** and returns an **ordered array of answer objects**:

```
+---------------------------------------------------------------------------------------------------+
| SystemOneCore Standard Schema (Jev / Clef)          OpenAI Decisions Wire Schema (gpt-6-luna)     |
+----------------------------------------------------+----------------------------------------------+
| questions: {                                       | questions: [                                 |
|   "isUrgent": {                                    |   {                                          |
|     "type": "noul",                                |     "type": "predicate",                     |
|     "instructions": "Determine if urgent"          |     "name": "isUrgent",                      |
|   },                                               |     "instructions": "Determine if urgent"    |
|   "dept": {                                        |   },                                         |
|     "type": "choice",                              |   {                                          |
|     "instructions": "Select department",           |     "type": "choice",                        |
|     "criteria": { "billing": "...", "tech": "..." }|     "name": "dept",                          |
|   }                                                |     "instructions": "Select department",     |
| }                                                  |     "choices": [                             |
|                                                    |       { "value": "billing", "description": "..." },
|                                                    |       { "value": "tech", "description": "..." }  |
|                                                    |     ]                                        |
|                                                    |   }                                          |
|                                                    | ]                                            |
|                                                    |                                              |
| answers: {                                         | answers: [                                   |
|   "isUrgent": { "noul": 0.94 },                    |   { "name": "isUrgent", "probability": 0.94 },
|   "dept": { "choice": "billing", ... }             |   { "name": "dept", "choice": "billing", ...}|
| }                                                  | ]                                            |
+---------------------------------------------------------------------------------------------------+
```

### 3.3 Question & Answer Primitives Mapping

#### 1. Boolean Proposition (`predicate` $\leftrightarrow$ `noul`)
- **OpenAI Request**:
  ```json
  {
    "type": "predicate",
    "name": "isSuspicious",
    "instructions": "Determine if the transaction exhibits fraudulent indicators."
  }
  ```
- **OpenAI Response**:
  ```json
  {
    "name": "isSuspicious",
    "probability": 0.912
  }
  ```
- **SystemOne Mapping**: Maps directly to/from `SystemOneQuestion.noul` and `SystemOneAnswer.noul`. The returned `probability` is mapped to `SystemOneAnswer(type: "noul", noul: probability)`.

#### 2. Categorical Choice (`choice` $\leftrightarrow$ `choice`)
- **OpenAI Request**:
  ```json
  {
    "type": "choice",
    "name": "ticketCategory",
    "instructions": "Select the primary customer issue category.",
    "choices": [
      { "value": "billing", "description": "Inquiries regarding charges, invoices, or subscriptions." },
      { "value": "technical", "description": "Bug reports, performance issues, or crash logs." },
      { "value": "general", "description": "Product questions, feedback, or general greetings." }
    ]
  }
  ```
- **OpenAI Response**:
  ```json
  {
    "name": "ticketCategory",
    "choice": "billing",
    "confidence": 0.945,
    "probabilities": [
      { "value": "billing", "probability": 0.945 },
      { "value": "technical", "probability": 0.042 },
      { "value": "general", "probability": 0.013 }
    ]
  }
  ```
- **SystemOne Mapping**: The internal dictionary `criteria: [String: String]` is serialized into an array of `choices: [{"value": key, "description": val}]`. The response is flattened into `SystemOneAnswer(type: "choice", choice: choice, confidence: confidence, probabilities: [key: prob])`.

#### 3. Ordinal Rubric Score (`score` $\leftrightarrow$ `score`)
- **OpenAI Request**:
  ```json
  {
    "type": "score",
    "name": "urgencyLevel",
    "instructions": "Rate the customer urgency from 1 (lowest) to 5 (critical emergency).",
    "levels": [
      { "label": "Low", "description": "No immediate impact. Informational inquiry." },
      { "label": "Minor", "description": "Minor inconvenience with available workarounds." },
      { "label": "Moderate", "description": "Partial functionality loss affecting single user." },
      { "label": "High", "description": "Major feature broken impacting business operations." },
      { "label": "Critical", "description": "Complete service outage or severe security incident." }
    ]
  }
  ```
- **OpenAI Response**:
  ```json
  {
    "name": "urgencyLevel",
    "score": 4.62,
    "confidence": 0.88,
    "probabilities": [
      { "value": 1, "label": "Low", "probability": 0.01 },
      { "value": 2, "label": "Minor", "probability": 0.02 },
      { "value": 3, "label": "Moderate", "probability": 0.05 },
      { "value": 4, "label": "High", "probability": 0.22 },
      { "value": 5, "label": "Critical", "probability": 0.70 }
    ]
  }
  ```
- **SystemOne Mapping**: The criteria array `[String]` is mapped into `levels: [{"label": label, "description": desc}]`. The probability-weighted numeric average `score` and `confidence` map directly to `SystemOneAnswer.score` and `SystemOneAnswer.confidence`.

#### 4. Safety Policy Refusal (`type: "refusal"`)
- **OpenAI Response**:
  ```json
  {
    "name": "riskEvaluation",
    "type": "refusal",
    "refusal": "The request violated OpenAI safety policy regarding harmful content generation."
  }
  ```
- **SystemOne Mapping**: If any answer contains `type: "refusal"`, the executor throws `SystemOneError.safetyRefusal(reason: String, questionName: String)`.

### 3.4 Multimodal Input & Base64 Data URL Format
The Decisions API explicitly restricts image inputs to inline Data URLs.
- **Accepted MIME Types**: `image/png`, `image/jpeg`, `image/webp`.
- **Payload Structure**:
  ```json
  {
    "model": "gpt-6-luna",
    "input": [
      {
        "role": "user",
        "content": [
          { "type": "input_text", "text": "Inspect this check for mobile deposit endorsement." },
          { "type": "input_image", "image_url": "data:image/jpeg;base64,/9j/4AAQSkZJRg..." }
        ]
      }
    ],
    "questions": [ ... ]
  }
  ```
- **Explicit Limitations**:
  - Hosted HTTP/HTTPS URLs (e.g. `https://example.com/receipt.jpg`) are **unsupported** and will be rejected with HTTP 400.
  - OpenAI Files API identifiers (e.g. `file-abc123xyz`) are **unsupported**.
  - All visual assets must be converted client-side to RFC 2397 base64 Data URLs prior to transmission.

---

## 4. Functional Requirements

### FR-1: Multimodal Data Attachment Support in Foundation Models
1. **Capability Reporting**:
   - `OpenAIDecisionsLanguageModel` shall declare native support for `[.guidedGeneration, .vision]`.
   - The model shall implement `supportsDataAttachmentType(_ type: UTType)` to return `true` for:
     - `UTType.png` (`public.png`)
     - `UTType.jpeg` (`public.jpeg`)
     - `UTType.webP` (`org.webmproject.webp`)
   - Any other data attachment type (e.g., audio, video, plain text blobs, PDF) shall return `false`.
   - `supportsDataEntryType(_:)` shall return `false`.
2. **Transcript Attachment Extraction & Base64 Formatting**:
   - The executor shall parse image attachments from the Foundation Models `Transcript`.
   - Supported images shall be converted into inline Base64 Data URLs (`data:<mime>;base64,<payload>`).
   - If an image attachment has an unsupported MIME type, the executor shall throw `SystemOneError.unsupportedAttachmentType(type: String)`.
3. **Payload Construction**:
   - When no image attachments are present, the `input` field of the request payload may be serialized as a single plain `String`.
   - When one or more image attachments are present, the `input` field shall be serialized as an array of message objects containing `input_text` and `input_image` blocks.

### FR-2: OpenAI Decisions Wire Schema Adapter
1. **Request Transformation**:
   - The framework shall provide `OpenAIDecisionsPayloadAdapter` to translate internal `SystemOneRequest` models into the OpenAI wire format:
     - Translate `SystemOneQuestion.noul` $\to$ `predicate` question object.
     - Translate `SystemOneQuestion.choice` $\to$ `choice` question object with an array of choice objects (`value`, `description`).
     - Translate `SystemOneQuestion.score` $\to$ `score` question object with an array of level objects (`label`, `description`).
2. **Response Transformation**:
   - The adapter shall deserialize the OpenAI JSON response:
     - Check for top-level errors and safety refusals (`type: "refusal"`).
     - Map the `answers` array back into a dictionary keyed by `name` (`[String: SystemOneAnswer]`).
     - Extract `input_tokens` from `usage` and assert `output_tokens == 0`.
3. **Structured Output Enforcement**:
   - Requests made without a `@Generable` schema shall throw `SystemOneError.structuredOutputRequired`. Unstructured chat completion is strictly prohibited.

### FR-3: Backend & Transport Architecture
The target `OpenAIFoundationModels` shall provide modular backend components conforming to `OpenAIDecisionsBackend`:

```
                           +-------------------------------+
                           | LanguageModelSession          |
                           +---------------+---------------+
                                           |
                           +---------------v---------------+
                           | OpenAIDecisionsLanguageModel  |
                           +---------------+---------------+
                                           |
                           +---------------v---------------+
                           | OpenAIDecisionsBackend (Proto)|
                           +---------------+---------------+
                                           |
          +--------------------------------+-------------------------------+
          |                                                                |
+---------v-------------------------+             +------------------------v-------------------+
| OpenAIDecisionsHTTPBackend        |             | MockOpenAIDecisionsBackend                 |
| - URLSession Transport            |             | - Deterministic offline unit testing       |
| - Multi-tenant Auth Headers       |             | - Synthetic payload verification           |
| - RFC 9110 Retry-After Handling   |             | - Zero network traffic                     |
+-----------------------------------+             +--------------------------------------------+
```

1. **`OpenAIDecisionsHTTPBackend`**:
   - Target URL: `https://api.openai.com/v1/decisions` (configurable for enterprise proxies).
   - Headers:
     - `Authorization: Bearer <apiKey>` (mandatory)
     - `Content-Type: application/json` (mandatory)
     - `OpenAI-Organization: <organizationID>` (optional)
     - `OpenAI-Project: <projectID>` (optional)
   - Timeout: Configurable (default: 30 seconds).
2. **`MockOpenAIDecisionsBackend`**:
   - Deterministic offline mock for CI/CD test suites.
   - Allows injecting synthetic question answers, simulating HTTP status codes (200, 400, 401, 429, 500), testing retry delays, and inspecting wire payloads without network access.

### FR-4: First-Class Swift & Foundation Models Ergonomics
1. **Public Model Initializers**:
   ```swift
   public struct OpenAIDecisionsLanguageModel: LanguageModel, Sendable {
       public init(
           apiKey: String? = nil,
           organization: String? = nil,
           project: String? = nil,
           endpoint: URL = URL(string: "https://api.openai.com/v1/decisions")!,
           session: URLSession = .shared,
           timeoutInterval: TimeInterval = 30,
           retryPolicy: RetryPolicy = .default
       )
   }
   ```
2. **Dynamic Credential Resolution**:
   - If `apiKey` is omitted from the initializer, the backend shall automatically check `ProcessInfo.processInfo.environment["OPENAI_API_KEY"]`.
   - If no key is found, initialization succeeds, but execution throws `SystemOneError.missingAPIKey("OpenAI API key not provided")`.
3. **Dual-Signal Metadata Emission**:
   - Emits structured metadata via `channel.send(.response(entryID:action:.updateMetadata(...)))`:
     - `"model"`: `"gpt-6-luna"`
     - `"probabilities"`: Calibrated JSON map of probabilities.
     - `"confidence"`: Calibrated JSON map of confidence ratings.
     - `"scores"`: Calibrated JSON map of rubric evaluations.
     - `"serverDurationMs"`: Latency reported by server or computed by client.
     - `"output_tokens"`: `"0"`.

### FR-5: Package Architecture, SPM Traits & Dependency Hygiene
1. **Target Isolation**:
   - New target: `OpenAIFoundationModels` depending strictly on `SystemOneCore`.
   - New library product: `OpenAIFoundationModels`.
   - Zero third-party runtime package dependencies. Uses pure Apple standard libraries (`Foundation`, `FoundationModels`, `UniformTypeIdentifiers`).
2. **Package Traits**:
   - Define new trait:
     ```swift
     .trait(
         name: "OpenAI",
         description: "Enables OpenAI Decisions API (GPT-6 Luna) remote hosted client"
     )
     ```
   - Update `Remote` trait to include `OpenAI`:
     ```swift
     enabledTraits: ["Jev", "LayaServe", "Clef", "OpenAI"]
     ```
   - Update `All` trait to include `OpenAI`:
     ```swift
     enabledTraits: ["Jev", "Laya", "LayaServe", "Clef", "OpenAI"]
     ```
   - Update `SystemOneFoundationModels` umbrella target with conditional dependency:
     ```swift
     .target(name: "OpenAIFoundationModels", condition: .when(traits: ["OpenAI"]))
     ```

### FR-6: Resilience, Rate Limiting & Confidence Routing
1. **HTTP 429 & RFC 9110 Retry Policy**:
   - The HTTP backend shall inspect `Retry-After` headers on HTTP 429 responses (both delta-seconds and IMF-fixdate format).
   - If `Retry-After` is absent, exponential backoff with jitter shall be applied up to `retryPolicy.maxRetries`.
2. **Routing Policy Integration**:
   - Results synthesized from `gpt-6-luna` answers seamlessly integrate into `RoutingPolicy`:
     - Probabilities $\ge 0.85 \implies$ `.auto` (execute immediately).
     - Probabilities between $0.60$ and $0.85 \implies$ `.confirm` (prompt user for confirmation).
     - Probabilities $< 0.60$ or high-entropy distributions $\implies$ `.escalate` (route to human triage).

---

## 5. Acceptance Criteria

### AC-1: Multimodal `@Generable` Evaluation with Inline Images
- **Scenario 1.1**: Text and Single Inline JPEG Evaluation
  - **Given** an open `LanguageModelSession` configured with `OpenAIDecisionsLanguageModel`,
  - **When** the caller submits a prompt containing state text and a 1.5MB JPEG attachment, generating a `@Generable` struct `ReceiptAuditDecision`,
  - **Then** the wire payload sent to `https://api.openai.com/v1/decisions` contains `model: "gpt-6-luna"`, an array-based `input` with `input_text` and `data:image/jpeg;base64,...`, and an array of translated questions, returning a populated `ReceiptAuditDecision` with zero output tokens billed.
- **Scenario 1.2**: Multiple Image Attachments (Up to 4 Images)
  - **Given** a prompt containing 3 PNG image attachments,
  - **When** evaluated via `session.respond(to:generating:)`,
  - **Then** all 3 images are serialized as sequential `input_image` blocks within the user message content array, and the request completes successfully.
- **Scenario 1.3**: Unsupported Attachment Type Rejection
  - **Given** a prompt containing a PDF or audio attachment,
  - **When** `session.respond(...)` is called,
  - **Then** the executor rejects the request with `SystemOneError.unsupportedAttachmentType` before making any network request.

### AC-2: Schema Translation & Protocol Adaptation
- **Scenario 2.1**: Translating All System One Primitives to OpenAI Wire Schema
  - **Given** a `@Generable` struct containing a boolean property (`isSpam: Bool`), an enum property (`priority: PriorityLevel`), and a guided integer score (`urgency: Int` with `@Guide(.range(1...5))`),
  - **When** translated by the OpenAI schema adapter,
  - **Then** the generated payload contains:
    - One `predicate` question with `name: "isSpam"`.
    - One `choice` question with `name: "priority"` and an array of `choices` containing string `value` and `description`.
    - One `score` question with `name: "urgency"` and an array of 5 `levels` with `label` and `description`.
- **Scenario 2.2**: Handling Safety Refusals
  - **Given** an OpenAI response where one question answer returns `{"name": "isSafe", "type": "refusal", "refusal": "Content blocked by safety filter"}`,
  - **When** the response is processed by the executor,
  - **Then** the executor throws `SystemOneError.safetyRefusal(reason: "Content blocked by safety filter", questionName: "isSafe")`.
- **Scenario 2.3**: Rejecting Unstructured Text Generation
  - **Given** a request to `OpenAIDecisionsLanguageModel` invoked without a `@Generable` schema (plain string chat prompt),
  - **When** `executor.respond(...)` executes,
  - **Then** it throws `SystemOneError.structuredOutputRequired`.

### AC-3: OpenAI API Communication, Auth & Enterprise Headers
- **Scenario 3.1**: Standard API Key Authorization
  - **Given** an `OpenAIDecisionsLanguageModel` configured with `apiKey: "sk-test-12345"`,
  - **When** an evaluation request is dispatched,
  - **Then** the outgoing HTTP request contains `Authorization: Bearer sk-test-12345`.
- **Scenario 3.2**: Organization and Project Multi-Tenancy Headers
  - **Given** configuration with `organization: "org-finance"` and `project: "proj-audit"`,
  - **When** the HTTP request is constructed,
  - **Then** the HTTP headers include `OpenAI-Organization: org-finance` and `OpenAI-Project: proj-audit`.
- **Scenario 3.3**: Missing API Key Error Surfacing
  - **Given** no API key provided in code and no `OPENAI_API_KEY` environment variable set,
  - **When** an evaluation is executed,
  - **Then** `SystemOneError.missingAPIKey` is thrown with clear setup instructions.

### AC-4: Resilient Network Transport & RFC 9110 Retry Policy
- **Scenario 4.1**: Rate Limit 429 with `Retry-After` Header
  - **Given** the OpenAI Decisions endpoint returns HTTP 429 with `Retry-After: 2`,
  - **When** `RetryPolicy.default` is configured,
  - **Then** the transport waits at least 2 seconds before retrying, succeeding when the subsequent request returns 200 OK.
- **Scenario 4.2**: Non-Retryable HTTP Errors (401 / 400)
  - **Given** an invalid API key causing HTTP 401 Unauthorized,
  - **When** the response is received,
  - **Then** the backend immediately terminates without retrying and surfaces `SystemOneError.authenticationFailed`.

### AC-5: Confidence Routing & Epistemic Guardrails
- **Scenario 5.1**: Decisive Visual Triage Execution
  - **Given** a high-confidence answer with probability $0.94$,
  - **When** passed through `RoutingPolicy.default`,
  - **Then** the decision resolves to `.auto`, enabling zero-click automated processing.
- **Scenario 5.2**: Ambiguous Indecision Band Escalation
  - **Given** an ambiguous image where the model returns probability $0.52$ (within the $0.35\dots0.65$ epistemic indecision window),
  - **When** evaluated by `RoutingPolicy.default`,
  - **Then** the decision resolves to `.escalate`, routing the item for human triage.

### AC-6: Swift 6 Strict Concurrency, SPM Trait Isolation & Offline Determinism
- **Scenario 6.1**: Strict Concurrency Compilation
  - **Given** the `OpenAIFoundationModels` target compiled with `-strict-concurrency=complete` in Swift 6.1,
  - **When** building for macOS 27, iOS 27, and visionOS 27,
  - **Then** the build completes with zero compiler warnings and all public types conform to `Sendable`.
- **Scenario 6.2**: Hermetic Offline Unit Testing
  - **Given** unit tests executing with `MockOpenAIDecisionsBackend` and no network connection,
  - **When** running `swift test`,
  - **Then** all tests pass deterministically in $<2$ seconds without making any network calls or requiring credentials.

---

## 6. Non-Functional Requirements

### 6.1 Performance & Latency Budgets
- **Server-Side Latency**: P50 latency $\le 150$ ms on broadband; P95 $\le 300$ ms.
- **Client Round-Trip Overhead**: Client serialization, schema translation, base64 encoding, and response synthesis must complete in $< 15$ ms on modern Apple Silicon (M3/M4/M5 / A18/A19/A20).
- **Zero Output Decoding Latency**: Because the Decisions API outputs zero tokens, there is zero autoregressive streaming delay. The full response is received in a single HTTP payload.
- **Memory Footprint**: Transient RAM allocation during JSON encoding of a 2MB image must remain $< 25$ MB.

### 6.2 Concurrency & Architectural Standards (Stratos Compliance)
- **Call-Site First Design**: The developer experience must mirror standard Apple Foundation Models code. Developers interact with `LanguageModelSession` and `@Generable` structs, not proprietary request builders.
- **Strict Concurrency Compliance**:
  - Full conformance to Swift 6 strict concurrency (`-strict-concurrency=complete`).
  - All public types (`OpenAIDecisionsLanguageModel`, `Configuration`, `Backend`, `DTOs`) conform to `Sendable`.
  - Proper task cancellation handling via cooperative cancellation checks.
- **Zero External Dependencies**:
  - Pure native implementation using `Foundation`, `FoundationModels`, `UniformTypeIdentifiers`, and `SystemOneCore`.
  - Zero third-party networking (no Alamofire, no swift-openapi-generator runtime).

### 6.3 Cost, Quotas & Token Accounting
- **Pricing Enforcement**: $0.10 per 1M input tokens; $0.00 per output tokens.
- **Token Telemetry**: The executor must report `input_tokens` from `response.usage` to the `LanguageModelExecutorGenerationChannel` and verify `output_tokens == 0`.
- **Zero Cache Surcharge Tracking**: Confirm that no unexpected cache fees are incurred.

### 6.4 Security, Privacy & Credential Hygiene
- **Credential Storage**: API keys, Organization IDs, and Project IDs must never be logged or serialized into metadata. Keys must be stored in secure memory or Apple Keychain.
- **Image Data Privacy**: Debug logging (`os_log` / `Logger`) must never print raw Base64 data strings. Images must be summarized with format, dimensions, and byte size (e.g. `[Attachment: image/jpeg, 1.2 MB]`).
- **Refusal Auditing**: When a safety refusal is encountered, the refusal message is captured in a typed error to assist debugging without leaking sensitive user context.

---

## 7. Edge Cases & Error Handling

1. **Hosted URLs & File IDs Submitted in Transcript**:
   - The OpenAI Decisions API explicitly rejects hosted URLs and `file_id` strings.
   - *Behavior*: The framework shall validate image attachments locally. If an attachment is not backed by in-memory `Data`, or if a caller attempts to pass a remote URL, the executor shall immediately throw `SystemOneError.invalidAttachment("OpenAI Decisions API requires inline Base64 data attachments. Hosted URLs are not supported.")`.
2. **Unsupported Image Formats (e.g., HEIC, GIF, TIFF, BMP, PDF)**:
   - OpenAI Decisions only accepts `image/png`, `image/jpeg`, and `image/webp`.
   - *Behavior*: If a user submits a HEIC photo directly from an iPhone camera roll without transcoding, the executor shall throw `SystemOneError.unsupportedAttachmentType(type: "image/heic")` or offer transparent transcoding to JPEG via ImageIO where platform APIs allow.
3. **Empty or Missing State Text**:
   - If a prompt has no text instructions and only contains an image:
   - *Behavior*: The framework shall supply a default state string (e.g. `"Evaluate the provided visual evidence against the requested decision schema."`) or throw `SystemOneError.invalidPrompt("State text cannot be empty.")`.
4. **Safety Refusal (`type: "refusal"`)**:
   - OpenAI's moderation pipeline may reject one or all questions.
   - *Behavior*: The response parser checks every answer object. If `type == "refusal"`, it throws `SystemOneError.safetyRefusal(reason: refusalText, questionName: name)`.
5. **Rate Limiting (HTTP 429) & Quota Depletion**:
   - *Behavior*: If `Retry-After` is present, wait and retry according to `RetryPolicy`. If quota is completely exhausted (insufficient credits error payload), fail immediately with `SystemOneError.quotaExceeded`.
6. **Mismatched Questions & Answers**:
   - If OpenAI returns an answers array missing an expected schema property:
   - *Behavior*: The response synthesizer detects the missing answer and throws `SystemOneError.synthesisError("Missing answer for property '\(key)'")`.

---

## 8. Out of Scope

1. **Autoregressive Prose Chat Completion**:
   - The Decisions API is strictly a System One decision engine. Generating paragraphs of text, conversational dialog, or open-ended prose is out of scope.
   - For conversational needs, developers must use the standard OpenAI Responses API or Apple's on-device foundation models.
2. **OpenAI Files API & Hosted Image Ingestion**:
   - Uploading images to `/v1/files` or providing public image URLs is explicitly unsupported by the Decisions API endpoint and will not be supported by this module.
3. **Audio and Real-Time Video Streaming**:
   - Ingestion of live audio streams or video feeds is out of scope for this release.
4. **On-Device Quantization of GPT-6 Luna**:
   - `gpt-6-luna` is a proprietary cloud model hosted exclusively by OpenAI. On-device execution is not possible. Developers requiring offline on-device decisions must use the `LayaOnDevice` target.

---

## 9. Handoff & Technical Dependencies

### Implementation Phasing

- **Phase 1: Wire DTOs & Schema Translation Adapter (`SystemOneCore` / `OpenAIFoundationModels`)**:
  - Implement `OpenAIDecisionsRequest`, `OpenAIDecisionsQuestion`, `OpenAIDecisionsAnswer`, `OpenAIDecisionsResponse`.
  - Implement `OpenAIDecisionsPayloadAdapter` translating `SystemOneRequest` to/from OpenAI Decisions wire format.
- **Phase 2: Target & Transport Implementation (`OpenAIFoundationModels`)**:
  - Create target `OpenAIFoundationModels` in `Package.swift`.
  - Implement `OpenAIDecisionsLanguageModel`, `OpenAIDecisionsExecutor`, `OpenAIDecisionsConfiguration`.
  - Implement `OpenAIDecisionsHTTPBackend` with `Authorization`, `OpenAI-Organization`, and `OpenAI-Project` headers.
- **Phase 3: Resilient Retry & Rate Limit Handling**:
  - Integrate RFC 9110 `Retry-After` parsing and exponential backoff into `OpenAIDecisionsHTTPBackend`.
  - Wire error mapping to `SystemOneError`.
- **Phase 4: Hermetic Mocking & Automated Unit Tests**:
  - Implement `MockOpenAIDecisionsBackend`.
  - Author comprehensive test suite in `Tests/OpenAIFoundationModelsTests/` covering predicate, choice, score, refusals, multimodal base64 attachments, and error states.
- **Phase 5: Package Trait Integration & Verification**:
  - Add `OpenAI` trait to `Package.swift`, update `Remote` and `All` trait groups.
  - Verify build with `flowdeck build` and tests with `flowdeck test`.
- **Phase 6: Reference Documentation & Demonstration**:
  - Author tech note `tech-notes/0017-openai-decisions-api-gpt-6-luna.md` documenting wire schema nuances and latency benchmarks.
  - Update `tech-notes/README.md` index.
  - Implement interactive demonstrator CLI `Examples/OpenAIDecisionDemo/`.

### Handoff Gate
This PRD is submitted for Phase 2 of the Spec-Driven Pipeline.
- **Assigned Architect**: Senior Architect Agent (`@senior-architect`)
- **Next Deliverable**: Architectural Decision Record (`docs/architecture/ADR-2026-10-08-01-openai-decisions-models-integration.md`) detailing wire DTO definitions, array adapter mechanics, and HTTP header management.
- **Next Subagents**: Platform Engineer (`@ios-engineer`), QA Agent (`@qa-agent`), Code Reviewer (`@code-reviewer`).
