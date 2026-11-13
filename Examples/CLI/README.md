# System One Unified CLI (`system-one-cli`) ⚡️

`system-one-cli` is the unified multi-provider command-line showcase for **System One for Apple Foundation Models**. It runs **4 production-representative `LanguageModelSession` workflows** across **all 7 execution modes** (`jev`, `laya`, `laya-ondevice`, `clef`, `openai`, `gemini`, and `proxy`) without changing a single line of domain schema or routing logic.

---

## 🚀 Usage & Global Flags

```bash
swift run system-one-cli [--provider <provider>] <subcommand> [options]
swift run system-one-cli --help
```

- **`-p, --provider <name>`** *(or `--provider=<name>` / `SYSTEM_ONE_PROVIDER` env var; default: `jev`)* — Selects the System One execution provider.
- **`.env` Auto-Discovery** — `CLIEnvironment` automatically reads credentials from shell environment variables first, then falls back to `./.env` or `../.env`.
- **`-h, --help`** — Prints usage and provider summary.

---

## 🧭 All 7 `--provider` Modes & Environment Variables

| `--provider` (Aliases) | Underlying Swift Type | Capabilities | Environment Variables & Prerequisites |
| :--- | :--- | :---: | :--- |
| **`jev`** *(default)* | `JevLanguageModel` | Text | **Required**: `TYPESAFE_API_KEY` |
| **`laya`** (`laya-serve`, `layaserve`) | `LayaLanguageModel` | Text | `LAYA_SERVE_URL` (+ optional `LAYA_API_KEY`) or local `laya-serve` on `LAYA_LOCAL_PORT` (default `8000`) |
| **`laya-ondevice`** (`ondevice`, `coreml`) | `LayaOnDeviceLanguageModel` | Text | `LAYA_MODEL_PATH` (or bundled/CWD `LayaDecisionModel.mlmodelc`) + optional `LAYA_TOKENIZER_PATH` |
| **`clef`** (`cloudflare`) | `ClefLanguageModel` | Text + **Vision** | **Workers AI**: `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`<br>**Custom URL**: `CLEF_URL`<br>**Local Runner**: `CLEF_LOCAL_PORT` (default `8000`) |
| **`openai`** | `OpenAILanguageModel` (`gpt-6-luna`) | Text + **Vision** | **Required**: `OPENAI_API_KEY` |
| **`gemini`** (`google`) | `GeminiLanguageModel` (`gemini-decision-1`) | Text + **Vision** | **Required**: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) |
| **`proxy`** | `SystemOneLanguageModel` (`SystemOneProxyBackend`) | Text + **Vision** | **Required**: `SYSTEM_ONE_PROXY_URL` (or `TYPESAFE_PROXY_URL`; HTTPS or loopback HTTP)<br>**Optional**: `SYSTEM_ONE_PROXY_TOKEN` (Bearer), `SYSTEM_ONE_PROXY_VISION=true\|false` |

---

## 🛠️ Subcommands Reference

### 1. `ticket-triage [TEXT...]` — Calibrated Confidence Routing
Evaluates a customer ticket (default sample or custom trailing text) into `@Generable struct TicketTriage` (`isUrgent: Bool`, `department: Department`, `frustrationLevel: Int` in `0...2`) and gates operational actions (`.auto`, `.confirm`, `.escalate`) through `RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)`.

```bash
# Default ticket across any of the 7 providers:
TYPESAFE_API_KEY="..."                              swift run system-one-cli --provider jev ticket-triage
swift run system-one-cli --provider laya ticket-triage
LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc" swift run system-one-cli --provider laya-ondevice ticket-triage
CLOUDFLARE_ACCOUNT_ID="..." CLOUDFLARE_API_TOKEN="..." swift run system-one-cli --provider clef ticket-triage
OPENAI_API_KEY="sk-..."                             swift run system-one-cli --provider openai ticket-triage
GEMINI_API_KEY="AIza..."                            swift run system-one-cli --provider gemini ticket-triage
SYSTEM_ONE_PROXY_URL="https://..."                  swift run system-one-cli --provider proxy ticket-triage

# Custom inline ticket text:
GEMINI_API_KEY="AIza..." swift run system-one-cli --provider gemini ticket-triage \
  "Production Kubernetes nodes cannot mount persistent volumes across eu-west-1!"
```

---

### 2. `duplicate-article` — Two-Layer Deterministic + Semantic Deduplication
Runs 4 scenarios demonstrating:
1. **Layer 1 (Sub-millisecond Deterministic)**: URL tracking-param stripping (`utm_*`, `fbclid`, `gclid`) and exact title + byline matching.
2. **Layer 2 (Concurrent System One `noul`)**: Parallel `withThrowingTaskGroup` semantic substance comparison (`@Generable ArticleDuplicateDecision`) catching rewritten wire stories while rejecting false-positive competitor stories.
3. **Swift 6 Cooperative Cancellation**: Proves `Task.cancel()` propagates `CancellationError` cleanly without wrapping.

```bash
TYPESAFE_API_KEY="..."                              swift run system-one-cli --provider jev duplicate-article
swift run system-one-cli --provider laya duplicate-article
LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc" swift run system-one-cli --provider laya-ondevice duplicate-article
CLOUDFLARE_ACCOUNT_ID="..." CLOUDFLARE_API_TOKEN="..." swift run system-one-cli --provider clef duplicate-article
OPENAI_API_KEY="sk-..."                             swift run system-one-cli --provider openai duplicate-article
GEMINI_API_KEY="AIza..."                            swift run system-one-cli --provider gemini duplicate-article
SYSTEM_ONE_PROXY_URL="https://..."                  swift run system-one-cli --provider proxy duplicate-article
```

---

### 3. `file-organizer [OPTIONS]` — `DynamicProfile` & Local Secret Redaction
Demonstrates Apple's declarative `LanguageModelSession.DynamicProfile`, live `@SessionPropertyEntry` switching (`session.properties.organizationStrategy = .domain` $\to$ `.workflow` on the **same** session), stateless turn isolation via `.historyTransform`, PDF snippet extraction (`PDFKit`), and `LocalSecretScanner` credential redaction (`Quarantine_Vault/`).

| Option | Description |
| :--- | :--- |
| `--demo` *(default when `--path` omitted)* | Creates an ephemeral 5-file sandbox and evaluates both `.domain` and `.workflow` passes live. |
| `--path <dir>` | Evaluates real files inside `<dir>` (skips hidden files and managed output folders). |
| `--strategy <domain\|workflow>` | Initial `OrganizationStrategy` when using `--path` (default: `domain`). |
| `--dry-run` *(default)* | Prints the audit routing table without moving files on disk. |
| `--apply` | Moves discovered files into `Organized/`, `Workflow/`, `Quarantine_Vault/`, or `Review_Queue/`. |

```bash
# Live 2-pass DynamicProfile sandbox walkthrough across any provider:
TYPESAFE_API_KEY="..."                              swift run system-one-cli --provider jev file-organizer --demo
swift run system-one-cli --provider laya file-organizer --demo
LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc" swift run system-one-cli --provider laya-ondevice file-organizer --demo
CLOUDFLARE_ACCOUNT_ID="..." CLOUDFLARE_API_TOKEN="..." swift run system-one-cli --provider clef file-organizer --demo
OPENAI_API_KEY="sk-..."                             swift run system-one-cli --provider openai file-organizer --demo
GEMINI_API_KEY="AIza..."                            swift run system-one-cli --provider gemini file-organizer --demo
SYSTEM_ONE_PROXY_URL="https://..."                  swift run system-one-cli --provider proxy file-organizer --demo

# Dry-run or apply organization on a real folder:
GEMINI_API_KEY="AIza..." swift run system-one-cli --provider gemini file-organizer --path ~/Downloads --strategy workflow --dry-run
```

---

### 4. `vision-inspect [IMAGE_PATH]` — Multimodal Visual Inspection
Loads a real PNG, JPEG, or WebP image via `ImageIO` (`[IMAGE_PATH]` or `-i, --image <path>`; defaults to bundled [`Examples/Quickstarts/ClefQuickstart/sample.jpg`](../Quickstarts/ClefQuickstart/sample.jpg)), wraps it in `Attachment(cgImage)`, and evaluates `@Generable VisualInspectionDecision` (`isRecognized`, `itemCategory`, `conditionScore`, `safetyApproval`).

> [!NOTE]
> `vision-inspect` requires a vision-capable provider (`clef`, `openai`, `gemini`, or `proxy`). Requesting a text-only provider (`jev`, `laya`, `laya-ondevice`) exits immediately with a capability remediation banner.

```bash
# Default sample photograph across all 4 vision-capable modes:
CLOUDFLARE_ACCOUNT_ID="..." CLOUDFLARE_API_TOKEN="..." swift run system-one-cli --provider clef vision-inspect
CLEF_LOCAL_PORT=8000                                swift run system-one-cli --provider clef vision-inspect
OPENAI_API_KEY="sk-..."                             swift run system-one-cli --provider openai vision-inspect
GEMINI_API_KEY="AIza..."                            swift run system-one-cli --provider gemini vision-inspect
SYSTEM_ONE_PROXY_URL="https://..."                  swift run system-one-cli --provider proxy vision-inspect

# Inspect a custom photograph:
GEMINI_API_KEY="AIza..." swift run system-one-cli --provider gemini vision-inspect --image /path/to/parcel.jpg
```

---

## 🛡️ Strict Real Execution (Principle 7)

Per repository engineering standards, `system-one-cli` never falls back to synthetic mock responses or generated placeholder frames. Missing API keys, unreachable daemons, missing image files, or unsupported provider capabilities emit a formatted remediation banner and exit immediately with status `1`.
