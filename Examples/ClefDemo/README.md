# Clef CLI Multimodal Decision Demonstrator 👁️⚡️

A command-line showcase demonstrating multimodal decision evaluation using **Cloudflare Clef (27B)** and **Clef-Flash (9B)** with Apple's **Foundation Models framework** (`LanguageModelSession`, `Prompt`, `Attachment`).

---

## 🚀 Key Highlights

1. **Apple-Native Multimodal Ergonomics**:
   - Visual data attachments are provided directly through Foundation Models `Prompt` builder closures:
     ```swift
     let prompt = Prompt {
         "Analyze the item in this camera capture."
         Attachment(cgImage)
     }
     let response = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)
     ```
2. **Single Forward-Pass Non-Autoregressive Decision Evaluation**:
   - Zero generated output tokens (`output_tokens: 0`).
   - Simultaneous evaluation of boolean propositions (`noul`), categorical classification (`choice`), and ordinal rubric scores (`score`).
3. **Calibrated Confidence Routing**:
   - Maps model epistemic certainty to automated operational decisions:
     - `.auto` ($\ge 85\%$): Autonomous processing.
     - `.confirm` ($60\%\dots84.9\%$): Prompt human reviewer with candidate suggestion.
     - `.escalate` ($< 60\%$): Escalate to manual review queue.
4. **Flexible Topology**:
   - Evaluate against Cloudflare's global edge infrastructure via **Cloudflare Workers AI**, or run 100% offline against a **Local Native Runner** (`http://localhost:8000`).

---

## 📦 Prerequisites

Choose one of two backends:

### Option A: Local Native Runner (Zero Cloud Credentials)

Run the local container runner on port 8000:
```bash
docker run -d -p 8000:8000 ghcr.io/typesafe-ai/clef-flash:latest
```

### Option B: Cloudflare Workers AI

Export your Cloudflare account ID and API token:
```bash
export CLOUDFLARE_ACCOUNT_ID="your-cloudflare-account-id"
export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"
```

---

## 🏃 Running the Demonstrator

### 1. In-Memory Synthetic Frame Evaluation

If no image path is passed, the CLI generates a 640x480 RGB synthetic electronics component frame in memory using CoreGraphics:

```bash
# Evaluate against local runner (default if credentials are not exported):
swift run clef-demo --backend local

# Evaluate against Cloudflare Workers AI:
swift run clef-demo --backend workers-ai
```

### 2. Evaluating a Real Image File

Pass any PNG, JPEG, or WebP image ($\le 16\text{MP}$):

```bash
swift run clef-demo /path/to/product_capture.jpg
```

### 3. Selecting Model Variants

Switch between Clef-Flash (9B, ultra-fast ~45ms) and Clef (27B, high-capacity reasoning):

```bash
# Evaluate with Clef-Flash (default):
swift run clef-demo --model clef-flash /path/to/capture.png

# Evaluate with Clef 27B:
swift run clef-demo --model clef /path/to/capture.png
```

---

## 📊 Sample Output

```
==============================================================
  System One Foundation Models — Clef Multimodal Demo 👁️⚡️
==============================================================
Target Endpoint:  http://localhost:8000/v1/evaluate
Model:            Cloudflare Clef-Flash (9B)
Image Attachment: 640x480 RGB Synthetic Electronics Component (Serial #SN-9281-OK) [Generated in-memory]

Evaluating multimodal decision via Apple LanguageModelSession...

Evaluation Complete in 58.4ms!
==============================================================
  Structured Decision Result (@Generable VisualInspectionDecision)
==============================================================
  • isRecognized:     true
  • itemCategory:     Electronics (electronics)
  • conditionScore:   Level 3 — Pristine
  • safetyApproval:   APPROVED ✅

Operational Confidence Routing (Policy: auto ≥ 85.0%, escalate < 60.0%):
--------------------------------------------------------------
  • Item Recognition: [AUTO-CONFIRMED] ──► Confidently recognized (Prob: 98.2%)
  • Item Category:    [AUTO-ROUTE]     ──► Routed to electronics pipeline (Conf: 94.6%)
  • Condition Rubric: Weighted: 2.92 | Rounded: Level 3 | Normalized: 0.97 (Confidence: 91.0%)
  • Safety Approval:  [AUTO-PASS]      ──► Passed safety verification (Prob: 99.1%)

Usage & Telemetry:
--------------------------------------------------------------
  • Input Tokens:     1,420
  • Output Tokens:    0 (Non-autoregressive forward pass)
  • Server Duration:  38.2ms (Forward pass inference on edge)
  • Transport Time:   52.1ms (HTTP roundtrip + inference)
  • Total Client:     58.4ms (Swift session wall time)
==============================================================
```
