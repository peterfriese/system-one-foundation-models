# Smart Directory Organizer with Dynamic Profiles 📁🤖

Demonstrates Apple Foundation Models **Dynamic Profiles** (`LanguageModelSession.DynamicProfile`), reactive session adaptation with `@SessionPropertyEntry`, turn isolation via `.historyTransform`, and resilient multi-primitive Jev System One file classification.

---

## 🎯 What This Sample Does

1. **Declarative Dynamic Profiles**:
   Defines session profiles using SwiftUI-like syntax (`DynamicProfileBuilder`), binding model configuration, instructions, and audit hooks into a single declarative structure.
2. **Runtime State Adaptation**:
   Modifies `session.properties.organizationStrategy` in-place (switching between **Semantic Domain** and **Workflow Triage**) without destroying or rebuilding the `LanguageModelSession`.
3. **Multi-Primitive Decision Model**:
   In a single sub-100ms request per file, Jev evaluates:
   - **Categorical Choice**: `domain` and `workflowStage`
   - **Calibrated Noul**: Secret and credential detection (`isSensitive`)
   - **Rubric Score**: Categorization confidence (`confidenceScore` 0...3)
4. **Confidence-Based Destination Routing**:
   - Sensitive credentials $\to$ `Quarantine_Vault/`
   - Low-confidence items ($< 2$) $\to$ `Review_Queue/`
   - High-confidence items $\to$ Organized folder hierarchy
5. **Turn Isolation (`.historyTransform`)**:
   Prunes prior file evaluations from the session transcript, keeping batch directory scanning stateless, fast, and token-efficient.

---

## 🚀 Running the Demo

> ⚠️ **Strict Real Execution Mandate**: In compliance with `AGENTS.md` Principle 7, this demonstrator does not use fake mock fallbacks. A valid `TYPESAFE_API_KEY` is required for all evaluations.

### 1. Interactive Sandbox Walkthrough

Runs directory reorganization on sample fixture files demonstrating live profile switching:

```bash
export TYPESAFE_API_KEY="your-api-key"
swift run file-organizer-demo --demo
```

### 2. Organizing an Actual Directory

Preview categorization for any directory in dry-run mode:

```bash
export TYPESAFE_API_KEY="your-api-key"
swift run file-organizer-demo --path ~/Downloads --strategy domain
```

Or add `--apply` to execute real filesystem moves:

```bash
export TYPESAFE_API_KEY="your-api-key"
swift run file-organizer-demo --path ~/Downloads --strategy workflow --apply
```

---

## 💡 How Key Features Work in Code

### 1. Multi-Primitive `@Generable` Schema

```swift
@Generable
struct FileTriageDecision: Sendable {
    @Guide(description: "The primary semantic topic of the file")
    var domain: ContentDomain

    @Guide(description: "Recommended workflow triage bucket based on immediate actionability")
    var workflowStage: WorkflowStage

    @Guide(description: "True if this file contains sensitive secrets, API keys, credentials, or PII")
    var isSensitive: Bool

    @Guide(description: "Decision confidence rating from 0 (ambiguous) to 3 (definitive match)", .range(0...3))
    var confidenceScore: Int
}
```

### 2. High-Throughput Batch Resilience

When scanning a directory containing hundreds of files, `RetryPolicy` prevents rate limits from halting the process:

```swift
let retryPolicy = RetryPolicy(
    maxAttempts: 4,
    initialDelay: .milliseconds(200),
    multiplier: 2.0,
    jitter: 0.2,
    retryableStatuses: [429, 529]
)

let model = JevLanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)
```

### 3. Destination Routing Logic

```swift
if quarantineSensitive && decision.isSensitive {
    return "Quarantine_Vault/\(filename)"
}

if decision.confidenceScore < 2 {
    // Model confidence is low: route to review queue for human confirmation
    return "Review_Queue/\(filename)"
}

// Model confidence is high: route to organized destination
return "\(strategyFolder)/\(filename)"
```
