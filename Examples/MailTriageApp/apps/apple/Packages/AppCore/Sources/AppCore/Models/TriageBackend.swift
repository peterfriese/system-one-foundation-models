import Foundation

/// The six distinct runtime deployment topologies supported by MailTriage.
public enum TriageBackend: String, Sendable, Hashable, Codable, CaseIterable, Identifiable, CodingKeyRepresentable {
    /// Backend 1: Core ML running locally on Apple Silicon ANE/GPU (LayaOnDevice).
    case onDeviceCoreML

    /// Backend 2: Local HTTP server at 127.0.0.1:8000 (LayaFoundationModels).
    case localServe

    /// Backend 3: Enterprise self-hosted VPC at https://api.impossibl.com/v1.
    case hostedVPC

    /// Backend 4: Managed cloud SaaS (TypeSafe Jev Cloud API).
    case cloudAPI

    /// Backend 5: Cloudflare Workers AI edge inference (Clef / Clef-Flash).
    case cloudflareClef

    /// Backend 6: OpenAI Decisions API (GPT-6 Luna).
    /// See tech-notes/0017-openai-decisions-api-architecture.md
    case openaiDecisions

    /// Backend 7: Generative baseline (Apple Intelligence On-Device LLM).
    case generativeBaseline

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .onDeviceCoreML:
            return "On-Device Core ML"
        case .localServe:
            return "Local laya-serve"
        case .hostedVPC:
            return "Hosted VPC"
        case .cloudAPI:
            return "Jev Cloud API"
        case .cloudflareClef:
            return "Cloudflare Clef"
        case .openaiDecisions:
            return "OpenAI Decisions"
        case .generativeBaseline:
            return "Generative Baseline"
        }
    }

    public var shortName: String {
        switch self {
        case .onDeviceCoreML:
            return "Core ML"
        case .localServe:
            return "laya-serve"
        case .hostedVPC:
            return "Hosted VPC"
        case .cloudAPI:
            return "Jev Cloud"
        case .cloudflareClef:
            return "Clef Edge"
        case .openaiDecisions:
            return "OpenAI"
        case .generativeBaseline:
            return "Apple LLM"
        }
    }

    public var description: String {
        switch self {
        case .onDeviceCoreML:
            return "Apple Neural Engine (ANE) on-device inference with zero network ingress/egress."
        case .localServe:
            return "Local microservice daemon running on localhost loopback (127.0.0.1:8000)."
        case .hostedVPC:
            return "Private enterprise container deployment behind corporate firewall / VPC."
        case .cloudAPI:
            return "Managed TypeSafe Jev cloud endpoints with automated retries and jitter backoff."
        case .cloudflareClef:
            return "Cloudflare Workers AI multimodal edge decision model (9B / 27B)."
        case .openaiDecisions:
            return "OpenAI Decisions API (GPT-6 Luna) fast decision primitive at $0.10/1M tokens."
        case .generativeBaseline:
            return "Apple Intelligence on-device ~3B generative LLM baseline comparison."
        }
    }

    public var iconName: String {
        switch self {
        case .onDeviceCoreML:
            return "cpu.fill"
        case .localServe:
            return "network"
        case .hostedVPC:
            return "server.rack"
        case .cloudAPI:
            return "cloud.fill"
        case .cloudflareClef:
            return "bolt.shield.fill"
        case .openaiDecisions:
            return "sparkle.magnifyingglass"
        case .generativeBaseline:
            return "sparkles"
        }
    }

    /// Expected typical latency description for display in picker and benchmarks.
    public var latencyDescription: String {
        switch self {
        case .onDeviceCoreML:
            return "5–12 ms"
        case .localServe:
            return "8–15 ms"
        case .hostedVPC:
            return "40–70 ms"
        case .cloudAPI:
            return "60–90 ms"
        case .cloudflareClef:
            return "< 100 ms"
        case .openaiDecisions:
            return "40–80 ms"
        case .generativeBaseline:
            return "800–1,200 ms"
        }
    }

    /// Relative latency tier classification.
    public var latencyTier: String {
        switch self {
        case .onDeviceCoreML:
            return "< 15ms"
        case .localServe:
            return "< 20ms"
        case .hostedVPC:
            return "< 70ms"
        case .cloudAPI:
            return "< 100ms"
        case .cloudflareClef:
            return "< 100ms"
        case .openaiDecisions:
            return "< 100ms"
        case .generativeBaseline:
            return "> 1000ms"
        }
    }

    /// Privacy and topology classification level.
    public enum PrivacyLevel: String, Sendable, Hashable, Codable, CaseIterable {
        case onDevice = "On-Device"
        case local = "Local"
        case vpc = "VPC"
        case edge = "Edge"
        case cloud = "Cloud"
    }

    public var privacyLevel: PrivacyLevel {
        switch self {
        case .onDeviceCoreML, .generativeBaseline:
            return .onDevice
        case .localServe:
            return .local
        case .hostedVPC:
            return .vpc
        case .cloudflareClef:
            return .edge
        case .cloudAPI, .openaiDecisions:
            return .cloud
        }
    }

    /// Whether this backend operates completely offline without network requests.
    public var isOffline: Bool {
        switch self {
        case .onDeviceCoreML, .generativeBaseline:
            return true
        case .localServe, .hostedVPC, .cloudAPI, .cloudflareClef, .openaiDecisions:
            return false
        }
    }

    /// Whether this backend evaluates a fast non-autoregressive decision model.
    public var isDecisionModel: Bool {
        self != .generativeBaseline
    }

    /// Price in USD per million input tokens.
    public var pricePerMillionInputTokens: Double {
        switch self {
        case .onDeviceCoreML, .localServe, .hostedVPC, .generativeBaseline:
            return 0.0
        case .cloudAPI:
            return 0.20
        case .cloudflareClef:
            return 0.05
        case .openaiDecisions:
            return 0.10
        }
    }

    /// Whether this backend supports multimodal inputs (visual image attachments).
    public var supportsMultimodal: Bool {
        switch self {
        case .cloudflareClef, .openaiDecisions:
            return true
        case .onDeviceCoreML, .localServe, .hostedVPC, .cloudAPI, .generativeBaseline:
            return false
        }
    }
}
