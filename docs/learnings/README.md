# Engineering Learnings (`docs/learnings/`) 📘

Deep-dive engineering articles capturing non-trivial architectural lessons, wire-protocol nuances, multimodal encoding patterns, and Swift 6 concurrency strategies discovered while building **System One for Apple Foundation Models**.

| Date | Article | Key Topics |
| :--- | :--- | :--- |
| **2026-10-05** | [**Bridging Cloudflare Clef Multimodal Decision Models to Apple Foundation Models in Swift 6**](2026-10-05-bridging-cloudflare-clef-to-apple-foundation-models.md) | Cloudflare Workers AI (`clef` 27B & `clef-flash` 9B), `.vision` capability gating, CoreGraphics 1024px JPEG normalization, URL/body model slug decoupling, and Client API v4 dual-envelope decoding. |
| **2026-10-08** | [**Bridging OpenAI's Decisions API (GPT-6 Luna) to Apple Foundation Models in Swift 6**](2026-10-08-bridging-openai-decisions-api-to-apple-foundation-models.md) | OpenAI `POST /v1/decisions` (`gpt-6-luna`), array-based `predicate` / `choice` / `score` wire adaptation, RFC 2397 Data URL multimodal images, zero-output-token billing telemetry, and Swift 6 strict concurrency. |

---

## Related Documentation

- [**Tech Notes (`tech-notes/`)**](../../tech-notes/README.md) — Concise SDK quirks, compiler behaviors, and wire-level findings (`0001`–`0019`).
- [**Architecture Decision Records (`docs/architecture/`)**](../architecture/README.md) — Formal ADRs across all 6 System One providers and universal `ProxyCredential` security.
- [**Product Requirements Documents (`docs/prd/`)**](../prd/README.md) — Specifications and acceptance criteria for provider integrations.
- [**Documentation Hub (`docs/README.md`)**](../README.md)
