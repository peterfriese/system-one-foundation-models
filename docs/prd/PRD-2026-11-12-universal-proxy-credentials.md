# PRD: Universal Zero-Dependency Proxy Credentials & Hardware-Attested Mobile Gateways

- **Document ID**: `PRD-2026-11-12-universal-proxy-credentials`
- **Date**: 2026-11-12
- **Status**: Draft / Ready for Architectural Review
- **Owner**: Product Manager Agent
- **Architect**: Senior Architect Agent
- **Target Branch**: `implement_google_decisions`
- **Target Release**: SystemOneFoundationModels 1.4.0 (iOS 27.0+, macOS 27.0+, visionOS 27.0+)
- **Upstream / Specs**: Apple Foundation Models Framework (`LanguageModel`, `LanguageModelSession`, `@Generable`), Apple App Attest (`DeviceCheck`), Firebase App Check, OAuth 2.0 / OIDC, TypeSafe AI System One Primitives, [Tech Note 0004](../../tech-notes/0004-secure-mobile-transport-appcheck.md), [Tech Note 0005](../../tech-notes/0005-spm-dependency-isolation-and-vendor-transports.md), [Tech Note 0010](../../tech-notes/0010-proxy-transport-and-dynamic-attestation.md)

---

## 1. Problem Statement & Strategic Vision

### The Mobile Client Secret Vulnerability
Production mobile and desktop applications running on iOS, macOS, and visionOS must **never embed static upstream cloud API keys** (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `TYPESAFE_API_KEY`, or `HOSTED_VPC_TOKEN`) inside their compiled application binaries.

Any static secret compiled into a Mach-O binary or bundled inside `.plist` / `.env` resources is trivially extractable via static binary disassembly (`strings`, Hopper, Ghidra) or runtime TLS interception on supervised/jailbroken devices (Proxyman, Charles, `mitmproxy`). A compromised master key exposes an organization's cloud billing balance, rate-limit quotas, and proprietary System One decision infrastructure to unrestricted abuse.

To secure mobile deployments, production apps route decision requests through a **hardware-attested reverse proxy or mobile gateway** (e.g., Firebase Cloud Functions v2 with Firebase App Check & Apple App Attest, Cloudflare Workers, Google Cloud Run, AWS API Gateway, or an enterprise Envoy/Kong ingress). The mobile client attaches a short-lived, cryptographically attested token (such as an `X-Firebase-AppCheck` header or an OAuth 2.0 `Authorization: Bearer` token) to each request; the gateway verifies the attestation before injecting the upstream provider secret server-side.

### The Current Architectural Asymmetry Across System One Models
Previously, as documented in [Tech Note 0010](../../tech-notes/0010-proxy-transport-and-dynamic-attestation.md), only `JevFoundationModels` offered first-class reverse-proxy support via `ProxyTransport` and closure-based dynamic credential injection (`ProxyTransport.Credential`). Developers adopting any of the other System One providers faced significant gaps:

1. **Missing Dynamic Attestation in Provider Modules**:
   - `GeminiDecisionsLanguageModel` (`GeminiLanguageModel`) only accepted a static `apiKey: String?` (injected into `x-goog-api-key`) or read `GEMINI_API_KEY` / `GOOGLE_API_KEY` from process environment variables.
   - `OpenAIDecisionsLanguageModel` only accepted a static `apiKey: String?` (`Authorization: Bearer <key>`) or `OPENAI_API_KEY`.
   - `ClefLanguageModel` only accepted a static `apiToken: String?` or `CLOUDFLARE_API_TOKEN` / `HOSTED_VPC_TOKEN`.
   - `LayaLanguageModel` only accepted a static `apiKey: String?`.
2. **Stale Credentials on Retry**:
   - Even if a developer attempted to pass a short-lived App Check or OAuth token as a static `apiKey` string at model initialization, that token would expire after 30–60 minutes or immediately fail on the second attempt when using single-use replay-protected tokens (`AppCheck.appCheck().limitedUseToken()`).
3. **No Vendor-Agnostic Proxy Backend in `SystemOneCore`**:
   - Teams building thin mobile clients that want to link *only* `SystemOneCore`—letting their backend gateway dynamically route or fail over between `gemini-decision-1`, `gpt-6-luna`, `clef`, and `jev-latest` without shipping an App Store binary update—had no built-in `SystemOneProxyBackend` or `SystemOneLanguageModel(proxyEndpoint:credential:...)` initializer.

### Strategic Vision: Universal Zero-Dependency Proxy Credentials
We will elevate the proven closure-based dynamic credential pattern from `JevFoundationModels` into `SystemOneCore` as a universal, zero-dependency primitive (`ProxyCredential`, `ProxyEndpointValidator`, and `SystemOneProxyBackend`) and wire first-class `(proxyEndpoint: URL, credential: ProxyCredential, ...)` initializers across **every** remote System One model provider.

This architecture supports two complementary mobile gateway patterns while maintaining **zero external third-party runtime dependencies** (`Package.swift` remains 100% pure Swift + Apple system frameworks):

#### Pattern A — Provider-Specific Passthrough Proxy
The mobile app uses a provider-specific model (`GeminiLanguageModel`, `OpenAIDecisionsLanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, or `JevLanguageModel`) so the client encodes the provider's native wire format (including multimodal images for Gemini, OpenAI, and Clef), while routing through a corporate gateway that verifies App Check / OAuth and injects the upstream secret:

```swift
import FoundationModels
import GeminiFoundationModels
import FirebaseAppCheck

let model = GeminiLanguageModel(
    proxyEndpoint: URL(string: "https://us-central1-my-app.cloudfunctions.net/geminiProxy")!,
    credential: .header(name: "X-Firebase-AppCheck") {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
let session = LanguageModelSession(model: model)
let decision = try await session.respond(to: prompt, generating: ReceiptTriageDecision.self).content
```

#### Pattern B — Vendor-Agnostic Canonical System One Gateway
The mobile app links only `SystemOneCore` and uses `SystemOneLanguageModel(proxyEndpoint:credential:modelID:)`. The client sends canonical `SystemOneRequest` JSON (`state`, `model`, `questions`, `images`) to the gateway, empowering backend engineers to switch or A/B test upstream providers (`gemini-decision-1` $\leftrightarrow$ `gpt-6-luna` $\leftrightarrow$ `clef`) purely server-side:

```swift
import FoundationModels
import SystemOneCore
import FirebaseAppCheck

let model = SystemOneLanguageModel(
    proxyEndpoint: URL(string: "https://gateway.mycompany.com/v1/systemone")!,
    credential: .header(name: "X-Firebase-AppCheck") {
        try await AppCheck.appCheck().limitedUseToken().token
    },
    modelID: "triage-production"
)
let session = LanguageModelSession(model: model)
let decision = try await session.respond(to: prompt, generating: TicketRoute.self).content
```

---

## 2. User Personas & User Stories

### User Personas
1. **Elena (Principal iOS Security & Platform Engineer)**: Enforces zero-secret binary policies across iOS 27, macOS 27, and visionOS 27 apps. Requires Apple App Attest / Firebase App Check integration (`token(forcingRefresh: false)` and `limitedUseToken()`) without bloating SPM build times with third-party SDK dependencies in `SystemOneFoundationModels`.
2. **Raj (Cloud & Mobile Gateway Architect)**: Operates Firebase Cloud Functions, Google Cloud Run, and Cloudflare Workers proxies in front of `gemini-decision-1`, `gpt-6-luna`, and `clef`. Needs both transparent wire passthrough (Pattern A) and canonical provider-abstracted routing (Pattern B).
3. **Marcus (Full-Stack Mobile Developer)**: Develops locally against the Firebase Local Emulator Suite (`http://127.0.0.1:5001/...`) and `wrangler dev` (`http://localhost:8787/...`), and deploys to `https://` production endpoints. Wants fail-closed TLS enforcement for remote hosts with seamless loopback support for local emulators.

### User Stories

- **US-1 (Unified Zero-Dependency `ProxyCredential` in `SystemOneCore`)**:
  - **As an** Apple platform engineer,
  - **I want** a single `ProxyCredential` type in `SystemOneCore` supporting `.bearer`, `.header(name:prefix:provider:)`, and `.custom` async `@Sendable` closures,
  - **So that** I can inject Firebase App Check, OAuth 2.0, or HMAC signatures across any System One model using identical call-site syntax and zero third-party package dependencies.

- **US-2 (Provider Passthrough Proxy Initializers — Pattern A)**:
  - **As a** developer using `GeminiDecisionsLanguageModel` (`GeminiLanguageModel`), `OpenAIDecisionsLanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, or `JevLanguageModel`,
  - **I want** a first-class `init(proxyEndpoint: URL, credential: ProxyCredential, ...)` initializer on each model and its HTTP backend,
  - **So that** requests are encoded in the provider's native wire schema and dispatched to my proxy with dynamic credentials instead of requiring a client-side `GEMINI_API_KEY` or `OPENAI_API_KEY`.

- **US-3 (Vendor-Agnostic Gateway via `SystemOneLanguageModel` — Pattern B)**:
  - **As a** mobile architect decoupling app binaries from specific AI vendors,
  - **I want** `SystemOneProxyBackend` and `SystemOneLanguageModel(proxyEndpoint:credential:modelID:...)` in `SystemOneCore` (with multimodal vision attachment capability),
  - **So that** our backend gateway can route or fail over between Gemini, OpenAI, Clef, Jev, and Laya without requiring an App Store release.

- **US-4 (Per-Attempt Dynamic Token Acquisition Inside Retry Loops)**:
  - **As a** security engineer using consumable `limitedUseToken()` App Check attestations or short-lived OAuth tokens,
  - **I want** every HTTP backend to evaluate `ProxyCredential` inside the per-attempt retry loop,
  - **So that** retried requests after HTTP 429 or transient network errors mint a fresh token rather than replaying an expired or consumed token.

- **US-5 (Fail-Closed HTTPS & Loopback Emulator Validation)**:
  - **As a** mobile developer testing against local emulators and deploying to production,
  - **I want** proxy endpoints to require `https://` for all remote hosts while permitting `http://localhost`, `http://127.0.0.1`, and `http://[::1]` for local emulators,
  - **So that** attestations and payloads are never accidentally transmitted in cleartext over public networks.

- **US-6 (100% Backward Compatibility for `JevFoundationModels`)**:
  - **As an** existing `JevFoundationModels` user,
  - **I want** `ProxyTransport.Credential` to typealias `ProxyCredential` and `JevLanguageModel(proxyEndpoint:credential:...)` to work seamlessly alongside existing `ProxyTransport` code,
  - **So that** upgrading to v1.4.0 introduces zero breaking changes.

---

## 3. Architecture & Technical Specifications

### 3.1 Core Primitives in `SystemOneCore`

#### 1. `ProxyCredential` (`Sources/SystemOneCore/Backend/ProxyCredential.swift`)
`ProxyCredential` is a `Sendable`, `Hashable` (by unique configuration identity, matching `AnySystemOneBackend`) enum representing dynamic, per-attempt request authentication:

```swift
public struct ProxyCredential: Sendable, Hashable {
    // Factory methods / cases matching ProxyTransport.Credential ergonomics:
    public static func bearer(_ provider: @escaping @Sendable () async throws -> String) -> ProxyCredential
    public static func header(
        name: String,
        prefix: String? = nil,
        provider: @escaping @Sendable () async throws -> String
    ) -> ProxyCredential
    public static func custom(_ modifier: @escaping @Sendable (inout URLRequest) async throws -> Void) -> ProxyCredential

    /// Applies the credential to an outbound URLRequest. Must be invoked per attempt inside retry loops.
    public func apply(to request: inout URLRequest) async throws
}
```
*(Note: Implementing `ProxyCredential` as an enum with an internal `UUID` token or a struct with enum-like static constructors `.bearer`, `.header`, `.custom` ensures both enum-dot-syntax call-site ergonomics and full `Hashable`/`Equatable` synthesis for `LanguageModel.Configuration`!)*

#### 2. `ProxyEndpointValidator` (`Sources/SystemOneCore/Backend/ProxyEndpointValidator.swift`)
Centralizes proxy URL security validation across all backends:
- Permits `scheme == "https"` (case-insensitive) for any non-empty host.
- Permits `scheme == "http"` **only** when `host?.lowercased()` is `"localhost"`, `"127.0.0.1"`, `"::1"`, or `"[::1]"`.
- Rejects all other schemes or non-loopback `http://` URLs by throwing `SystemOneError.networkError("Insecure proxy endpoint: HTTPS is required for remote proxy connections.")`.

#### 3. `SystemOneProxyBackend` (`Sources/SystemOneCore/Backend/SystemOneProxyBackend.swift`)
A canonical `SystemOneBackend` implementation in `SystemOneCore` for Pattern B gateways:
- Serializes standard `SystemOneRequest` JSON (`state`, `model`, `questions`, `images`).
- Validates `proxyEndpoint` via `ProxyEndpointValidator`.
- Evaluates `credential.apply(to: &urlRequest)` on **every attempt** inside its `RetryPolicy` loop.
- Extracts server timing headers (`x-goog-processing-ms`, `x-envoy-upstream-service-time`, `server-timing`) and measures client `transportDurationMs`.
- Maps HTTP 401/403 to `SystemOneError.authenticationFailed`, HTTP 429 with quota exhaustion to `SystemOneError.quotaExceeded`, and honours RFC 9110 `Retry-After` headers.

#### 4. `SystemOneLanguageModel` Proxy & Multimodal Enhancements
- Adds convenience initializers:
  ```swift
  public init(
      proxyEndpoint: URL,
      credential: ProxyCredential,
      modelID: String = "systemone-default",
      session: URLSession = .shared,
      timeoutInterval: TimeInterval = 30,
      retryPolicy: RetryPolicy = .default
  )
  ```
- Declares `[.guidedGeneration, .vision]` capabilities and supports `.png`, `.jpeg`, and `.webP` attachments so multimodal prompts flow through `SystemOneProxyBackend` to vision-capable gateways.

### 3.2 Provider-Specific Proxy Support (Pattern A)

| Module | Model Type(s) | Backend Type | Direct Mode Auth | Proxy Mode Behavior (`credential: ProxyCredential`) |
| :--- | :--- | :--- | :--- | :--- |
| **`GeminiFoundationModels`** | `GeminiDecisionsLanguageModel` (`GeminiLanguageModel`) | `GeminiDecisionsHTTPBackend` | `x-goog-api-key` (`apiKey` / `GEMINI_API_KEY` / `GOOGLE_API_KEY`) | Validates `proxyEndpoint`, skips local API key check, omits `x-goog-api-key`, applies `ProxyCredential` per attempt, sends `GeminiDecisionsRequest` wire JSON. |
| **`OpenAIFoundationModels`** | `OpenAIDecisionsLanguageModel` | `OpenAIDecisionsHTTPBackend` | `Authorization: Bearer` (`apiKey` / `OPENAI_API_KEY`) | Validates `proxyEndpoint`, skips local API key check, applies `ProxyCredential` per attempt (plus optional `OpenAI-Organization` / `OpenAI-Project`), sends `OpenAIDecisionsRequest` wire JSON. |
| **`ClefFoundationModels`** | `ClefLanguageModel` | `ClefHTTPBackend` | `Authorization: Bearer` (`apiToken` / `CLOUDFLARE_API_TOKEN` / `HOSTED_VPC_TOKEN`) | Validates `proxyEndpoint`, skips local token check, applies `ProxyCredential` per attempt, sends Clef wire JSON. |
| **`LayaFoundationModels`** | `LayaLanguageModel` | `LayaHTTPBackend` | Optional `Authorization: Bearer` (`apiKey`) | Validates `proxyEndpoint`, applies `ProxyCredential` per attempt with `RetryPolicy`, sends `SystemOneRequest` wire JSON. |
| **`JevFoundationModels`** | `JevLanguageModel` | `ProxyTransport` | `Authorization: Bearer` (`apiKey` / `TYPESAFE_API_KEY`) | `ProxyTransport.Credential` aliases `ProxyCredential`; adds `JevLanguageModel(proxyEndpoint:credential:modelID:...)` convenience initializer. |

---

## 4. Functional Requirements

### FR-1: Universal `ProxyCredential` & Per-Attempt Execution
1. `ProxyCredential` in `SystemOneCore` shall support:
   - `.bearer(@Sendable () async throws -> String)` $\to$ sets `Authorization: Bearer <token>`.
   - `.header(name: String, prefix: String? = nil, provider: @Sendable () async throws -> String)` $\to$ sets `<name>: <token>` (or `<name>: <prefix> <token>` when `prefix` is non-nil).
   - `.custom(@Sendable (inout URLRequest) async throws -> Void)` $\to$ mutates the outbound `URLRequest` directly.
2. In all HTTP backends (`SystemOneProxyBackend`, `GeminiDecisionsHTTPBackend`, `OpenAIDecisionsHTTPBackend`, `ClefHTTPBackend`, `LayaHTTPBackend`, and `ProxyTransport`), `credential.apply(to: &urlRequest)` **must** be executed inside the `while` retry loop so that each retry attempt invokes the async closure afresh.
3. If the credential closure throws `CancellationError`, cancellation must propagate immediately without retrying. If the closure throws any other error (e.g. App Attest token fetch failure), the error is surfaced cleanly without leaking sensitive state.

### FR-2: Endpoint Security Validation (`ProxyEndpointValidator`)
1. When any backend is configured with a `ProxyCredential` (or via `SystemOneProxyBackend` / `ProxyTransport`), it shall validate the target URL via `ProxyEndpointValidator.validate(_:)` before dispatching network traffic.
2. Non-HTTPS remote URLs (e.g. `http://proxy.example.com/v1/decisions`) shall be rejected immediately with `SystemOneError.networkError` (or `JevError.networkError` in `ProxyTransport`).
3. Loopback HTTP URLs (`http://localhost:...`, `http://127.0.0.1:...`, `http://[::1]:...`) shall be permitted for local emulator workflows.

### FR-3: Provider Passthrough Proxy Initializers (Pattern A)
1. **`GeminiDecisionsLanguageModel` & `GeminiDecisionsHTTPBackend`**:
   - Add `init(proxyEndpoint: URL, credential: ProxyCredential, model: String = GeminiDecisionsEndpoint.defaultModel, clientRequestID: String? = nil, session: URLSession = .shared, timeoutInterval: TimeInterval = 30, retryPolicy: RetryPolicy = .default)`.
   - When `credential` is present, `GeminiDecisionsHTTPBackend` does not require `GEMINI_API_KEY` or `GOOGLE_API_KEY` and does not set `x-goog-api-key` (unless explicitly added by a `.custom` credential).
2. **`OpenAIDecisionsLanguageModel` & `OpenAIDecisionsHTTPBackend`**:
   - Add `init(proxyEndpoint: URL, credential: ProxyCredential, model: String = OpenAIDecisionsEndpoint.defaultModel, organization: String? = nil, project: String? = nil, clientRequestID: String? = nil, session: URLSession = .shared, timeoutInterval: TimeInterval = 30, retryPolicy: RetryPolicy = .default)`.
   - When `credential` is present, `OpenAIDecisionsHTTPBackend` does not require `OPENAI_API_KEY`.
3. **`ClefLanguageModel` & `ClefHTTPBackend`**:
   - Add `init(proxyEndpoint: URL, model: ClefModel = .clef, credential: ProxyCredential, session: URLSession = .shared, timeoutInterval: TimeInterval = 45, retryPolicy: RetryPolicy = .default)`.
   - When `credential` is present, `ClefHTTPBackend` does not require `CLOUDFLARE_API_TOKEN` or `HOSTED_VPC_TOKEN`.
4. **`LayaLanguageModel` & `LayaHTTPBackend`**:
   - Add `init(proxyEndpoint: URL, modelID: String = "english", credential: ProxyCredential, session: URLSession = .shared, timeoutInterval: TimeInterval = 30, retryPolicy: RetryPolicy = .default)`.
5. **`JevLanguageModel` & `ProxyTransport`**:
   - Unify `ProxyTransport.Credential` with `ProxyCredential` (`public typealias Credential = ProxyCredential`).
   - Add `JevLanguageModel.init(proxyEndpoint: URL, credential: ProxyCredential, modelID: String = "jev-latest", session: URLSession = .shared, timeoutInterval: TimeInterval = 30, retryPolicy: RetryPolicy = .default)`.

### FR-4: Vendor-Agnostic Gateway Support in `SystemOneCore` (Pattern B)
1. Implement `SystemOneProxyBackend` conforming to `SystemOneBackend`, `Sendable`, and `Hashable`.
2. Add `SystemOneLanguageModel.init(proxyEndpoint: URL, credential: ProxyCredential, modelID: String = "systemone-default", session: URLSession = .shared, timeoutInterval: TimeInterval = 30, retryPolicy: RetryPolicy = .default)`.

---

## 5. Acceptance Criteria

### AC-1: Dynamic Token Re-Acquisition Across Retries
- **Given** any System One model (`GeminiLanguageModel`, `OpenAIDecisionsLanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, `JevLanguageModel`, or `SystemOneLanguageModel`) configured with a `ProxyCredential.header(name: "X-Firebase-AppCheck")` closure that increments an atomic counter (`token-1`, `token-2`),
- **When** the proxy endpoint returns HTTP 429 on attempt 1 and HTTP 200 on attempt 2,
- **Then** attempt 1 transmits `X-Firebase-AppCheck: token-1`, attempt 2 transmits `X-Firebase-AppCheck: token-2`, and no upstream environment variable (`GEMINI_API_KEY`, `OPENAI_API_KEY`, etc.) is required.

### AC-2: Fail-Closed HTTPS Enforcement & Loopback Exemption
- **Given** a proxy-configured model targeting `http://insecure-gateway.example.com/decisions`,
- **When** `session.respond(...)` is called,
- **Then** it fails immediately with an insecure endpoint error before making any network request.
- **Given** a proxy-configured model targeting `http://127.0.0.1:5001/demo/us-central1/decisions` or `http://localhost:8787/decisions`,
- **When** `session.respond(...)` is called,
- **Then** the request is permitted and dispatched with the configured `ProxyCredential`.

### AC-3: Provider Wire Format Preservation in Pattern A
- **Given** `GeminiLanguageModel(proxyEndpoint: ..., credential: ...)` or `OpenAIDecisionsLanguageModel(proxyEndpoint: ..., credential: ...)` with a multimodal image prompt,
- **When** evaluated through `LanguageModelSession`,
- **Then** the HTTP body sent to `proxyEndpoint` uses the provider's exact native wire format (`GeminiDecisionsRequest` with `inline_data` or `OpenAIDecisionsRequest` with `input_image`), and the response is adapted back into the caller's `@Generable` type.

### AC-4: Canonical `SystemOneRequest` Routing in Pattern B
- **Given** `SystemOneLanguageModel(proxyEndpoint: ..., credential: ..., modelID: "router-v1")`,
- **When** evaluated through `LanguageModelSession`,
- **Then** `SystemOneProxyBackend` sends a canonical `SystemOneRequest` JSON payload with the dynamic credential headers and synthesizes the returned `SystemOneResponse` into the `@Generable` result.

### AC-5: Swift 6 Strict Concurrency & Zero External Dependencies
- **Given** the complete workspace built with `-strict-concurrency=complete`,
- **When** running `swift test`,
- **Then** all targets and new proxy test suites compile with zero warnings and pass 100% offline using mock `URLProtocol` handlers.

---

## 6. Non-Functional Requirements

- **Zero External Dependencies**: `Package.swift` must not add `firebase-ios-sdk` or any third-party library. All attestation integration occurs via `@Sendable` closures at the application boundary.
- **Credential Redaction**: Dynamic tokens resolved by `ProxyCredential` must never be written to console logs or included in `SystemOneError` localized descriptions.
- **Zero-Overhead Hashability**: `ProxyCredential` must conform to `Hashable` and `Sendable` so all `LanguageModel.Configuration` structs remain `Hashable` and `Sendable` as required by Apple's `LanguageModel` protocol.

---

## 7. Out of Scope

1. **Bundling Vendor Attestation SDKs**: `SystemOneFoundationModels` will not link `FirebaseAppCheck`, `DeviceCheck`, or OAuth client libraries directly; apps inject them via `ProxyCredential` closures.
2. **Server-Side Cloud Function / Worker Deployment Scripts**: While documented in `docs/mobile-security.md` and `tech-notes/`, server-side Terraform/Firebase deployment tooling is outside the Swift package runtime.

---

## 8. Handoff & Technical Dependencies

### Implementation Phasing
1. **Stage 2 (ADR)**: Senior Architect Agent (`@senior-architect`) authors `docs/architecture/ADR-2026-11-12-01-universal-proxy-credentials.md`.
2. **Stage 3 (User Approval Gate)**: Present PRD & ADR for sign-off.
3. **Stage 4 (Implementation)**:
   - Add `ProxyCredential`, `ProxyEndpointValidator`, and `SystemOneProxyBackend` to `SystemOneCore`, and update `SystemOneLanguageModel`.
   - Integrate `ProxyCredential` into `GeminiDecisionsHTTPBackend` / `GeminiDecisionsLanguageModel`, `OpenAIDecisionsHTTPBackend` / `OpenAIDecisionsLanguageModel`, `ClefHTTPBackend` / `ClefLanguageModel`, `LayaHTTPBackend` / `LayaLanguageModel`, and bridge `JevFoundationModels` (`ProxyTransport` & `JevLanguageModel`).
4. **Stage 5 (Verification & Docs)**: Add hermetic unit tests across all modules and update `docs/mobile-security.md` and `tech-notes/0010-proxy-transport-and-dynamic-attestation.md`.
