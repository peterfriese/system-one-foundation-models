# AI Coding Agent Skills (`skills/`) 🤖⚡

This directory provides ready-to-install **SKILL.md** packages for AI coding assistants (Claude Code, Gemini CLI, Antigravity, Cursor, Codex, and Windsurf). Installing these skills teaches your coding agent the exact Swift 6 APIs, `@Generable` schema constraints, epistemic `RoutingPolicy` patterns, multimodal `Attachment` downscaling rules, and zero-secret `ProxyCredential` security architecture of **System One for Apple Foundation Models**.

---

## 🧭 Available Agent Skills (6 Packages)

| Skill Directory | Scope & When to Use |
| :--- | :--- |
| [**`system-one-foundation-models/`**](system-one-foundation-models/SKILL.md) | **Umbrella Multi-Provider Skill** *(recommended default)* — Covers all **6** System One providers (`LayaOnDevice`, `LayaFoundationModels`, `JevFoundationModels`, `ClefFoundationModels`, `OpenAIFoundationModels`, `GeminiFoundationModels`), `SystemOneProxyBackend`, `ProxyCredential`, `.probability`/`.choice`/`.score` shortcuts, SE-0402 package traits, and offline `MockSystemOneBackend` testing. |
| [**`laya-foundation-models/`**](laya-foundation-models/SKILL.md) | **On-Device Core ML & Self-Hosted Laya** — Deep dive into `LayaOnDeviceLanguageModel` (Apple Neural Engine, `.mlmodelc` conversion, `ModernBERTTokenizer` / `MMBERTTokenizer`, `[1, 512]` fixed-shape tensors) and `LayaLanguageModel` (`laya-serve` HTTP / private VPCs). |
| [**`jev-foundation-models/`**](jev-foundation-models/SKILL.md) | **TypeSafe AI Jev Cloud** — `JevLanguageModel`, `JevEndpoint`, `RetryPolicy` backoff, `ProxyCredential` / `ProxyTransport` Firebase App Check gateways, and `MockJevTransport` testing. |
| [**`clef-foundation-models/`**](clef-foundation-models/SKILL.md) | **Cloudflare Clef & Clef-Flash Multimodal** — `ClefLanguageModel` (9B & 27B), Workers AI catalog/body slug decoupling, AI Gateway, local MPS runner, AVFoundation camera downscaling, and v4 envelope dual-decoding. |
| [**`openai-foundation-models/`**](openai-foundation-models/SKILL.md) | **OpenAI Decisions (`gpt-6-luna`)** — `OpenAILanguageModel` (`OpenAIDecisionsLanguageModel`), `POST /v1/decisions` `predicate`/`choice`/`score` wire alignment, `$0.00` output token economics, `OpenAI-Organization` / `OpenAI-Project` headers, and multimodal Data URL guardrails. |
| [**`gemini-foundation-models/`**](gemini-foundation-models/SKILL.md) | **Google Gemini Decisions (`gemini-decision-1`)** — `GeminiLanguageModel` (`GeminiDecisionsLanguageModel`), `POST /v1beta/decisions` dictionary-keyed wire adapter, 256K context & 1,000-question batching, raw Base64 multimodal `input` segments, and `x-goog-api-key` / `ProxyCredential` auth. |

---

## 📦 Installation

Copy or symlink `skills/system-one-foundation-models` (plus any provider-specific skill) into your project's `.agents/skills/` or `.claude/skills/` directory:

```bash
mkdir -p .agents/skills
cp -R path/to/system-one-foundation-models/skills/system-one-foundation-models .agents/skills/
```
