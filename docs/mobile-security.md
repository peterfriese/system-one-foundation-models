# Secure Mobile Deployments: Universal `ProxyCredential`, Firebase App Check & Apple App Attest

This guide details how to securely deploy **System One Foundation Models** (`GeminiLanguageModel`, `OpenAIDecisionsLanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, `JevLanguageModel`, and vendor-agnostic `SystemOneLanguageModel`) in client-side Apple applications (iOS, iPadOS, macOS, visionOS) using **`ProxyCredential`**, **Firebase App Check**, and **Apple App Attest** (`DeviceCheck`).

---

## 1. The Threat Model

When building an Apple platform application with AI capabilities, embedding third-party API credentials into the app bundle is a severe security vulnerability:

1. **Decompilation:** Anyone can inspect compiled Mach-O binaries using tools like `strings`, Hopper, or Ghidra and extract embedded strings.
2. **Network Interception:** Even with HTTPS, an attacker on a supervised or jailbroken device can install a custom root certificate authority and inspect outbound traffic using Proxyman or Charles.
3. **Account Depletion:** A leaked `GEMINI_API_KEY`, `OPENAI_API_KEY`, `CLOUDFLARE_API_TOKEN`, or `TYPESAFE_API_KEY` grants unrestricted access to your cloud AI account balance and models.

Because cloud AI providers require secret master API keys that cannot be safely shipped inside client binaries, **client applications must never communicate directly with upstream cloud endpoints using a client-bundled master key.**

---

## 2. Architecture: Hardware Attestation + Cloud Proxy

To solve this, we place a lightweight **Firebase Cloud Function (2nd Gen)** or API gateway between the client app and your upstream System One provider (Google Gemini, OpenAI, Cloudflare Clef, Laya, or TypeSafe Jev), protected by **Apple App Attest**:

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Client (iOS 27+)                 │
│                                                         │
│  1. Device creates key pair in Secure Enclave           │
│  2. Firebase App Check obtains Apple Attestation token  │
│  3. ProxyCredential attaches dynamic token header       │
│  4. Standard LanguageModelSession executes decision     │
└────────────────────────────┬────────────────────────────┘
                             │
                POST /systemone
                Header: X-Firebase-AppCheck: <JWT>
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│         Firebase Cloud Function (2nd Gen Proxy)         │
│                                                         │
│  5. Ingress automatically validates Apple Attestation   │
│     (Unauthorized requests rejected with 401 at edge)   │
│  6. Injects secret API key from Secret Manager          │
│  7. Forwards payload to Gemini / OpenAI / Clef / Jev    │
└────────────────────────────┬────────────────────────────┘
                             │
                POST https://generativelanguage.googleapis.com/v1beta/decisions
                (or api.openai.com / api.cloudflare.com / api.typesafe.ai)
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│       Upstream System One Provider (Gemini / etc.)      │
│  Evaluates state & returns typed decision probabilities │
└─────────────────────────────────────────────────────────┘
```

### Why this is secure
* **Hardware-Backed:** App Attest uses the device's physical **Secure Enclave**. The private key never leaves the chip and cannot be copied or spoofed by bots.
* **Ingress-Level Filtering:** Firebase Cloud Functions v2 with `enforceAppCheck: true` validates the token at Google's ingress edge. Requests from tampered apps or curl scripts are rejected **before** your Cloud Function executes, preventing unwanted compute and API costs.
* **Zero Credential Exposure:** Your upstream API keys (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `CLOUDFLARE_API_TOKEN`, `TYPESAFE_API_KEY`) exist only in Google Cloud Secret Manager.

---

## 3. Step-by-Step Implementation

### Step 1: Firebase Console Setup
1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com).
2. Add your Apple App (iOS/macOS) with your **Bundle ID**.
3. Under **Build > App Check > Apps**:
   - Select your Apple app.
   - Choose **App Attest**.
   - Enter your Apple **Team ID** (found in your Apple Developer account).

---

### Step 2: Deploy the Firebase Cloud Function Proxy

In a Node/TypeScript Firebase Functions directory:

#### `functions/src/index.ts`
```typescript
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";

// Initialize Firebase Admin SDK for token verification and consumption
initializeApp();

// Define the secret stored in Google Cloud Secret Manager
const typesafeApiKey = defineSecret("TYPESAFE_API_KEY");

export const systemone = onRequest(
  {
    cors: false,
    enforceAppCheck: true, // Rejects unverified traffic at Google Cloud edge
    secrets: [typesafeApiKey],
    // minInstances: 1 keeps a container warm 24/7 to eliminate ~500ms-1.5s cold starts
    minInstances: 1,
    concurrency: 80,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    // App Check Token Verification & Optional Replay Protection
    const appCheckToken = req.header("X-Firebase-AppCheck");
    if (!appCheckToken) {
      res.status(401).json({ error: "Unauthorized: Missing X-Firebase-AppCheck header" });
      return;
    }

    const consume = process.env.CONSUME_APP_CHECK === "true";
    try {
      const claims = await getAppCheck().verifyToken(appCheckToken, { consume });
      if (claims.alreadyConsumed) {
        res.status(401).json({ error: "Unauthorized: App Check token has already been consumed" });
        return;
      }
    } catch (error: any) {
      res.status(401).json({ error: `Unauthorized: Invalid App Check token (${error.message ?? error})` });
      return;
    }

    try {
      const upstreamResponse = await fetch("https://api.typesafe.ai/v1/systemone", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${typesafeApiKey.value()}`,
        },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(15000), // 15-second upstream timeout
      });

      const responseText = await upstreamResponse.text();
      res
        .status(upstreamResponse.status)
        .header("Content-Type", upstreamResponse.headers.get("Content-Type") || "application/json")
        .send(responseText);
    } catch (error: any) {
      res.status(502).json({ error: error.message ?? "Upstream proxy failure" });
    }
  }
);
```

#### Set Secret & Deploy
```bash
# 1. Set the secret in Google Secret Manager
firebase functions:secrets:set TYPESAFE_API_KEY

# 2. Deploy the function
firebase deploy --only functions
```

Note your deployed endpoint URL:
`https://systemone-<unique-hash>.a.run.app` or `https://us-central1-<project-id>.cloudfunctions.net/systemone`.

---

### Step 3: Configure App Check in your iOS Application

Add the Firebase iOS SDK to your Xcode project (`FirebaseAppCheck`).

In your `App` or `AppDelegate`:

```swift
import SwiftUI
import FirebaseCore
import FirebaseAppCheck

class AppCheckSetup {
    static func configure() {
        #if DEBUG
        // In Debug (Simulator, Previews), use debug provider
        let providerFactory = AppCheckDebugProviderFactory()
        #else
        // In Production (TestFlight, App Store), use Apple Secure Enclave App Attest
        let providerFactory = AppAttestProviderFactory()
        #endif

        AppCheck.setAppCheckProviderFactory(providerFactory)
        FirebaseApp.configure()
    }
}

@main
struct MyApp: App {
    init() {
        AppCheckSetup.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

### Step 4: Configure Universal `ProxyCredential` Across Any System One Model

`SystemOneCore` provides **`ProxyCredential`** and **`SystemOneProxyBackend`** so you can authenticate against your reverse proxy with **any** hosted System One model (`GeminiLanguageModel`, `OpenAIDecisionsLanguageModel`, `ClefLanguageModel`, `LayaLanguageModel`, `JevLanguageModel`, or vendor-agnostic `SystemOneLanguageModel`).

> **Zero Third-Party Runtime Dependencies via Closure Injection:**
> `SystemOneFoundationModels` maintains a strict mandate of **Zero External Third-Party Runtime Dependencies** ([Tech Note 0005](../tech-notes/0005-spm-dependency-isolation-and-vendor-transports.md)). Rather than forcing all package consumers to compile Google Firebase or Apple DeviceCheck SDKs, `ProxyCredential` uses dynamic closure injection (`.appCheck`, `.header`, `.bearer`, `.custom`, or inline `authorize:` trailing closures).
>
> Your application target links `FirebaseAppCheck`, and passes an asynchronous token acquisition closure directly into the model initializer. Token resolution occurs **per attempt inside the retry loop**, ensuring automatic refresh during exponential backoff. For architectural details, see [ADR-2026-11-12-01](architecture/ADR-2026-11-12-01-universal-proxy-credentials.md) and [Tech Note 0010](../tech-notes/0010-proxy-transport-and-dynamic-attestation.md).

#### Pattern A: Provider Passthrough Proxy (`.appCheck` Shorthand Across All Models)

Every hosted provider model accepts `proxyEndpoint: URL` and `credential: ProxyCredential` directly:

```swift
import Foundation
import FirebaseAppCheck
import GeminiFoundationModels
import OpenAIFoundationModels
import ClefFoundationModels
import LayaFoundationModels
import JevFoundationModels

let proxyBaseURL = URL(string: "https://us-central1-myproject.cloudfunctions.net")!

// Shared zero-dependency App Check credential (defaults to "X-Firebase-AppCheck" header)
let appCheckCredential = ProxyCredential.appCheck {
    try await AppCheck.appCheck().token(forcingRefresh: false).token
}

// 1. Google Gemini Decisions (gemini-decision-1)
let gemini = GeminiLanguageModel(
    proxyEndpoint: proxyBaseURL.appending(path: "geminiDecisions"),
    credential: appCheckCredential
)

// 2. OpenAI Decisions (gpt-6-luna)
let openai = OpenAIDecisionsLanguageModel(
    proxyEndpoint: proxyBaseURL.appending(path: "openaiDecisions"),
    credential: appCheckCredential
)

// 3. Cloudflare Clef Multimodal (clef-flash / clef)
let clef = ClefLanguageModel(
    proxyEndpoint: proxyBaseURL.appending(path: "clefDecisions"),
    model: .clefFlash,
    credential: appCheckCredential
)

// 4. Self-Hosted Laya (laya-serve)
let laya = LayaLanguageModel(
    proxyEndpoint: proxyBaseURL.appending(path: "layaDecisions"),
    credential: appCheckCredential
)

// 5. TypeSafe AI Jev
let jev = JevLanguageModel(
    proxyEndpoint: proxyBaseURL.appending(path: "systemone"),
    credential: appCheckCredential
)
```

#### Pattern B: Vendor-Agnostic Gateway (`SystemOneLanguageModel` + `SystemOneProxyBackend`)

If your backend gateway accepts canonical `SystemOneRequest` JSON and routes or fails over between Gemini, OpenAI, Clef, Jev, and Laya server-side, use `SystemOneLanguageModel` directly from `SystemOneCore`:

```swift
import Foundation
import FirebaseAppCheck
import SystemOneCore

let gatewayURL = URL(string: "https://us-central1-myproject.cloudfunctions.net/systemone")!

let model = SystemOneLanguageModel(
    proxyEndpoint: gatewayURL,
    credential: .appCheck {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    },
    modelID: "gemini-decision-1"
)
```

#### Inline Trailing-Closure `authorize:` (Multi-Header Gateways)

When your gateway requires multiple dynamic headers (e.g., `X-Firebase-AppCheck` for device attestation plus `Authorization: Bearer` for user identity), use `.custom` or the inline `authorize:` trailing-closure initializer available on all hosted `LanguageModel` types:

```swift
let gemini = GeminiLanguageModel(
    proxyEndpoint: URL(string: "https://us-central1-myproject.cloudfunctions.net/geminiDecisions")!
) { request in
    let appCheckToken = try await AppCheck.appCheck().token(forcingRefresh: false).token
    let userIDToken = try await Auth.auth().currentUser?.getIDToken() ?? ""
    request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
    request.setValue("Bearer \(userIDToken)", forHTTPHeaderField: "Authorization")
}
```

#### Single-Use Consumable Tokens (Replay-protected, recommended for high-value decisions)

```swift
let replayProtectedModel = GeminiLanguageModel(
    proxyEndpoint: URL(string: "https://us-central1-myproject.cloudfunctions.net/geminiDecisions")!,
    credential: .appCheck {
        try await AppCheck.appCheck().limitedUseToken().token
    }
)
```

---

### Step 5: Evaluate with Apple Foundation Models

At your application call site, pass your proxy-configured model to standard Apple Foundation Models `LanguageModelSession`:

```swift
import FoundationModels
import GeminiFoundationModels
import FirebaseAppCheck

// 1. Configure GeminiLanguageModel (or OpenAI / Clef / Laya / Jev / SystemOneLanguageModel) with .appCheck
// No API key is needed on the client — key injection happens server-side in the Cloud Function
let gemini = GeminiLanguageModel(
    proxyEndpoint: URL(string: "https://us-central1-myproject.cloudfunctions.net/geminiDecisions")!,
    credential: .appCheck {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)

// 2. Initialize standard Apple LanguageModelSession
let session = LanguageModelSession(model: gemini)

// 3. Evaluate typed @Generable schema
let ticketText = "My payment failed and I was double charged!"
let response = try await session.respond(to: ticketText, generating: TicketTriage.self)

print("Department: \(response.content.department)")
print("Is Urgent: \(response.content.isUrgent)")
if let confidence = response.metadata["confidence"] {
    print("Decision Confidence: \(confidence)")
}
```

---

## 4. Development & Testing Workflow

### Xcode Simulator & SwiftUI Previews
Xcode Simulators do not have access to Apple's Secure Enclave App Attest service. When running with `AppCheckDebugProviderFactory()`:

1. Launch your app in the Simulator.
2. In the Xcode console, look for the debug message:
   ```text
   [Firebase/AppCheck] Firebase App Check Debug Token:
   6B952F37-B30B-4D78-9BA3-6625B6EEA072
   ```
3. Copy this token.
4. In the Firebase Console, go to **App Check > Apps > Manage debug tokens**, and register the token.
5. Your Simulator and Previews can now test end-to-end inference without triggering `401 Unauthorized` errors.

### Production (TestFlight / App Store)
When compiled for release, `AppAttestProviderFactory` communicates with Apple's production attestation servers. No debug tokens are needed.

---

## 5. Performance Implications & Latency Breakdown

Deploying an intermediary Cloud Function proxy with App Check validation introduces minimal overhead when properly configured.

### Performance Summary
* **Warm Invocations:** Adds only **~15–35 ms** of total overhead compared to calling TypeSafe directly. Total round-trip latency is typically **~120–250 ms**, well within the threshold for responsive interactive UI transitions.
* **Cold Starts (if scaled to 0):** Adds **+500 ms to 1.5 s** on the initial request after an idle period while the Cloud Run container boots.
* **On-Device Overhead:** **< 1 ms** in-memory token lookup; virtually zero battery or CPU consumption.

### Step-by-Step Latency Profile

```
[iOS Device]               [Google Cloud / Ingress]         [Cloud Function Container]         [TypeSafe AI]
     │                                │                                  │                           │
     ├─ App Check token (< 1 ms)      │                                  │                           │
     ├───────────────────────────────►│                                  │                           │
     │      Client RTT (~30-80 ms)    ├─ Ingress JWT Verify (2-5 ms)     │                           │
     │                                ├─────────────────────────────────►│                           │
     │                                │      Container Exec (2-5 ms)     ├──────────────────────────►│
     │                                │                                  │    GCP -> TypeSafe (15-25 ms)
     │                                │                                  │    Jev Inference (40-120 ms)
     │                                │                                  │◄──────────────────────────┤
     │                                │◄─────────────────────────────────┤                           │
     │◄───────────────────────────────┤                                  │                           │
     │      Return RTT (~30-80 ms)    │                                  │                           │
```

| Phase | Latency | Mechanism & Details |
| :--- | :--- | :--- |
| **1. On-Device Token Retrieval** | **< 1 ms** | `AppCheck.appCheck().token(forcingRefresh: false)` fetches a **cached JWT** from memory. It does not perform hardware attestation on every call. Hardware attestation with Apple occurs only once per hour in the background. |
| **2. Mobile Client $\to$ Cloud Function** | **~30–80 ms** | Standard cellular or Wi-Fi HTTPS round-trip time (RTT). |
| **3. Google Ingress Validation** | **~2–5 ms** | Google's front-edge proxy verifies the cryptographic signature of the `X-Firebase-AppCheck` token against Apple's cached public keys. |
| **4. Cloud Function Execution** | **~2–5 ms** | `typesafeApiKey.value()` is an in-memory process environment lookup (0 ms); Node parses and forwards the JSON payload. |
| **5. Cloud Function $\to$ TypeSafe AI** | **~15–25 ms** | High-bandwidth data center-to-data center connection with persistent TLS keep-alive. |
| **6. Jev Model Evaluation** | **~40–120 ms** | TypeSafe's feed-forward decision inference. |
| **Total Round-Trip (Warm)** | **~120–240 ms** | **Virtually indistinguishable from a direct API call.** |

### Eliminating Bottlenecks

#### 1. Zero Cold Starts via `minInstances: 1`
Firebase Cloud Functions (2nd Gen) are built on Google Cloud Run. By default, they scale down to zero when idle. To guarantee consistent sub-250 ms responses for user-facing actions, set `minInstances: 1`:

```typescript
export const systemone = onRequest(
  {
    cors: false,
    secrets: [typesafeApiKey],
    minInstances: 1, // Keeps 1 container warm 24/7 to eliminate cold starts
    concurrency: 80, // Handles up to 80 concurrent requests per warm container
  },
  ...
);
```

#### 2. Geographic Placement
Deploy your Cloud Function in a region close to either your predominant user base (e.g. `europe-west1`) or TypeSafe's data centers (`us-central1`, `us-east1`). Because Jev inference is exceptionally fast (~40–120 ms), placing the proxy in `us-central1` or `us-east1` minimizes server-to-server latency.

#### 3. Concurrency & DoS Resilience
- **80 Concurrent Calls per Instance:** Cloud Functions 2nd Gen multiplex connections over HTTP/2, allowing a single warm container to comfortably handle high peak mobile traffic.
- **App Check Ingress & Verification:** Requests without a valid App Check token or with an already-consumed token are rejected with `401 Unauthorized`.

---

## 6. Token Replay Protection: Cached vs. Single-Use Tokens

By default, Firebase App Check issues tokens that remain valid for **up to 1 hour**. These tokens are cached in-memory on the device:
- Calling `AppCheck.appCheck().token(forcingRefresh: false)` returns the cached JWT in **< 1 ms**.
- This enables Jev's fast **System One** latency budget (~120–240 ms total round-trip).

### The Threat: Token Replay Attacks
If a user runs your app on a jailbroken or proxied device (e.g., Charles Proxy or Proxyman with a custom trust certificate installed), they can intercept their authentic `X-Firebase-AppCheck` header. Because the token is valid for 1 hour, an attacker could replay that single token thousands of times from a script to burn your TypeSafe AI quota.

### The Solution: Consumable Single-Use Tokens
Firebase App Check provides **Limited-Use Tokens** designed for replay protection:
1. **Client:** The app requests a consumable token via `AppCheck.appCheck().limitedUseToken()`.
2. **Server:** The Cloud Function verifies the token with `{ consume: true }`.
3. **Consumption:** Google's App Check backend registers the token as consumed. Any subsequent request presenting that same token receives `claims.alreadyConsumed === true` and is rejected with `401 Unauthorized`.

### Strategy Comparison & Recommendations

| Metric | `.cached` (Standard) | `.singleUse` (Limited-Use) |
| :--- | :--- | :--- |
| **Client Token Retrieval** | **< 1 ms** (in-memory cache) | **~40–120 ms** (network round-trip to mint token) |
| **Server Verification Overhead** | **0 ms** (local cryptographic check) | **~25–60 ms** (`verifyToken` with `{ consume: true }`) |
| **Total Round-Trip Latency** | **~120–240 ms** (feels instantaneous) | **~250–450 ms** (perceptible UI pause) |
| **Replay Window** | Up to 1 hour | **0 seconds (Consumed on first use)** |
| **Apple Attest Quota Impact** | Minimal (1 attestation/hour) | Higher (1 attestation per request) |
| **Recommended Use Case** | Interactive UI, continuous triage, autocomplete | High-value decisions, billing actions, batch jobs |

### Enabling Replay Protection in Production

1. **Grant IAM Permissions:**
   The function's compute service account requires the `roles/appcheck.tokenVerifier` role to consume tokens:
   ```bash
   gcloud projects add-iam-policy-binding <PROJECT_ID> \
     --member="serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com" \
     --role="roles/appcheck.tokenVerifier"
   ```

2. **Configure Cloud Function:**
   Set the environment variable `CONSUME_APP_CHECK=true` in your function's environment.

3. **Configure Swift Client:**
   Initialize any hosted `LanguageModel` with `.appCheck` and `limitedUseToken()`:
   ```swift
   let model = GeminiLanguageModel(
       proxyEndpoint: proxyURL,
       credential: .appCheck {
           try await AppCheck.appCheck().limitedUseToken().token
       }
   )
   ```
