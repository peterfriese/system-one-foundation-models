# MailTriageApp 📬⚡️

`MailTriageApp` is the flagship native Apple reference application demonstrating end-to-end integration of **System One decision models** into Apple's **Foundation Models framework** (`LanguageModel`, `LanguageModelSession`, `@Generable`) on macOS 27+ and iOS 27+.

Built with native Swift 6 and modern SwiftUI, `MailTriageApp` illustrates how to evaluate strongly typed decisions against email context in single-digit to low-double-digit milliseconds with calibrated confidence, zero text-generation hallucinations, and 6 hot-swappable execution backends.

---

## 📸 Screenshots

| macOS 3-Pane Triage View | iOS Compact Triage View |
| :---: | :---: |
| ![MailTriageApp macOS Triaged View](../../docs/plans/screenshot-mailtriage-triaged.png) | ![MailTriageApp iOS View](../../docs/plans/screenshot-mailtriage-ios.png) |
| *Split-view desktop experience with Liquid Glass banner, urgency tokens, and action stubs* | *Adaptive mobile layout with inline urgency badges and swipe actions* |

---

## ✨ Features

- **Native Mail Navigation**: Standard 3-pane split view (`NavigationSplitView`) on macOS and adaptive column navigation on iOS. Includes mailboxes for Inbox, Flagged, Sent, Archive, and Trash, alongside Smart Folders filtered by triage state.
- **Urgency Scoring & Priority Tokens**:
  - `P0 Critical` (Red): Production outages, security breaches, and blocking billing issues.
  - `P1 High` (Orange): Urgent enterprise client queries, deadline escalations.
  - `P2 Normal` (Blue): Routine operational emails, internal updates, standard requests.
  - `P3 Low` (Secondary): Newsletters, announcements, marketing correspondence.
- **Categorical Routing**: Automatic classification into domain categories (`security`, `billing`, `support`, `inquiry`, `marketing`) with calibrated confidence scores.
- **Action Suggestions & Compose Integration**: Suggested actions (`Reply`, `Forward`, `Archive`, `Compose`) automatically pre-populate `ComposeMessageSheet` with the original sender, `Re:`/`Fwd:` subjects, and formatted quoted text bodies.
- **Batch Triage Sheet**: Evaluate hundreds of inbox items concurrently with real-time progress bars, duration tracking, and cooperative cancellation (`Task.checkCancellation()`).
- **Liquid Glass Header Banner**: Contextual triage results banner rendered with high-contrast native materials, displaying model confidence percentages, urgency badges, and quick-action triggers.
- **6 Execution Topologies**: Seamlessly toggle between on-device Apple Neural Engine execution, local localhost daemons, enterprise VPC clusters, managed cloud SaaS, Cloudflare Workers AI global edge, and generative LLM baselines.

---

## 🔌 6 Selectable Execution Backends

Switch backends dynamically via the **Approach dropdown** in the message list toolbar or in the **Settings** view (`Cmd + ,` on macOS) without restarting the application:

| Backend | Mode | Target / Driver | Latency | Network | Secrets | Best For |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **On-Device Core ML** | On-Device | `LayaOnDeviceLanguageModel` via Core ML | 5–12 ms | ❌ None | ❌ None | 100% air-gapped privacy on Apple Neural Engine (ANE) & GPU. Zero network data leakage. |
| **Local laya-serve** | Local HTTP | `LayaLanguageModel` to `http://127.0.0.1:8000` | 8–15 ms | ✅ Local | ❌ None | Developer workstations running `laya-serve` via Docker or Python. Zero API costs. |
| **Hosted VPC** | Enterprise HTTP | `LayaLanguageModel` to `https://api.impossibl.com/v1` | 40–70 ms | ✅ WAN | ❌ None | Private enterprise container deployment behind corporate firewall or internal VPC. |
| **Jev Cloud API** | Cloud HTTPS | `JevLanguageModel` to `https://api.typesafe.ai` | 60–90 ms | ✅ Cloud | ✅ Key | TypeSafe AI managed cloud endpoints with automated exponential backoff retries. |
| **Cloudflare Clef** | Edge HTTPS | `ClefLanguageModel` via Cloudflare Workers AI | < 100 ms | ✅ Edge | ✅ Token | Global serverless edge evaluation across 330+ cities using open-weight `@cf/cloudflare/clef-flash`. |
| **Generative Baseline** | On-Device LLM | `LanguageModelSession` via Apple Intelligence | 800–1,200 ms | ❌ None | ❌ None | Standard ~3B autoregressive text LLM for latency, token efficiency, and determinism comparisons. |

> [!NOTE]
> `MockSystemOneBackend` is also provided in the core package and test suites for instant, deterministic offline evaluation during unit testing and SwiftUI Canvas Previews.

---

## ⚡️ Configuring and Using Cloudflare Clef

`MailTriageApp` includes native support for evaluating emails using Cloudflare's open-weight **Clef-Flash (9B)** multimodal decision model hosted on Cloudflare Workers AI.

### 1. Enter Credentials in Settings

1. Open **Settings** (`Cmd + ,` on macOS or tap the gear icon on iOS).
2. Locate the **Cloudflare Clef** card.
3. Enter your 32-character **Account ID** and **Workers AI API Token** (created with `Account` > `Workers AI` > `Read/Edit` permissions).
4. Credentials can also be loaded automatically from the environment or `.env` via `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`. Values are securely stored in the system Keychain via `KeychainService`.

### 2. Verify Health Status

Observe the **Connection Status** row in the Cloudflare Clef card:
- The app executes a lightweight probe request against `ClefEndpoint.workersAI(accountID:model:)`.
- When reachable, the status turns green (**Connected**) and displays live round-trip edge latency (typically 40–80ms).

### 3. Select Backend in the Toolbar

In the message list toolbar, open the **Approach** menu and select **Cloudflare Clef** (labeled **Clef Edge** with the `bolt.shield.fill` icon).

### 4. Triage Emails

- **Single Email**: Select any message and click the **Sparkles** (`✨`) button in the detail view toolbar to evaluate urgency, category, and suggested reply actions.
- **Batch Triage**: Click the **Sparkles** (`✨`) button next to the approach dropdown in the mailbox toolbar to evaluate all unread messages concurrently against Cloudflare Workers AI with real-time progress counters.

> For a complete setup guide including Cloudflare AI Gateway caching and custom reverse proxy deployment, see [Cloudflare Workers AI and Clef Setup Guide](../../docs/cloudflare-workers-setup.md).

---

## 💾 Pre-Seeded Fixtures & Reference Truth Benchmark

- **10 Realistic Sample Emails**: Pre-loaded in the default store, spanning billing chargebacks, database connection timeouts, enterprise renewals, product feedback, and spam newsletters.
- **500-Email Reference Benchmark**: Bundled in `AppCore` (`benchmark-truth.json`) with cryptographic integrity verification. Used by automated unit tests to ensure parity and verify accuracy across all 6 execution backends.
- **Self-Healing Storage**: If local cached emails or Application Support benchmark files are ever corrupted, `BenchmarkTruthStore` automatically falls back to the immutable bundled reference in `Bundle.module`.

---

## 🏛️ Architecture & Code Layout

The project follows clean architectural boundaries with Swift 6 strict concurrency:

```text
apps/
└── apple/
    ├── MailTriageApp.xcodeproj          # Xcode project (iOS & macOS targets)
    ├── MailTriageApp/                   # App entrypoint, menu commands, window lifecycle
    └── Packages/
        ├── AppCore/                     # Pure domain logic & service layers
        │   ├── Sources/AppCore/
        │   │   ├── Models/              # Email, EmailTriageDecision, UrgencyPriority
        │   │   ├── Services/            # TriageEngine, BenchmarkTruthStore, KeychainService
        │   │   ├── Storage/             # MailStore (actor-isolated mailbox repository)
        │   │   └── DI/                  # Container+AppCore.swift (FactoryKit registrations)
        │   └── Tests/AppCoreTests/      # 160+ unit tests with 100% offline coverage
        └── AppUI/                       # Pure declarative SwiftUI presentation
            ├── Sources/AppUI/
            │   ├── Views/               # MailSplitView, MailListView, MailDetailView, SettingsView
            │   ├── Components/          # UrgencyBadge, ActionButton, DecisionActionBarView
            │   └── Sheets/              # BatchTriageSheet, ComposeMessageSheet
            └── Tests/AppUITests/        # UI component and snapshot tests
```

- **Dependency Injection**: Uses [FactoryKit](https://github.com/hmlongco/Factory) for modular, swappable service containers (`Container.shared.triageEngine`, `Container.shared.mailStore`).
- **State Management**: Uses SwiftUI `@Observable` for fine-grained dependency tracking. Zero legacy `ObservableObject` or `@Published` wrappers.
- **Thread Safety**: All mutable state is isolated to Swift 6 actors (`MailStore`, `KeychainService`, `BackendConfigurationStore`).

---

## 🛠️ Building & Running

### Option A: Standard Xcode GUI

1. Open `Examples/MailTriageApp/apps/apple/MailTriageApp.xcodeproj` in Xcode 27+.
2. In the scheme selector, choose **MailTriageApp**.
3. Select your run destination:
   - **My Mac** (Designed for Mac / native macOS)
   - **iPhone 17 Pro** (or any iOS 27.0+ Simulator)
4. Press **Cmd + R** to build and run.
5. Press **Cmd + U** to run all automated unit and integration tests.

### Option B: FlowDeck CLI

FlowDeck provides deterministic, JSON-driven builds and simulator test execution:

```bash
# Navigate to application folder
cd Examples/MailTriageApp

# Build macOS/iOS application target
flowdeck build -w apps/apple/MailTriageApp.xcodeproj -s MailTriageApp

# Run complete application test suite
flowdeck test -w apps/apple/MailTriageApp.xcodeproj -s MailTriageApp

# Run AppCore package test suite
flowdeck test --package-path apps/apple/Packages/AppCore
```

### Option C: Justfile Shortcuts (From Repository Root)

```bash
just mail-build      # Build the application target
just mail-test       # Run application tests
just mail-test-core  # Run AppCore package tests
```

---

## 🔒 Security & Credentials

- **API Keys & Edge Tokens**: When using **Jev Cloud** (`TYPESAFE_API_KEY`) or **Cloudflare Clef** (`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`), credentials entered in **Settings** or discovered in the environment/`.env` are stored exclusively in the macOS/iOS **Keychain** via `KeychainService`. Secrets are never committed, cached in `UserDefaults`, or written to unencrypted disk storage.
- **Keychain Sharing & Data Protection Keychain**: On macOS and iOS, `KeychainService` utilizes Apple's modern Data Protection Keychain (`kSecUseDataProtectionKeychain = true`). To run and debug the app natively on macOS with keychain access enabled, ensure your Apple Developer Team is selected and the **Keychain Sharing** capability is enabled with group `$(AppIdentifierPrefix)dev.peterfriese.mailtriageapp`. For full setup details, architecture, and troubleshooting (such as `errSecMissingEntitlement` / `-34018`), see the [macOS & iOS Keychain Sharing Setup Guide](../../docs/keychain-setup.md).
- **Zero Secrets On-Device**: For production consumer deployments, select **On-Device Core ML** for 100% on-device evaluation without embedding credentials, requiring network connectivity, or routing traffic through third-party services.
