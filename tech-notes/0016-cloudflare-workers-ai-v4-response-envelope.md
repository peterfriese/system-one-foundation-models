# 0016 — Cloudflare Workers AI Client API v4 Response Envelope & Dual-Decoding Fallback

- **Date**: 2026-10-03
- **Author**: Peter Friese
- **Framework**: `ClefFoundationModels`, `SystemOneCore`
- **Upstream**: Cloudflare Workers AI Client API v4, Cloudflare AI Gateway, `laya-serve` / Docker Clef runners

---

## Context

When issuing decision evaluation requests to Cloudflare Workers AI edge endpoints:

```
POST https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/@cf/cloudflare/clef-flash
```

Cloudflare returns HTTP status `200 OK` upon successful model execution. However, during initial live integration with the native Foundation Models bridge (`ClefHTTPBackend`), response parsing unexpectedly failed with a client-side decoding exception:

```
SystemOneError.decodingError("Failed to decode Clef response: The data couldn't be read because it is missing.")
```

The underlying Swift `JSONDecoder` failed to locate required top-level fields (such as `model`, `answers`, or `usage`), causing the entire evaluation pipeline to terminate with an error even though the remote model had generated valid decision answers.

---

## Findings

### 1. Cloudflare Client API v4 Envelope Structure

Cloudflare Workers AI sits behind Cloudflare's unified Client API v4 architecture. All standard REST responses routed through `api.cloudflare.com/client/v4/` wrap service-specific payloads inside a canonical envelope:

```json
{
  "result": {
    "model": "@cf/cloudflare/clef-flash",
    "answers": {
      "hasDefect": {
        "type": "noul",
        "noul": 0.93,
        "confidence": 0.93
      },
      "defectType": {
        "type": "choice",
        "choice": "scratch",
        "confidence": 0.89
      },
      "severity": {
        "type": "score",
        "score": 2.0,
        "confidence": 0.85
      }
    },
    "usage": {
      "input_tokens": 240,
      "output_tokens": 12
    }
  },
  "success": true,
  "errors": [],
  "messages": []
}
```

The actual inference output (`SystemOneResponse`) is nested beneath the `"result"` key. Additional top-level keys include:
- `success`: A boolean indicating whether the Cloudflare worker and edge pipeline completed without unhandled errors.
- `errors`: An array of structured error objects (`code`, `message`).
- `messages`: Operational or informational notices.

### 2. Discrepancy with Local & Docker Model Runners

Local and self-hosted System One runners (such as `laya-serve`, PR #31, or Dockerized Clef instances running on local ports like `http://127.0.0.1:8080/v1/systemone`) operate as direct decision microservices. They return raw, un-enveloped `SystemOneResponse` payloads directly at the JSON root:

```json
{
  "model": "clef-flash",
  "answers": {
    "hasDefect": {
      "type": "noul",
      "noul": 0.93,
      "confidence": 0.93
    }
  },
  "usage": {
    "input_tokens": 240,
    "output_tokens": 12
  }
}
```

Attempting to decode Cloudflare's enveloped response directly into `SystemOneResponse` resulted in `DecodingError.keyNotFound` / "data missing" because `SystemOneResponse` expects keys like `answers` at the JSON root level rather than wrapped in `result`.

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                 Incoming HTTP 200 Body                  │
                  └─────────────────────────────────────────────────────────┘
                                               │
                       ┌───────────────────────┴───────────────────────┐
                       ▼                                               ▼
         Cloudflare Workers AI v4                           Local Runner / Docker
     { "result": { ... }, "success": true }               { "model": ..., "answers": ... }
                       │                                               │
                       ▼                                               ▼
              Nested Under "result"                                Raw JSON Root
                       │                                               │
                       └───────────────────────┬───────────────────────┘
                                               ▼
                                 Single-Strategy Decoder ❌
                             (Direct root decode fails on CF;
                              Envelope decode fails on local)
```

### 3. Edge-Condition Error Responses with HTTP 200

In certain edge failure modes, Cloudflare Workers AI returns HTTP status 200 while reporting failure within the envelope:

```json
{
  "result": null,
  "success": false,
  "errors": [
    {
      "code": 1000,
      "message": "Inference worker execution failed"
    }
  ],
  "messages": []
}
```

A robust decoding strategy must not only unpack the `"result"` object on success, but also inspect `"success": false` and surface descriptive error messages directly as `SystemOneError.apiError`.

---

## Resolution: Dual-Decoding Fallback Strategy

To seamlessly support Cloudflare Workers AI edge gateways, Cloudflare AI Gateway proxies, local `laya-serve` daemons, and mock servers without configuration branching, `ClefHTTPBackend.decodeResponse` implements a resilient dual-decoding fallback pipeline.

### 1. Decoding Pipeline Implementation

In `Sources/ClefFoundationModels/ClefHTTPBackend.swift`:

```swift
// MARK: - Response Decoding
// See tech-notes/0016-cloudflare-workers-ai-v4-response-envelope.md
private func decodeResponse(data: Data, httpResponse: HTTPURLResponse, transportDuration: Double) throws -> SystemOneResponse {
    do {
        var decoded: SystemOneResponse

        if let direct = try? JSONDecoder().decode(SystemOneResponse.self, from: data) {
            // Fast path: raw root JSON payload (local runner, laya-serve, Docker)
            decoded = direct
        } else if let envelope = try? JSONDecoder().decode(CloudflareAPIEnvelope.self, from: data) {
            // Cloudflare v4 envelope: check for internal failures
            if envelope.success == false {
                let errorMessage = envelope.errors?.first?.message ?? "Cloudflare API request failed"
                throw SystemOneError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            if let result = envelope.result {
                decoded = result
            } else {
                decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
            }
        } else {
            // Final attempt to trigger informative DecodingError
            decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        }

        decoded.transportDurationMs = transportDuration

        // Preserve Cloudflare edge timing telemetry
        if let serverTimingHeader = httpResponse.value(forHTTPHeaderField: "server-timing"),
           let dur = parseServerTimingDuration(serverTimingHeader) {
            decoded.serverDurationMs = dur
        } else if let envoyHeader = httpResponse.value(forHTTPHeaderField: "x-envoy-upstream-service-time"),
                  let envoyMs = Double(envoyHeader) {
            decoded.serverDurationMs = envoyMs
        } else {
            decoded.serverDurationMs = transportDuration
        }

        return decoded
    } catch let error as SystemOneError {
        throw error
    } catch {
        throw SystemOneError.decodingError("Failed to decode Clef response: \(error.localizedDescription)")
    }
}
```

### 2. Private Envelope Data Structures

The envelope DTOs are private to `ClefFoundationModels`, ensuring zero leakage into public API surfaces while fully conforming to `Sendable`:

```swift
// MARK: - Cloudflare API Envelope Types

private struct CloudflareAPIEnvelope: Codable, Sendable {
    let result: SystemOneResponse?
    let success: Bool?
    let errors: [CloudflareAPIError]?
}

private struct CloudflareAPIError: Codable, Sendable {
    let code: Int?
    let message: String?
}
```

### 3. Server-Timing Telemetry Extraction

In addition to payload un-nesting, Cloudflare provides exact inference duration in edge response headers:
- `server-timing`: RFC 7668 header formatting (e.g., `cfL4;dur=12, inference;dur=45`).
- `x-envoy-upstream-service-time`: Milliseconds spent in upstream compute.

The parser extracts `inference;dur=<ms>` when present and stamps `decoded.serverDurationMs`, giving developers accurate on-device metrics separating network latency from edge GPU compute time.

---

## Implications

1. **Transparent Topology Portability**: Developers can switch between Cloudflare edge endpoints (`.workersAI`, `.aiGateway`) and local development servers (`.custom(url)`) using the identical client code and configuration.
2. **Deterministic Error Propagation**: Envelope errors with HTTP 200 (such as quota exceeded, internal worker aborts, or edge rate limits) are converted into structured `SystemOneError.apiError` instead of opaque JSON decoding failures.
3. **Zero Overhead for Local Inference**: Direct payload decoding is attempted first, adding sub-microsecond latency and avoiding envelope overhead for local `laya-serve` / Docker executions.
4. **Verified via Automated Swift Testing**: Verified offline with `MockClefBackendProtocol` in `Tests/ClefFoundationModelsTests/ClefBackendTests.swift` covering both valid envelope extractions and `success: false` error surfaces.

---

## Evidence / Sources

- Cloudflare Workers AI REST API Specification: Client API v4 Envelope standard (`result`, `success`, `errors`, `messages`).
- Implementation: `Sources/ClefFoundationModels/ClefHTTPBackend.swift`
- Verification Suite: `Tests/ClefFoundationModelsTests/ClefBackendTests.swift` (`testCloudflareEnvelopeEvaluation`, `testCloudflareEnvelopeErrorSurfaced`)
- Wire Format Parity: `tech-notes/0007-pluggable-system-one-backends-and-laya-serve.md`
- Model Schema Nuance: `tech-notes/0014-cloudflare-workers-ai-model-schema-nuance.md`
