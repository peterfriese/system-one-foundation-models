---
name: jev-foundation-models
license: Apache-2.0
description: >-
  Evaluate TypeSafe Jev System One decision models natively through Apple's Foundation
  Models framework in Swift 6. Use when building iOS 27+, macOS 27+, or visionOS 27+
  apps that evaluate strongly-typed @Generable structs and enums using LanguageModelSession,
  implementing confidence routing (RoutingPolicy, NoulJudgement, ScoreValue), configuring
  resilient network retries (RetryPolicy), securing mobile traffic via App Check proxy transports,
  or writing deterministic offline unit tests with MockJevTransport.
metadata:
  author: peterfriese
  version: "1.1"
---

# Jev Foundation Models Bridge

> [!TIP]
> **Modern Multi-Backend Standard**: For projects requiring on-device inference via Core ML (`LayaOnDevice`) or local self-hosted evaluation (`LayaFoundationModels`) alongside TypeSafe Jev cloud, refer to the unified `system-one-foundation-models` skill and package target. This skill remains focused on TypeSafe Jev cloud evaluation, resilience policies, and App Check security proxy architectures.

This skill guides the design, implementation, and testing of applications integrating **TypeSafe AI's Jev System One decision model** via **Apple's Foundation Models framework** (`FoundationModels`) in Swift 6.

---

## 1. Core Mental Model: Decisions, Not Chat

Jev is a **System One decision model**, not a text-generating LLM. It evaluates application state against a set of typed questions in a single forward pass, returning calibrated probabilities and discrete categorical decisions in 40–150ms.

- **Prompt $\to$ Application State**: The text passed to `session.respond(to:)` represents current application context (support tickets, sensor readings, transaction logs, user inputs, or parsed documents).
- **`@Generable` Type $\to$ Decision Questions**: The struct or enum defines the typed questions being asked over that state.
- **Dual Signal Output**:
  1. **The Answer**: *What* the model judged (`response.content` containing typed enum choices, booleans, or rubric scores). For `Bool` fields this decode is a hard 0.5 cutoff — see §3; decisions must consume `response.probability(for:)` / `response.judgement(for:policy:)`.
  2. **The Calibrated Confidence / Probability**: *Whether* to automate the action (`response.judgement(...)`, `response.decision(...)`, `response.scoreValue(...)`).

---

## 2. `@Generable` Schema Modeling Rules

`SchemaTranslator` maps Apple `@Generable` types directly to Jev decision primitives. Follow these mapping rules strictly:

| Swift Type & Annotations | Jev Primitive | Question Key Convention | Behavior / Output |
| :--- | :--- | :--- | :--- |
| `Bool` | **`noul`** | Field name (e.g. `"isUrgent"`) or `"root"` | Calibrated probability of truth ($0.0 \dots 1.0$). Decodes to Swift `Bool`. |
| `enum: String` | **`choice`** | Field name (e.g. `"department"`) or `"choice"` | Discrete categorical selection among defined enum cases. |
| `Int` or `Double` + `@Guide(.range(min...max))` | **`score`** | Field name (e.g. `"frustrationLevel"`) or `"root"` | Ordinal rubric scoring mapped to integer/numeric levels with continuous weighting. |
| `@Guide(description: "...")` | **`instructions`** | N/A | Natural language instructions steering Jev's judgment. |
| Nested `@Generable struct` | **`nested questions`** | Dot-notation (e.g. `"metadata.priority"`) | Evaluates hierarchical sub-properties concurrently. |

### Negative Constraints (Strictly Forbidden)
- ❌ **No unconstrained `String` properties**: Jev does not generate free-form text. A `String` property without enum choices throws `JevError.invalidSchema`.
- ❌ **No unstructured collections**: Arrays of open-ended values (`[String]`) or dictionaries are not supported.
- ❌ **No text generation requests without schemas**: Calling `session.respond(to: "Hello")` without a `generating:` argument throws `JevError.structuredOutputRequired`.
- ❌ **No tool calling**: `LanguageModelCapabilities` for Jev only includes `[.guidedGeneration]`. It does not support `Tool` execution.

### Correct Schema Example

```swift
import FoundationModels

@Generable
enum SupportDepartment: String, Sendable {
    case billing
    case technicalSupport
    case sales
}

@Generable
struct TriageDecision: Sendable {
    @Guide(description: "Is this customer inquiry urgent or blocking critical business?")
    var isUrgent: Bool

    @Guide(description: "Which department is best suited to resolve this issue?")
    var department: SupportDepartment

    @Guide(description: "Customer frustration rating on a 0 to 3 scale", .range(0...3))
    var frustrationLevel: Int
}
```

### Batched Questions Must Self-Identify

When a single `@Generable` type emits **multiple questions in one call** (e.g. two `Bool` fields → two batched nouls), each question's `@Guide(description:)` MUST name the entity it targets ("Candidate A", "transaction #8491"). Observably **identical instruction text collapses the batch** — Jev cannot discriminate between two questions that read exactly the same, and both answers land near 0.5 (observed live in a duplicate-detection integration: 0.77/0.79 before naming the candidates, 0.94/0.01 after). The library's `Examples/DuplicateArticleDemo` sidesteps the problem by evaluating **one question per request** (a task group of separate `respond` calls), which is simpler but forfeits the single-call batching contract — prefer self-identifying guides when one call must answer many questions.

---

## 3. Canonical Call-Site, Telemetry & Confidence Routing

Always use standard Apple Foundation Models APIs (`LanguageModelSession`)—do not introduce proprietary session wrappers:

```swift
import FoundationModels
import JevFoundationModels

// 1. Initialize the model provider
let model = JevLanguageModel(apiKey: apiKey)
let session = LanguageModelSession(model: model)

// 2. Evaluate state against the @Generable schema
let customerTicket = """
Ticket #8491: Urgent! I was charged $500 twice for renewal, and our accounts are locked!
"""

let response = try await session.respond(to: customerTicket, generating: TriageDecision.self)

// 3. Consume strongly typed decision content
let decision: TriageDecision = response.content
print("Department:", decision.department)       // .billing
print("Is Urgent:", decision.isUrgent)           // true
print("Frustration:", decision.frustrationLevel) // 3
```

> [!WARNING]
> **`response.content` is a hard 0.5 cutoff for `Bool` fields.** The synthesized decode (`ResponseSynthesizer`) maps a noul probability to a Swift `Bool` with `noul >= 0.5` — p = 0.55 decodes `true`, p = 0.45 decodes `false`, regardless of how decisive the model actually was. Treat `response.content` as display/fallback material only. All decisions must consume the **calibrated signal** — `response.probability(for:)` and `response.judgement(for:policy:)` — and route through a `RoutingPolicy`; never gate automation on a decoded content `Bool`.

### Confidence Routing with `RoutingPolicy`

Never write naive `if prob > 0.5` checks. In Jev:
- **`0.50` indicates maximum epistemic uncertainty**, not "half true".
- The **undecided band** ($0.35 \dots 0.65$) indicates the model is genuinely undecided (`answer == nil`).
- A probability of `0.05` is a **confident "no"** ($\text{decisiveness} = \max(p, 1 - p) = 0.95$), which routes to `.auto` with `answer: false`.

Use `RoutingPolicy` to map calibrated signals into three operational actions (`.auto`, `.confirm`, `.escalate`):

```swift
let policy = RoutingPolicy(
    escalateBelow: 0.60,
    autoAtOrAbove: 0.85,
    undecidedBand: 0.35...0.65
)

// Categorical or Scored Decision (.auto, .confirm, .escalate)
let deptAction = response.decision(for: "department", policy: policy)
switch deptAction {
case .auto:
    routeToDepartment(decision.department)
case .confirm:
    suggestDepartment(decision.department)
case .escalate:
    routeToGeneralQueue()
}

// Boolean (Noul) Judgement
let urgencyJudgement = response.judgement(for: "isUrgent", policy: policy)
switch urgencyJudgement.decision {
case .auto:
    if urgencyJudgement.answer == true {
        pageOnCallLead()       // Confident Yes (p >= 0.85)
    } else {
        markStandardPriority() // Confident No (p <= 0.15)
    }
case .confirm:
    promptAgentToConfirm()     // Leaning (0.16...0.34 or 0.65...0.84)
case .escalate:
    assignManualReview()       // Undecided band (0.35...0.65): answer is nil
}
```

### Rubric Scoring Telemetry with `ScoreValue`

For `@Guide(.range(...))` score properties, Jev returns probability-weighted positions across rubric levels:

```swift
if let score = response.scoreValue(for: "frustrationLevel") {
    print("Continuous Weighted Score:", score.value)      // e.g. 2.75 (leaning toward level 3)
    print("Discrete Rounded Level:", score.rounded)       // 3
    print("Confidence Score:", score.confidence)          // 0.0 ... 1.0
    if let normalized = score.normalized {
        print("Normalized Rubric Position:", normalized)  // 0.0 ... 1.0
    }
}
```

---

## 4. HTTP Resilience & Swift 6 Cooperative Cancellation

Configure automated retry backoff via `RetryPolicy` on `JevLanguageModel`:

```swift
let retryPolicy = RetryPolicy(
    maxAttempts: 3,                  // Initial attempt + up to 2 retries
    initialDelay: .milliseconds(500), // First retry delay
    multiplier: 2.0,                 // Exponential backoff
    jitter: 0.2,                     // +/- 20% random jitter to avoid thundering herds
    retryableStatuses: [429, 529],   // Retry rate-limits and temporary capacity limits
    maxRetryAfter: .seconds(60)      // Respects RFC 9110 Retry-After headers
)

let model = JevLanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)
```

> [!NOTE]
> **The model-level `retryPolicy:` only applies to the default `URLSessionTransport`.** When you pass an explicit `transport:` to `JevLanguageModel`, the `retryPolicy:` parameter is ignored — the transport is resolved first, and the transport owns its own retry semantics. On the proxy path (`ProxyTransport`, `FirebaseAppCheckTransport`), set `RetryPolicy` on the **transport** (`ProxyTransport.retryPolicy`, default retryable statuses `[429, 529]`), or the model-level knob silently does nothing.

### Cooperative Cancellation
In Swift 6 concurrency, task cancellation must never be swallowed or converted into a generic error:
- **`CancellationError` is NEVER wrapped in `JevError`**: If a parent `Task` is cancelled (e.g., user navigates away in SwiftUI), `CancellationError` propagates directly.
- Retry sleeps abort immediately upon cancellation.

```swift
let task = Task {
    try await session.respond(to: ticket, generating: TriageDecision.self)
}

// When user dismisses view or cancels operation:
task.cancel()

do {
    let response = try await task.value
} catch is CancellationError {
    print("Decision task cancelled cleanly.")
} catch let error as JevError {
    print("Jev failure: \(error)")
}
```

---

## 5. Production Mobile Architecture (`JevTransport`)

**Never embed `TYPESAFE_API_KEY` inside client application binaries.** 

In production iOS, macOS, or visionOS apps, route requests through a backend reverse proxy (such as a Firebase Cloud Function, Vapor backend, or Cloudflare Worker) protected by **Apple App Attest / Firebase App Check**.

The repository includes a ready-to-use reference transport in `Integrations/FirebaseAppCheckProxy/FirebaseAppCheckTransport.swift`:

```swift
import JevFoundationModels

// 1. Configure the proxy transport (supports .cached or .singleUse replay-protected tokens)
let transport = FirebaseAppCheckTransport(
    proxyEndpoint: URL(string: "https://your-cloud-function.cloudfunctions.net/triageProxy")!,
    tokenStrategy: .cached // < 1ms cached hardware token lookup
)

// 2. Initialize model without apiKey (authentication handled by App Check + backend proxy secret)
let model = JevLanguageModel(
    endpoint: URL(string: "https://your-cloud-function.cloudfunctions.net/triageProxy")!,
    transport: transport
)
let session = LanguageModelSession(model: model)
```

> [!WARNING]
> **App Check token acquisition can crash or come up empty.** `AppCheck.appCheck().token(forcingRefresh:)` throws an **uncaught Objective-C exception** when no default `FirebaseApp` is configured — `try?` cannot catch it — and yields no token on simulators without attestation or in hosted-test launches that skip app initialization. Guard with `FirebaseApp.app() != nil` before touching App Check, and provide a Monitor-mode/dev fallback value for hosts that cannot attest. The backend proxy MUST run in **Monitor mode** (log token validity, never reject) until enforcement is deliberately flipped on for every client.

### Server-Side Proxy Contract

The proxy function your transport calls should follow this compact contract — a plain HTTPS POST reverse proxy, **NOT a callable**:

- **POST-only** `onRequest` (405 + `Allow: POST` otherwise). Forward the client body **byte-verbatim** to `POST https://api.typesafe.ai/v1/systemone` with the server-side key injected as `Authorization: Bearer <key>` — no envelope, no transformation.
- **App Check**: read the raw token from `X-Firebase-AppCheck` (no prefix); verify with the Admin SDK `verifyToken(token, { consume: true })` on key-spending endpoints (single-use replay protection; `consume` is a documented no-op for App Attest/DeviceCheck tokens). **Monitor mode by default** — an env-driven flip (e.g. `APP_CHECK_ENFORCE === 'true'`) switches to rejecting missing/invalid tokens with 401 before any upstream work.
- **Cost gates BEFORE billing**: reject non-object bodies, empty `state`, empty `questions` with 400; oversized bodies with 413.
- **Rate limiter keyed on VERIFIED identity only**: key on the verified `uid` or the verified token's stable `appId`; garbage or unverified tokens fall into a shared `anonymous` bucket so token rotation cannot reset a per-token budget. Deny with 429 + `Retry-After` so client retry loops (429/529 only) engage.
- **Replicate upstream faithfully**: pass through upstream status + body + `content-type` + `Retry-After`; on fetch/read failure return a GENERIC 502 (detail logged server-side only, never echoed).

---

## 6. Deterministic Offline Testing with Swift Testing (`@Test`)

Always test decision workflows deterministically without live network access or API credentials using `MockJevTransport`:

```swift
import Testing
import FoundationModels
@testable import JevFoundationModels

@Suite("Triage Decision Tests")
struct TriageWorkflowTests {

    @Test("Verifies triage routing and high-probability escalation")
    func testUrgentBillingTriage() async throws {
        let mockTransport = MockJevTransport { request in
            #expect(request.questions.count == 3)
            #expect(request.state.contains("charged $500 twice"))

            return JevResponse(
                model: "jev-mock",
                answers: [
                    "isUrgent": JevAnswer(type: "noul", noul: 0.97, confidence: 0.95),
                    "department": JevAnswer(type: "choice", choice: "billing", confidence: 0.98),
                    "frustrationLevel": JevAnswer(type: "score", score: 2.8, confidence: 0.90)
                ],
                usage: JevUsage(inputTokens: 85, outputTokens: 10)
            )
        }

        let model = JevLanguageModel(apiKey: "mock-key", transport: mockTransport)
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(
            to: "charged $500 twice",
            generating: TriageDecision.self
        )

        // Verify strongly typed content
        #expect(response.content.isUrgent == true)
        #expect(response.content.department == .billing)
        #expect(response.content.frustrationLevel == 3) // rounded from 2.8

        // Verify routing policy decision
        let judgement = response.judgement(for: "isUrgent")
        #expect(judgement.decision == .auto)
        #expect(judgement.answer == true)

        // Verify rubric telemetry
        let frustration = response.scoreValue(for: "frustrationLevel")
        #expect(frustration?.rounded == 3)
        #expect(frustration?.value == 2.8)
    }
}
```

---

## 7. Implementation Nuances & Troubleshooting

| Issue / Error | Cause | Resolution |
| :--- | :--- | :--- |
| `JevError.invalidSchema` | `@Generable` type contains an unconstrained `String` or unsupported collection. | Convert `String` to `enum: String`, `Bool`, or numeric `@Guide(.range(...))`. |
| `JevError.structuredOutputRequired` | `session.respond(to:)` was called without a `generating:` schema. | Always pass a `@Generable` type to `generating:`. |
| `response.probability(...)` or `confidence(...)` returns `nil` | Question key does not match schema convention. | **Key Resolution Matrix**:<br>• Struct field: `"propertyName"` (e.g. `"isUrgent"`)<br>• Nested struct: `"parent.child"` (e.g. `"metadata.priority"`)<br>• Root `@Generable enum`: `"choice"`<br>• Root `Bool` or score: `"root"` |
| Root Enum Decoding (`Fatal error: Unexpected rawValue`) | Apple Foundation Models expects bare strings for root `@Generable enum`s (e.g. `billing`), not JSON quotes (`"\"billing\""`). | Handled automatically by `ResponseSynthesizer` (Tech Note 0002). |
| `NoulJudgement.answer` is `nil` | Probability fell within the undecided band ($0.35 \dots 0.65$). | Expected behavior. Handle `decision == .escalate` and route to human review or fallback logic. |
| Task cancellation handling | Catching `JevError` does not catch cancelled requests. | Catch `CancellationError` separately from `JevError`—cooperative cancellation is never wrapped in `JevError`. |
