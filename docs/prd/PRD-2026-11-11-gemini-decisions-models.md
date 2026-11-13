# PRD: Google Gemini Decisions API (`gemini-decision-1`) Model Support

- **Document ID**: `PRD-2026-11-11-gemini-decisions-models`
- **Date**: 2026-11-11
- **Status**: Draft / Ready for Architectural Review
- **Owner**: Product Manager Agent
- **Architect**: Senior Architect Agent
- **Target Branch**: `implement_google_decisions`
- **Target Release**: SystemOneFoundationModels 1.4.0 (iOS 27.0+, macOS 27.0+, visionOS 27.0+)
- **Upstream / Specs**: Apple Foundation Models Framework (`LanguageModel`, `LanguageModelSession`, `@Generable`), Google Gemini Decisions API (`POST https://generativelanguage.googleapis.com/v1beta/decisions`), `gemini-decision-1`, TypeSafe AI System One Primitives

---

## 1. Problem Statement & Strategic Vision

Modern client applications, reactive user interfaces, and autonomous agent workflows require continuous, high-throughput, low-latency micro-decisions across massive multimodal context windows:
- **Large-Scale Document & Repository Triage**: Evaluating up to 1,000 independent policy, compliance, and routing questions simultaneously against a 256K-token context window (e.g., full legal contracts, multi-file pull requests, or medical intake dossiers).
- **Multimodal Visual & Document Verification**: Inspecting inline images (`PNG`, `JPEG`, `WebP`) alongside dense text instructions to verify receipt authenticity, detect UI accessibility regressions, or audit physical inventory condition.
- **Agent Guardrails & Action Selection**: Evaluating whether proposed tool invocations violate safety invariants, selecting state transitions across hundreds of candidate branches, and computing calibrated confidence scores to govern human-in-the-loop escalation.
- **High-Frequency Enterprise Triage**: Classifying support tickets, emails, and telemetry alerts with zero output token overhead and sub-250ms round-trip latency.

### The Generative LLM Bottleneck in High-Density Decision Workflows
Historically, engineering teams using Google's Gemini ecosystem (`gemini-2.5-pro`, `gemini-2.5-flash`) for classification and routing had to rely on autoregressive `generateContent` endpoints with `responseSchema` constrained decoding. While capable of general reasoning, autoregressive generation introduces severe architectural and economic friction for System One decision workloads:

1. **Autoregressive Decoding Latency**: Standard `generateContent` requests decode JSON tokens sequentially. Evaluating 50 to 1,000 structured attributes autoregressively takes multiple seconds—far too slow for interactive mobile UI transitions or real-time agent guardrails.
2. **Lack of Calibrated Epistemic Probabilities**: Autoregressive JSON generation outputs discrete token choices rather than calibrated Bayesian probability distributions over candidate classes (`probabilities`), boolean propositions (`noul`), or ordinal rubrics (`score`). Extracting raw token log-probabilities (`logprobs`) from nested JSON syntax is brittle and uncalibrated.
3. **Output Token Billing Penalties**: When evaluating large schemas (up to 1,000 questions per pass), autoregressive models bill for every generated JSON key, bracket, and string value. High-throughput classification pipelines incur substantial output token costs for purely structural boilerplate.

### The Google Gemini Decisions Breakthrough: `gemini-decision-1`
Google's **Gemini Decisions API** (`POST https://generativelanguage.googleapis.com/v1beta/decisions`), powered by the purpose-built **`gemini-decision-1`** model, brings native non-autoregressive System One decision computing to the Google Generative Language platform.

Key capabilities of the Gemini Decisions API (`gemini-decision-1`):
- **Dedicated Endpoint**: `POST https://generativelanguage.googleapis.com/v1beta/decisions` authenticated via `x-goog-api-key`.
- **Native System One Dictionary Schema**: Unlike OpenAI's array-based `predicate` wire format, Google Gemini Decisions adopts the canonical dictionary-keyed `questions: [String: Question]` and `answers: [String: Answer]` structure with native System One primitive types (`noul`, `choice`, `score`).
- **Massive Parallel Question Capacity**: Evaluates up to **1,000 independent questions** in a single forward pass against a shared multimodal input context of up to **256K (262,144) tokens**.
- **Low-Latency Single-Pass Execution**: ~150ms–250ms median latency with zero autoregressive token streaming delay.
- **Zero-Output-Token Economics**: Priced at **$0.10 per 1M input tokens** and **$0.00 per 1M output tokens** (`output_tokens: 0`), eliminating cost scaling as the number of evaluated questions grows from 1 to 1,000.
- **Multimodal Inline Parts**: Supports plain text strings for text-only state, or Gemini `parts` arrays (`[{"parts": [{"text": "..."}, {"inline_data": {"mime_type": "...", "data": "..."}}]}]`) when visual attachments are present.

### The Architectural & Pedagogical Mission in SystemOneFoundationModels
`SystemOneFoundationModels` is the unified Apple platform bridge connecting System One decision engines (TypeSafe Jev, on-device Laya Core ML, self-hosted `laya-serve`, Cloudflare Clef, and OpenAI `gpt-6-luna`) to Apple's native **Foundation Models** framework (`LanguageModel`, `LanguageModelSession`, `@Generable`, `@Guide`).

Integrating Google's `gemini-decision-1` into `SystemOneFoundationModels` via the `GeminiFoundationModels` module and `Gemini` SPM package trait empowers Apple developers to evaluate `@Generable` structs against Google's 256K-token multimodal decision engine with 100% native Apple ergonomics:

```swift
import FoundationModels
import GeminiFoundationModels

// 1. Initialize Gemini Decisions model (resolves GEMINI_API_KEY or GOOGLE_API_KEY automatically)
let model = GeminiDecisionsLanguageModel()
let session = LanguageModelSession(model: model)

// 2. Prepare multimodal prompt with optional inline image attachments
let prompt = Prompt {
    "Evaluate this reimbursement claim and attached receipt against corporate policy."
    Attachment(imageURL: receiptImageURL)
}

// 3. Strongly-typed decision evaluation in a single forward pass (~150-250ms)
let response = try await session.respond(to: prompt, generating: ExpenseAuditDecision.self)

// 4. Access dual signals: strongly-typed @Generable struct + calibrated epistemic confidence
let decision = response.content                                             // ExpenseAuditDecision(isApproved: true, category: .meals, riskScore: 1)
let routing = response.judgement(for: "isApproved", policy: routingPolicy)  // .auto (>=0.85), .confirm (0.60..<0.85), .escalate (<0.60)
```

This PRD specifies the product requirements, user personas, wire protocol mappings, functional requirements, acceptance criteria, non-functional requirements, and architectural boundaries for `GeminiFoundationModels`.

---

## 2. User Personas & User Stories

### User Personas
1. **Elena (Senior iOS / macOS Platform Engineer)**: Builds native productivity and enterprise apps for iOS 27, macOS 27, and visionOS 27. Demands strict Swift 6 concurrency compliance, idiomatic Apple `LanguageModelSession` APIs, zero third-party dependencies, and interchangeable `GeminiLanguageModel` / `GeminiDecisionsLanguageModel` ergonomics.
2. **Raj (Cloud & Vertex/AI Studio Solutions Architect)**: Standardizes enterprise mobile and backend workloads on Google Cloud and Google AI Studio (`GEMINI_API_KEY` / `GOOGLE_API_KEY`). Needs native support for Google's `x-goog-api-key` authentication, standard Google RPC error envelopes, and custom gateway URL overrides.
3. **Marcus (Autonomous Agent & Document Workflow Engineer)**: Evaluates dense 100K+ token documents and multi-page visual attachments against complex `@Generable` schemas containing dozens of boolean, categorical, and rubric properties in a single pass.
4. **Chloe (Mobile Product & FinOps Lead)**: Optimizes unit economics across millions of daily client classifications. Relies on `gemini-decision-1`'s $0.10/1M input token rate and $0.00 output token pricing, alongside `RoutingPolicy` confidence thresholds to prevent costly human escalations.

### User Stories

- **US-1 (Native Foundation Models Call-Site Ergonomics)**:
  - **As an** Apple platform engineer,
  - **I want to** initialize `GeminiDecisionsLanguageModel` (or its typealias `GeminiLanguageModel`) and pass it to Apple's `LanguageModelSession`,
  - **So that** I can evaluate `@Generable` decision structs using standard Foundation Models syntax without learning Google-specific REST wrappers.

- **US-2 (Dictionary-Keyed System One Wire Fidelity)**:
  - **As an** SDK consumer,
  - **I want** `GeminiDecisionsPayloadAdapter` to translate internal `SystemOneRequest` models into Google's dictionary-keyed `questions: [String: Question]` wire format (`noul`, `choice`, `score`) and resiliently decode `answers: [String: Answer]`,
  - **So that** all calibrated probabilities, choice distributions, and 0-indexed rubric scores map cleanly into my Swift types.

- **US-3 (Multimodal `inline_data` Image Evaluation)**:
  - **As an** iOS developer building document and visual inspection features,
  - **I want to** attach `PNG`, `JPEG`, or `WebP` images to a Foundation Models `Transcript`,
  - **So that** `gemini-decision-1` receives standard Gemini `parts` with `inline_data` (`mime_type` and raw Base64 `data`) alongside state text.

- **US-4 (Dual Environment Variable Credential Resolution)**:
  - **As a** developer using Google AI Studio and Gemini CLI tools,
  - **I want** `GeminiDecisionsHTTPBackend` to resolve credentials from an explicit `apiKey` parameter first, falling back to `GEMINI_API_KEY` and then `GOOGLE_API_KEY` in the process environment, sent via the `x-goog-api-key` HTTP header,
  - **So that** my existing Google AI environment configuration works out of the box.

- **US-5 (Calibrated Epistemic Routing & Dual Signals)**:
  - **As an** agent workflow engineer,
  - **I want** `gemini-decision-1` responses to emit calibrated probabilities, confidence ratings, and rubric legends through the `LanguageModelExecutorGenerationChannel` and integrate with `RoutingPolicy`,
  - **So that** high-confidence decisions ($\ge 0.85$) execute automatically while low-confidence or ambiguous evaluations ($< 0.60$) escalate safely.

- **US-6 (Google RPC Error Decoding & RFC 9110 Retry Resilience)**:
  - **As a** mobile engineer operating on variable network connections,
  - **I want** the HTTP transport to parse Google's standard `{"error": {"code": 400, "message": "...", "status": "INVALID_ARGUMENT"}}` envelope into typed `SystemOneError` cases and honor HTTP 429 `Retry-After` headers with exponential jitter backoff,
  - **So that** API errors are actionable and transient rate limits recover transparently.

- **US-7 (SPM Trait Modularity & Hermetic Offline Testing)**:
  - **As a** CI/CD and release engineer,
  - **I want** Gemini support isolated in the `GeminiFoundationModels` target gated by the `Gemini` SPM package trait, paired with `MockGeminiDecisionsBackend`,
  - **So that** unit tests run hermetically offline in milliseconds without live Google API keys.

---

## 3. Model Architecture, API Contracts & Ecosystem Context

### 3.1 Model Specifications & Ecosystem Comparison

| Attribute | Google Gemini Decisions (`gemini-decision-1`) | OpenAI Decisions (`gpt-6-luna`) | TypeSafe Jev (`jev-latest`) | Cloudflare Clef (`clef` / `clef-flash`) |
| :--- | :--- | :--- | :--- | :--- |
| **Model ID** | `gemini-decision-1` | `gpt-6-luna` | `jev-latest` | `clef` (27B), `clef-flash` (9B) |
| **Endpoint** | `POST https://generativelanguage.googleapis.com/v1beta/decisions` | `POST https://api.openai.com/v1/decisions` | `POST https://api.typesafe.ai/v1/systemone` | `POST /client/v4/accounts/{id}/ai/run/{model}` |
| **Auth Header** | `x-goog-api-key: <apiKey>` | `Authorization: Bearer <apiKey>` | `Authorization: Bearer <apiKey>` | `Authorization: Bearer <apiKey>` |
| **Context Window** | **256K (262,144) tokens** | 128K tokens | 32K tokens | 32K – 128K tokens |
| **Max Questions / Pass** | **Up to 1,000 questions** | Up to 256 questions | Up to 256 questions | Up to 256 questions |
| **Median Latency** | **~150 ms – 250 ms** | ~150 ms | ~90 ms | 90 ms – 280 ms |
| **Input Token Pricing** | **$0.10 / 1M tokens** | $0.10 / 1M tokens | Billed by plan | Workers AI pricing |
| **Output Token Pricing** | **$0.00 / 1M tokens** (`output_tokens: 0`) | $0.00 / 1M tokens (`output_tokens: 0`) | $0.00 (`output_tokens: 0`) | $0.00 (`output_tokens: 0`) |
| **Question Container** | Dictionary (`questions: [String: Question]`) | Array (`questions: [Question]`) | Dictionary (`questions: [String: Question]`) | Dictionary (`questions: [String: Question]`) |
| **Boolean Primitive** | `noul` (`noul` / `probability`) | `predicate` (`probability`) | `noul` (`noul`) | `noul` (`noul`) |
| **Multimodal Input** | Gemini `parts` with `inline_data` (raw Base64) | OpenAI `input_image` (RFC 2397 Data URL) | Text only (v1) | Inline Base64 images array |

### 3.2 Wire Schema & Protocol Comparison

Unlike OpenAI Decisions (which renames `noul` to `predicate` and wraps questions/answers in ordered arrays), Google's Gemini Decisions API preserves the dictionary-keyed `questions: [String: Question]` and `answers: [String: Answer]` structure of System One, while using `input` (string or multimodal `parts` array) instead of `state`:

```
+----------------------------------------------------------------------------------------------------------+
| SystemOneCore Internal DTO (SystemOneRequest)     | Google Gemini Decisions Wire Schema (gemini-decision-1)|
+---------------------------------------------------+------------------------------------------------------+
| {                                                 | {                                                    |
|   "model": "gemini-decision-1",                   |   "model": "gemini-decision-1",                      |
|   "state": "Customer requests refund...",         |   "input": "Customer requests refund...",            |
|   "questions": {                                  |   "questions": {                                     |
|     "isUrgent": {                                 |     "isUrgent": {                                    |
|       "type": "noul",                             |       "type": "noul",                                |
|       "instructions": "Is immediate action req?"  |       "instructions": "Is immediate action req?"     |
|     },                                            |     },                                               |
|     "category": {                                 |     "category": {                                    |
|       "type": "choice",                           |       "type": "choice",                              |
|       "instructions": "Select ticket category",   |       "instructions": "Select ticket category",      |
|       "criteria": {                               |       "criteria": {                                  |
|         "billing": "Invoice or charge issue",     |         "billing": "Invoice or charge issue",        |
|         "tech": "Technical bug or crash"          |         "tech": "Technical bug or crash"             |
|       }                                           |       }                                              |
|     },                                            |     },                                               |
|     "severity": {                                 |     "severity": {                                    |
|       "type": "score",                            |       "type": "score",                               |
|       "instructions": "Rate severity 0 to 2",     |       "instructions": "Rate severity 0 to 2",        |
|       "criteria": ["Low", "Medium", "High"]       |       "criteria": ["Low", "Medium", "High"]          |
|     }                                             |     }                                                |
|   }                                               |   }                                                  |
| }                                                 | }                                                    |
+---------------------------------------------------+------------------------------------------------------+
```

### 3.3 Question & Answer Primitives Mapping

#### 1. Boolean Proposition (`noul` — Yes/No Probability)
Evaluates the calibrated probability ($0.0 \dots 1.0$) that a boolean proposition holds true for the given input.
- **Gemini Request**:
  ```json
  {
    "type": "noul",
    "instructions": "Determine whether the invoice contains a valid tax identification number.",
    "criteria": {
      "true_description": "A valid tax ID or VAT number is explicitly present.",
      "false_description": "No tax ID or VAT number is visible on the invoice."
    }
  }
  ```
  *(Note: `criteria` with `true_description` and `false_description` is optional on `noul` questions; standard `SystemOneQuestion.noul(instructions:)` omits `criteria` unless explicitly provided via wire DTOs).*
- **Gemini Response**:
  ```json
  {
    "type": "noul",
    "noul": 0.94,
    "confidence": 0.96
  }
  ```
- **SystemOne Mapping**:
  - Maps from `SystemOneQuestion.noul(instructions:)`.
  - On response decoding, `GeminiDecisionsAnswer` decodes `noul` (and flexibly falls back to `probability` if returned by an upstream gateway version) alongside optional `confidence`, synthesizing `SystemOneAnswer(type: "noul", noul: resolvedNoul, confidence: confidence)`.

#### 2. Categorical Selection (`choice` — 2 to 255 Options)
Evaluates a mutually exclusive categorical choice across $2 \dots 255$ candidate options, returning the winning option, calibrated confidence, and full normalized probability distribution.
- **Gemini Request**:
  ```json
  {
    "type": "choice",
    "instructions": "Classify the primary department responsible for handling this request.",
    "criteria": {
      "billing": "Questions regarding invoices, refunds, or subscription charges.",
      "support": "Technical troubleshooting, bug reports, or outage inquiries.",
      "sales": "Enterprise licensing, seat expansion, or custom quotes."
    }
  }
  ```
  *(Note: `GeminiDecisionsQuestion` primarily encodes `criteria` as `[String: String]`, while also supporting array-based option lists if constructed directly via wire DTOs).*
- **Gemini Response**:
  ```json
  {
    "type": "choice",
    "choice": "billing",
    "confidence": 0.95,
    "probabilities": {
      "billing": 0.95,
      "support": 0.04,
      "sales": 0.01
    }
  }
  ```
- **SystemOne Mapping**:
  - Maps from `SystemOneQuestion.choice(instructions:criteria:)`.
  - On response decoding, `GeminiDecisionsAnswer` decodes `choice` (and flexibly falls back to `selected` if present), `confidence`, and `probabilities: [String: Double]`, mapping directly to `SystemOneAnswer(type: "choice", choice: resolvedChoice, confidence: confidence, probabilities: probabilities)`.

#### 3. Ordered Rubric (`score` — 2 to 255 Levels, 0-Indexed)
Evaluates an ordered rubric across $2 \dots 255$ levels (0-indexed: `"0"`, `"1"`, `"2"`, ...), returning a probability-weighted continuous expectation (`score`), `confidence`, per-level `probabilities`, and `legend`.
- **Gemini Request**:
  ```json
  {
    "type": "score",
    "instructions": "Evaluate the urgency of the customer escalation.",
    "criteria": [
      "Level 0: Routine informational inquiry with no business impact.",
      "Level 1: Moderate issue affecting a single user with a known workaround.",
      "Level 2: Critical production outage impacting multiple customers."
    ]
  }
  ```
- **Gemini Response**:
  ```json
  {
    "type": "score",
    "score": 1.81,
    "confidence": 0.91,
    "probabilities": {
      "0": 0.01,
      "1": 0.17,
      "2": 0.82
    },
    "legend": {
      "0": "Level 0: Routine informational inquiry with no business impact.",
      "1": "Level 1: Moderate issue affecting a single user with a known workaround.",
      "2": "Level 2: Critical production outage impacting multiple customers."
    }
  }
  ```
- **SystemOne Mapping**:
  - Maps from `SystemOneQuestion.score(instructions:criteria:)`.
  - On response decoding, `score`, `confidence`, `probabilities: [String: Double]`, and `legend: [String: String]` map directly to `SystemOneAnswer`, where `SystemOneAnswer.scoreValue(minimum:maximum:isInteger:)` automatically handles index shifting (e.g., mapping 0-indexed `0...4` wire levels to 1-indexed `@Guide(.range(1...5))` Swift properties).

### 3.4 Multimodal `input` Wire Format
The Gemini Decisions API supports both compact text-only strings and multimodal content part arrays in the `input` field:

1. **Text-Only Input** (when `request.images` is `nil` or empty):
   ```json
   {
     "model": "gemini-decision-1",
     "input": "Evaluate the following customer support transcript...",
     "questions": { ... }
   }
   ```
2. **Multimodal Input** (when one or more `SystemOneImage` attachments are extracted from the Foundation Models `Transcript`):
   ```json
   {
     "model": "gemini-decision-1",
     "input": [
       {
         "parts": [
           {
             "text": "Inspect this damaged package photo and delivery manifest."
           },
           {
             "inline_data": {
               "mime_type": "image/jpeg",
               "data": "/9j/4AAQSkZJRgABAQAAAQABAAD..."
             }
           }
         ]
       }
     ],
     "questions": { ... }
   }
   ```
   - **Important Wire Distinction**: Unlike OpenAI Decisions (which requires a `data:image/jpeg;base64,...` RFC 2397 Data URL prefix), Google's `inline_data.data` field requires the **raw Base64-encoded string** without a `data:` URI prefix, paired with an explicit `inline_data.mime_type` (`image/png`, `image/jpeg`, or `image/webp`).

### 3.5 Error Envelope & Safety Handling
1. **Standard Google Cloud / Generative Language RPC Error Envelope**:
   ```json
   {
     "error": {
       "code": 400,
       "message": "Invalid question criteria: choice questions require between 2 and 255 options.",
       "status": "INVALID_ARGUMENT"
     }
   }
   ```
   - HTTP `401` / `403` (`UNAUTHENTICATED` / `PERMISSION_DENIED`) $\to$ `SystemOneError.unauthorized`
   - HTTP `429` (`RESOURCE_EXHAUSTED`) $\to$ Retried via `RetryPolicy` (respecting `Retry-After`), or throws `SystemOneError.rateLimited(retryAfterSeconds:)`
   - HTTP `400` / `422` (`INVALID_ARGUMENT`) $\to$ `SystemOneError.httpError(statusCode:body:)` with extracted Google RPC `status` and `message`
   - Safety Refusal answers (`type == "refusal"` or explicit refusal message) $\to$ `SystemOneError.safetyRefusal(question:reason:)`

---

## 4. Functional Requirements

### FR-1: Naming, Module Topology & Public API Surface
1. **Module & Library Name**:
   - Target and library product name: `GeminiFoundationModels` (depending strictly on `SystemOneCore`).
2. **Primary Model Struct & Typealias**:
   - Primary type: `public struct GeminiDecisionsLanguageModel: LanguageModel, Sendable`
   - Convenience typealias: `public typealias GeminiLanguageModel = GeminiDecisionsLanguageModel`
3. **Core Component Naming**:
   - Executor: `public struct GeminiDecisionsExecutor: LanguageModelExecutor, Sendable`
   - Endpoint Configuration: `public enum GeminiDecisionsEndpoint: Hashable, Sendable`
   - HTTP Backend: `public struct GeminiDecisionsHTTPBackend: SystemOneBackend, Sendable`
   - Mock Backend: `public final class MockGeminiDecisionsBackend: SystemOneBackend, @unchecked Sendable`
   - Payload Adapter: `public enum GeminiDecisionsPayloadAdapter`
   - Wire DTOs: `GeminiDecisionsWireDTOs.swift` (`GeminiDecisionsRequest`, `GeminiDecisionsInput`, `GeminiDecisionsContentItem`, `GeminiDecisionsPart`, `GeminiDecisionsInlineData`, `GeminiDecisionsQuestion`, `GeminiDecisionsNoulCriteria`, `GeminiDecisionsCriteria`, `GeminiDecisionsResponse`, `GeminiDecisionsAnswer`, `GeminiDecisionsErrorEnvelope`)
   - Executable Demo Targets: `gemini-quickstart` ([`Examples/Quickstarts/GeminiQuickstart`](../../Examples/Quickstarts/README.md)), `system-one-cli --provider gemini` ([`Examples/CLI/`](../../Examples/CLI/README.md)), and standalone trait sample [`Examples/TraitSamples/08-CloudGeminiDecisions`](../../Examples/TraitSamples/08-CloudGeminiDecisions/README.md) *(superseding the initial standalone `gemini-demo` / `Examples/GeminiDemo` prototype)*.

### FR-2: Multimodal Data Attachment Support in Foundation Models
1. **Capability Declaration**:
   - `GeminiDecisionsLanguageModel.capabilities` shall declare `LanguageModelCapabilities([.guidedGeneration, .vision])`.
   - `supportsDataAttachmentType(_ type: UTType)` shall return `true` for:
     - `UTType.png` (`public.png`)
     - `UTType.jpeg` (`public.jpeg`)
     - `UTType.webP` (`org.webmproject.webp`)
   - All other `UTType` attachments shall return `false`.
   - `supportsDataEntryType(_ type: UTType)` shall return `false`.
2. **Multimodal Transcript Extraction**:
   - `GeminiDecisionsExecutor` shall extract both state text and supported image attachments (`SystemOneImage`) from the Foundation Models `Transcript` via `TranscriptExtractor`.
   - When `request.images` is empty or `nil`, `GeminiDecisionsPayloadAdapter` shall encode `input` as a plain JSON string (`GeminiDecisionsInput.text(String)`).
   - When `request.images` is non-empty, `GeminiDecisionsPayloadAdapter` shall encode `input` as `GeminiDecisionsInput.multimodal([GeminiDecisionsContentItem])`, placing the text part first followed by `inline_data` parts for each image (`mime_type` and raw Base64 `data`, stripping any accidental `data:*;base64,` prefix if present).

### FR-3: Gemini Decisions Wire Schema Adapter (`GeminiDecisionsPayloadAdapter`)
1. **Request Adaptation (`toWireRequest`)**:
   - Validates that `request.questions` contains between 1 and 1,000 questions (throwing `SystemOneError.schemaTranslationFailed` if empty or $> 1,000$).
   - Translates each `[String: SystemOneQuestion]` entry into `[String: GeminiDecisionsQuestion]`:
     - `.noul(let instructions)` $\to$ `GeminiDecisionsQuestion(type: "noul", instructions: instructions)`
     - `.choice(let instructions, let criteria)` $\to$ Validates $2 \dots 255$ options, producing `GeminiDecisionsQuestion(type: "choice", instructions: instructions, criteria: .choiceMap(criteria))`
     - `.score(let instructions, let criteria)` $\to$ Validates $2 \dots 255$ rubric levels, producing `GeminiDecisionsQuestion(type: "score", instructions: instructions, criteria: .scoreRubric(criteria))`
2. **Response Adaptation (`fromWireResponse`)**:
   - Inspects every `[String: GeminiDecisionsAnswer]` entry:
     - If `answer.type == "refusal"` or `answer.refusal != nil`, throws `SystemOneError.safetyRefusal(question: key, reason: reason)`.
     - For `"noul"`: resolves `answer.noul ?? answer.probability`, validates finite $[0.0, 1.0]$ bounds, and constructs `SystemOneAnswer(type: "noul", noul: prob, confidence: answer.confidence)`.
     - For `"choice"`: resolves `answer.choice ?? answer.selected`, validates non-empty string, and constructs `SystemOneAnswer(type: "choice", choice: selected, confidence: answer.confidence, probabilities: answer.probabilities)`.
     - For `"score"`: validates finite `answer.score`, constructs `legend` (using wire `legend` or synthesizing a 0-indexed legend from the request's `score` criteria array if omitted by the server), and returns `SystemOneAnswer(type: "score", score: score, confidence: answer.confidence, probabilities: answer.probabilities, legend: resolvedLegend)`.
   - Preserves `usage` (`input_tokens`, `output_tokens`) and timing telemetry (`serverDurationMs`, `transportDurationMs`).

### FR-4: Backend & Transport Architecture
```
                           +--------------------------------+
                           | LanguageModelSession           |
                           +---------------+----------------+
                                           |
                           +---------------v----------------+
                           | GeminiDecisionsLanguageModel   |
                           | (typealias GeminiLanguageModel)|
                           +---------------+----------------+
                                           |
                           +---------------v----------------+
                           | GeminiDecisionsExecutor        |
                           +---------------+----------------+
                                           |
                           +---------------v----------------+
                           | SystemOneBackend (Protocol)    |
                           +---------------+----------------+
                                           |
          +--------------------------------+-------------------------------+
          |                                                                |
+---------v-------------------------+             +------------------------v-------------------+
| GeminiDecisionsHTTPBackend        |             | MockGeminiDecisionsBackend                 |
| - URLSession Transport            |             | - Deterministic offline unit testing       |
| - x-goog-api-key Auth Header      |             | - Queueable responses & error simulation   |
| - GEMINI_API_KEY / GOOGLE_API_KEY |             | - Wire payload inspection                  |
| - RFC 9110 Retry-After & Backoff  |             | - Zero network traffic                     |
+-----------------------------------+             +--------------------------------------------+
```

1. **`GeminiDecisionsEndpoint`**:
   - Default URL: `https://generativelanguage.googleapis.com/v1beta/decisions`
   - Default Model: `gemini-decision-1`
   - Cases: `.hosted(model: String = defaultModel, clientRequestID: String? = nil)` and `.custom(URL, model: String = defaultModel, clientRequestID: String? = nil)`.
2. **`GeminiDecisionsHTTPBackend`**:
   - Resolves API key in priority order:
     1. Explicit `apiKey` passed to initializer (trimmed, non-empty).
     2. `ProcessInfo.processInfo.environment["GEMINI_API_KEY"]`.
     3. `ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]`.
   - If no key is available, throws `SystemOneError.missingAPIKey(environmentVariable: "GEMINI_API_KEY")`.
   - Sets HTTP headers:
     - `x-goog-api-key: <resolvedKey>`
     - `Content-Type: application/json`
     - `Accept: application/json`
     - `X-Client-Request-Id: <clientRequestID>` (when configured on `GeminiDecisionsEndpoint`)
   - Parses server timing headers (`x-Response-Time`, `Server-Timing`, or wire `serverDurationMs`) and measures client transport duration (`ContinuousClock`).
3. **`MockGeminiDecisionsBackend`**:
   - Thread-safe (`NSLock`) conforming to `SystemOneBackend` for deterministic offline testing.
   - Records all `SystemOneRequest` and translated `GeminiDecisionsRequest` wire payloads.
   - Supports static responses, queued FIFO responses, custom closure handlers, and simulated `SystemOneError` failures.

### FR-5: Package Architecture & SPM Package Traits
1. **Target & Product Registration in `Package.swift`**:
   - Library product: `.library(name: "GeminiFoundationModels", targets: ["GeminiFoundationModels"])`
   - Executable products: `.executable(name: "gemini-quickstart", targets: ["GeminiQuickstart"])` and `.executable(name: "system-one-cli", targets: ["SystemOneCLI"])` *(consolidated from the initial `gemini-demo` target)*
   - Target `GeminiFoundationModels` depending on `SystemOneCore` with `.enableUpcomingFeature("StrictConcurrency")`.
   - Test target `GeminiFoundationModelsTests` depending on `GeminiFoundationModels` and `SystemOneCore`.
2. **SPM Package Traits**:
   - Declare trait:
     ```swift
     .trait(
         name: "Gemini",
         description: "Enables Google Gemini Decisions API (gemini-decision-1) hosted client"
     )
     ```
   - Add `"Gemini"` to composite traits:
     - `Remote`: `enabledTraits: ["Jev", "LayaServe", "Clef", "OpenAI", "Gemini"]`
     - `All`: `enabledTraits: ["Jev", "Laya", "LayaServe", "Clef", "OpenAI", "Gemini"]`
   - Conditionally link `GeminiFoundationModels` in umbrella target `SystemOneFoundationModels`:
     ```swift
     .target(name: "GeminiFoundationModels", condition: .when(traits: ["Gemini"]))
     ```
   - Re-export `GeminiFoundationModels` in `Sources/SystemOneFoundationModels/SystemOneFoundationModels.swift` using `#if canImport(GeminiFoundationModels) @_exported import GeminiFoundationModels #endif`.

### FR-6: CLI Demonstrators (`Examples/Quickstarts/GeminiQuickstart`, `Examples/CLI/`, & `Examples/TraitSamples/08-CloudGeminiDecisions`)
1. Provide real, production-representative CLI executables (`gemini-quickstart` in `Examples/Quickstarts/GeminiQuickstart`, `system-one-cli --provider gemini` in `Examples/CLI`, and trait-isolated `08-CloudGeminiDecisions` — superseding the standalone `Examples/GeminiDemo` folder):
   - Evaluates realistic `@Generable` decision schemas (including `@Guide` descriptions, boolean `noul` checks, categorical `choice` enums, and `@Guide(.range(...))` `score` fields) against `GeminiDecisionsLanguageModel` and prints calibrated probabilities, rubric scores, token usage, latency, and `RoutingPolicy` outcomes.
   - Supports `--image <path>` (via `system-one-cli vision-inspect --provider gemini --image <path>`) to demonstrate multimodal inline image evaluation (`PNG`, `JPEG`, `WebP`).
   - Adheres strictly to Workspace Principle #7 (No mock fallbacks in example apps): if neither `GEMINI_API_KEY` nor `GOOGLE_API_KEY` is set, prints a clear remediation banner and exits immediately with `exit(1)`.

---

## 5. Acceptance Criteria

### AC-1: Native `@Generable` Evaluation & Call-Site Ergonomics
- **Scenario 1.1**: End-to-End `@Generable` Evaluation via `LanguageModelSession`
  - **Given** a `LanguageModelSession` initialized with `GeminiDecisionsLanguageModel` (or `GeminiLanguageModel`),
  - **When** `session.respond(to: prompt, generating: SupportTicketDecision.self)` is invoked,
  - **Then** the executor translates the `@Generable` schema into a dictionary of `noul`, `choice`, and `score` questions, dispatches the request to `gemini-decision-1`, synthesizes the strongly-typed `SupportTicketDecision` struct, and emits calibrated metadata (`probabilities`, `confidence`, `scores`, `model: "gemini-decision-1"`).
- **Scenario 1.2**: Unstructured Text Generation Rejection
  - **Given** a `LanguageModelSession` backed by `GeminiDecisionsLanguageModel`,
  - **When** `session.respond(to: "Write a poem")` is invoked without a `@Generable` schema,
  - **Then** `GeminiDecisionsExecutor` immediately throws `SystemOneError.structuredOutputRequired` without performing any network request.

### AC-2: Wire Schema Translation (`noul`, `choice`, `score` & Multimodal `parts`)
- **Scenario 2.1**: Text-Only Request Wire Encoding
  - **Given** a prompt without image attachments and a `@Generable` schema with `Bool`, `enum`, and `@Guide(.range(1...5))` `Int` properties,
  - **When** encoded by `GeminiDecisionsPayloadAdapter.toWireRequest`,
  - **Then** the resulting JSON has `"model": "gemini-decision-1"`, `"input": "<state text>"`, and `"questions"` keyed by property name with `"type": "noul"`, `"type": "choice"`, and `"type": "score"`.
- **Scenario 2.2**: Multimodal Inline Image Wire Encoding
  - **Given** a prompt containing state text and a JPEG attachment,
  - **When** encoded by `GeminiDecisionsPayloadAdapter.toWireRequest`,
  - **Then** `"input"` is serialized as `[{"parts": [{"text": "<state text>"}, {"inline_data": {"mime_type": "image/jpeg", "data": "<raw_base64>"}}]}]`.
- **Scenario 2.3**: Flexible Answer Field Decoding & 1-Indexed Score Shifting
  - **Given** a Gemini wire response containing `noul` (or `probability`), `choice` (or `selected`), and a 0-indexed `score` of `3.0` across 5 rubric levels (`"0"` through `"4"`),
  - **When** decoded and synthesized into a `@Generable` struct with `@Guide(.range(1...5))`,
  - **Then** the 0-indexed wire score `3.0` is accurately shifted to `4` in the synthesized Swift struct, and `ScoreValue` probabilities/legends reflect keys `1...5`.

### AC-3: Authentication & Credential Resolution (`x-goog-api-key`)
- **Scenario 3.1**: Explicit `apiKey` Parameter
  - **Given** `GeminiDecisionsLanguageModel(apiKey: "AIzaSyTestKey123")`,
  - **When** an HTTP request is constructed,
  - **Then** the request header `x-goog-api-key` equals `"AIzaSyTestKey123"`, and no `Authorization: Bearer` header is sent.
- **Scenario 3.2**: Environment Variable Fallback (`GEMINI_API_KEY` $\to$ `GOOGLE_API_KEY`)
  - **Given** `apiKey` is `nil`,
  - **When** `GEMINI_API_KEY` is present in the environment, it is used; if absent and `GOOGLE_API_KEY` is present, `GOOGLE_API_KEY` is used; if both are absent, `SystemOneError.missingAPIKey(environmentVariable: "GEMINI_API_KEY")` is thrown.

### AC-4: Error Handling, Safety Refusals & Rate-Limit Backoff
- **Scenario 4.1**: Google RPC Error Envelope Parsing
  - **Given** an HTTP 400 response with `{"error": {"code": 400, "message": "Invalid argument", "status": "INVALID_ARGUMENT"}}`,
  - **When** processed by `GeminiDecisionsHTTPBackend`,
  - **Then** it throws `SystemOneError.httpError(statusCode: 400, body: "INVALID_ARGUMENT: Invalid argument")` without retrying.
- **Scenario 4.2**: HTTP 429 Rate-Limit Retry with `Retry-After`
  - **Given** an initial HTTP 429 response with header `Retry-After: 1` followed by an HTTP 200 response,
  - **When** `RetryPolicy.default` is active,
  - **Then** the backend awaits the retry delay and returns the valid `SystemOneResponse` on the second attempt.
- **Scenario 4.3**: Safety Refusal Handling
  - **Given** a response where an answer has `"type": "refusal"`,
  - **When** adapted by `GeminiDecisionsPayloadAdapter`,
  - **Then** `SystemOneError.safetyRefusal(question:reason:)` is thrown.

### AC-5: Swift 6 Concurrency, SPM Traits & Hermetic Unit Tests
- **Scenario 5.1**: Zero-Warning Swift 6 Compilation
  - **Given** the package built with `StrictConcurrency` enabled,
  - **When** compiling `GeminiFoundationModels`, `SystemOneFoundationModels`, `GeminiQuickstart`, `SystemOneCLI`, and `GeminiFoundationModelsTests`,
  - **Then** compilation succeeds with zero warnings or concurrency errors.
- **Scenario 5.2**: Hermetic Offline Test Suite
  - **Given** `GeminiFoundationModelsTests` using `MockGeminiDecisionsBackend` and mock `URLProtocol`,
  - **When** running `swift test`,
  - **Then** 100% of tests pass deterministically offline without live API keys.

---

## 6. Non-Functional Requirements

### 6.1 Performance & Capacity Budgets
- **Server-Side Latency**: ~150ms–250ms P50 latency for single-pass evaluations.
- **Client Serialization Overhead**: Schema translation and JSON adaptation for up to 1,000 questions must complete in $< 10$ ms on Apple Silicon.
- **Question Capacity**: Support up to 1,000 concurrent questions per `SystemOneRequest` and up to 256K tokens of input context.

### 6.2 Concurrency & Dependency Hygiene
- **Strict Concurrency**: Complete Swift 6 `Sendable` conformance across all public and internal types.
- **Zero External Dependencies**: Relies strictly on Apple's `Foundation`, `FoundationModels`, `UniformTypeIdentifiers`, and internal `SystemOneCore`.

### 6.3 Security & Credential Hygiene
- **Header Security**: Never log the value of `x-goog-api-key` in error descriptions or debug telemetry.
- **Attachment Redaction**: Never log raw Base64 image data in error messages or console logs.

---

## 7. Edge Cases & Error Handling

1. **Exceeding 1,000 Questions Limit**:
   - *Behavior*: `GeminiDecisionsPayloadAdapter` validates `request.questions.count <= 1000` before network transmission and throws `SystemOneError.schemaTranslationFailed("Gemini Decisions API supports between 1 and 1,000 questions per request (got \(count)).")`.
2. **Invalid `choice` or `score` Cardinality**:
   - *Behavior*: If a `choice` question has $< 2$ or $> 255$ options, or a `score` question has $< 2$ or $> 255$ levels, the adapter throws `SystemOneError.schemaTranslationFailed` locally before sending the HTTP request.
3. **Data URL Prefix in `SystemOneImage.base64Data`**:
   - *Behavior*: If caller code supplies a `SystemOneImage` whose `base64Data` includes a `data:image/jpeg;base64,` prefix, `GeminiDecisionsPayloadAdapter` strips the prefix so Google's `inline_data.data` receives pure Base64 bytes.
4. **Missing Legend in `score` Response**:
   - *Behavior*: If the server omits the `legend` dictionary on a `score` answer, `GeminiDecisionsPayloadAdapter` reconstructs the 0-indexed `legend` from the request's `score` criteria array so `ScoreValue` always has complete level descriptions.
5. **Empty Prompt Text with Image Attachment**:
   - *Behavior*: If a user submits an image attachment with an empty text string, `TranscriptExtractor` / `GeminiDecisionsPayloadAdapter` preserves valid non-empty prompt instructions or throws `SystemOneError.emptyTranscript` when both text and attachments are empty.

---

## 8. Out of Scope

1. **Autoregressive Text Generation (`generateContent` / `streamGenerateContent`)**:
   - `GeminiFoundationModels` exclusively targets the non-autoregressive `/v1beta/decisions` endpoint (`gemini-decision-1`). Open-ended chat completion is out of scope.
2. **Google File API (`files.upload`) & Cloud Storage (`gs://`) URIs**:
   - Visual inputs in v1.4.0 are transmitted strictly as inline Base64 (`inline_data`). External `file_data` URI references are out of scope for this release.
3. **Vertex AI OAuth2 IAM Token Refresh**:
   - Authentication in v1.4.0 uses `x-goog-api-key` (with support for custom gateway endpoints via `GeminiDecisionsEndpoint.custom`). Full OAuth2 service-account JWT signing is out of scope.

---

## 9. Handoff & Technical Dependencies

### Implementation Phasing
- **Phase 1: Architectural Decision Record (`docs/architecture/ADR-2026-11-11-01-gemini-decisions-models-integration.md`)**:
  - Formalize module structure, wire DTO schemas, `x-goog-api-key` credential resolution, and multimodal `parts` encoding.
- **Phase 2: Core Target Implementation (`Sources/GeminiFoundationModels/`)**:
  - Implement `GeminiDecisionsEndpoint`, `GeminiDecisionsWireDTOs`, `GeminiDecisionsPayloadAdapter`, `GeminiDecisionsHTTPBackend`, `MockGeminiDecisionsBackend`, `GeminiDecisionsExecutor`, and `GeminiDecisionsLanguageModel` (`GeminiLanguageModel`).
- **Phase 3: Package Trait & Umbrella Integration (`Package.swift`)**:
  - Add `Gemini` trait, `GeminiFoundationModels` library/target, `GeminiFoundationModelsTests` test target, and CLI executable targets (`gemini-quickstart` and `system-one-cli`, consolidated from the initial `gemini-demo` prototype).
- **Phase 4: Comprehensive Unit Tests & CLI Demos**:
  - Author `Tests/GeminiFoundationModelsTests/GeminiFoundationModelsTests.swift`, `Examples/Quickstarts/GeminiQuickstart/main.swift`, `Examples/TraitSamples/08-CloudGeminiDecisions/`, and `Examples/CLI/` (`--provider gemini`).
  - Document findings in `tech-notes/0018-gemini-decisions-api-architecture.md`.

### Handoff Gate
This PRD is ready for Stage 2 of the Spec-Driven Pipeline:
- **Assigned Architect**: Senior Architect Agent (`@senior-architect`)
- **Next Deliverable**: `docs/architecture/ADR-2026-11-11-01-gemini-decisions-models-integration.md`
