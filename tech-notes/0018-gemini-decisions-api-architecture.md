# 0018 — Google Gemini Decisions API (`gemini-decision-1`) System One Model Architecture

- **Date**: 2026-11-11
- **Author**: Peter Friese
- **Framework**: `FoundationModels` (iOS 27.0+, macOS 27.0+, visionOS 27.0+), `SystemOneCore`, `GeminiFoundationModels`
- **Upstream**: Google Gemini Decisions API (`POST https://generativelanguage.googleapis.com/v1beta/decisions`), `gemini-decision-1`

---

## Context

Enterprise and mobile applications built on Google's Gemini ecosystem often need to evaluate high-density operational decisions—classifying support tickets, auditing expense receipts, checking policy compliance across 256K-token context windows, and routing agent state transitions. Historically, engineering teams had to invoke autoregressive `generateContent` endpoints with constrained JSON decoding (`responseSchema`).

### Why Autoregressive `generateContent` Falls Short for System One Decisions

1. **Sequential Token Decoding Latency**: Generating structured JSON token-by-token introduces 800ms–2,500ms of latency, which scales linearly with the number of fields in the schema.
2. **Output Token Billing Overhead**: Autoregressive endpoints bill for every generated JSON key, brace, and value token, penalizing rich multi-field `@Generable` schemas.
3. **Lack of Calibrated Epistemic Probabilities**: Autoregressive decoders emit discrete token selections rather than calibrated Bayesian probability distributions over boolean propositions (`noul`), categorical choices (`choice`), or ordinal rubrics (`score`).

### The Google Gemini Decisions API & `gemini-decision-1`

Google's **Gemini Decisions API** (`POST https://generativelanguage.googleapis.com/v1beta/decisions`), powered by **`gemini-decision-1`**, provides a dedicated, non-autoregressive System One decision engine on the Google Generative Language platform:
- Evaluates up to **1,000 independent questions** in a single forward pass against a **256K-token** multimodal context window.
- Priced at **$0.10 per 1M input tokens** and **$0.00 per 1M output tokens** (`output_tokens: 0` / `candidatesTokenCount: 0`).
- Uses native System One dictionary-keyed `questions: [String: Question]` and `answers: [String: Answer]` wire structures (`noul`, `choice`, `score`).

This tech note documents the wire protocol, dictionary-keyed primitive alignment, multimodal `parts` / `inline_data` raw Base64 extraction, `usage` vs. `usageMetadata` normalization, and Google RPC error envelope handling in `GeminiFoundationModels`.

---

## Findings

### 1. Dictionary-Keyed `noul` / `choice` / `score` Wire Alignment

Unlike OpenAI's Decisions API (`POST /v1/decisions`), which uses an ordered array of questions (`questions: [Question]`) and renames boolean propositions to `"predicate"`, Google's Gemini Decisions API natively adopts the dictionary-keyed System One schema:

| System One Primitive | Gemini Wire `type` | Request `criteria` Format | Response Answer Fields |
| :--- | :--- | :--- | :--- |
| **`noul`** | `"noul"` | Optional `{ "true_description": "...", "false_description": "..." }` | `noul` (or alias `probability`: $0.0 \dots 1.0$), `confidence` |
| **`choice`** | `"choice"` | `[String: String]` (`{ "optionKey": "description" }`) | `choice` (or alias `selected`), `confidence`, `probabilities: [String: Double]` |
| **`score`** | `"score"` | `[String]` (ordered rubric level descriptions) | `score` (0-indexed expectation), `confidence`, `probabilities: [String: Double]`, `legend: [String: String]` |

Because `v1beta` and gateway proxies can emit either `"noul"` or `"probability"` for boolean propositions and either `"choice"` or `"selected"` for categorical selections, `GeminiDecisionsAnswer` normalizes both aliases during `init(from: Decoder)` so downstream `GeminiDecisionsPayloadAdapter` logic always receives a canonical representation.

### 2. Multimodal Typed `input` Array & Raw Base64 Image Extraction

When visual attachments (`PNG`, `JPEG`, `WebP`) are included in a Foundation Models `Transcript`, `TranscriptAttachmentExtractor` produces `SystemOneImage` values whose `dataURL` property is formatted as an RFC 2397 Data URL (`data:image/jpeg;base64,/9j/4AAQ...`).

Unlike conversational `generateContent` endpoints (which use `[{"role": "user", "parts": [{"text": ...}, {"inline_data": ...}]}]`), the live Google Gemini Decisions API (`POST /v1beta/decisions`) rejects `parts` envelopes without a `"type"` parameter (`The 'type' parameter is required at 'input[0]'`) and rejects `"image_url"` (`The value 'image_url' is not supported for 'type' at 'input[1]'. Supported values: 'audio', 'document', 'image', 'text', 'video'.`). Instead, `/v1beta/decisions` requires:
1. Plain string `"input": "<state text>"` when no images are attached.
2. A flat array of typed multimodal content items (`[{"type": "text", "text": "..."}, {"type": "image", "mime_type": "...", "data": "..."}]`) when images are attached, where `"image"` items separate `"mime_type"` from the **raw Base64 string** (`image.base64DataString`, without the RFC 2397 `data:<mime>;base64,` prefix):

```json
{
  "model": "gemini-decision-1",
  "input": [
    {
      "type": "text",
      "text": "Inspect this receipt photo."
    },
    {
      "type": "image",
      "mime_type": "image/jpeg",
      "data": "/9j/4AAQSkZJRgABAQAAAQABAAD..."
    }
  ],
  "questions": { ... }
}
```

`GeminiDecisionsPayloadAdapter.adaptRequest(_:)` validates all attachments via `GeminiDecisionsAttachmentValidator.validate(attachments:)`, strips the `data:<mime>;base64,` prefix via `image.base64DataString`, and encodes `.multimodal([.text(...), .image(mimeType:data:)])` (while `GeminiDecisionsRequest.InputPayload.init(from:)` also preserves backward-compatible decoding of legacy `parts` / `inline_data` payloads).

### 3. Dual `usage` and `usageMetadata` Telemetry Normalization

Depending on whether a request is served directly by the `/v1beta/decisions` edge or routed through a Google Cloud / Vertex AI gateway, token accounting may appear under either:
- `"usage": { "input_tokens": 140, "output_tokens": 0 }`, or
- `"usageMetadata": { "promptTokenCount": 140, "candidatesTokenCount": 0, "totalTokenCount": 140 }`.

`GeminiDecisionsResponse` decodes both `usage` and `usageMetadata` and exposes `resolvedUsage: Usage?`, ensuring `SystemOneResponse.usage` and the `LanguageModelExecutorGenerationChannel` always report accurate input token counts and `0` output tokens.

### 4. `x-goog-api-key` Authentication & Google RPC Error Envelopes

`GeminiDecisionsHTTPBackend` authenticates via the `x-goog-api-key` HTTP header (never leaking credentials into URL query parameters) and resolves API keys in priority order:
1. Explicit `apiKey` passed to `GeminiDecisionsLanguageModel` / `GeminiDecisionsHTTPBackend`.
2. `ProcessInfo.processInfo.environment["GEMINI_API_KEY"]`.
3. `ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]`.

Error responses from `generativelanguage.googleapis.com` follow the Google Cloud RPC error envelope:
```json
{
  "error": {
    "code": 403,
    "message": "The caller does not have permission",
    "status": "PERMISSION_DENIED"
  }
}
```
- HTTP `401` / `403` or RPC status `"UNAUTHENTICATED"` / `"PERMISSION_DENIED"` map immediately to `SystemOneError.authenticationFailed` without retrying.
- HTTP `429` with quota/billing exhaustion messages maps immediately to `SystemOneError.quotaExceeded` without retrying.
- Transient HTTP `429` (`RESOURCE_EXHAUSTED`) and `5xx` responses honor RFC 9110 `Retry-After` headers and `RetryPolicy` exponential backoff.

---

## Implications

1. **Drop-In Apple Foundation Models Ergonomics**: Developers can initialize `GeminiDecisionsLanguageModel()` (or `GeminiLanguageModel()`) and pass it directly to `LanguageModelSession`:
   ```swift
   let session = LanguageModelSession(model: GeminiLanguageModel())
   let response = try await session.respond(to: prompt, generating: ExpenseAuditDecision.self)
   ```
2. **Swift 6.1 Package Trait Isolation**: The `Gemini` trait enables `GeminiFoundationModels` in both `Remote` and `All` trait bundles while keeping `OnDevice` builds free of remote client code.
3. **Hermetic Offline Testing**: `MockGeminiDecisionsBackend` records both `lastRequest: SystemOneRequest?` and `lastGeminiRequest: GeminiDecisionsRequest?`, enabling complete offline unit testing of multimodal `parts` and `@Generable` synthesis.

---

## Evidence / Sources

- `docs/prd/PRD-2026-11-11-gemini-decisions-models.md`
- `docs/architecture/ADR-2026-11-11-01-gemini-decisions-models-integration.md`
- `Sources/GeminiFoundationModels/GeminiDecisionsEndpoint.swift`
- `Sources/GeminiFoundationModels/GeminiDecisionsWireDTOs.swift`
- `Sources/GeminiFoundationModels/GeminiDecisionsPayloadAdapter.swift`
- `Sources/GeminiFoundationModels/GeminiDecisionsHTTPBackend.swift`
- `Sources/GeminiFoundationModels/GeminiDecisionsLanguageModel.swift`
- `Sources/GeminiFoundationModels/GeminiDecisionsExecutor.swift`
