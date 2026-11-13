# Product Requirements Documents (PRDs) 📋

This directory contains the Product Requirements Documents defining user stories, developer ergonomics, latency budgets, security constraints, and acceptance criteria for **System One for Apple Foundation Models** and its flagship reference apps.

| PRD | Date | Title | Scope & Key Requirements |
| :--- | :--- | :--- | :--- |
| [**PRD-2026-09-25**](PRD-2026-09-25-mail-triage-system-one-engine.md) | 2026-09-25 | Mail Triage System One Engine | Multi-pane macOS & iOS Mail triage client, hot-swappable System One vs. generative baseline evaluation, calibrated confidence tokens, batch triage with cancellation, and 500-email benchmark suite. |
| [**PRD-2026-10-03**](PRD-2026-10-03-clef-decision-models.md) | 2026-10-03 | Cloudflare Clef Multimodal Decision Models | Native `Attachment` multimodal evaluation for Clef (27B) and Clef-Flash (9B) across Workers AI, AI Gateway, and local Apple Silicon MPS runners, plus live camera inspection. |
| [**PRD-2026-10-08**](PRD-2026-10-08-openai-decisions-models.md) | 2026-10-08 | OpenAI Decisions Models (`gpt-6-luna`) | Native `OpenAIDecisionsLanguageModel` / `OpenAILanguageModel` bridge on `POST /v1/decisions` with zero output token billing, enterprise multi-tenant headers, and multimodal visual inspection. |
| [**PRD-2026-11-11**](PRD-2026-11-11-gemini-decisions-models.md) | 2026-11-11 | Google Gemini Decisions Models (`gemini-decision-1`) | High-density `GeminiLanguageModel` bridge on `POST /v1beta/decisions`, 256K-token context, up to 1,000 concurrent questions per pass, multimodal vision, and `"Gemini"` SwiftPM trait isolation. |
| [**PRD-2026-11-12**](PRD-2026-11-12-universal-proxy-credentials.md) | 2026-11-12 | Universal Mobile Proxy Credentials | Unified zero-dependency `ProxyCredential` (`.appCheck`, `.bearer`, `.header`, `.custom`), `ProxyEndpointValidator`, and `SystemOneProxyBackend` across all 5 networked System One providers. |

---

## Related Documentation

- [**Architecture Decision Records (`docs/architecture/`)**](../architecture/README.md)
- [**Documentation Hub (`docs/README.md`)**](../README.md)
- [**Examples Catalog (`Examples/README.md`)**](../../Examples/README.md)
