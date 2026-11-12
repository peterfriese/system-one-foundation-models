# 0010 — Dynamic Credential Resolution & Reverse Proxying with ProxyCredential, SystemOneProxyBackend, and ProxyTransport

- **Date**: 2026-09-26 (Updated 2026-11-12)
- **Author**: Peter Friese
- **Framework**: `FoundationModels` (iOS 27.0+, macOS 27.0+, visionOS 27.0+), `SystemOneCore`, `GeminiFoundationModels`, `OpenAIFoundationModels`, `ClefFoundationModels`, `LayaFoundationModels`, `JevFoundationModels`
- **Upstream**: Apple App Attest (`DeviceCheck`), Firebase App Check, Cloudflare Turnstile / Access, OAuth 2.0 / OIDC, Google Gemini Decisions (`gemini-decision-1`), OpenAI Decisions (`gpt-6-luna`), Cloudflare Clef, TypeSafe AI Jev, Laya (`laya-serve`)

---

## Context

Production mobile deployments of System One decision models face a critical security requirement: **client-side applications must never bundle long-lived upstream cloud API keys (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `TYPESAFE_API_KEY`, or `HOSTED_VPC_TOKEN`) within their application binary**.

Static secrets embedded in compiled Mach-O binaries are readily recoverable through binary disassembly tools (`strings`, Hopper, Ghidra) or runtime memory analysis. Furthermore, client-side HTTPS traffic can be inspected on supervised or jailbroken devices using local proxy tools (Proxyman, Charles, mitmproxy). A leaked master key exposes the organisation's cloud AI account quota, billing balances, and proprietary decision configurations to abuse.

To eliminate this threat vector, mobile clients must route their decision queries through an **authenticated reverse proxy gateway** (such as Firebase Cloud Functions v2, Cloudflare Workers, Google Cloud Run, AWS API Gateway, or a corporate Kubernetes ingress) that validates client authenticity before injecting the secret master key server-side.

Historically, bridging this flow across all System One providers presented three architectural challenges:
1. **The Dependency Dilemma (Tech Note 0005):** As documented in [Tech Note 0005](0005-spm-dependency-isolation-and-vendor-transports.md), `SystemOneFoundationModels` enforces a strict mandate of **Zero External Third-Party Runtime Dependencies**. Directly linking vendor SDKs (e.g., `firebase-ios-sdk`, AWS SDK, or Auth0) in `Package.swift` would force all consumers to resolve large transitive dependency trees, increasing clean build times from ~1 second to over 45 seconds.
2. **Provider Asymmetry & Boilerplate:** Initially, only `JevFoundationModels` supported dynamic reverse-proxy credentials via `ProxyTransport`. Developers using `GeminiLanguageModel`, `OpenAILanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, or vendor-agnostic `SystemOneLanguageModel` needed the same zero-dependency, retry-aware credential abstraction without duplicating transport boilerplate.
3. **Token Rotation & Stale Retries:** Authenticated gateways frequently rely on dynamic, short-lived, or consumable credentials:
   - **Apple App Attest / Firebase App Check tokens:** Valid for up to 1 hour, or consumable single-use tokens valid for a single request (`limitedUseToken()`).
   - **OAuth 2.0 / OIDC access tokens:** Ephemeral bearer tokens subject to automated refresh cycles.
   - **Dynamic HMAC signatures:** Calculated per-request timestamps and nonce non-replay headers.

If an HTTP transport caches a single static token at initialization, network retries against rate limits (`429 Too Many Requests`) or token expiration (`401 Unauthorized`) will repeatedly fail with stale credentials.

This tech note documents the design and architecture of universal **`ProxyCredential`**, **`SystemOneProxyBackend`**, **`ProxyEndpointValidator`** (in `SystemOneCore`), and **`ProxyTransport`** (in `JevFoundationModels`), providing **dynamic credential resolution**, **per-attempt token re-acquisition**, and **resilient reverse proxying** across every System One model backend.

---

## Findings

### 1. Universal `ProxyCredential` in `SystemOneCore`

`ProxyCredential` (`Sources/SystemOneCore/Backend/ProxyCredential.swift`) is a `Sendable`, `Hashable` value type in `SystemOneCore` backed by an internal identity `UUID` and an `@Sendable (inout URLRequest) async throws -> Void` request modifier. By conforming to `Hashable` via its identity `UUID`, every `LanguageModel.Configuration` and `*HTTPBackend` struct automatically synthesizes `Equatable` and `Hashable` conformance under Swift 6 strict concurrency:

```swift
public struct ProxyCredential: Sendable, Hashable {
    private let id: UUID
    private let modifier: @Sendable (inout URLRequest) async throws -> Void

    public func apply(to request: inout URLRequest) async throws {
        try await modifier(&request)
    }

    public static func bearer(id: UUID = UUID(), _ provider: @escaping @Sendable () async throws -> String) -> ProxyCredential
    public static func header(name: String, prefix: String? = nil, id: UUID = UUID(), provider: @escaping @Sendable () async throws -> String) -> ProxyCredential
    public static func appCheck(headerName: String = "X-Firebase-AppCheck", id: UUID = UUID(), _ provider: @escaping @Sendable () async throws -> String) -> ProxyCredential
    public static func custom(id: UUID = UUID(), _ modifier: @escaping @Sendable (inout URLRequest) async throws -> Void) -> ProxyCredential
}
```

In `JevFoundationModels`, `ProxyTransport.Credential` is a `public typealias Credential = ProxyCredential`, preserving 100% source compatibility with existing `ProxyTransport` code while unifying all 6 hosted providers:
- **Pattern A (Provider Passthrough Proxy):** `GeminiLanguageModel`, `OpenAILanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, and `JevLanguageModel` each accept `(proxyEndpoint: URL, credential: ProxyCredential, ...)` or an inline trailing closure `(proxyEndpoint: URL, ..., authorize: { request in ... })`, dispatching the provider's native wire format (`GeminiDecisionsRequest`, `OpenAIDecisionsRequest`, `SystemOneRequest`, `JevRequest`) to your proxy without requiring local API keys.
- **Pattern B (Vendor-Agnostic Gateway via `SystemOneProxyBackend`):** `SystemOneLanguageModel(proxyEndpoint:credential:modelID:)` dispatches canonical `SystemOneRequest` payloads (including multimodal vision attachments) via `SystemOneProxyBackend`, allowing your backend gateway to route or fail over between `gemini-decision-1`, `gpt-6-luna`, `clef`, `jev-latest`, and `laya-serve` server-side.
- **Fail-Closed Endpoint Validation (`ProxyEndpointValidator`):** All proxy-configured backends validate that `proxyEndpoint` uses `https://` for remote hosts, permitting `http://` strictly for local loopback emulators (`localhost`, `127.0.0.1`, `::1`, `[::1]`).

### 2. The `ProxyCredential` Factory Methods & Inline `authorize:` Closure

`ProxyCredential` decouples all System One HTTP backends from any specific authentication vendor, supporting five ergonomic call-site patterns:

| Factory / Initializer | Target Pattern | Mechanism | Example Header Output |
| :--- | :--- | :--- | :--- |
| `.appCheck(headerName:provider)` | Firebase App Check & Apple App Attest | Evaluates async token closure and sets `X-Firebase-AppCheck` (or custom header) | `X-Firebase-AppCheck: <token>` |
| `.header(name:prefix:provider)` | Cloudflare Turnstile / Access, custom API gateways | Evaluates async string provider, formats with optional prefix | `X-Custom-Key: Key <token>` |
| `.bearer(provider)` | OAuth 2.0, OIDC, JWT session tokens | Evaluates async string provider closure | `Authorization: Bearer <token>` |
| `.custom(modifier)` | Multi-header gateways (e.g. App Check + Bearer JWT), HMAC signatures | Passes mutable `inout URLRequest` to async closure | Arbitrary headers, query parameters, or request metadata |
| `init(proxyEndpoint:authorize:)` | Inline trailing-closure request mutation on any `*LanguageModel` | Wraps `authorize` in `.custom(authorize)` | Direct `request.setValue(...)` mutation at call site |

### 3. Per-Attempt Dynamic Token Acquisition Inside the Retry Loop

A subtle bug in naive custom transport implementations is resolving credentials once before entering the retry loop:

```swift
// ANTI-PATTERN: Resolving credentials outside the retry loop
let token = try await provider() // Evaluated once!
while attempt <= maxAttempts {
    var req = URLRequest(url: endpoint)
    req.setValue(token, forHTTPHeaderField: "Authorization")
    let (data, res) = try await session.data(for: req)
    // If res is 401 or 429, subsequent attempts reuse the expired or rejected token!
}
```

In `ProxyTransport`, credential application occurs **strictly inside the attempt loop**:

```swift
var attempt = 1
while true {
    var urlRequest = URLRequest(url: proxyEndpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.timeoutInterval = timeoutInterval
    urlRequest.httpBody = requestData

    // Apply configured credentials for each attempt to support rotating/refreshed tokens
    try await applyCredential(to: &urlRequest)

    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await session.data(for: urlRequest)
    } catch is CancellationError {
        throw CancellationError()
    } ...
```

This guarantees:
1. **Automatic Token Refresh:** If an OAuth token or App Check token expires during backoff or between attempts, the provider closure fetches a freshly minted or refreshed token on attempt $N+1$.
2. **Replay-Protected Consumable Tokens:** When using Firebase App Check limited-use tokens (`limitedUseToken()`), each retry attempt mints a new non-consumed token, avoiding immediate `401 Token Already Consumed` rejections on retried requests.
3. **Dynamic HMAC Timestamping:** Custom signature modifiers recalculate accurate request timestamps and nonces on each attempt.

### 4. Zero-Dependency Closure Injection Pattern (Referencing Tech Note 0005)

[Tech Note 0005](0005-spm-dependency-isolation-and-vendor-transports.md) highlighted why `#if canImport(...)` fails within SPM package targets and proved that adding vendor dependencies to `Package.swift` causes unacceptable dependency bloat.

`ProxyTransport` resolves this dilemma using **Closure-Based Inversion of Control**:
- `JevFoundationModels` compiles purely against standard Apple platform frameworks (`Foundation`, `Security`, `Network`). It imports zero third-party packages.
- The consuming application links its preferred identity and attestation frameworks (e.g. `FirebaseAppCheck`, `GoogleSignIn`, `AWSMobileClient`).
- At the initialization boundary, the app passes an inline `@Sendable () async throws -> String` closure invoking the vendor SDK.

```
┌─────────────────────────────────────────────────────────┐
│              Consuming iOS / macOS Target               │
│  • Imports FirebaseAppCheck / DeviceCheck               │
│  • Holds hardware key in Secure Enclave                 │
│  • Injects closure: { try await AppCheck.token() }      │
└────────────────────────────┬────────────────────────────┘
                             │ passes closure
                             ▼
┌─────────────────────────────────────────────────────────┐
│          JevFoundationModels (ProxyTransport)           │
│  • ZERO vendor dependencies (pure Swift + URLSession)   │
│  • Invokes closure per retry attempt                    │
│  • Dispatches payload to reverse proxy                  │
└─────────────────────────────────────────────────────────┘
```

This delivers the ideal balance:
- **Zero package dependencies** in the core SPM manifest.
- **Full first-class library support** without copying unmanaged source files into user projects.
- **Complete type safety and Swift 6 Sendability** across concurrency boundaries.

---

## Implications & Call-Site Design

### 1. Universal Provider Passthrough with `.appCheck` (`GeminiLanguageModel`, `OpenAILanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, `JevLanguageModel`)

All hosted System One language models accept `proxyEndpoint` and `credential: .appCheck { ... }` (or `.header`, `.bearer`, `.custom`), allowing your mobile app to call any upstream provider through your Cloud Function / Worker gateway with zero embedded secrets:

```swift
import FoundationModels
import GeminiFoundationModels
import OpenAIFoundationModels
import ClefFoundationModels
import LayaFoundationModels
import JevFoundationModels
import FirebaseAppCheck

let appCheckCredential = ProxyCredential.appCheck {
    try await AppCheck.appCheck().token(forcingRefresh: false).token
}

// 1. Google Gemini Decisions (gemini-decision-1) via proxy
let gemini = GeminiLanguageModel(
    proxyEndpoint: URL(string: "https://my-gateway.run.app/gemini/decisions")!,
    credential: appCheckCredential
)

// 2. OpenAI Decisions (gpt-6-luna) via proxy
let openai = OpenAILanguageModel(
    proxyEndpoint: URL(string: "https://my-gateway.run.app/openai/decisions")!,
    credential: appCheckCredential
)

// 3. Cloudflare Clef Multimodal via proxy
let clef = ClefLanguageModel(
    proxyEndpoint: URL(string: "https://my-gateway.run.app/clef")!,
    model: .clefFlash,
    credential: appCheckCredential
)

// 4. Self-Hosted Laya (laya-serve) via proxy
let laya = LayaLanguageModel(
    proxyEndpoint: URL(string: "https://my-gateway.run.app/laya")!,
    credential: appCheckCredential
)

// 5. TypeSafe AI Jev via proxy
let jev = JevLanguageModel(
    proxyEndpoint: URL(string: "https://my-gateway.run.app/jev")!,
    credential: appCheckCredential
)
```

### 2. Vendor-Agnostic Gateway (`SystemOneLanguageModel` + `SystemOneProxyBackend`) & Inline `authorize:` Closure

When your backend gateway accepts canonical `SystemOneRequest` JSON and routes between providers server-side, or when you want to attach multiple headers inline (e.g., App Check + user Bearer JWT), use `SystemOneLanguageModel` or the trailing `authorize:` closure:

```swift
import FoundationModels
import SystemOneCore
import FirebaseAppCheck

// Pattern B: Vendor-agnostic canonical gateway with .appCheck
let gatewayModel = SystemOneLanguageModel(
    proxyEndpoint: URL(string: "https://api.mycompany.com/v1/decisions")!,
    credential: .appCheck {
        try await AppCheck.appCheck().limitedUseToken().token
    },
    modelID: "gemini-decision-1"
)

// Inline trailing-closure `authorize:` (available on all hosted LanguageModel types)
let multiHeaderModel = GeminiLanguageModel(
    proxyEndpoint: URL(string: "https://api.mycompany.com/v1/gemini")!
) { request in
    let appCheck = try await AppCheck.appCheck().token(forcingRefresh: false).token
    let userJWT = try await AuthManager.shared.validAccessToken()
    request.setValue(appCheck, forHTTPHeaderField: "X-Firebase-AppCheck")
    request.setValue("Bearer \(userJWT)", forHTTPHeaderField: "Authorization")
}
```

### 3. Corporate API Gateway with OAuth 2.0 / OIDC Bearer Tokens

For enterprise internal apps communicating with a private ingress gateway requiring dynamic user tokens:

```swift
let oauthModel = OpenAILanguageModel(
    proxyEndpoint: URL(string: "https://gateway.internal.company.com/v1/decisions")!,
    credential: .bearer {
        // Asynchronously retrieves or refreshes user session token on every attempt
        try await AuthenticationManager.shared.validAccessToken()
    },
    timeoutInterval: 15,
    retryPolicy: RetryPolicy(maxAttempts: 3)
)

let session = LanguageModelSession(model: oauthModel)
```

### 4. Multi-Tenant Gateway with Dynamic Signing Headers

For edge architectures requiring custom multi-tenant headers and cryptographic HMAC signatures:

```swift
let signedModel = SystemOneLanguageModel(
    proxyEndpoint: URL(string: "https://edge.api.company.com/systemone")!,
    credential: .custom { request in
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let signature = try await CryptoSigner.sign(requestBody: request.httpBody, timestamp: timestamp)
        
        request.setValue("tenant-enterprise-42", forHTTPHeaderField: "X-Tenant-ID")
        request.setValue(timestamp, forHTTPHeaderField: "X-Request-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature-SHA256")
    }
)
```

### 5. Direct Ergonomic Decision Evaluation Through Proxy

All proxy-configured models seamlessly support Apple Foundation Models evaluation mechanisms, including composite `@Generable` schemas, multimodal `Transcript` image attachments, and ergonomic session shortcuts:

```swift
// Evaluates binary probability via proxy
let isFraud = try await session.probability(
    of: "Does this transaction exhibit anomalous velocity?",
    state: transactionDetails
)

// Evaluates categorical choice via proxy
let priority = try await session.choice(
    "Determine escalation level",
    from: IncidentPriority.self,
    state: serverAlertLog
)
```

---

## Sources & Cross-References

- **Architecture Decision Records & PRDs**:
  - [ADR-2026-11-12-01 — Universal Zero-Dependency Proxy Credentials & Hardware-Attested Mobile Gateways](../docs/architecture/ADR-2026-11-12-01-universal-proxy-credentials.md)
  - [PRD-2026-11-12 — Universal Proxy Credentials & Hardware-Attested Gateways](../docs/prd/PRD-2026-11-12-universal-proxy-credentials.md)
- **Tech Notes**:
  - [Tech Note 0004 — Secure Mobile Transport with Firebase App Check & Apple App Attest](0004-secure-mobile-transport-appcheck.md)
  - [Tech Note 0005 — SPM Dependency Isolation & Decoupling Vendor Transports](0005-spm-dependency-isolation-and-vendor-transports.md)
  - [Tech Note 0006 — HTTP Resilience, RFC 9110 Backoff & Calibrated Decision Routing](0006-http-resilience-and-confidence-routing.md)
  - [Tech Note 0009 — Package Traits & Ergonomic Decision Shortcuts](0009-package-traits-and-ergonomic-shortcuts.md)
- **Reference Code & Tests**:
  - `Sources/SystemOneCore/Backend/ProxyCredential.swift`
  - `Sources/SystemOneCore/Backend/ProxyEndpointValidator.swift`
  - `Sources/SystemOneCore/Backend/SystemOneProxyBackend.swift`
  - `Sources/JevFoundationModels/Transport/ProxyTransport.swift`
  - `Tests/SystemOneCoreTests/ProxyCredentialTests.swift`
  - `Tests/JevFoundationModelsTests/ProxyTransportTests.swift`
  - `Examples/TraitSamples/05-SecureAppCheckApp/`
- **Guides**:
  - [Mobile Security Guide](../docs/mobile-security.md)
  - [Resilience & Retries Guide](../docs/resilience-and-retries.md)
