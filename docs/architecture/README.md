# Architecture Decision Records (ADRs) 🏛️

This directory contains the Architecture Decision Records governing **System One for Apple Foundation Models**, its provider protocol adapters, Swift 6 concurrency boundaries, and zero-dependency mobile security architecture.

| ADR | Date | Title | Summary |
| :--- | :--- | :--- | :--- |
| [**ADR-2026-09-25**](ADR-2026-09-25-mail-triage-system-one-engine.md) | 2026-09-25 | Mail Triage System One Engine & Pluggable Backends | Multi-backend `SystemOneBackend` architecture, on-device Core ML (`LayaCoreMLEngine`) + `laya-serve` + Jev Cloud execution, FactoryKit DI, and actor-isolated storage in `MailTriageApp`. |
| [**ADR-2026-10-03-01**](ADR-2026-10-03-01-clef-foundation-models-integration.md) | 2026-10-03 | Cloudflare Clef & Clef-Flash Multimodal Integration | Bridging Cloudflare's 27B/9B multimodal decision models (`ClefLanguageModel`), `.vision` capability gating, 1024px JPEG downscaling, URL/body slug decoupling, and Client API v4 dual-decoding. |
| [**ADR-2026-10-08-01**](ADR-2026-10-08-01-openai-decisions-models-integration.md) | 2026-10-08 | OpenAI Decisions API (`gpt-6-luna`) Integration | Wire adapter mapping `noul`/`choice`/`score` to `POST /v1/decisions` (`predicate`/`choice`/`score`), zero-output-token normalization, enterprise headers (`OpenAI-Organization`, `OpenAI-Project`), and inline Data URL vision guardrails. |
| [**ADR-2026-11-11-01**](ADR-2026-11-11-01-gemini-decisions-models-integration.md) | 2026-11-11 | Google Gemini Decisions API (`gemini-decision-1`) Integration | Dictionary-keyed `POST /v1beta/decisions` wire adapter (`GeminiLanguageModel`), flat typed multimodal `input` segments (`text` + raw Base64 `image`), `x-goog-api-key` auth, and 256K-context batching. |
| [**ADR-2026-11-12-01**](ADR-2026-11-12-01-universal-proxy-credentials.md) | 2026-11-12 | Universal `ProxyCredential` & `SystemOneProxyBackend` | Zero-dependency dynamic request authorization (`.appCheck`, `.bearer`, `.header`, `.custom`), `ProxyEndpointValidator` HTTPS enforcement, per-attempt token refresh inside retry loops, and vendor-agnostic `SystemOneProxyBackend` gateways across all 5 networked providers. |

---

## Related Documentation

- [**Product Requirements Documents (`docs/prd/`)**](../prd/README.md)
- [**Tech Notes (`tech-notes/`)**](../../tech-notes/README.md)
- [**Mobile Security Guide (`docs/mobile-security.md`)**](../mobile-security.md)
- [**Documentation Hub (`docs/README.md`)**](../README.md)
