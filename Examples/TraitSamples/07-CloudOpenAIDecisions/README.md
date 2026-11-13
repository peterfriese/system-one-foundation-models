# 07-CloudOpenAIDecisions: Enterprise Release Gate Evaluation

This standalone sample demonstrates cloud CI/CD release gate evaluation using **`OpenAIDecisionsLanguageModel`**, **`session.probability(...)`**, **`session.choice(...)`**, and **`session.score(...)`** connecting to the **OpenAI Decisions API (`gpt-6-luna`)**.

---

## SPM Trait Configuration

This package links **only** the `OpenAI` trait of `SystemOneFoundationModels`:

```swift
// Package.swift
dependencies: [
    .package(name: "SystemOneFoundationModels", path: "../../..", traits: ["OpenAI"])
],
targets: [
    .executableTarget(
        name: "CloudOpenAIDecisions",
        dependencies: [
            .product(name: "SystemOneFoundationModels", package: "SystemOneFoundationModels")
        ]
    )
]
```

### Architectural Benefits
1. **Minimal CI/CD Binary Footprint**: Compiles only `SystemOneCore` and `OpenAIFoundationModels`—ideal for GitHub Actions runners, Kubernetes admission webhooks, and serverless deployment gates.
2. **Enterprise Multi-Tenant Headers**: Native support for `OpenAI-Organization` (`OPENAI_ORGANIZATION`) and `OpenAI-Project` (`OPENAI_PROJECT`) governance headers.
3. **Full Decision Primitive Coverage**: Demonstrates binary `probability` (`noul`), categorical `choice`, and ordinal `score` rubrics through Apple's standard `LanguageModelSession`.
4. **Epistemic Routing Safety**: Uses `RoutingPolicy` so borderline confidence or undecided probability bands escalate to human reviewers instead of silently auto-approving.

---

## Running the Sample

This sample requires a valid **OpenAI API key** (`OPENAI_API_KEY`) to evaluate real OpenAI Decisions API models. Synthetic mock bypasses are prohibited; if `OPENAI_API_KEY` is missing, the CLI terminates immediately with exact remediation instructions.

```bash
cd Examples/TraitSamples/07-CloudOpenAIDecisions

export OPENAI_API_KEY="sk-..."
# Optional enterprise headers:
# export OPENAI_ORGANIZATION="org-..."
# export OPENAI_PROJECT="proj-..."

swift run CloudOpenAIDecisions
```

### Missing Configuration Output

If `OPENAI_API_KEY` is not set:

```text
=== 07-CloudOpenAIDecisions: Enterprise Release Gate Evaluation ===
Backend: OpenAI Decisions API (gpt-6-luna)
Binary footprint: Ultra-lean OpenAI-only trait (Zero Core ML, Jev, Laya, or Clef targets linked)
================================================================================
  ⚠️  CONFIGURATION ERROR: MISSING OPENAI_API_KEY
================================================================================
  This example application requires a valid OpenAI API key to evaluate real
  OpenAI Decisions API models (gpt-6-luna). Synthetic mock bypasses are not
  permitted.

  Remediation:
    export OPENAI_API_KEY="sk-..."
    # Optional multi-tenant enterprise headers:
    # export OPENAI_ORGANIZATION="org-..."
    # export OPENAI_PROJECT="proj-..."
================================================================================
```
