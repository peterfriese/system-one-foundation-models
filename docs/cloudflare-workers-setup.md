# Cloudflare Workers AI and Clef Setup Guide ⚡️☁️

This guide covers configuring and evaluating Cloudflare Clef multimodal System One decision models in native Apple applications using Apple's Foundation Models framework (`LanguageModelSession`, `@Generable`), with step-by-step instructions for `MailTriageApp`.

---

## Overview

[Cloudflare Workers AI](https://developers.cloudflare.com/workers-ai/) provides serverless GPU inference running across Cloudflare's global edge network in over 330 cities. Unlike conversational vision-language models (VLMs) that autoregressively stream text tokens over several seconds, **Cloudflare Clef** models are open-weight multimodal System One decision models designed for high-velocity classification, boolean verification, and rubric scoring:

* **Clef-Flash (9B)**: Built on Qwen3.5, optimized for interactive mobile clients, live camera frame triage, and sub-100ms edge decision latencies.
* **Clef (27B)**: Built on Qwen3.8, optimized for high-resolution document forensics, multi-page KYC verification, and subtle defect analysis.

Both models evaluate structured questions in a **single forward pass** with **zero output tokens** (`output_tokens: 0`), producing calibrated Bayesian confidence scores rather than hallucinated text strings.

---

## Step 1: Acquire Cloudflare Credentials

To evaluate Clef models through Cloudflare Workers AI, you need your Cloudflare **Account ID** and an **API Token** with permissions to execute Workers AI models.

### Finding Your 32-Character Account ID

1. Log in to the [Cloudflare Dashboard](https://dash.cloudflare.com/).
2. Select your account or domain.
3. In the right-hand sidebar of the **Overview** page (or in the URL: `https://dash.cloudflare.com/<account_id>`), locate your **Account ID**.
4. Copy the 32-character hexadecimal string (for example, `0123456789abcdef0123456789abcdef`).

### Creating a Workers AI API Token

1. In the Cloudflare Dashboard, navigate to **My Profile** > **API Tokens** (or visit [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)).
2. Click **Create Token**.
3. Scroll to **Custom Token** and click **Get started**.
4. Configure the token permissions:
   * **Token name**: `MailTriageApp Workers AI Token`
   * **Permissions**:
     * **Account** — **Workers AI** — **Read**
     * **Account** — **Workers AI** — **Edit**
   * **Account Resources**:
     * **Include** — **All accounts** (or select your specific account)
5. Under **TTL**, set an expiration date or leave it open according to your security policy.
6. Click **Continue to summary**, verify the scopes, and click **Create Token**.
7. Copy the generated secret token immediately. Store it securely; Cloudflare does not display this token again.

### Setting Shell Environment Variables (Optional)

`MailTriageApp` automatically loads credentials from your local environment or `.env` file on startup:

```bash
# Add to ~/.zshrc or ~/.bash_profile
export CLOUDFLARE_ACCOUNT_ID="0123456789abcdef0123456789abcdef"
export CLOUDFLARE_API_TOKEN="cf_ai_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Alternatively, create a `.env` file in the application's working directory:

```env
CLOUDFLARE_ACCOUNT_ID=0123456789abcdef0123456789abcdef
CLOUDFLARE_API_TOKEN=cf_ai_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

When present in the environment or `.env`, `MailTriageApp` automatically persists them to the secure system **Keychain** on launch.

---

## Step 2: Configure Cloudflare Clef in MailTriageApp

With credentials acquired, configure the `MailTriageApp` client to execute triage decisions on Cloudflare's edge.

### 1. Open Settings

* **macOS**: Press `Cmd + ,` or choose **MailTriageApp** > **Settings…** from the menu bar.
* **iOS / iPadOS**: Tap the gear icon in the navigation toolbar.

### 2. Enter Credentials in the Cloudflare Clef Card

Scroll to the **Cloudflare Clef** section in Settings:

1. **Account ID**: Paste your 32-character Account ID into the text field.
2. **API Token**: Paste your Workers AI API Token into the secure field. The token is stored directly in the Apple Keychain (`KeychainService`) and is never written to disk or `UserDefaults`.

```
┌────────────────────────────────────────────────────────┐
│ Cloudflare Clef                                        │
├────────────────────────────────────────────────────────┤
│ Account ID          [ 0123456789abcdef0123456789abcdef ]
│ Cloudflare dashboard account identifier                │
├────────────────────────────────────────────────────────┤
│ API Token           [ •••••••••••••••••••••••••••••••• ]
│ Workers AI API token stored securely in Keychain       │
├────────────────────────────────────────────────────────┤
│ Connection Status   ● Connected (52ms)                 │
└────────────────────────────────────────────────────────┘
```

### 3. Verify Live Connection Status

`MailTriageApp` includes an integrated `BackendHealthProbeService`. Below the credential inputs, observe the **Connection Status** row:

* **Checking**: Displays an inline progress spinner while executing an edge probe request.
* **Healthy (Green)**: Indicates successful connection to Cloudflare Workers AI edge nodes, displaying round-trip probe latency (typically `40–80 ms`).
* **Unreachable (Red)**: Displays an error badge with actionable guidance:
  * *Missing Cloudflare Account ID*: Verify the account identifier is pasted correctly.
  * *Missing Cloudflare API Token*: Ensure the secret token is entered.
  * *Unauthorized (HTTP 401)*: Verify the API token has `Workers AI: Read/Edit` permissions.

### 4. Select Cloudflare Clef in the Toolbar Switcher

Return to the main inbox view. In the top toolbar, click the **Approach** menu (displaying the current backend icon and title):

1. Under the **Decision Model Topologies** section, select **Cloudflare Clef** (`Clef Edge`).
2. The toolbar indicator updates to show the `bolt.shield.fill` icon with the label **Clef Edge**.

```
┌──────────────────────────────────────────────┐
│  Inbox  ▾   [ ⚡️ Clef Edge ▾ ] [ ✨ ] [ ⚲ ] │
└──────────────────────────────────────────────┘
```

### 5. Execute Single-Email and Batch Triage

* **Single-Email Triage**:
  1. Select an email from the message list.
  2. Click the **Sparkles** (`✨`) button in the detail pane toolbar.
  3. `MailTriageApp` constructs an Apple Foundation Models `LanguageModelSession` backed by `ClefLanguageModel`, serializes the `@Generable` schema, and evaluates the email at the Cloudflare edge.
  4. The **Liquid Glass** triage banner appears with calculated urgency priority (`P0`–`P3`), category assignment, confidence score, and suggested quick actions.

* **Batch Triage**:
  1. Click the **Sparkles** (`✨`) button located next to the backend dropdown menu in the message list toolbar.
  2. The application evaluates all unread emails in parallel against Cloudflare Workers AI.
  3. A progress counter displays completed items in real time (`processed/total`).
  4. Upon completion, review aggregate statistics and duration metrics across the mailbox.

---

## Step 3: Set Up Cloudflare AI Gateway (Optional / Advanced)

[Cloudflare AI Gateway](https://developers.cloudflare.com/ai-gateway/) sits as a reverse proxy between your mobile clients and Workers AI, providing enterprise caching, rate limiting, and observability.

### Creating an AI Gateway

1. In the [Cloudflare Dashboard](https://dash.cloudflare.com/), select **AI** > **AI Gateway**.
2. Click **Create Gateway**.
3. Name your gateway (for example, `mailtriage-production`).
4. Click **Create**.

### Gateway URL Structure

Cloudflare AI Gateway formats requests using the following endpoint pattern:

```text
https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/workers-ai/@cf/cloudflare/{model}
```

For Clef-Flash:

```text
POST https://gateway.ai.cloudflare.com/v1/0123456789abcdef0123456789abcdef/mailtriage-production/workers-ai/@cf/cloudflare/clef-flash
```

### Swift Integration

In Swift, initialize `ClefLanguageModel` using the `.gateway` case:

```swift
import FoundationModels
import ClefFoundationModels

let endpoint = ClefEndpoint.gateway(
    accountID: "0123456789abcdef0123456789abcdef",
    gatewayID: "mailtriage-production",
    model: .clefFlash
)

let model = ClefLanguageModel(
    endpoint: endpoint,
    apiToken: "cf_ai_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
)

let session = LanguageModelSession(model: model)
```

### Key Gateway Benefits

* **Edge Response Caching**: Identical email bodies or repeated verification prompts return cached evaluations in under **10ms**, without consuming GPU inference credits.
* **Rate Limiting & Cost Caps**: Protects against client runaway loops by configuring requests-per-minute thresholds and monthly spending alerts.
* **Real-Time Analytics**: Visualizes p50/p99 latencies, token consumption, cache hit ratios, and error distributions.

---

## Step 4: Deploy a Custom Cloudflare Worker Reverse Proxy (Optional / Enterprise)

Embedding master Cloudflare API tokens directly into distributed client binaries is discouraged for enterprise mobile deployments. Deploying a lightweight Cloudflare Worker as a reverse proxy enables authenticating mobile clients via **JSON Web Tokens (JWT)**, session tokens, or **Firebase App Check / Apple App Attest**.

```
┌─────────────────────┐       JWT / App Check        ┌─────────────────────────────┐
│  MailTriageApp      │ ───────────────────────────► │  Cloudflare Worker Proxy    │
│  (iOS / macOS)      │                              │  (Validates client identity)│
└─────────────────────┘                              └──────────────┬──────────────┘
                                                                    │ env.AI.run(...)
                                                                    ▼
                                                     ┌─────────────────────────────┐
                                                     │  Workers AI (@cf/.../clef)  │
                                                     │  (Master token stays hidden)│
                                                     └─────────────────────────────┘
```

### Project Setup

Initialize a new Worker project using Wrangler:

```bash
npm create cloudflare@latest clef-proxy -- --type hello-world-ts
cd clef-proxy
```

### 1. `wrangler.toml`

Configure the Workers AI binding in your `wrangler.toml`:

```toml
name = "clef-edge-proxy"
main = "src/index.ts"
compatibility_date = "2024-04-01"

[ai]
binding = "AI"

[vars]
ENVIRONMENT = "production"
```

### 2. `src/index.ts`

Implement request validation, client authentication, and invocation of `@cf/cloudflare/clef-flash`:

```typescript
export interface Env {
  AI: Ai;
  AUTH_SECRET?: string;
}

interface SystemOneRequestBody {
  state: string;
  model: string;
  questions: Record<string, unknown>;
  images?: string[];
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Only accept POST requests
    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method Not Allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" }
      });
    }

    // 1. Authenticate mobile client (Bearer Token or App Check)
    const authHeader = request.headers.get("Authorization");
    const appCheckToken = request.headers.get("X-Firebase-AppCheck");

    if (!authHeader && !appCheckToken) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: Missing client authentication token" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // Optional: Validate JWT or App Check token here before proceeding

    try {
      const body = (await request.json()) as SystemOneRequestBody;

      // 2. Validate input schema
      if (!body.state || !body.questions) {
        return new Response(
          JSON.stringify({ error: "Bad Request: Missing state or questions" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      // 3. Ensure body model matches regex expected by Workers AI container
      const modelSlug = body.model?.includes("clef") ? "clef-flash" : "clef-flash";

      // 4. Execute Clef-Flash via Workers AI binding
      const aiResponse = await env.AI.run("@cf/cloudflare/clef-flash", {
        state: body.state,
        model: modelSlug,
        questions: body.questions,
        images: body.images ?? []
      });

      // 5. Return standardized System One response
      return new Response(JSON.stringify(aiResponse), {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "private, no-transform"
        }
      });
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Internal Error";
      return new Response(
        JSON.stringify({ error: "Workers AI Execution Failed", details: message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }
};
```

Deploy the worker to Cloudflare's edge:

```bash
npx wrangler deploy
```

In `MailTriageApp`, configure the custom endpoint in Swift:

```swift
let customEndpoint = ClefEndpoint.custom(
    URL(string: "https://clef-edge-proxy.<your-subdomain>.workers.dev")!,
    model: .clefFlash
)
let model = ClefLanguageModel(endpoint: customEndpoint, apiToken: "client-jwt-token")
```

---

## Step 5: Troubleshooting and Error Reference

The following matrix covers common HTTP status codes, edge diagnostics, and remediation steps encountered when integrating Cloudflare Workers AI with the Foundation Models bridge:

| HTTP Status | Error String / Symptom | Root Cause | Remediation |
| :--- | :--- | :--- | :--- |
| **HTTP 400** | `AiError: Bad input: Error: '/model' failed test ^\s*(clef\|clef-flash)\s*$ pattern` | Passed the full catalog path (`@cf/cloudflare/clef-flash`) inside the JSON request body. | Cloudflare expects the short slug (`clef-flash` or `clef`) in the body `/model` parameter, reserving the catalog path exclusively for the URL path. `ClefEndpoint` and `ClefModel` handle this decoupling automatically (Tech Note 0014). |
| **HTTP 401** | `Unauthorized` / `Code 10000: Authentication error` | The API Token is missing, expired, or lacks the necessary permissions. | Verify your token in `dash.cloudflare.com/profile/api-tokens`. Ensure it includes **Account** > **Workers AI** > **Read** and **Edit** permissions. Re-enter the token in Settings. |
| **HTTP 404** | `Model not found` / `Invalid URL` | The URL path omitted the `@cf/cloudflare/` catalog prefix, or the Account ID is mistyped. | Ensure the URL path conforms to `/ai/run/@cf/cloudflare/clef-flash`. Double-check the 32-character Account ID in Settings. |
| **HTTP 413** | `AiError: The estimated number of tokens (745945) exceeded context limit (65536)` | Uncompressed 12MP–48MP mobile camera frames triggered text Byte-Pair Encoding (BPE) tokenization fallback. | Downscale visual attachments to a maximum dimension of **1024px** and compress to **JPEG (quality 0.8)** before serialization. Ensure images are serialized as RFC 2397 Data URLs (`data:image/jpeg;base64,...`) (Tech Note 0015). |
| **HTTP 429** | `Rate limit exceeded` / `Too Many Requests` | The account exceeded concurrent inference allocations or rate thresholds. | `ClefHTTPBackend` automatically applies exponential backoff and jitter via `RetryPolicy`. For high-volume production, configure an **AI Gateway** to cache identical queries. |
| **HTTP 524** | `A timeout occurred (Cloudflare Gateway Timeout)` | Upstream GPU container cold-start delay or network latency exceeded connection timeout. | `RetryPolicy` automatically retries HTTP 524 with randomized jitter. Verify device network connectivity. |
| **Decoding Error** | `The data couldn't be read because it is missing.` | The client expected direct root JSON, but Cloudflare returned a Client API v4 envelope (`{ "result": ... }`). | `ClefHTTPBackend` includes a dual-decoding fallback pipeline that unwraps the v4 `"result"` envelope from Workers AI while remaining compatible with direct root responses from local runners (Tech Note 0016). |

---

## Related Documentation

* [Bridging Cloudflare Clef Multimodal Decision Models to Apple Foundation Models](learnings/2026-10-05-bridging-cloudflare-clef-to-apple-foundation-models.md)
* [Tech Note 0014: Workers AI Model Schema Nuance & Identifier Decoupling](../tech-notes/0014-cloudflare-workers-ai-model-schema-nuance.md)
* [Tech Note 0015: Clef Multimodal Token Estimation & Camera Downscaling](../tech-notes/0015-clef-multimodal-token-estimation-and-data-url-encoding.md)
* [Tech Note 0016: Cloudflare Workers AI v4 Response Envelope](../tech-notes/0016-cloudflare-workers-ai-v4-response-envelope.md)
* [Confidence & Routing Policies](confidence-routing.md)
* [HTTP Resilience & Retries](resilience-and-retries.md)
