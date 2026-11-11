# Google Gemini Decisions API (`gemini-decision-1`) CLI Demonstrator

This demonstrator showcases evaluating strongly-typed `@Generable` decision models against Google's **Gemini Decisions API** (`gemini-decision-1`) via Apple's native `LanguageModelSession`.

## Overview
- **Model**: `gemini-decision-1`
- **Endpoint**: `https://generativelanguage.googleapis.com/v1beta/decisions`
- **Latency**: ~150ms–250ms single forward pass
- **Pricing**: $0.10 / 1M input tokens, **$0.00 / 1M output tokens** (zero output token billing)

## Prerequisites
Export your Google Gemini API key with access to the Decisions API:

```bash
export GEMINI_API_KEY="AIza..."
```

(Alternatively, `GOOGLE_API_KEY` is also recognized automatically.)

## Running the Demonstrator
```bash
swift run gemini-demo
```

Or pass a custom customer ticket:
```bash
swift run gemini-demo "Customer reported unauthorized charge on their Visa card ending in 4112."
```
