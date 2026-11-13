# SystemOneFoundationModels

`SystemOneFoundationModels` is the top-level umbrella module for **System One for Apple Foundation Models**. Importing `SystemOneFoundationModels` automatically re-exports `SystemOneCore` alongside every System One provider module enabled by your Swift Package Manager **Package Traits** (SE-0450 / SE-0402).

```swift
import FoundationModels
import SystemOneFoundationModels

let session = LanguageModelSession(model: JevLanguageModel())
```

## Available Package Traits

| Trait | Type | Enabled Targets |
| :--- | :--- | :--- |
| **`All`** *(default)* | Persona | `Jev`, `Laya`, `LayaServe`, `Clef`, `OpenAI`, `Gemini` |
| **`OnDevice`** | Persona | `Laya` (`LayaOnDevice` Core ML / Apple Neural Engine only; zero HTTP clients) |
| **`Remote`** | Persona | `Jev`, `LayaServe`, `Clef`, `OpenAI`, `Gemini` (excludes Core ML `LayaOnDevice`) |
| **`Jev`** | Provider | `JevFoundationModels` (TypeSafe Jev Cloud) |
| **`Laya`** | Provider | `LayaOnDevice` (On-device Core ML & ANE) |
| **`LayaServe`** | Provider | `LayaFoundationModels` (Self-hosted `laya-serve`) |
| **`Clef`** | Provider | `ClefFoundationModels` (Cloudflare Clef 27B / 9B Multimodal) |
| **`OpenAI`** | Provider | `OpenAIFoundationModels` (OpenAI Decisions API `gpt-6-luna`) |
| **`Gemini`** | Provider | `GeminiFoundationModels` (Google Gemini Decisions API `gemini-decision-1`) |

## Selecting Traits in `Package.swift`

```swift
dependencies: [
    .package(
        url: "https://github.com/peterfriese/system-one-foundation-models.git",
        from: "0.3.0",
        traits: ["Remote"]
    )
]
```
