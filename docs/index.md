# System One for Apple Foundation Models Documentation 📚🧠

Welcome to the comprehensive documentation for **System One for Apple Foundation Models**, the Swift 6 library that bridges Apple's native Foundation Models framework (`LanguageModelSession`, `@Generable`, `@Guide`) with **System One decision models**—supporting on-device Core ML on Apple Neural Engine (**Laya**), local/remote self-hosted servers (**`laya-serve`**), open-weight multimodal decision models (**Cloudflare Clef & Clef-Flash**), frontier non-autoregressive classification (**OpenAI Decisions `gpt-6-luna`**), and hosted cloud endpoints (**TypeSafe Jev**).

---

## 🧭 Guides & Specifications

* [**Getting Started**](getting-started.md): "Choose Your Path" onboarding, target selection guide, installation, and running your first query across Core ML, Laya HTTP, Clef, OpenAI Decisions, and Jev Cloud.
* [**Cloudflare Workers AI & Clef Setup**](cloudflare-workers-setup.md): Complete setup guide for evaluating Cloudflare Clef & Clef-Flash edge decision models, managing Workers AI API credentials, configuring AI Gateway, and deploying secure Worker proxies.
* [**CLI & Server Deployment Guide**](laya-cli-guide.md): Developing CLI developer tools with `laya-serve` and bundling standalone Core ML binaries.
* [**Mobile & On-Device Deployment Guide**](laya-mobile-guide.md): On-Device Core ML on Apple Neural Engine, SwiftUI Canvas preview mocking, and Xcode On-Demand Resources (ODR).
* [**Confidence & Noul Routing**](confidence-routing.md): Operational decision gating (`.auto`, `.confirm`, `.escalate`), epistemic uncertainty in the undecided band ($0.35\dots0.65$), and rubric scoring.
* [**HTTP Resilience & Retries**](resilience-and-retries.md): Configurable `RetryPolicy`, exponential backoff with jitter, RFC 9110 `Retry-After`, and cooperative Swift Concurrency cancellation.
* [**Mobile Security Guide**](mobile-security.md): Deploying securely to iOS/visionOS using Firebase App Check, Apple App Attest, and Cloud Function proxies.
* [**Keychain Sharing & Data Protection Setup**](keychain-setup.md): Configuring macOS & iOS Data Protection Keychain access groups in Xcode, `@KeychainStorage` property wrapper architecture, and troubleshooting `errSecMissingEntitlement`.
* [**Architecture Decision Records (ADRs)**](architecture/):
  * [ADR: Mail Triage System One Engine](architecture/ADR-2026-09-25-mail-triage-system-one-engine.md)
  * [ADR: Cloudflare Clef Foundation Models Integration](architecture/ADR-2026-10-03-01-clef-foundation-models-integration.md)
  * [ADR: OpenAI Decisions API Integration](architecture/ADR-2026-10-08-01-openai-decisions-models-integration.md)
* [**Product Requirements Documents (PRDs)**](prd/):
  * [PRD: Mail Triage System One Engine](prd/PRD-2026-09-25-mail-triage-system-one-engine.md)
  * [PRD: Clef Multimodal Decision Models](prd/PRD-2026-10-03-clef-decision-models.md)
  * [PRD: OpenAI Decisions Models (`gpt-6-luna`)](prd/PRD-2026-10-08-openai-decisions-models.md)
* [**Repository Audit Sweep & Remediation Report**](plans/AUDIT-SWEEP-2026-10-09.md): Complete repository-wide adversarial audit, dead code cleanup, security hardening, and Principle 7 compliance sweep.
* [**Type Mapping Guide**](mapping-guide.md): Comprehensive reference mapping `@Generable` Swift types (`Bool`, `enum`, ranges) to System One primitives (`noul`, `choice`, `score`).
* [**Mobile Application Blueprints**](example-app-ideas.md): Production-ready mobile application blueprints demonstrating sub-100ms decision capabilities across iOS, watchOS, and visionOS.
* [**Contributing Guide**](../CONTRIBUTING.md): Setup, offline testing protocol, coding standards, and Tech Note curation for contributors.

---

## 📱 Sample Applications & Reference Demos

* [**Examples Catalog (`Examples/README.md`)**](../Examples/README.md): Comprehensive comparison and run instructions for all reference applications and CLI tools.
* [**MailTriageApp (`Examples/MailTriageApp/`)**](../Examples/MailTriageApp/README.md): **Flagship Reference App** for macOS and iOS. Features 3-pane split view, 7 selectable execution backends (On-Device Core ML, Local laya-serve, Hosted VPC, Cloudflare Clef, OpenAI Decisions, Jev Cloud, Generative Baseline), urgency priority tokens, batch triage with cancellation, and pre-seeded reference truth benchmarks.
* [**Clef Camera Scanner (`Examples/ClefCameraScanner/`)**](../Examples/ClefCameraScanner/README.md): Real-time camera viewfinder app for macOS and iOS inspecting live physical objects with Cloudflare Clef multimodal decision models and Liquid Glass HUD overlays.
* [**Clef Multimodal Demo (`Examples/ClefDemo/`)**](../Examples/ClefDemo/README.md): CLI executable demonstrating single forward-pass multimodal evaluation with visual image attachments or synthetic CoreGraphics test frames.
* [**OpenAI Decisions Demo (`Examples/OpenAIDemo/`)**](../Examples/OpenAIDemo/README.md): CLI executable evaluating strongly typed `@Generable` models against OpenAI Decisions API (`gpt-6-luna`) with zero output token billing and enterprise multi-tenant headers.
* [**Nutrition Label Scanner (`Examples/NutritionLabelScannerApp/`)**](../Examples/NutritionLabelScannerApp/): Camera-first iOS application evaluating dietary safety and allergens against live OCR packaging and Open Food Facts with Apple Liquid Glass design.
* [**Local Laya Demo (`Examples/LayaDemo/`)**](../Examples/LayaDemo/README.md): Zero-key CLI tool connecting to local or remote `laya-serve` instances via `POST /v1/systemone`.
* [**Ticket Triage Demo (`Examples/TicketTriageDemo/`)**](../Examples/TicketTriageDemo/README.md): Customer inquiry routing with `RetryPolicy` resilience, multi-primitive `@Generable` schema, and confidence-gated operations.
* [**Duplicate Article Detection (`Examples/DuplicateArticleDemo/`)**](../Examples/DuplicateArticleDemo/README.md): Two-layer deduplication engine using deterministic checks, System One semantic evaluation, and cooperative cancellation.
* [**Directory Organizer (`Examples/FileOrganizerDemo/`)**](../Examples/FileOrganizerDemo/README.md): Declarative Dynamic Profiles (`LanguageModelSession.DynamicProfile`), reactive state adaptation with `@SessionPropertyEntry`, and turn isolation.

---

## 🔧 Tools & Integrations

* [**Core ML Converter (`Tools/CoreMLConverter/`)**](../Tools/CoreMLConverter/README.md): Python scripts using `coremltools` to convert Hugging Face Laya checkpoints (`ModernBERT` 421M and `mmBERT` 322M) into Apple Neural Engine-optimized `.mlpackage` bundles.
* [**Clef Local Runner (`Tools/ClefLocalRunner/`)**](../Tools/ClefLocalRunner/README.md): Local inference runner recipe executing quantized Clef and Clef-Flash weights on Apple Silicon Metal Performance Shaders (MPS).
* [**Firebase App Check Proxy (`Integrations/FirebaseAppCheckProxy/`)**](../Integrations/FirebaseAppCheckProxy/README.md): Reference zero-trust mobile proxy architecture using Firebase App Check and Apple App Attest to protect cloud endpoints from unauthorized API access.

---

## 🛠️ Field Notes & Trajectory

* [**Research & Architectural Deep-Dives (`docs/learnings/`)**](learnings/):
  * [Bridging Cloudflare Clef Multimodal Decision Models to Apple Foundation Models in Swift 6](learnings/2026-10-05-bridging-cloudflare-clef-to-apple-foundation-models.md)
  * [Bridging OpenAI Decisions API (`gpt-6-luna`) to Apple Foundation Models in Swift 6](learnings/2026-10-08-bridging-openai-decisions-api-to-apple-foundation-models.md)
* [**Tech Notes (`tech-notes/`)**](../tech-notes/README.md): Curated technical findings, Foundation Models SDK quirks, and runtime observations (Tech Notes 0001 through 0017).
* [**Engineering Journal (`docs/journal/`)**](journal/OVERVIEW.md): Chronological daily engineering trajectory, decisions, and remediation milestones.
* [**Repository Audit & Hardening Sweep**](plans/AUDIT-SWEEP-2026-10-09.md): Complete findings, verification matrices, and remediation tracking.
