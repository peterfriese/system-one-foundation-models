# Workspace Agent Directives & Principles

Welcome to the **System One for Apple Foundation Models & ACMD Mobile Engineering** workspace. This repository provides a native bridge between **Apple's Foundation Models framework** (`LanguageModel`, `LanguageModelExecutor`, `@Generable`, `Attachment`) and all **6 System One decision model providers** (`LayaOnDevice` Core ML, `LayaFoundationModels` `laya-serve`, `JevFoundationModels` TypeSafe Cloud, `ClefFoundationModels` Cloudflare Clef 27B/9B, `OpenAIFoundationModels` `gpt-6-luna`, and `GeminiFoundationModels` `gemini-decision-1`) plus universal `ProxyCredential` / `SystemOneProxyBackend` mobile security, alongside 4 tiers of runnable examples (`Examples/Quickstarts/`, `Examples/CLI/`, `Examples/TraitSamples/`, and `Examples/Apps/`).

---

## 🛑 Dynamic On-Demand Workflow Directives

Workflows can be triggered via prompt intent or slash commands:

1. **⚡ Fast-Path Fix Mode (`/fix`, `/fast`)**:
   - For bug fixes, compiler issues, and targeted tweaks.
   - Tech Lead routes directly to platform engineers (`@ios-engineer` / `@android-engineer`) or QA (`@qa-agent`).
   - Platform engineers make targeted edits and verify immediately with test suites (`flowdeck test` / `./gradlew testDebugUnitTest`).

2. **🛠️ Pragmatic Feature Mode (`/feature`, `/build`)**:
   - For standard feature development, ViewModel wiring, and UI additions.
   - Tech Lead drafts a lightweight 2-3 bullet execution plan.
   - Directly delegates implementation to `@ios-engineer` and/or `@android-engineer`.
   - `@senior-architect` is invoked only if the feature crosses 3+ architectural modules or changes core data structures.
   - Verified via FlowDeck (`flowdeck build` & `flowdeck test`) or Gradle.

3. **🏛️ Full Spec-Driven Pipeline (`/spec`, `/plan`)**:
   - For greenfield modules, cross-cutting architectures, multi-tenant sync engines, or book/demo evaluation showcases.
   - Stage 1: **Product Manager Agent** (`@product-manager`) drafts PRD in `docs/prd/`.
   - Stage 2: **Senior Architect Agent** (`@senior-architect`) drafts ADR in `docs/architecture/`.
   - Stage 3: **🛑 User Approval Gate** — Pause and await explicit user sign-off.
   - Stage 4: Native platform engineers implement pure native code.
   - Stage 5: **QA Agent** (`@qa-agent`) verifies and **Code Reviewer Agent** (`@code-reviewer`) audits diffs.
   - Stage 6: **Journal Agent** (`@journal-agent`) & **Learnings Agent** (`@learnings-agent`) log entries in `docs/journal/` and `docs/learnings/`.

4. **🔍 Multi-Agent Audit Mode (`/audit`)**:
   - Invokes `@senior-architect` and `@code-reviewer` in sequence for compliance, concurrency, and security auditing without modifying files.

---

## 🛑 Orchestrator Non-Coding Mandate & Fleet Continuity

1. **Non-Coding Tech Lead**:
   - The primary root agent is strictly the **Tech Lead / Orchestrator** (`@tech-lead`).
   - **NEVER edit source code files or run raw build commands directly from the root agent context.**
   - All code authoring, bug fixes, refactoring, and test executions **MUST** be dispatched to specialized subagents (`ios-engineer`, `qa-agent`, etc.).

2. **Conversational Subagent Continuity**:
   - During iterative feedback and conversational debugging, **DO NOT collapse into a monolithic coding agent**.
   - Dispatch targeted tasks via the `subagent` tool to the relevant specialist.

3. **Mandatory Verification & Knowledge Gates**:
   - Every completed fix/feature requires verification sign-off via `@qa-agent` (including simulator log/state inspection).
   - Major architectural decisions and milestones must trigger trajectory logging via `@journal-agent` and `@docs-writer`.

---

## 🤖 Active Subagent Fleet

- **`tech-lead`**: Primary workflow orchestrator. Coordinates multi-agent mobile pipelines and strictly delegates coding to subagents.
- **`ios-engineer`**: Implements pure native Apple features using Swift 6 strict concurrency, modern SwiftUI (`@Observable`), FactoryKit DI, and FlowDeck.
- **`android-engineer`**: Implements native Android features and fixes with Kotlin/Jetpack tooling and Gradle validation.
- **`senior-architect`**: Analyzes PRDs for technical feasibility, designs data models, creates ADRs, and generates architecture diagrams via Archify.
- **`qa-agent`**: Executes builds, boots simulators via RocketSim/simctl, runs tests, and captures verification proof.
- **`code-reviewer`**: Audits PR diffs against Apple architectural standards, Swift 6 concurrency, and memory safety.
- **`product-manager`**: Interacts with the user, defines product requirements, user stories, and acceptance criteria in `docs/prd/`.
- **`docs-writer`**: Keeps README, architecture specs, PRDs, and API documentation synchronized with codebase changes.
- **`journal-agent`**: Logs daily engineering trajectories, decisions, and progress in `docs/journal/YYYY-MM-DD.md`.
- **`learnings-agent`**: Extracts non-trivial technical discoveries and architectural lessons into publishable articles in `docs/learnings/`.

---

## 🏛️ Architectural Principles & Standards: Jev Foundation Models

When building or updating the core Swift package (`Sources/`):

### 1. Apple-Native Foundation Models Ergonomics
- The primary developer experience must use standard Apple Foundation Models APIs:
  ```swift
  let session = LanguageModelSession(model: JevLanguageModel(apiKey: "..."))
  let response = try await session.respond(to: stateText, generating: MyDecision.self)
  ```
- No proprietary wrapper syntax or non-standard session classes. Conformance to `LanguageModel` and `LanguageModelExecutor` is mandatory.

### 2. Swift 6 Concurrency & Stratos Compliance
- Complete strict concurrency checking (`-strict-concurrency=complete`).
- Value types must naturally conform to `Sendable`.
- Avoid `@unchecked Sendable` unless wrapping proven thread-safe primitives (with explicit comments).
- Do not introduce blocking operations in async contexts.
- Follow **Call-Site First** design (`stratos-swift`): demonstrate the ideal call-site before writing implementation code.

### 3. Jev Decision Primitives Mapping
The bridge translates Foundation Models generation schemas to TypeSafe System One questions:
- `Bool` properties $\to$ Jev **`noul`** (0.0 – 1.0 probability of truth).
- `enum` properties / `anyOf` $\to$ Jev **`choice`** (discrete categorical selection).
- `@Guide(description: "...")` $\to$ question **`instructions`**.
- `@Guide(.range(...))` $\to$ Jev **`score`** (ordinal rubric scoring).
- Bounded decision outputs only: unstructured prose requests without a `@Generable` schema must throw an informative, typed error (`JevError.structuredOutputRequired`).

### 4. Zero External Third-Party Runtime Dependencies
- Keep the library core lightweight.
- Use native `URLSession`, `JSONDecoder`, and `JSONSerialization` for networking. Do not introduce heavy third-party HTTP clients.

### 5. Deterministic, Offline-First Automated Testing
- All core unit tests must be executable without requiring a live `TYPESAFE_API_KEY`.
- Provide a `MockJevTransport` / `MockJevExecutor` to test schema translation, error handling, and JSON response synthesis offline.
- Use modern **Swift Testing** (`@Test`, `#expect`) instead of legacy XCTest.

### 6. Tech Note Curation
- Any time an Apple Foundation Models SDK quirk, undocumented behavior, compilation discrepancy, platform restriction, or serialization nuance is discovered or required debugging, immediately document it in `tech-notes/`.
- **File Naming & Structure**:
  - File path: `tech-notes/NNNN-kebab-slug.md` (sequential `max + 1`, e.g. `0005-my-finding.md`).
  - Standard Template: `# NNNN — Short Title`, Metadata (Date, Author, Framework, Upstream), Sections (`## Context`, `## Findings`, `## Implications`, `## Evidence / Sources`).
- **Index & Cross-Referencing**:
  - Always update the index table in `tech-notes/README.md`.
  - Embed inline code comments in relevant Swift files: `// See tech-notes/NNNN-short-title.md`.

### 7. Example & Demonstration Applications (NOT Unit Tests — Strict Real Execution)
- Example applications and CLI demonstrators in `Examples/` and `Examples/TraitSamples/` are production-representative showcases, **NOT unit tests**.
- **NEVER implement mock fallbacks, fake offline simulators, or synthetic response bypasses in example apps.** Mocks in example apps hide configuration errors, provide false confidence, and prevent developers from verifying real model integration.
- If any required credential (e.g. `TYPESAFE_API_KEY`), configuration (e.g. `LAYA_SERVE_URL`), or background process (e.g. `laya-serve` daemon, Firebase Local Emulator) is missing or unreachable:
  1. **Issue a clear, formatted warning banner** explaining what is missing.
  2. **Provide the exact remediation command** (e.g. `export TYPESAFE_API_KEY="..."`, `laya-serve`, or `./run-emulator-and-cli.sh`).
  3. **Terminate immediately with `exit(1)`**.
- Mocks are restricted strictly to automated test suites in `Tests/`.

---

## 📱 Mobile Platform Engineering Standards (`Examples/Apps/`)

### 🍏 Apple Platform (Swift & SwiftUI)
- **Language**: Swift 6 (strict concurrency compliance, `Sendable`, actor isolation, `@MainActor`).
- **UI**: Native SwiftUI with `@Observable` macro (no legacy `ObservableObject`).
- **DI**: FactoryKit container registrations in `Container+*.swift` with `@ObservationIgnored @Injected`.
- **Previews**: Lightweight `#Preview` blocks with `@Previewable @State` and Factory mock overrides.
- **Build & Test Toolchain (MANDATORY)**: **ALWAYS use FlowDeck CLI (`flowdeck`)** as the required, primary tool for Apple builds and tests:
  - Build App: `flowdeck build -w Examples/Apps/MailTriageApp/apps/apple/MailTriageApp.xcodeproj -s MailTriageApp -S "iPhone 18 Pro"`
  - Test App: `flowdeck test -w Examples/Apps/MailTriageApp/apps/apple/MailTriageApp.xcodeproj -s MailTriageApp -S "iPhone 18 Pro"`
  - Package Tests (`AppCore` / `AppUI`):
    - `flowdeck test -p Examples/Apps/MailTriageApp/apps/apple/Packages/AppCore -s AppCore-Package -S "iPhone 18 Pro"`
    - `flowdeck test -p Examples/Apps/MailTriageApp/apps/apple/Packages/AppUI -s AppUI -S "iPhone 18 Pro"`
