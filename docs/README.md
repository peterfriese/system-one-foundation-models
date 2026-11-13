# System One for Apple Foundation Models — Documentation Hub 📚🧠

Welcome to the documentation hub for **System One for Apple Foundation Models**, the zero-dependency Swift 6 bridge connecting Apple's native [`FoundationModels`](https://developer.apple.com/documentation/foundationmodels) framework (`LanguageModelSession`, `@Generable`, `@Guide`, `Attachment`) to all **6 System One decision model providers** plus vendor-agnostic mobile reverse proxies (`ProxyCredential` / `SystemOneProxyBackend`).

---

## 🧭 Core Developer Guides

| Guide | What It Covers |
| :--- | :--- |
| [**Getting Started**](getting-started.md) | Per-provider onboarding across **Laya On-Device** (`.mlmodelc`), **Laya HTTP** (`laya-serve` / VPC), **TypeSafe Jev**, **Cloudflare Clef** (Workers AI / AI Gateway / Local Runner), **OpenAI Decisions** (`gpt-6-luna`), and **Google Gemini Decisions** (`gemini-decision-1`). |
| [**Decision Shortcuts Reference**](decision-shortcuts.md) | Complete API guide to `session.probability(of:)`, `session.choice(_:)`, `session.score(_:)`, `Choosable`, `Choice`, `ScoreResult`, and multimodal `@PromptBuilder` `Attachment` overloads. |
| [**Mobile Security & `ProxyCredential`**](mobile-security.md) | Zero-secret client deployments with `ProxyCredential` (`.appCheck`, `.bearer`, `.header`, `.custom`), `ProxyEndpointValidator`, `SystemOneProxyBackend`, Firebase App Check, and Apple App Attest. |
| [**Type Mapping Guide**](mapping-guide.md) | Exact rules translating `@Generable` Swift `Bool`, `enum`, `@Guide(.range(...))`, and nested structs into `noul`, `choice`, and `score` primitives. |
| [**Confidence & Epistemic Routing**](confidence-routing.md) | Operational gating (`.auto`, `.confirm`, `.escalate`), epistemic uncertainty inside the undecided band ($0.35\dots0.65$), `NoulJudgement`, and `ScoreValue` telemetry. |
| [**HTTP Resilience & Retries**](resilience-and-retries.md) | Configurable `RetryPolicy`, exponential backoff with jitter, RFC 9110 `Retry-After` parsing, fail-fast auth handling, and cooperative Swift 6 cancellation. |
| [**Cloudflare Workers AI & Clef Setup**](cloudflare-workers-setup.md) | Provisioning Workers AI credentials, configuring Cloudflare AI Gateway caching/analytics, and deploying edge Worker proxies for Clef 27B & Clef-Flash 9B. |
| [**CLI & Server Deployment Guide**](laya-cli-guide.md) | Building macOS/Linux CLI workflows and server-side Swift services backed by `laya-serve` or standalone Core ML bundles. |
| [**Mobile & On-Device Deployment Guide**](laya-mobile-guide.md) | Running Laya on the Apple Neural Engine (ANE), SwiftUI `#Preview` mocking, and On-Demand Resources (ODR). |
| [**Keychain Sharing & Data Protection**](keychain-setup.md) | macOS & iOS Data Protection Keychain entitlements, `@KeychainStorage`, and troubleshooting `errSecMissingEntitlement` (`-34018`). |
| [**Mobile Application Blueprints**](example-app-ideas.md) | Architectural blueprints for sub-100ms decision workflows across iOS, watchOS, and visionOS. |

---

## 🏛️ Specifications, Architecture & Research

| Directory / Index | Description |
| :--- | :--- |
| [**Architecture Decision Records (`docs/architecture/`)**](architecture/README.md) | Index of all 5 ADRs covering the System One engine, Cloudflare Clef multimodal bridge, OpenAI Decisions (`gpt-6-luna`), Google Gemini Decisions (`gemini-decision-1`), and universal `ProxyCredential`. |
| [**Product Requirements (`docs/prd/`)**](prd/README.md) | Index of all 5 PRDs defining user stories, latency budgets, guardrails, and acceptance criteria. |
| [**Tech Notes (`tech-notes/`)**](../tech-notes/README.md) | Curated deep-dives (`0001`–`0019`) documenting Apple `FoundationModels` SDK quirks, wire protocol nuances, Core ML tensor shapes, and cross-provider homogeneity. |
| [**Engineering Learnings (`docs/learnings/`)**](learnings/) | Long-form technical articles:<br>• [Bridging Cloudflare Clef Multimodal Decision Models to Apple Foundation Models](learnings/2026-10-05-bridging-cloudflare-clef-to-apple-foundation-models.md)<br>• [Bridging OpenAI Decisions API (`gpt-6-luna`) to Apple Foundation Models](learnings/2026-10-08-bridging-openai-decisions-api-to-apple-foundation-models.md) |
| [**Engineering Journal (`docs/journal/`)**](journal/OVERVIEW.md) | Chronological daily engineering log, architectural milestones, and verification records. |
| [**Audit & Verification Plans (`docs/plans/`)**](plans/AUDIT-SWEEP-2026-10-09.md) | Adversarial security/concurrency audit sweeps and QA verification reports. |

---

## 🗂️ Repository Modules, Examples & Tooling

- **Source Module READMEs**:
  - [`SystemOneCore`](../Sources/SystemOneCore/README.md) • [`LayaOnDevice`](../Sources/LayaOnDevice/README.md) • [`LayaFoundationModels`](../Sources/LayaFoundationModels/README.md) • [`JevFoundationModels`](../Sources/JevFoundationModels/README.md) • [`ClefFoundationModels`](../Sources/ClefFoundationModels/README.md) • [`OpenAIFoundationModels`](../Sources/OpenAIFoundationModels/README.md) • [`GeminiFoundationModels`](../Sources/GeminiFoundationModels/README.md)
- **4-Tier Examples Catalog ([`Examples/README.md`](../Examples/README.md))**:
  - [Tier 1: `< 10`-Line Quickstarts (`Examples/Quickstarts/`)](../Examples/Quickstarts/README.md)
  - [Tier 2: Unified Multi-Provider CLI (`Examples/CLI/`)](../Examples/CLI/README.md)
  - [Tier 3: Swift 6.1 Package Trait Samples (`Examples/TraitSamples/`)](../Examples/TraitSamples/README.md)
  - [Tier 4: SwiftUI Reference Apps (`Examples/Apps/`)](../Examples/Apps/README.md)
- **Ecosystem & Contributors**:
  - [Proxy Integrations (`Integrations/README.md`)](../Integrations/README.md) • [Local Inference & Conversion Tools (`Tools/README.md`)](../Tools/README.md)
  - [Deterministic Offline Tests (`Tests/README.md`)](../Tests/README.md) • [AI Coding Agent Skills (`skills/README.md`)](../skills/README.md)
  - [Contributing Guide (`CONTRIBUTING.md`)](../CONTRIBUTING.md)
