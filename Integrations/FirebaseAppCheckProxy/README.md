# Multi-Provider Firebase App Check Reverse Proxy (`Integrations/FirebaseAppCheckProxy/`)

This directory contains a ready-to-deploy **Firebase Cloud Function (2nd Gen) reverse proxy** and a drop-in Swift helper ([`FirebaseAppCheckTransport.swift`](FirebaseAppCheckTransport.swift)) supporting **all 5 networked System One providers** (`jev`, `laya`, `clef`, `openai`, `gemini`) across **both** mobile proxy patterns with **zero SSRF risk**:

- **Pattern A — Provider-Native Passthrough** (`<Provider>LanguageModel(proxyEndpoint:credential:)`): Validates and forwards native OpenAI (`/v1/decisions`), Google Gemini (`/v1beta/decisions`), Cloudflare Clef, Laya, or TypeSafe Jev wire payloads verbatim.
- **Pattern B — Provider-Agnostic Gateway** (`SystemOneLanguageModel(proxyEndpoint:credential:)` / `SystemOneProxyBackend`): Accepts canonical `SystemOneRequest` payloads (`{ state, model?, questions, images? }`) and automatically adapts requests and responses to/from OpenAI Decisions, Google Gemini Decisions, or Cloudflare Workers AI (`{ success, result }` envelope unwrapping) on the server.

---

## Directory Structure

```text
Integrations/FirebaseAppCheckProxy/
├── README.md                          # Deployment, routing, secrets & Swift usage guide
├── firebase.json                      # Firebase configuration
├── FirebaseAppCheckTransport.swift    # ProxyCredential.firebaseAppCheck(...) + SystemOneBackend / JevTransport
└── functions/                         # Firebase Cloud Functions v2 TypeScript project
    ├── package.json                   # Build & automated node --test scripts
    ├── tsconfig.json                  # Strict TypeScript config
    └── src/
        ├── index.ts                   # Cloud Function v2 entry point (systemone & jevProxy alias)
        ├── proxyCore.ts               # SSRF-safe allowlisted provider router & credential injector
        ├── adapters.ts                # Bidirectional Pattern A / Pattern B wire validators & adapters
        └── __tests__/
            └── proxyCore.test.ts      # Offline unit test suite (App Check, routing, adapters, SSRF)
```

---

## Provider Routing & Environment Secrets

The proxy **never** fetches client-supplied URLs. It resolves one of the 5 allowlisted providers in priority order:

1. **URL path suffix**: `POST .../systemone/jev`, `/systemone/laya`, `/systemone/clef`, `/systemone/openai`, or `/systemone/gemini` (unknown suffixes return `400 Bad Request`).
2. **`X-SystemOne-Provider` header**: `jev` | `laya` | `clef` | `openai` | `gemini` (unknown values return `400 Bad Request`).
3. **Payload / `model` auto-detection**:
   - `Array.isArray(questions)` or `model` starting with `gpt-` / `openai` $\to$ `openai`
   - `input !== undefined` (object `questions`) or `model` starting with `gemini-` $\to$ `gemini`
   - `model` starting with `@cf/` or `clef` $\to$ `clef`
   - `model` starting with `laya` $\to$ `laya`
   - `model` starting with `jev` $\to$ `jev`
4. **`DEFAULT_PROVIDER` env var**: Defaults to `jev` for 100% backward compatibility.

### Upstream Secrets & Endpoints (Zero Mandatory Unused Secrets)

Only configure the secret(s) for the provider(s) you actually use:

| Provider | Required Secret / Env Var(s) | Optional Env Overrides | Outbound Auth Header |
| :--- | :--- | :--- | :--- |
| **`jev`** | `TYPESAFE_API_KEY` | `TYPESAFE_ENDPOINT` (default `https://api.typesafe.ai/v1/systemone`), `JEV_MODEL` | `Authorization: Bearer <key>` |
| **`laya`** | `LAYA_UPSTREAM_URL` (or `LAYA_SERVE_URL`) | `LAYA_API_KEY`, `LAYA_MODEL` | Optional `Authorization: Bearer <key>` |
| **`clef`** | `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN` *(or `CLEF_UPSTREAM_URL`)* | `CLOUDFLARE_GATEWAY_ID`, `CLEF_MODEL` (`clef-flash` / `clef`) | `Authorization: Bearer <token>` |
| **`openai`** | `OPENAI_API_KEY` | `OPENAI_DECISIONS_URL` (default `https://api.openai.com/v1/decisions`), `OPENAI_ORGANIZATION`, `OPENAI_PROJECT`, `OPENAI_MODEL` | `Authorization: Bearer <key>` |
| **`gemini`** | `GEMINI_API_KEY` *(or `GOOGLE_API_KEY`)* | `GEMINI_DECISIONS_URL` (default `https://generativelanguage.googleapis.com/v1beta/decisions`), `GEMINI_MODEL` | `x-goog-api-key: <key>` |

Upstream telemetry and rate-limit headers (`Retry-After`, `server-timing`, `x-envoy-upstream-service-time`, `openai-processing-ms`, `x-goog-processing-ms`, `x-inference-time-ms`) are automatically preserved on responses.

---

## Build, Test & Deploy

From `Integrations/FirebaseAppCheckProxy/`:

```bash
# 1. Install dependencies & run the offline TypeScript unit test suite
npm --prefix functions ci
npm --prefix functions test

# 2. Store ONLY the secret(s) for the provider(s) you deploy in Google Secret Manager
firebase functions:secrets:set GEMINI_API_KEY

# 3. Declare active Secret Manager bindings in functions/.env so unused secrets are never required
echo 'ENABLED_SECRETS="GEMINI_API_KEY"' >> functions/.env
echo 'DEFAULT_PROVIDER="gemini"' >> functions/.env

# 4. Deploy to Firebase Cloud Functions (2nd Gen)
firebase deploy --only functions
```

### Enabling Replay Protection (Single-Use / Limited-Use Tokens)

1. Grant the **Firebase App Check Token Verifier** role to the function's compute service account:
   ```bash
   gcloud projects add-iam-policy-binding <PROJECT_ID> \
     --member="serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com" \
     --role="roles/appcheck.tokenVerifier"
   ```
2. Set `CONSUME_APP_CHECK=true` in `functions/.env`, and use `.singleUse` (`limitedUseToken()`) on the client.

---

## Swift Client Usage (`FirebaseAppCheckTransport.swift`)

Copy [`FirebaseAppCheckTransport.swift`](FirebaseAppCheckTransport.swift) into your Xcode app target (or use `ProxyCredential.appCheck { ... }` directly from `SystemOneCore` — see [Tech Note 0005](../../tech-notes/0005-spm-dependency-isolation-and-vendor-transports.md)).

### Recommended: `ProxyCredential.firebaseAppCheck(strategy:)` Across Any Provider

Works with `GeminiLanguageModel`, `OpenAILanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, `JevLanguageModel`, and `SystemOneLanguageModel` without requiring `JevFoundationModels`:

```swift
import FoundationModels
import GeminiFoundationModels // or OpenAI / Clef / Laya / Jev / SystemOneCore

let baseURL = URL(string: "https://us-central1-<project-id>.cloudfunctions.net/systemone")!

// Pattern A: Provider-native wire passthrough (cached token < 1 ms, or .singleUse for replay protection)
let gemini = GeminiLanguageModel(
    proxyEndpoint: baseURL.appending(path: "gemini"),
    credential: .firebaseAppCheck(strategy: .singleUse)
)
let session = LanguageModelSession(model: gemini)
```

```swift
import FoundationModels
import SystemOneCore

// Pattern B: Provider-agnostic canonical gateway (routes/adapts server-side via DEFAULT_PROVIDER or path)
let gateway = SystemOneLanguageModel(
    proxyEndpoint: URL(string: "https://us-central1-<project-id>.cloudfunctions.net/systemone/openai")!,
    credential: .firebaseAppCheck(strategy: .cached)
)
let session = LanguageModelSession(model: gateway)
```

### Legacy `FirebaseAppCheckTransport` (`SystemOneBackend` & `JevTransport`)

`FirebaseAppCheckTransport` remains 100% source-compatible for existing `SystemOneBackend` and `JevLanguageModel(apiKey:transport:)` call sites:

```swift
let proxyURL = URL(string: "https://us-central1-<project-id>.cloudfunctions.net/systemone")!
let transport = FirebaseAppCheckTransport(proxyEndpoint: proxyURL, tokenStrategy: .cached)
let model = SystemOneLanguageModel(backend: transport)
```

---

## Production Hardening: User Authorization & Abuse Quotas

While Firebase App Check (via Apple App Attest) cryptographically verifies that requests originate from a **genuine, un-tampered Apple application binary**, pair it in production with:

1. **User Identity Binding (Firebase Auth / Sign in with Apple)**: Attach a user JWT alongside `X-Firebase-AppCheck` via `ProxyCredential.custom { ... }` and enforce per-tier quotas.
2. **Server-Side Rate Limiting (Firestore / Memorystore Redis)**: Enforce per-UID rolling token buckets (`HTTP 429 Too Many Requests`).
3. **Google Cloud Armor**: Volumetric IP-level ingress throttling in front of Cloud Run.

See the [**Mobile Security Guide**](../../docs/mobile-security.md) and runnable [**`05-SecureAppCheckApp`**](../../Examples/TraitSamples/05-SecureAppCheckApp/README.md) sample for end-to-end details.
