# OpenAI Decisions API (`gpt-6-luna`) CLI Demonstrator

This demonstrator showcases evaluating strongly-typed `@Generable` decision models against OpenAI's **Decisions API** (`gpt-6-luna`) via Apple's native `LanguageModelSession`.

## Overview
- **Model**: `gpt-6-luna`
- **Endpoint**: `https://api.openai.com/v1/decisions`
- **Latency**: ~150ms single forward pass
- **Pricing**: $0.10 / 1M input tokens, **$0.00 / 1M output tokens** (zero output token billing)

## Prerequisites
Export your OpenAI API key with access to the Decisions API:

```bash
export OPENAI_API_KEY="sk-..."
```

Optionally configure multi-tenant enterprise headers:
```bash
export OPENAI_ORGANIZATION="org-..."
export OPENAI_PROJECT="proj-..."
```

## Running the Demonstrator
```bash
swift run openai-demo
```

Or pass a custom customer ticket:
```bash
swift run openai-demo "Customer reported unauthorized charge on their Visa card ending in 4112."
```
