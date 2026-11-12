---
name: jev-foundation-models
license: Apache-2.0
description: >-
  Evaluate TypeSafe Jev System One decision models natively through Apple's Foundation
  Models framework in Swift 6. Use when building iOS 27+, macOS 27+, or visionOS 27+
  apps that evaluate strongly-typed @Generable structs and enums using LanguageModelSession,
  implementing confidence routing (RoutingPolicy, NoulJudgement, ScoreValue), configuring
  resilient network retries (RetryPolicy), securing mobile traffic via zero-dependency
  ProxyCredential / ProxyTransport and Firebase App Check gateways, or writing deterministic
  offline unit tests with MockJevTransport.
metadata:
  author: peterfriese
  version: "1.2"
---

# Jev Foundation Models Bridge

> [!TIP]
> **Modern Multi-Backend Standard**: For projects combining TypeSafe Jev with on-device Core ML (`LayaOnDevice`), self-hosted `laya-serve` (`LayaFoundationModels`), Cloudflare Clef multimodal (`ClefFoundationModels`), OpenAI Decisions (`OpenAIFoundationModels`), Google Gemini Decisions (`GeminiFoundationModels`), or vendor-agnostic gateways (`SystemOneLanguageModel`), refer to the unified `system-one-foundation-models` skill. This skill focuses on TypeSafe Jev cloud evaluation, `RetryPolicy` resilience, and hardened App Check reverse-proxy architectures.

This skill guides the design, implementation, and testing of applications integrating **TypeSafe AI's Jev System One decision model** via **Apple's Foundation Models framework** (`FoundationModels`) in Swift 6.

---

## 1. Core Mental Model: Decisions, Not Chat

Jev is a **System One decision model**, not a text-generating LLM. It evaluates application state against a set of typed questions in a single forward pass, returning calibrated probabilities and discrete categorical decisions in 40–150ms.

- **Prompt $\to$ Application State**: The text passed to `session.respond(to:)` represents current application context (support tickets, sensor readings, transaction logs, user inputs, or parsed documents).
- **`@Generable` Type $\to$ Decision Questions**: The struct or enum defines the typed questions being asked over that state.
- **Dual Signal Output**:
  1. **The Answer**: *What* the model judged (`response.content` containing typed enum choices, booleans, or rubric scores). For `Bool` fields this decode is a hard `0.5` cutoff — see §3; decisions must consume `response.probability(for:)` / `response.judgement(for:policy:)`.
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

Configure automated retry backoff via `RetryPolicy` (`SystemOneCore`) on `JevLanguageModel`:

```swift
let retryPolicy = RetryPolicy(
    maxAttempts: 3,                                          // Initial attempt + up to 2 retries
    initialDelay: .milliseconds(500),                        // First retry delay
    multiplier: 2.0,                                         // Exponential backoff
    jitter: 0.2,                                             // +/- 20% random jitter to avoid thundering herds
    retryableStatuses: RetryPolicy.defaultRetryableStatuses, // [408, 429, 500, 502, 503, 504, 524, 529]
    maxRetryAfter: .seconds(60)                              // Respects RFC 9110 Retry-After headers
)

// Server / CLI with direct API key (uses URLSessionTransport):
let model = JevLanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)

// Mobile / Client via proxy (forwards retryPolicy directly to ProxyTransport):
let proxyModel = JevLanguageModel(
    proxyEndpoint: proxyURL,
    credential: appCheckCredential,
    retryPolicy: retryPolicy
)
```

- **Default Retryable Statuses**: `RetryPolicy.defaultRetryableStatuses` retries `[408, 429, 500, 502, 503, 504, 524, 529]` — covering request timeouts (`408`), rate limits (`429`), transient 5xx/proxy errors (`500`, `502`, `503`, `504`), Cloudflare origin timeouts (`524`), and upstream capacity overload (`529`).
- **Authentication Fail-Fast**: On `ProxyTransport` (and `SystemOneProxyBackend`), HTTP `401` / `403` responses and non-cancellation `ProxyCredential` provider errors fail fast immediately on attempt 1 with `JevError.authenticationFailed` (`SystemOneError.authenticationFailed`) without burning retries. On retryable statuses, the `ProxyCredential` closure re-executes before every attempt so short-lived or single-use tokens (`limitedUseToken()`) are minted fresh.

> [!NOTE]
> **Low-level `transport:` override caveat**: While `JevLanguageModel(apiKey:retryPolicy:)` and `JevLanguageModel(proxyEndpoint:credential:retryPolicy:)` (plus trailing-closure `authorize:`) wire `retryPolicy:` automatically, calling the low-level `JevLanguageModel(apiKey:modelID:endpoint:transport:retryPolicy:)` initializer with a non-`nil` `transport:` ignores the model-level `retryPolicy:` parameter because the pre-built transport already owns its retry state. When constructing `ProxyTransport` manually, pass `retryPolicy:` to `ProxyTransport(proxyEndpoint:credential:retryPolicy:)`.

### Cooperative Cancellation
In Swift 6 concurrency, task cancellation must never be swallowed or converted into a generic error:
- **`CancellationError` is NEVER wrapped in `JevError`**: If a parent `Task` is cancelled (or `URLSession` throws `URLError(.cancelled)` — e.g., user navigates away in SwiftUI), `CancellationError` propagates directly, including during `ProxyCredential` token acquisition and retry backoff sleeps.

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

## 5. Production Mobile Architecture (`ProxyCredential` & `ProxyTransport`)

**Never embed `TYPESAFE_API_KEY` inside client application binaries.**

In production iOS, macOS, or visionOS apps, route requests through a backend reverse proxy (such as a Firebase Cloud Function 2nd Gen `onRequest` handler, Vapor service, or Cloudflare Worker) protected by **Apple App Attest / Firebase App Check**.

### Recommended Zero-Dependency Setup (`ProxyCredential`)

`JevFoundationModels` re-exports `ProxyCredential` from `SystemOneCore` so your app target links `FirebaseAppCheck` (or any OAuth / attestation SDK) while the Swift package core retains zero third-party dependencies:

```swift
import Foundation
import FoundationModels
import JevFoundationModels
import FirebaseCore
import FirebaseAppCheck

let proxyURL = URL(string: "https://us-central1-your-project.cloudfunctions.net/systemone")!

// 1. Dynamic App Check credential (resolved on every attempt inside ProxyTransport's retry loop)
let appCheckCredential = ProxyCredential.appCheck {
    guard FirebaseApp.app() != nil else {
        #if DEBUG
        return "dev-monitor-placeholder"
        #else
        throw JevError.authenticationFailed("FirebaseApp is not configured.")
        #endif
    }
    return try await AppCheck.appCheck().token(forcingRefresh: false).token
}

// 2. Initialize JevLanguageModel without an API key (forwards retryPolicy to ProxyTransport)
let model = JevLanguageModel(
    proxyEndpoint: proxyURL,
    credential: appCheckCredential,
    retryPolicy: .default
)
let session = LanguageModelSession(model: model)
```

- **Multi-Header & HMAC Signing (`authorize:` / `.custom`)**: Use `JevLanguageModel(proxyEndpoint: proxyURL) { request in ... }` (or `ProxyCredential.custom`) when attaching both `X-Firebase-AppCheck` and `Authorization: Bearer <firebaseAuthIDToken>`, or computing an HMAC signature — `ProxyTransport` populates `request.httpBody` **before** invoking the credential modifier, and `.appCheck` / `.header` / `.bearer` automatically reject empty strings or CR/LF/NUL header-injection characters with `JevError.authenticationFailed`.
- **SwiftUI Identity Lifecycle**: Each `ProxyCredential` factory call mints a new `UUID` for `Hashable` synthesis unless an explicit `id:` is supplied. Store your `ProxyCredential`, `JevLanguageModel`, or `LanguageModelSession` in `@State`, an `@Observable` ViewModel, or your DI container rather than recreating it inside `View.body` on every render.
- **Standalone Reference Transport**: A copy-pasteable `JevTransport` sample is also available in `Integrations/FirebaseAppCheckProxy/FirebaseAppCheckTransport.swift` (`tokenStrategy: .cached` or `.singleUse`), though `JevLanguageModel(proxyEndpoint:credential:retryPolicy:)` is preferred because it includes built-in `RetryPolicy` backoff, `ProxyEndpointValidator` HTTPS enforcement, and fail-fast auth handling.

> [!WARNING]
> **App Check token acquisition can crash with an Objective-C exception or fail on unattested hosts.** Calling `AppCheck.appCheck()` before `FirebaseApp.configure()` throws an **uncaught Objective-C `NSException`** — Swift `do/catch` and `try?` **cannot** intercept it — and token requests fail on iOS Simulators without `AppCheckDebugProviderFactory` or in hosted unit-test runners that skip app initialization. Always guard with `FirebaseApp.app() != nil` before touching `AppCheck.appCheck()`, register `AppCheckDebugProviderFactory` in `#if DEBUG`, and roll out your backend proxy in **Monitor mode** (logging missing/invalid tokens without rejecting) until every active client version is attested.

### Server-Side Proxy Contract

Your proxy endpoint should be a plain HTTPS `POST` reverse proxy (`onRequest`), **NOT a Firebase Callable (`onCall`)** (`enforceAppCheck: true` applies only to `onCall` functions; `onRequest` handlers must verify `X-Firebase-AppCheck` explicitly via `firebase-admin/app-check`):

- **POST-only `onRequest`**: Return `405` (`Allow: POST`) for non-`POST` methods. Forward the validated JSON payload to `POST https://api.typesafe.ai/v1/systemone` with the server-managed secret injected as `Authorization: Bearer <TYPESAFE_API_KEY>` — no callable envelope or schema transformation.
- **App Check Verification & Replay-Protection Pairing (`alreadyConsumed` + `.singleUse` vs `.cached`)**:
  - Read the raw token from `X-Firebase-AppCheck`. Support **Monitor mode** during rollout (e.g. `APP_CHECK_ENFORCE === "true"` flips from logging invalid/missing tokens to rejecting with `401` before any upstream work).
  - **Mandatory `alreadyConsumed` check when `{ consume: true }` is enabled**: In `firebase-admin/app-check`, `await getAppCheck().verifyToken(token, { consume: true })` **does NOT throw** when a token has already been spent — it resolves normally with `{ alreadyConsumed: true }`. Your handler **MUST** explicitly check `if (verified.alreadyConsumed) { res.status(401).json({ error: "Unauthorized" }); return; }`; omitting that check makes replay protection a silent no-op!
  - **Attestation Provider Support**: Apple **App Attest** (`DCAppAttestService`) *does* support single-use token consumption; only legacy **DeviceCheck** lacks limited-use replay protection.
  - **Strict Client/Server Strategy Pairing**: Server-side `{ consume: true }` + `alreadyConsumed` rejection **MUST** be paired with client-side `AppCheck.appCheck().limitedUseToken()` (single-use per attempt, minted fresh on each retry by `ProxyCredential`), **NEVER** with cached `token(forcingRefresh: false)` (1-hour TTL — every request after the first within an hour would fail fast with `401`). For standard low-latency interactive UI using cached tokens (`token(forcingRefresh: false)`), call `verifyToken(token)` *without* `{ consume: true }`.
- **Cost Gates BEFORE Billing**: Reject non-object bodies, empty `state`, or empty `questions` with `400`, and oversized bodies with `413` before contacting TypeSafe AI.
- **Rate Limiting — NEVER Key Per-User Limits on App Check `appId` Alone**:
  - In an App Check token, `verified.appId` (`sub`) is the **global Firebase App ID** shared by 100% of users and physical devices running your app (App Check claims contain no per-device or per-user ID). Keying a per-caller limiter solely on `verified.appId` places every user into a single global bucket, allowing one noisy client to DoS your entire user base!
  - Key per-caller limits on **verified Firebase Auth `uid`** when user authentication is present, or deploy a **two-tier limiter** for attest-only endpoints: a per-client IP limit (from Cloud Run / Cloud Functions' trusted `X-Forwarded-For` entry) beneath a high global `verified.appId` ceiling, with unverified/garbage tokens in Monitor mode routed to a tight shared `anonymous` bucket so token rotation cannot reset budgets. Return `429` with `Retry-After`.
- **Upstream Passthrough & `502` Retry Interaction**: Pass through upstream status, body, `Content-Type`, timing headers (`x-envoy-upstream-service-time`, `server-timing`), and `Retry-After` (on `429`/`503`). On upstream fetch/timeout/read failure, log details server-side only and return a generic `502`. Because `502` is included in `RetryPolicy.defaultRetryableStatuses` (`[408, 429, 500, 502, 503, 504, 524, 529]`), a `502` triggers client exponential backoff (up to `maxAttempts = 3`) and re-invokes `ProxyCredential` on each attempt (rotating `limitedUseToken()` automatically), whereas `401`/`403` fails fast on attempt 1 with `JevError.authenticationFailed`.

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
| `JevError.authenticationFailed` | Proxy returned `401`/`403` (e.g. `alreadyConsumed` when pairing `{ consume: true }` with a cached token), or `ProxyCredential` threw / returned an empty or CR/LF token. | Fails fast on attempt 1 without retry. Pair `{ consume: true }` strictly with `limitedUseToken()`, guard `FirebaseApp.app() != nil`, and ensure non-empty tokens. |
| `response.probability(...)` or `confidence(...)` returns `nil` | Question key does not match schema convention. | **Key Resolution Matrix**:<br>• Struct field: `"propertyName"` (e.g. `"isUrgent"`)<br>• Nested struct: `"parent.child"` (e.g. `"metadata.priority"`)<br>• Root `@Generable enum`: `"choice"`<br>• Root `Bool` or score: `"root"` |
| Root Enum Decoding (`Fatal error: Unexpected rawValue`) | Apple Foundation Models expects bare strings for root `@Generable enum`s (e.g. `billing`), not JSON quotes (`"\"billing\""`). | Handled automatically by `ResponseSynthesizer` (Tech Note 0002). |
| `NoulJudgement.answer` is `nil` | Probability fell within the undecided band ($0.35 \dots 0.65$). | Expected behavior. Handle `decision == .escalate` and route to human review or fallback logic. |
| Task cancellation handling | Catching `JevError` does not catch cancelled requests. | Catch `CancellationError` separately from `JevError`—cooperative cancellation is never wrapped in `JevError`. |
