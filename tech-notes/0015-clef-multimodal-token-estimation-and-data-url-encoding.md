# 0015 — Clef Multimodal Token Estimation, Data URL Wire Encoding & Camera Frame Downscaling

- **Date**: 2026-10-03
- **Author**: Peter Friese
- **Framework**: `SystemOneCore`, `ClefFoundationModels`
- **Upstream**: Cloudflare Workers AI (`@cf/cloudflare/clef-flash`), Apple Foundation Models (`Transcript.Segment.attachment`)

---

## Context

When evaluating multimodal prompts with Cloudflare Workers AI (`@cf/cloudflare/clef` or `@cf/cloudflare/clef-flash`) using native Apple Foundation Models attachments (`Transcript.Segment.attachment`), camera frames or photo attachments are serialized into the `SystemOneRequest` payload sent to Cloudflare's edge inference gateway:

```
POST https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/@cf/cloudflare/clef-flash
```

During live end-to-end integration with a high-resolution camera frame from an iOS device, Cloudflare Workers AI rejected the request with HTTP 413 Payload Too Large / Bad Request:

```
AiError: Ai: The estimated number of input and maximum output tokens (745945) exceeded this model context window limit (65536)
```

The Clef-Flash model provides an expansive 64k token context window (65,536 tokens). However, Cloudflare's input token estimator calculated an astronomical **745,945 tokens** for a single camera frame—over 11 times the maximum model context limit.

---

## Findings

### 1. Schema Validation Mismatch & BPE Tokenization Fallback

Cloudflare Workers AI accepts multimodal image inputs under the `images` JSON array. The underlying inference runtime recognizes two valid schema representations for each image element:
1. **Raw RFC 2397 Data URL String**: `"data:image/jpeg;base64,/9j/4AAQSkZJRg..."`
2. **Standard Image Object**: `{"content_type": "image/jpeg", "base64": "/9j/4AAQSkZJRg..."}`

When `SystemOneImage` was originally serialized as a custom keyed dictionary (`{"format": "image/png", "data_url": "data:image/png;base64,..."}`), Cloudflare's gateway schema validator did not identify it as an image attachment. 

Instead of terminating with a schema error or forwarding the data to the vision encoder, the Workers AI preprocessor treated the unrecognized object as plain textual input and passed the multi-megabyte Base64 payload directly to the standard Byte-Pair Encoding (BPE) text tokenizer:

```
                            ┌──────────────────────────────────────────────┐
                            │ Cloudflare Workers AI Preprocessor           │
                            └──────────────────────────────────────────────┘
                                                    │
                                     Incoming "images" Array
                                                    │
                 ┌──────────────────────────────────┴──────────────────────────────────┐
                 │                                                                     │
                 ▼                                                                     ▼
    Unrecognized Object Schema                                             Direct Data URL String
 { "format": ..., "data_url": ... }                                      "data:image/jpeg;base64,..."
                 │                                                                     │
                 ▼                                                                     ▼
    BPE Text Tokenizer Fallback                                            Clef Vision Patch Encoder
 ~3-4 chars / token on Base64 text                                      Grid decomposition (e.g. 14x14)
                 │                                                                     │
                 ▼                                                                     ▼
     745,945 Text Tokens ❌                                                 ~1,000 Vision Tokens ✅
 (Exceeds 65,536 Context Limit -> HTTP 413)                             (Comfortably within 64k Context)
```

Because Base64 strings consist of dense alphanumeric character sequences without natural language spaces or word boundaries, standard BPE algorithms tokenize Base64 at approximately 3 to 4 characters per token. A typical 2.5–3 MB Base64 string expands into **700,000+ text tokens**.

When properly routed to Clef's vision patch encoder, an image is divided into a spatial grid of image patches (e.g., 14×14 pixels per patch). Regardless of the Base64 representation length, a patch grid consumes only **~500 to 1,500 vision tokens**.

### 2. Mobile Sensor Resolutions & Uncompressed Raw Frames

Modern Apple mobile hardware (such as the 48MP Fusion camera on iPhone 17 Pro) captures images at resolutions up to 8064×6048 (48 megapixels) or 4032×3024 (12 megapixels). 

Transmitting raw, uncompressed 4K frames or PNG exports from mobile devices creates two critical bottlenecks:
1. **Network Payload Blowout**: An uncompressed 12MP–48MP frame encoded as PNG produces a 10–30 MB payload, easily exceeding mobile upload bandwidth limits and approaching `SystemOneImage.Guardrails.maxPayloadBytes` (13 MiB).
2. **Excessive Vision Patch Allocations**: Even when processed by vision transformers, extremely high-resolution images produce tens of thousands of vision patches, inflating inference latency on edge GPUs and risking context overflow when multiple images or long transcripts are evaluated simultaneously.

---

## Resolution

The issue is resolved across two layers: wire serialization and mobile image preprocessing.

### 1. Direct Single-Value RFC 2397 Data URL String Encoding

In `Sources/SystemOneCore/Models/SystemOneImage.swift`, `SystemOneImage` customizes its `Codable` implementation. During serialization, it encodes directly into a `singleValueContainer` as an RFC 2397 Data URL string (`"data:image/jpeg;base64,..."`), completely avoiding keyed wrapper dictionaries:

```swift
public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(dataURL)
}
```

To ensure backwards compatibility when receiving responses or parsing local configurations, `init(from decoder:)` flexibly accommodates both direct string decoding and legacy keyed containers (`content_type`, `base64`, `data_url`):

```swift
public init(from decoder: Decoder) throws {
    // 1. Single value container: RFC 2397 Data URL string
    if let singleValueContainer = try? decoder.singleValueContainer(),
       let urlString = try? singleValueContainer.decode(String.self) {
        let parts = urlString.split(separator: ";")
        guard urlString.hasPrefix("data:"), parts.count >= 2 else {
            throw DecodingError.dataCorruptedError(in: singleValueContainer, debugDescription: "Invalid RFC 2397 Data URL: \(urlString)")
        }
        let mime = String(parts[0].dropFirst(5))
        guard let format = Format(rawValue: mime) else {
            throw DecodingError.dataCorruptedError(in: singleValueContainer, debugDescription: "Unsupported MIME format in data URL: \(mime)")
        }
        self.format = format
        self.dataURL = urlString
        self.identifier = nil
        return
    }

    // 2. Keyed container fallback: {"format": ..., "data_url": ...} or {"content_type": ..., "base64": ...}
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ...
}
```

This guarantees that `SystemOneRequest` serializes image attachments as:

```json
{
  "state": "Visual inspection of parcel packaging",
  "model": "clef-flash",
  "images": [
    "data:image/jpeg;base64,/9j/4AAQSkZJRg..."
  ],
  "questions": {
    "is_damaged": {
      "type": "noul",
      "statement": "The parcel shows transit damage."
    }
  }
}
```

Cloudflare Workers AI detects the direct Data URL format and routes the attachment straight into Clef's vision patch encoder.

### 2. Camera Frame Downscaling & Lossy JPEG Compression

In `Sources/SystemOneCore/Attachment/TranscriptAttachmentExtractor.swift`, the attachment processing pipeline extracts `CGImage` attachments and scales them down prior to wire transmission:

```swift
case .image(let imageAttachment):
    if let url = imageAttachment.url, let image = try? SystemOneImage(fileURL: url, identifier: attachmentSegment.label) {
        return image
    }
    let cgImage = imageAttachment.cgImage
    guard let jpegData = convertCGImageToJPEG(cgImage, maxDimension: 1024, quality: 0.8) else {
        throw SystemOneError.modelExecutionError("Failed to convert image attachment to JPEG data.")
    }
    return SystemOneImage(data: jpegData, format: .jpeg, identifier: attachmentSegment.label)
```

The downscaling implementation `convertCGImageToJPEG` applies CoreGraphics scaling and lossy JPEG compression:

```swift
public static func convertCGImageToJPEG(
    _ cgImage: CGImage,
    maxDimension: Int = 1024,
    quality: Double = 0.8
) -> Data? {
    let origWidth = cgImage.width
    let origHeight = cgImage.height

    let finalImage: CGImage
    let maxDim = max(origWidth, origHeight)
    if maxDim > maxDimension {
        let scale = Double(maxDimension) / Double(maxDim)
        let targetWidth = max(1, Int((Double(origWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(origHeight) * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let scaledImage = context.makeImage() else {
            return nil
        }
        finalImage = scaledImage
    } else {
        finalImage = cgImage
    }

    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        mutableData as CFMutableData,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality
    ]
    CGImageDestinationAddImage(destination, finalImage, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return mutableData as Data
}
```

---

## Implications

1. **Payload Size Reduction**: Compressing to JPEG with `maxDimension = 1024` and `quality = 0.8` reduces 48MP/12MP raw captures (~5–20 MB) to approximately **100–200 KB**, enabling sub-second uploads over cellular networks.
2. **Deterministic Token Economy**: A 1024px image generates approximately **~1,000 vision patch tokens** in Clef-Flash, using less than **1.6%** of the 65,536 token context window and leaving ample space (>64,000 tokens) for conversation turns, document text, and multi-hypothesis questions.
3. **Guardrail Compliance**: Downscaling prevents client-side rejection by `SystemOneImage.Guardrails.maxMegapixels` (16 MP) and guarantees payloads stay well below `maxPayloadBytes` (13 MiB).
4. **Offline Test Fidelity**: The roundtrip serialization is verified in `Tests/SystemOneCoreTests/SystemOneImageTests.swift` ensuring that `SystemOneImage` encodes strictly to a single-value Data URL string (`"\"data:image/webp;base64,...\""`).

---

## Evidence / Sources

- Cloudflare Workers AI HTTP 413 Error: `AiError: Ai: The estimated number of input and maximum output tokens (745945) exceeded this model context window limit (65536)`
- Image Model & Codable Implementation: `Sources/SystemOneCore/Models/SystemOneImage.swift`
- Downscaling Pipeline: `Sources/SystemOneCore/Attachment/TranscriptAttachmentExtractor.swift`
- DTO Wire Structure: `Sources/SystemOneCore/Models/SystemOneDTOs.swift`
- Unit Test Suite: `Tests/SystemOneCoreTests/SystemOneImageTests.swift`
