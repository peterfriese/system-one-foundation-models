# Firebase App Check Proxy Integration

This directory contains a ready-to-deploy reference implementation of a **Firebase Cloud Function (2nd Gen) reverse proxy** and a client-side **`FirebaseAppCheckTransport`** for Apple platforms.

---

## Directory Structure

```
Integrations/FirebaseAppCheckProxy/
├── README.md                          # Quick start instructions
├── firebase.json                      # Firebase configuration
├── FirebaseAppCheckTransport.swift     # Swift transport conforming to JevTransport
└── functions/                         # Firebase Cloud Functions v2 project
    ├── package.json                   # Dependencies
    ├── tsconfig.json                  # TypeScript config
    └── src/
        └── index.ts                   # Proxies requests with App Check verification
```

---

## Deployment Instructions

### 1. Configure Secret & Deploy Function
From `Integrations/FirebaseAppCheckProxy/`:

```bash
# Install dependencies
npm --prefix functions install

# Set your TypeSafe API key securely
firebase functions:secrets:set TYPESAFE_API_KEY

# Deploy to Firebase using the local firebase.json
firebase deploy --only functions
```

Note the deployed URL (e.g. `https://us-central1-<project-id>.cloudfunctions.net/systemone`).

#### Enabling Replay Protection (Single-Use / Limited-Use Tokens)
If you wish to enforce **single-use tokens** to prevent token replay attacks:

1. Grant the **Firebase App Check Token Verifier** role to the function's compute service account:
   ```bash
   gcloud projects add-iam-policy-binding <PROJECT_ID> \
     --member="serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com" \
     --role="roles/appcheck.tokenVerifier"
   ```

2. Set the `CONSUME_APP_CHECK` environment variable:
   ```bash
   # In functions/.env or Cloud Console
   CONSUME_APP_CHECK=true
   ```

---

### 2. Add Swift Transport to your App
Copy `FirebaseAppCheckTransport.swift` into your Xcode project (iOS 27+, macOS 27+, visionOS 27+).

> **Why a drop-in file?** `FirebaseAppCheckTransport.swift` is intentionally kept as an unbundled reference implementation rather than an SPM library target to preserve `JevFoundationModels`'s zero-dependency mandate and avoid pulling hundreds of megabytes of Firebase dependencies into projects that don't use it. See [Tech Note 0005](../../tech-notes/0005-spm-dependency-isolation-and-vendor-transports.md).

Initialize `JevLanguageModel` with your deployed Cloud Function endpoint:

#### Strategy A: Cached Tokens (Default — Lowest Latency)
Best for UI transitions, autocomplete, and interactive feedback loops (`< 1 ms` token check overhead):

```swift
let proxyURL = URL(string: "https://us-central1-<project-id>.cloudfunctions.net/systemone")!
let transport = FirebaseAppCheckTransport(proxyEndpoint: proxyURL, tokenStrategy: .cached)
let model = JevLanguageModel(apiKey: "app-check", transport: transport)
let session = LanguageModelSession(model: model)
```

#### Strategy B: Single-Use Tokens (Hardened — Replay Protection)
Best for high-value triage, automated decisions, or billing-sensitive actions (`~40–120 ms` token exchange):

```swift
let proxyURL = URL(string: "https://us-central1-<project-id>.cloudfunctions.net/systemone")!
let transport = FirebaseAppCheckTransport(proxyEndpoint: proxyURL, tokenStrategy: .singleUse)
let model = JevLanguageModel(apiKey: "app-check", transport: transport)
let session = LanguageModelSession(model: model)
```

---

### 3. Production Hardening: User Authorization & Abuse Quotas

While Firebase App Check (via Apple App Attest) cryptographically verifies that requests originate from a **genuine, un-tampered iOS application binary**, it verifies *device and application integrity*, not *user identity* or *consumption limits*.

In a production environment where upstream TypeSafe AI tokens carry real financial cost, deploy the following defense-in-depth measures:

#### A. User Identity Binding (Firebase Auth / Sign in with Apple)
Pass an authenticated user token (`Authorization: Bearer <ID_TOKEN>`) alongside the `X-Firebase-AppCheck` header. The proxy verifies the caller's identity via `getAuth().verifyIdToken(idToken)`:
- Anonymous users: strictly limited rate limits (e.g. 5 scans/day).
- Authenticated subscribers: higher tiered quotas based on their subscription status.

#### B. Server-Side Rate Limiting (Firestore / Redis)
Store a rolling timestamp window or token bucket per user UID in Firestore or Google Cloud Memorystore (Redis). Reject calls with `HTTP 429 Too Many Requests` if the user exceeds policy limits (e.g. max 20 requests/minute).

#### C. Google Cloud Armor / API Gateway Ingress Rules
For high-traffic deployments, terminate requests behind Cloud Armor or Google Cloud API Gateway with volumetric IP-level throttling to absorb malicious traffic bursts at Google's global edge before containers spin up.
