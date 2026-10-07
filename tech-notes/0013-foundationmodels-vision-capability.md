# 0013 — Foundation Models Vision Capability & Multimodal Attachment Gating

- **Date**: 2026-10-03
- **Author**: Peter Friese
- **Framework**: `FoundationModels` (iOS 27.0+, macOS 27.0+, visionOS 27.0+), `SystemOneCore`, `ClefFoundationModels`
- **Upstream**: Apple Foundation Models Framework SDK

---

## Context

When integrating multimodal decision models (such as Cloudflare Clef and Clef-Flash) into Apple's native `FoundationModels` framework, visual inputs (camera frames, screenshots, document photos) are submitted through `LanguageModelSession.respond(to:generating:)` using `Prompt` attachments:

```swift
let attachment = Attachment(cgImage)
let prompt = Prompt {
    "Evaluate the item shown in the camera capture."
    attachment
}
let response = try await session.respond(to: prompt, generating: VisualInspectionDecision.self)
```

During initial test harness execution with `Attachment(cgImage)` attachments, `LanguageModelSession` trapped immediately prior to invoking `LanguageModelExecutor.respond(to:model:streamingInto:)`, failing with an opaque runtime error:

```
Caught error: The selected model does not support image input. Consider trying again with a different model.
```

---

## Findings

### 1. SDK Gating via `LanguageModelCapabilities.Capability.vision`

Apple's `FoundationModels` framework performs client-side capability validation before passing any generation request to an underlying `LanguageModelExecutor`.

If a caller passes any `Attachment` containing visual data (such as `CGImage`, `CIImage`, `CVPixelBuffer`, or an image `URL`), `LanguageModelSession` inspects the provider's `capabilities` property:

```swift
public var capabilities: LanguageModelCapabilities { get }
```

In text-only decision models (e.g. TypeSafe Jev, Laya On-Device Core ML), models advertise:

```swift
public var capabilities: LanguageModelCapabilities {
    LanguageModelCapabilities([.guidedGeneration])
}
```

However, if `capabilities` does not include `.vision`, the Foundation Models session runtime throws a `LanguageModelSession.GenerationError.unsupportedCapability` exception:
*"The selected model does not support image input. Consider trying again with a different model."*

### 2. Required Multimodal Capabilities for Clef

To satisfy Apple's runtime gate while continuing to enforce schema-guided generation for System One decision models, `ClefLanguageModel` must explicitly advertise both `.guidedGeneration` and `.vision`:

```swift
public var capabilities: LanguageModelCapabilities {
    LanguageModelCapabilities([.guidedGeneration, .vision])
}
```

With `.vision` declared:
1. `LanguageModelSession` permits prompts containing `Attachment(cgImage)`, `Attachment(pixelBuffer)`, and other visual representations.
2. The session passes the full `Transcript` to `ClefExecutor`.
3. `TranscriptAttachmentExtractor` extracts the raw image data segments, validates dimensions and payload limits ($\le 16\text{MP}$, $\le 13\text{MB}$), and formats the request into `SystemOneRequest(images: [...])`.

---

## Implications

1. **Mandatory `.vision` Capability**: Any custom `LanguageModel` implementation intended for multimodal evaluation must declare `.vision` in its `capabilities` set.
2. **Backward Compatibility**: Text-only models (`JevLanguageModel`, `LayaLanguageModel`, `LayaOnDeviceLanguageModel`) continue to declare only `.guidedGeneration`. If an image is erroneously passed to a text-only session, Apple's SDK fails fast at the API boundary before network transmission or Core ML invocation.
3. **Verified Call-Site**: Developers can pass standard Apple `Attachment` objects inside `Prompt` builder closures with zero proprietary wrappers.

---

## Evidence / Sources

- Apple Foundation Models SDK Headers: `LanguageModelCapabilities.Capability.vision`
- Unit Test: `ClefLanguageModelTests.testLanguageModelSessionWithAttachment` in `Tests/ClefFoundationModelsTests/ClefLanguageModelTests.swift`
- Implementation: `Sources/ClefFoundationModels/ClefLanguageModel.swift`
