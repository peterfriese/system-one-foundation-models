# 04-HybridRouter: Local-First Intelligent Confidence Routing (`traits: ["All"]`)

This standalone sample demonstrates **local-first edge-to-cloud confidence routing**: decisions evaluate locally on the **Apple Neural Engine (ANE)** via `LayaOnDevice` first (< 2ms, 0 bytes sent, $0 cloud cost), and dynamically escalate to **any configured cloud System One provider** (`Jev`, `Gemini`, `OpenAI`, `Clef`, or `LayaServe`) only when on-device confidence falls below `80%`.

---

## 📦 SPM Trait Configuration

Links `traits: ["All"]` on `SystemOneFoundationModels`, verified via a compile-time `#if !(canImport(...))` assertion across all **6** System One provider modules:

```swift
dependencies: [
    .package(name: "SystemOneFoundationModels", path: "../../..", traits: ["All"])
]
```

---

## ⚙️ Escalation Target Auto-Resolution

`CloudEscalationTier.resolveFromEnvironment()` automatically picks the cloud escalation tier from your environment (in priority order):
1. **`TYPESAFE_API_KEY`** $\to$ `JevLanguageModel` (TypeSafe AI Jev)
2. **`GEMINI_API_KEY`** / **`GOOGLE_API_KEY`** $\to$ `GeminiLanguageModel` (`gemini-decision-1`)
3. **`OPENAI_API_KEY`** $\to$ `OpenAILanguageModel` (`gpt-6-luna`)
4. **`CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`** $\to$ `ClefLanguageModel` (`clef-flash`)
5. **`LAYA_SERVE_URL`** (+ optional `LAYA_API_KEY`) $\to$ `LayaLanguageModel` (`laya-serve`)

---

## 🚀 Running the Sample

Requires **both** a compiled Core ML model (`LAYA_MODEL_PATH` or `~/Library/Application Support/dev.peterfriese.mailtriageapp/Models/LayaDecisionModel.mlmodelc`) **and** at least one cloud escalation credential above. Per Principle 7, missing prerequisites print a formatted remediation banner and `exit(1)`.

```bash
export LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc"
export GEMINI_API_KEY="AIza..."   # or TYPESAFE_API_KEY / OPENAI_API_KEY / CLOUDFLARE_* / LAYA_SERVE_URL

swift run --package-path Examples/TraitSamples/04-HybridRouter
```

### Sample Output

```text
=== 04-HybridRouter: Local-First Intelligent Confidence Routing ===
Active Trait: All (LayaOnDevice + Jev + LayaServe + Clef + OpenAI + Gemini)
Policy: Local Laya evaluated first on ANE; escalates to Cloud when confidence < 80%
Escalation Target: Cloud Gemini Decisions (Google)

--- Scenario A: Clear Outage Alert ---
Input: "URGENT: 500 Internal Server Error when processing credit card transactions. 14 customers failed."
Decision Tier: On-Device Laya (Apple Neural Engine)
Priority: Urgent
Confidence: 98.0%
Latency: < 2ms (0 bytes sent, $0 cloud cost)

--- Scenario B: Ambiguous / Borderline Note ---
Input: "Noticed a slight formatting typo in the staging documentation footer, but not sure if it matters."
Decision Tier: Cloud Gemini Decisions (Google) (Escalated: Local confidence 38.1% < 80%)
Priority: Routine
Confidence: 94.2%
Latency: ~30-80ms round-trip
```
