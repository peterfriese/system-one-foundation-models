# MailTriageApp 📬⚡️

`MailTriageApp` is the flagship native Apple reference application demonstrating end-to-end integration of **System One decision models** into Apple's **Foundation Models framework** (`LanguageModel`, `LanguageModelSession`, `@Generable`) on macOS 27+ and iOS 27+.

Built with native Swift 6 and modern SwiftUI, `MailTriageApp` illustrates how to evaluate strongly typed decisions against email context in single-digit to low-double-digit milliseconds with calibrated confidence, zero text-generation hallucinations, and **9 hot-swappable execution backends** covering every System One provider, authenticated reverse proxy gateways, and Apple's on-device generative LLM baseline.

---

## 📸 Screenshots

| macOS 3-Pane Triage View | iOS Compact Triage View |
| :---: | :---: |
| ![MailTriageApp macOS Triaged View](../../../docs/plans/screenshot-mailtriage-triaged.png) | ![MailTriageApp iOS View](../../../docs/plans/screenshot-mailtriage-ios.png) |
| *Split-view desktop experience with Liquid Glass banner, urgency tokens, and action stubs* | *Adaptive mobile layout with inline urgency badges and swipe actions* |

---

## ✨ Features

- **Native Mail Navigation**: Standard 3-pane split view (`NavigationSplitView`) on macOS and adaptive column navigation on iOS. Includes mailboxes for Inbox, Flagged, Sent, Archive, and Trash, alongside Smart Folders filtered by triage state.
- **Urgency Scoring & Priority Tokens**:
  - `P0 Critical` (Red): Production outages, security breaches, phishing wire threats, and blocking billing issues.
  - `P1 High` (Orange): Urgent enterprise client queries, deadline escalations.
  - `P2 Medium` (Blue): Routine operational emails, internal updates, standard requests.
  - `P3 Low` (Secondary): Paid invoice receipts, newsletters, announcements, and casual notes.
- **Categorical Routing**: Automatic classification into domain categories (`work`, `securityAlerts`, `billing`, `meetings`, `newsletters`, `quarantine`) with calibrated confidence scores.
- **Action Suggestions & Compose Integration**: Suggested actions (`Reply`, `Forward`, `Archive`, `Compose`) automatically pre-populate `ComposeMessageSheet` with the original sender, `Re:`/`Fwd:` subjects, and formatted quoted text bodies.
- **Batch Triage Sheet**: Evaluate hundreds of inbox items concurrently with real-time progress bars, duration tracking, and cooperative cancellation (`Task.checkCancellation()`).
- **Liquid Glass Header Banner**: Contextual triage results banner rendered with high-contrast native materials, displaying model confidence percentages, urgency badges, and quick-action triggers.
- **9 Execution Topologies**: Seamlessly toggle between on-device Apple Neural Engine execution (`LayaOnDevice`), local localhost daemons (`laya-serve`), enterprise VPC clusters, TypeSafe Jev Cloud, Cloudflare Workers AI (`Clef`), OpenAI Decisions (`gpt-6-luna`), Google Gemini Decisions (`gemini-decision-1`), universal Authenticated Reverse Proxy gateways (`SystemOneProxyBackend`), and Apple Intelligence generative LLM baselines.

---

## 🔌 9 Selectable Execution Backends

Switch backends dynamically via the **Approach dropdown** in the message list toolbar or in the **Settings** view (`Cmd + ,` on macOS) without restarting the application:

| Backend | Mode | Target / Driver | Latency | Network | Secrets | Best For |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **On-Device Core ML** | On-Device | `LayaOnDeviceLanguageModel` via Core ML | 5–12 ms | ❌ None | ❌ None | 100% air-gapped privacy on Apple Neural Engine (ANE) & GPU. Zero network data leakage. |
| **Local laya-serve** | Local HTTP | `LayaLanguageModel` to `http://127.0.0.1:8000` | 8–15 ms | ✅ Local | ❌ None | Developer workstations running `laya-serve` via Docker or Python. Zero API costs. |
| **Hosted VPC** | Enterprise HTTP | `LayaLanguageModel` to `https://api.impossibl.com/v1` | 40–70 ms | ✅ WAN | ⚪ Optional | Private enterprise container deployment behind corporate firewall or internal VPC. |
| **Jev Cloud API** | Cloud HTTPS | `JevLanguageModel` to `https://api.typesafe.ai` | 60–90 ms | ✅ Cloud | ✅ Key | TypeSafe AI managed cloud endpoints with automated exponential backoff retries. |
| **Cloudflare Clef** | Edge HTTPS | `ClefLanguageModel` via Cloudflare Workers AI | < 100 ms | ✅ Edge | ✅ Token | Global serverless edge evaluation across 330+ cities using multimodal `@cf/cloudflare/clef-flash`. |
| **OpenAI Decisions** | Cloud HTTPS | `OpenAIDecisionsLanguageModel` (`gpt-6-luna`) | 40–80 ms | ✅ Cloud | ✅ Key | Multimodal non-autoregressive decision computing on `POST /v1/decisions` ($0.10/1M input, $0.00 output). |
| **Google Gemini Decisions** | Cloud HTTPS | `GeminiDecisionsLanguageModel` (`gemini-decision-1`) | 50–120 ms | ✅ Cloud | ✅ Key | Multimodal decision evaluation up to 256K context & 1,000 questions at $0.10/1M input tokens. |
| **Authenticated Proxy** | Gateway HTTPS | `SystemOneLanguageModel(proxyEndpoint:credential:)` | 35–85 ms | ✅ Gateway | ⚪ Bearer / App Check | Production mobile gateways (Firebase App Check, Cloudflare Access, custom JWT) routing to any upstream System One provider without shipping API keys in the client binary. |
| **Generative Baseline** | On-Device LLM | `LanguageModelSession` via Apple Intelligence | 800–1,200 ms | ❌ None | ❌ None | Standard ~3B autoregressive text LLM for latency, token efficiency, and determinism comparisons. |

> [!NOTE]
> `MockSystemOneBackend` and isolated test doubles in `Tests/` provide deterministic offline evaluation during automated unit testing, while the shipping `MailTriageApp` binary executes strictly real inference per `AGENTS.md` Principle 7.

---

## 🛡️ Configuring Authenticated Proxy (`SystemOneProxyBackend`)

For consumer mobile deployments where provider API keys must never be embedded on-device, select **Authenticated Proxy** (`reverseProxy`):

1. Open **Settings** (`Cmd + ,` on macOS or the ellipsis menu on iOS) and locate the **Authenticated Proxy (SystemOneProxyBackend)** card.
2. Enter your **Proxy Endpoint URL** (for example `https://gateway.example.com/v1/systemone`, or `http://127.0.0.1:5001/...` when testing against a local emulator). `ProxyEndpointValidator` automatically enforces HTTPS for all non-loopback hosts and rejects embedded URL credentials.
3. Choose a **Credential Mode**:
   - **Bearer Token (`Authorization`)**: Injects `Authorization: Bearer <token>` via `ProxyCredential.bearer`.
   - **App Check / Custom Header**: Injects `X-Firebase-AppCheck: <token>` (or any custom attestation header) via `ProxyCredential.appCheck`.
4. Optionally configure defaults via environment variables or `.env`:
   ```bash
   export SYSTEM_ONE_PROXY_URL="https://gateway.example.com/v1/systemone" # or TYPESAFE_PROXY_URL
   export SYSTEM_ONE_PROXY_TOKEN="your-jwt-or-app-check-token"
   ```

---

## ⚡️ Configuring Cloudflare Clef & Cloud Decision Providers

1. Open **Settings** (`Cmd + ,` on macOS or tap **Settings...** on iOS).
2. Configure any combination of cloud/edge decision providers:
   - **TypeSafe Jev Cloud**: `TYPESAFE_API_KEY`
   - **Cloudflare Clef**: `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`
   - **OpenAI Decisions**: `OPENAI_API_KEY` (plus optional `OpenAI-Organization` / `OpenAI-Project`)
   - **Google Gemini Decisions**: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)
3. Click **Probe** on any card (or **Probe All Backends**) to verify live connectivity and round-trip latency.
4. Select your preferred backend in the toolbar **Approach** picker and click **Sparkles** (`✨`) to triage individual messages or the entire inbox concurrently.

> For a complete setup guide including Cloudflare AI Gateway caching and custom reverse proxy deployment, see [Cloudflare Workers AI and Clef Setup Guide](../../../docs/cloudflare-workers-setup.md).

---

## 💾 Pre-Seeded Fixtures & Reference Truth Benchmark

- **500 Realistic Sample Emails**: Generated deterministically in `InboxData`, spanning CI/CD build failures, P0 database outages, billing invoices, phishing wire threats (with synthetic PNG screenshot attachments for multimodal models), and engineering digests.
- **Reference Benchmark (`benchmark-truth.json`)**: Bundled in `AppCore` and used to compare live session latency and throughput against reference hardware baselines.
- **Self-Healing Storage**: If Application Support benchmark files are absent, `BenchmarkTruthStore` falls back cleanly to the immutable bundled reference in `Bundle.module`.

---

## 🏛️ Architecture & Code Layout

The project follows clean architectural boundaries with Swift 6 complete strict concurrency:

```text
Examples/Apps/MailTriageApp/
├── README.md
├── justfile                                 # Local FlowDeck & SwiftPM task recipes
└── apps/
    └── apple/
        ├── MailTriageApp.xcodeproj          # Xcode project (iOS & macOS targets)
        ├── MailTriageApp/                   # App entrypoint, menu commands, window lifecycle
        └── Packages/
            ├── AppCore/                     # Pure domain logic, BenchmarkCLI & service layers
            │   ├── Sources/AppCore/
            │   │   ├── Data/                # InboxData deterministic 500-email generator
            │   │   ├── Models/              # Email, EmailTriageDecision, TriageBackend, RoutingPolicy
            │   │   └── Services/            # TriageEngine, BackendHealthProbeService, CoreMLModelManager, KeychainService
            │   ├── Sources/BenchmarkCLI/    # Scientific CLI benchmark runner across all 9 backends
            │   └── Tests/AppCoreTests/      # 100+ offline unit tests
            └── AppUI/                       # Pure declarative SwiftUI presentation
                ├── Sources/AppUI/Views/     # MailSplitView, MailListView, MailDetailView, SettingsView
                └── Tests/AppUITests/        # SwiftUI view & state tests
```

---

## 🛠️ Building & Running

### Option A: Standard Xcode GUI

1. Open `Examples/Apps/MailTriageApp/apps/apple/MailTriageApp.xcodeproj` in Xcode 27+.
2. In the scheme selector, choose **MailTriageApp**.
3. Select **My Mac** or **iPhone 18 Pro** (or any iOS 27.0+ Simulator) and press **Cmd + R**.

### Option B: FlowDeck CLI (1.26.5+) & SwiftPM

```bash
# Navigate to application folder
cd Examples/Apps/MailTriageApp

# Build iOS/macOS application target with zero-warning verification
flowdeck build -w apps/apple/MailTriageApp.xcodeproj -s MailTriageApp -S "iPhone 18 Pro" --show-warnings

# Run AppCore & AppUI package test suites on iOS Simulator via FlowDeck
flowdeck test -p apps/apple/Packages/AppCore -s AppCore-Package -S "iPhone 18 Pro"
flowdeck test -p apps/apple/Packages/AppUI -s AppUI -S "iPhone 18 Pro"

# Or run fast macOS host unit tests directly via SwiftPM
swift test --package-path apps/apple/Packages/AppCore
swift test --package-path apps/apple/Packages/AppUI
```

### Option C: Local `justfile` Shortcuts

From inside `Examples/Apps/MailTriageApp`:

```bash
just build       # Build MailTriageApp via FlowDeck (--show-warnings)
just test        # Run AppCore + AppUI iOS Simulator test suites via FlowDeck
just test-core   # Run AppCore package tests via FlowDeck
just test-ui     # Run AppUI package tests via FlowDeck
just benchmark   # Run BenchmarkCLI against reachable backends
```

---

## 🔒 Security & Credentials

- **API Keys, Proxy Tokens & Edge Credentials**: Secrets entered in **Settings** or discovered in the environment/`.env` (`TYPESAFE_API_KEY`, `CLOUDFLARE_API_TOKEN`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `SYSTEM_ONE_PROXY_TOKEN`) are stored in the macOS/iOS **Data Protection Keychain** via `KeychainService` (`kSecUseDataProtectionKeychain = true`). See the [macOS & iOS Keychain Sharing Setup Guide](../../../docs/keychain-setup.md) for signing details.
- **Zero Client Secrets in Production**: Use **On-Device Core ML** (`LayaOnDevice`) for 100% air-gapped on-device execution, or **Authenticated Proxy** (`SystemOneProxyBackend` + `ProxyCredential`) to keep cloud API keys strictly on your backend gateway.
