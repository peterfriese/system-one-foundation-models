# 08-CloudGeminiDecisions: Calibrated Trust & Safety Triage (`traits: ["Gemini"]`)

Demonstrates isolating the **`Gemini`** Swift Package trait so your binary compiles **only** `GeminiFoundationModels` and `SystemOneCore`—completely excluding Core ML (`LayaOnDevice`) and all sibling cloud provider targets (`Jev`, `LayaServe`, `Clef`, `OpenAI`).

---

## 📦 Package Manifest & Compile-Time Isolation

```swift
dependencies: [
    .package(name: "SystemOneFoundationModels", path: "../../..", traits: ["Gemini"])
]
```

`Sources/main.swift` includes a compile-time `#if canImport(...)` guard proving that `LayaOnDevice`, `JevFoundationModels`, `LayaFoundationModels`, `ClefFoundationModels`, and `OpenAIFoundationModels` are never compiled or linked.

---

## 🧠 What It Evaluates

Evaluates a suspicious SSO phishing community post against Google's **Gemini Decisions API** (`gemini-decision-1`) using all three ergonomic shortcuts + `RoutingPolicy`:
1. **`session.probability(of:state:)`** — Phishing / admin-impersonation truth probability (`noul`) routed via `policy.decide(Probability(clamping:))`.
2. **`session.choice(_:from:state:)`** — Strongly-typed `ContentModerationAction` (`Choosable` enum with per-case `optionDescription`) + full candidate probability distribution.
3. **`session.score(_:levels:state:)`** — 4-level ordinal threat rubric (`Benign` $\to$ `Critical Phishing Threat`).

---

## 🚀 Running the Sample

```bash
export GEMINI_API_KEY="AIza..."   # or GOOGLE_API_KEY
# Optional overrides: GEMINI_MODEL="gemini-decision-1", GEMINI_DECISIONS_URL="https://..."

swift run --package-path Examples/TraitSamples/08-CloudGeminiDecisions
```
