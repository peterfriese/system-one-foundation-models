# Duplicate Article Detection Demo 📰🔍

Demonstrates a production-ready **two-layer deduplication engine** for read-it-later and content-ingestion applications using Apple's **Foundation Models** framework, **TypeSafe AI Jev**, and **calibrated confidence routing**.

---

## 🎯 The Problem

When saving articles across the web, headline paraphrasing and syndicated rewrites fool traditional string matching:
- An AP wire story republished by local affiliates uses completely different URLs, modified headlines, and altered bylines.
- Traditional LLMs (System 2) take 2–5 seconds and hundreds of tokens to evaluate similarity, making them too slow and expensive for interactive save extensions.
- Jev (System One) evaluates semantic substance in **40–150ms** with calibrated probabilities, enabling instant duplicate detection.

---

## 🏗️ The Two-Layer Architecture

```
Incoming Article
       │
       ▼
┌─────────────────────────────────┐
│ Layer 1: Deterministic Engine   │ ──► [Exact Match] ──► Immediate Warning (0ms, 0 tokens)
│ • URL normalization             │
│ • Title/Author exact matching   │
└────────────────┬────────────────┘
                 │ Miss (Hard cases / syndication)
                 ▼
┌─────────────────────────────────┐
│ Layer 2: Jev System One (AFM)   │
│ • Apple Foundation Models API   │
│ • Evaluates semantic substance  │
│ • Calibrated Noul Probability   │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ Operational Confidence Routing  │
│ • ≥ 0.85: Confident Duplicate   │ ──► Auto-warn / Suppress
│ • 0.35...0.65: Undecided Band   │ ──► Escalate to manual verification
│ • ≤ 0.15: Confident Unique      │ ──► Save directly without prompt
└─────────────────────────────────┘
```

---

## 🚀 Running the Walkthrough

> ⚠️ **Strict Real Execution Mandate**: In compliance with `AGENTS.md` Principle 7, this demonstrator does not use fake mock fallbacks. A valid `TYPESAFE_API_KEY` is required for live semantic deduplication.

Run the sample application:

```bash
export TYPESAFE_API_KEY="your-api-key"
swift run duplicate-article-demo
```

The walkthrough evaluates 4 realistic scenarios:
1. **Scenario 1**: Identical article published on different URLs (Personal Blog vs. X.com) $\to$ caught instantly by Layer 1.
2. **Scenario 2**: Rewritten wire story $\to$ missed by Layer 1, caught by Layer 2 via Jev Foundation Models ($p = 0.93 \implies \text{.auto}$).
3. **Scenario 3**: Distinct story on similar topic (Foldable Google Pixel phone) $\to$ Layer 2 evaluates low probability ($p = 0.01 \implies \text{.auto}$ with `answer = false`, preventing false alarms).
4. **Scenario 4**: Swift 6 Concurrency Cancellation $\to$ cancelling an in-flight evaluation cleanly throws `CancellationError` without wrapping or resource leaks.

---

## 💡 How Key Features Work in Code

### 1. Confidence Routing with the Undecided Band

Instead of an arbitrary $\ge 0.50$ cutoff:

```swift
let routingPolicy = RoutingPolicy(
    escalateBelow: 0.60,
    autoAtOrAbove: 0.85,
    undecidedBand: 0.35...0.65
)

let judgement = response.judgement(for: "isDuplicate", policy: routingPolicy)

switch judgement.decision {
case .auto:
    if judgement.answer == true {
        displayDuplicateWarning()
    } else {
        saveArticleDirectly()
    }
case .confirm:
    promptUserToConfirmSimilarity()
case .escalate:
    // Inside 0.35...0.65: model is genuinely unsure, judgement.answer is nil
    askUserDirectly("AI is undecided on this article. Save as new?")
}
```

### 2. HTTP Resilience Policy

Configures network retries for 429 rate limits and 529 gateway overloads:

```swift
let retryPolicy = RetryPolicy(
    maxAttempts: 3,
    initialDelay: .milliseconds(250),
    multiplier: 2.0,
    jitter: 0.15,
    retryableStatuses: [429, 529]
)

let model = JevLanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)
```

### 3. Swift Concurrency Cancellation

In interactive apps (like Safari Share Sheets or reader apps), users frequently dismiss the sheet before network requests finish. Jev ensures cooperative cancellation propagates without being wrapped into a custom error:

```swift
let task = Task {
    try await deduplicator.check(incoming, against: library)
}
task.cancel() // Request halts cleanly and throws CancellationError
```
