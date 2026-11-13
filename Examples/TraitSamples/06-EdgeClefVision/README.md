# 06-EdgeClefVision: Multimodal Edge Parcel & Asset Inspection

This standalone sample demonstrates multimodal visual decision evaluation using **`ClefLanguageModel`**, **`Attachment(imageURL:)`**, **`session.probability(...)`**, and **`session.choice(...)`** against **Cloudflare Workers AI (`clef-flash`)** or a local Clef inference runner.

---

## SPM Trait Configuration

This package links **only** the `Clef` trait of `SystemOneFoundationModels`:

```swift
// Package.swift
dependencies: [
    .package(name: "SystemOneFoundationModels", path: "../../..", traits: ["Clef"])
],
targets: [
    .executableTarget(
        name: "EdgeClefVision",
        dependencies: [
            .product(name: "SystemOneFoundationModels", package: "SystemOneFoundationModels")
        ]
    )
]
```

### Architectural Benefits
1. **Isolated Multimodal Dependency Graph**: Compiles `SystemOneCore` and `ClefFoundationModels` without linking Core ML on-device weights, Jev, Laya, or OpenAI client modules.
2. **Native Apple `Attachment` Ergonomics**: Uses standard `FoundationModels.Attachment` inside `@PromptBuilder` closures (`session.probability` and `session.choice`).
3. **Edge-to-Local Portability**: Seamlessly switches between Cloudflare Workers AI global edge, Cloudflare AI Gateway, and local Docker/vLLM/MLX Clef runners.
4. **Calibrated Epistemic Routing**: Pairs multimodal probabilities with `RoutingPolicy` so ambiguous visual captures escalate cleanly to human operators.

---

## Running the Sample

This sample requires either valid **Cloudflare Workers AI credentials** (`CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`) or a reachable local Clef inference server (`CLEF_LOCAL_PORT`). Synthetic mock bypasses are prohibited; if unconfigured, the CLI terminates immediately with exact remediation instructions.

```bash
cd Examples/TraitSamples/06-EdgeClefVision

# Option A: Run against Cloudflare Workers AI edge
export CLOUDFLARE_ACCOUNT_ID="your-cloudflare-account-id"
export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"
swift run EdgeClefVision

# Option B: Run against a local Clef runner with a custom image
docker run -p 8000:8000 ghcr.io/typesafe-ai/clef-flash:latest
export CLEF_LOCAL_PORT=8000
swift run EdgeClefVision ../../Quickstarts/ClefQuickstart/sample.jpg
```

### Missing Configuration Output

If neither Cloudflare credentials nor `CLEF_LOCAL_PORT` are configured:

```text
=== 06-EdgeClefVision: Multimodal Edge Parcel & Asset Inspection ===
Backend: Cloudflare Clef / Clef-Flash Multimodal Decision Model
Binary footprint: Lean Clef-only trait (Zero Core ML, Jev, or OpenAI targets linked)
================================================================================
  ⚠️  CONFIGURATION ERROR: MISSING CLEF CREDENTIALS OR RUNNER
================================================================================
  This example application requires either Cloudflare Workers AI credentials
  or a running local Clef inference daemon. Synthetic mock bypasses are not
  permitted.

  Remediation (Cloudflare Workers AI):
    export CLOUDFLARE_ACCOUNT_ID="your-cloudflare-account-id"
    export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"

  Remediation (Local Clef Runner):
    docker run -p 8000:8000 ghcr.io/typesafe-ai/clef-flash:latest
    export CLEF_LOCAL_PORT=8000
================================================================================
```
