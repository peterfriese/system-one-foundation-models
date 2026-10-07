# 0014 — Cloudflare Workers AI Model Schema Validation Nuance & Identifier Decoupling

- **Date**: 2026-10-03
- **Author**: Peter Friese
- **Framework**: `SystemOneCore`, `ClefFoundationModels`
- **Upstream**: Cloudflare Workers AI REST API, Cloudflare AI Gateway

---

## Context

When integrating Cloudflare Workers AI and Cloudflare AI Gateway endpoints for the Clef multimodal decision models (`@cf/cloudflare/clef` and `@cf/cloudflare/clef-flash`), requests are routed via HTTP POST to Cloudflare's edge inference gateway:

```
POST https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/@cf/cloudflare/clef-flash
```

or through Cloudflare AI Gateway:

```
POST https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/workers-ai/@cf/cloudflare/clef-flash
```

In the System One protocol, the evaluation request payload (`SystemOneRequest`) carries contextual text, model identification, schema-derived questions, and optional image attachments:

```json
{
  "state": "Document inspection request for parcel return",
  "model": "@cf/cloudflare/clef-flash",
  "questions": {
    "is_damaged": {
      "type": "noul",
      "statement": "The item depicted in the image shows transit damage."
    }
  }
}
```

During live probes against Cloudflare Workers AI edge nodes using the full catalog identifier (`@cf/cloudflare/clef-flash`) in the JSON payload body, Cloudflare rejected the request with HTTP 400 Bad Request:

```
AiError: Bad input: Error: '/model' failed test ^\s*(clef|clef-flash)\s*$ pattern
```

---

## Findings

### 1. Dual-Identifier Schema Inconsistency in Workers AI

Cloudflare Workers AI enforces two distinct model identification schemas across the HTTP boundary:

1. **Edge URL Routing Identifier**:
   - The edge API gateway inspects the URL path component to determine container routing, GPU allocation, and billing catalog lookup.
   - It **requires** the full catalog prefix: `@cf/cloudflare/clef` or `@cf/cloudflare/clef-flash`.
   - Omitting the prefix (e.g. `/ai/run/clef-flash`) causes edge routing to fail with HTTP 404 (`Model not found`).

2. **JSON Body Schema Validation**:
   - The underlying inference container runs a JSON schema validator on the incoming request payload.
   - The `/model` parameter in the body is validated against the following strict regular expression:
     ```regex
     ^\s*(clef|clef-flash)\s*$
     ```
   - If the request body passes the fully-qualified catalog string (`@cf/cloudflare/clef` or `@cf/cloudflare/clef-flash`), the regex assertion fails and Cloudflare terminates the request with `AiError: Bad input`.

```
                       ┌─────────────────────────────────────────────────────────┐
                       │               Cloudflare Workers AI Gateway             │
                       └─────────────────────────────────────────────────────────┘
                                                    │
                 URL Path                           │                Request Body
   /ai/run/@cf/cloudflare/clef-flash                │           { "model": "clef-flash", ... }
                    │                               │                         │
                    ▼                               │                         ▼
       ┌────────────────────────┐                   │            ┌────────────────────────┐
       │   Edge Routing Table   │                   │            │  JSON Schema Validator │
       │  Requires catalog ID   │                   │            │  Regex: ^(clef|...)$   │
       │ @cf/cloudflare/clef-flash                  │            │   Rejects catalog ID   │
       └────────────────────────┘                   │            └────────────────────────┘
                    │                               │                         │
                    └───────────────────────┬───────┴─────────────────────────┘
                                            ▼
                                ┌───────────────────────┐
                                │   Inference Engine    │
                                │   Clef-Flash (9B)     │
                                └───────────────────────┘
```

---

## Resolution: Decoupled Identifier Architecture

To resolve the discrepancy and prevent runtime schema rejections, the library cleanly decouples the **URL routing identifier** from the **payload body identifier**:

### 1. `ClefModel` Identifier Segregation

In `Sources/ClefFoundationModels/ClefModel.swift`, the enum raw values provide the un-prefixed identifiers expected by the body schema regex, while `workersAIIdentifier` provides the catalog URI expected by edge routing:

```swift
public enum ClefModel: String, Codable, Sendable, CaseIterable {
    case clef = "clef"
    case clefFlash = "clef-flash"

    /// The Cloudflare Workers AI model identifier string used in URL paths.
    public var workersAIIdentifier: String {
        switch self {
        case .clef:
            return "@cf/cloudflare/clef"
        case .clefFlash:
            return "@cf/cloudflare/clef-flash"
        }
    }
}
```

### 2. URL and Body Specialization in `ClefEndpoint`

In `Sources/ClefFoundationModels/ClefEndpoint.swift`:
- `ClefEndpoint.url` consumes `model.workersAIIdentifier` for edge routing.
- `ClefEndpoint.modelIdentifier` exposes `model.rawValue` (`"clef"` or `"clef-flash"`) for wire payload encoding.

```swift
public enum ClefEndpoint: Hashable, Sendable {
    case workersAI(accountID: String, model: ClefModel = .clefFlash)
    case gateway(accountID: String, gatewayID: String, model: ClefModel = .clefFlash)
    case local(port: Int = 8000, model: ClefModel = .clefFlash)
    case custom(URL, model: ClefModel = .clefFlash)

    public var url: URL {
        switch self {
        case .workersAI(let accountID, let model):
            return URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/ai/run/\(model.workersAIIdentifier)")!
        case .gateway(let accountID, let gatewayID, let model):
            return URL(string: "https://gateway.ai.cloudflare.com/v1/\(accountID)/\(gatewayID)/workers-ai/\(model.workersAIIdentifier)")!
        case .local(let port, _):
            return URL(string: "http://localhost:\(port)/v1/evaluate")!
        case .custom(let customURL, _):
            return customURL
        }
    }

    /// The model identifier sent over the wire in the JSON body.
    public var modelIdentifier: String {
        model.rawValue
    }
}
```

### 3. Payload Construction in `ClefLanguageModel` & `ClefExecutor`

When initializing `ClefLanguageModel.Configuration`, `modelID` defaults to `endpoint.modelIdentifier` (`model.rawValue`):

```swift
self.modelID = endpoint.modelIdentifier // "clef-flash" or "clef"
```

This guarantees that `SystemOneRequest(model: configuration.modelID, ...)` serializes `{"model": "clef-flash"}` in the JSON body, satisfying Cloudflare's `^\s*(clef|clef-flash)\s*$` validation pattern while preserving accurate edge routing via the URL path.

---

## Implications

1. **Zero-Configuration Routing**: Developers configure standard high-level endpoints such as `ClefEndpoint.workersAI(accountID: "...")` or `ClefEndpoint.gateway(accountID: "...", gatewayID: "...")` without having to manually manipulate model naming nuances or regex patterns.
2. **Local Server Consistency**: Local inference servers (e.g. vLLM, Cog, Docker Model Runner) also expect short model slugs (`"clef"`, `"clef-flash"`) rather than Cloudflare-specific catalog prefixes (`@cf/cloudflare/...`), ensuring uniform wire payloads across all target topologies.
3. **Fail-Fast Validation**: Swift Testing suites in `Tests/ClefFoundationModelsTests/ClefEndpointTests.swift` verify that `workersAIIdentifier` always yields the catalog path (`@cf/cloudflare/...`) and `modelIdentifier` always yields the schema slug (`clef` / `clef-flash`).

---

## Evidence / Sources

- Cloudflare Workers AI Error Response: `AiError: Bad input: Error: '/model' failed test ^\s*(clef|clef-flash)\s*$ pattern`
- Model Declaration: `Sources/ClefFoundationModels/ClefModel.swift`
- Endpoint Mapping: `Sources/ClefFoundationModels/ClefEndpoint.swift`
- Unit Test Suite: `Tests/ClefFoundationModelsTests/ClefEndpointTests.swift`
- System One DTO: `Sources/SystemOneCore/Models/SystemOneDTOs.swift`
