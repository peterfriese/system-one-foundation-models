import Foundation
import FoundationModels
import SystemOneCore
import JevFoundationModels
import LayaFoundationModels
import LayaOnDevice
import ClefFoundationModels
import OpenAIFoundationModels
import GeminiFoundationModels

// MARK: - Provider Enumeration

enum CLIProvider: String, CaseIterable, Sendable {
    case jev = "jev"
    case laya = "laya"
    case layaOnDevice = "laya-ondevice"
    case clef = "clef"
    case openai = "openai"
    case gemini = "gemini"
    case proxy = "proxy"

    var displayName: String {
        switch self {
        case .jev: return "TypeSafe Jev Cloud"
        case .laya: return "Laya Self-Hosted (laya-serve)"
        case .layaOnDevice: return "Laya On-Device (Core ML / ANE)"
        case .clef: return "Cloudflare Clef Multimodal"
        case .openai: return "OpenAI Decisions API"
        case .gemini: return "Google Gemini Decisions API"
        case .proxy: return "Universal Reverse Proxy (SystemOneProxyBackend)"
        }
    }

    var supportsVision: Bool {
        switch self {
        case .clef, .openai, .gemini, .proxy:
            return true
        case .jev, .laya, .layaOnDevice:
            return false
        }
    }

    static func parse(_ raw: String) -> CLIProvider? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "jev": return .jev
        case "laya", "laya-serve", "layaserve": return .laya
        case "laya-ondevice", "layaondevice", "ondevice", "coreml": return .layaOnDevice
        case "clef", "cloudflare": return .clef
        case "openai": return .openai
        case "gemini", "google": return .gemini
        case "proxy": return .proxy
        default: return nil
        }
    }
}

// MARK: - Environment & .env Lookup

enum CLIEnvironment {
    static func value(for key: String) -> String? {
        if let envVal = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envVal.isEmpty {
            return envVal
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let searchPaths = [
            cwd.appendingPathComponent(".env"),
            cwd.deletingLastPathComponent().appendingPathComponent(".env")
        ]

        for envURL in searchPaths {
            guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { continue }
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == key {
                    var val = parts[1].trimmingCharacters(in: .whitespaces)
                    if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                        val = String(val.dropFirst().dropLast())
                    }
                    if !val.isEmpty { return val }
                }
            }
        }
        return nil
    }
}

// MARK: - Configured Provider Container

struct ConfiguredProvider: Sendable {
    enum UnderlyingModel: Sendable {
        case jev(JevLanguageModel)
        case laya(LayaLanguageModel)
        case layaOnDevice(LayaOnDeviceLanguageModel)
        case clef(ClefLanguageModel)
        case openai(OpenAILanguageModel)
        case gemini(GeminiLanguageModel)
        case proxy(SystemOneLanguageModel)
    }

    let provider: CLIProvider
    let endpointSummary: String
    let underlying: UnderlyingModel

    var supportsVision: Bool {
        switch underlying {
        case .clef, .openai, .gemini:
            return true
        case .proxy(let model):
            return model.supportsVision
        case .jev, .laya, .layaOnDevice:
            return false
        }
    }

    func makeSession() -> LanguageModelSession {
        switch underlying {
        case .jev(let model):
            return LanguageModelSession(model: model)
        case .laya(let model):
            return LanguageModelSession(model: model)
        case .layaOnDevice(let model):
            return LanguageModelSession(model: model)
        case .clef(let model):
            return LanguageModelSession(model: model)
        case .openai(let model):
            return LanguageModelSession(model: model)
        case .gemini(let model):
            return LanguageModelSession(model: model)
        case .proxy(let model):
            return LanguageModelSession(model: model)
        }
    }

    func makeProfiledSession(auditLogger: TelemetryAuditModifier? = nil) -> LanguageModelSession {
        switch underlying {
        case .jev(let model):
            return LanguageModelSession(profile: DirectoryOrganizerProfile(model: model, auditLogger: auditLogger))
        case .laya(let model):
            return LanguageModelSession(profile: DirectoryOrganizerProfile(model: model, auditLogger: auditLogger))
        case .layaOnDevice(let model):
            return LanguageModelSession(profile: DirectoryOrganizerProfile(model: model, auditLogger: auditLogger))
        case .clef(let model):
            return LanguageModelSession(profile: DirectoryOrganizerProfile(model: model, auditLogger: auditLogger))
        case .openai(let model):
            return LanguageModelSession(profile: DirectoryOrganizerProfile(model: model, auditLogger: auditLogger))
        case .gemini(let model):
            return LanguageModelSession(profile: DirectoryOrganizerProfile(model: model, auditLogger: auditLogger))
        case .proxy(let model):
            return LanguageModelSession(profile: DirectoryOrganizerProfile(model: model, auditLogger: auditLogger))
        }
    }

    func requireVisionSupport(forCommand subcommand: String) {
        guard supportsVision else {
            print("""
            ================================================================================
              🛑 UNSUPPORTED CAPABILITY: \(provider.displayName.uppercased()) IS TEXT-ONLY
            ================================================================================
              The '\(subcommand)' subcommand attaches real camera/image pixels and requires
              a vision-capable System One provider (Clef, OpenAI, Gemini, or Vision Proxy).

              Remediation — choose a vision-capable provider:
                swift run system-one-cli --provider clef \(subcommand)
                swift run system-one-cli --provider openai \(subcommand)
                swift run system-one-cli --provider gemini \(subcommand)
                swift run system-one-cli --provider proxy \(subcommand)
            ================================================================================
            """)
            exit(1)
        }
    }

    func failFastOnError(_ error: any Error) -> Never {
        print("""

        ================================================================================
          🛑 EXECUTION FAILED (\(provider.displayName))
        ================================================================================
          \(error.localizedDescription)

        \(remediationHint)
        ================================================================================
        """)
        exit(1)
    }

    private var remediationHint: String {
        switch provider {
        case .jev:
            return """
              Remediation:
                export TYPESAFE_API_KEY="your-typesafe-api-key"
                swift run system-one-cli --provider jev ticket-triage
            """
        case .laya:
            return """
              Remediation — ensure laya-serve is running and reachable:
                uv tool install laya-serve && laya-serve
                # Or point to a custom host:
                export LAYA_SERVE_URL="http://127.0.0.1:8000"
            """
        case .layaOnDevice:
            return """
              Remediation — provide a compiled Core ML model bundle:
                python3 Tools/CoreMLConverter/convert_laya_to_coreml.py
                export LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc"
            """
        case .clef:
            return """
              Remediation — run a local Clef runner or configure Cloudflare Workers AI:
                docker run -p 8000:8000 ghcr.io/typesafe-ai/clef-flash:latest
                # Or for Cloudflare Workers AI edge:
                export CLOUDFLARE_ACCOUNT_ID="your-account-id"
                export CLOUDFLARE_API_TOKEN="your-api-token"
            """
        case .openai:
            return """
              Remediation:
                export OPENAI_API_KEY="sk-..."
                swift run system-one-cli --provider openai ticket-triage
            """
        case .gemini:
            return """
              Remediation:
                export GEMINI_API_KEY="AIza..."
                swift run system-one-cli --provider gemini ticket-triage
            """
        case .proxy:
            return """
              Remediation — verify your reverse proxy URL and optional bearer token:
                export SYSTEM_ONE_PROXY_URL="https://your-gateway.example.com/v1/evaluate"
                export SYSTEM_ONE_PROXY_TOKEN="your-proxy-token" # optional
            """
        }
    }
}

// MARK: - Provider Factory (Principle 7: Fail-Fast Real Execution)

enum ProviderFactory {
    static func build(provider: CLIProvider) -> ConfiguredProvider {
        let retryPolicy = RetryPolicy(
            maxAttempts: 3,
            initialDelay: .milliseconds(250),
            multiplier: 2.0,
            jitter: 0.15,
            retryableStatuses: [429, 503, 529]
        )

        switch provider {
        case .jev:
            guard let apiKey = CLIEnvironment.value(for: "TYPESAFE_API_KEY") else {
                printMissingBanner(
                    title: "MISSING TYPESAFE_API_KEY",
                    detail: "TypeSafe Jev cloud evaluation requires a valid TYPESAFE_API_KEY.",
                    remediation: """
                      export TYPESAFE_API_KEY="your-typesafe-api-key"
                      swift run system-one-cli --provider jev ticket-triage
                    """
                )
            }
            let model = JevLanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)
            return ConfiguredProvider(
                provider: .jev,
                endpointSummary: JevEndpoint.hosted.url.absoluteString,
                underlying: .jev(model)
            )

        case .laya:
            if let rawURL = CLIEnvironment.value(for: "LAYA_SERVE_URL") {
                guard let url = URL(string: rawURL), url.scheme != nil, url.host != nil else {
                    printMissingBanner(
                        title: "INVALID LAYA_SERVE_URL",
                        detail: "LAYA_SERVE_URL '\(rawURL)' is not a valid HTTP(S) URL.",
                        remediation: """
                          export LAYA_SERVE_URL="http://127.0.0.1:8000"
                          swift run system-one-cli --provider laya ticket-triage
                        """
                    )
                }
                let apiKey = CLIEnvironment.value(for: "LAYA_API_KEY")
                let model = LayaLanguageModel(endpoint: .custom(url), apiKey: apiKey, retryPolicy: retryPolicy)
                return ConfiguredProvider(
                    provider: .laya,
                    endpointSummary: url.absoluteString,
                    underlying: .laya(model)
                )
            } else {
                let port = CLIEnvironment.value(for: "LAYA_LOCAL_PORT").flatMap(Int.init) ?? 8000
                let endpoint = LayaEndpoint.local(port: port)
                let model = LayaLanguageModel(endpoint: endpoint, retryPolicy: retryPolicy)
                return ConfiguredProvider(
                    provider: .laya,
                    endpointSummary: endpoint.url.absoluteString,
                    underlying: .laya(model)
                )
            }

        case .layaOnDevice:
            let explicitURL: URL?
            if let rawPath = CLIEnvironment.value(for: "LAYA_MODEL_PATH") {
                let expanded = (rawPath as NSString).expandingTildeInPath
                explicitURL = URL(fileURLWithPath: expanded)
            } else {
                explicitURL = nil
            }
            do {
                let model = try LayaOnDeviceLanguageModel(modelURL: explicitURL)
                return ConfiguredProvider(
                    provider: .layaOnDevice,
                    endpointSummary: explicitURL?.path ?? "Local Core ML (LayaDecisionModel)",
                    underlying: .layaOnDevice(model)
                )
            } catch {
                printMissingBanner(
                    title: "MISSING ON-DEVICE LAYA CORE ML MODEL",
                    detail: error.localizedDescription,
                    remediation: """
                      python3 Tools/CoreMLConverter/convert_laya_to_coreml.py
                      export LAYA_MODEL_PATH="/path/to/LayaDecisionModel.mlmodelc"
                      swift run system-one-cli --provider laya-ondevice ticket-triage
                    """
                )
            }

        case .clef:
            let accountID = CLIEnvironment.value(for: "CLOUDFLARE_ACCOUNT_ID")
            let apiToken = CLIEnvironment.value(for: "CLOUDFLARE_API_TOKEN")
            if accountID != nil || apiToken != nil {
                guard let validAccount = accountID, let validToken = apiToken else {
                    printMissingBanner(
                        title: "INCOMPLETE CLOUDFLARE CREDENTIALS",
                        detail: "Both CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN are required for Workers AI.",
                        remediation: """
                          export CLOUDFLARE_ACCOUNT_ID="your-cloudflare-account-id"
                          export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"
                          swift run system-one-cli --provider clef vision-inspect
                        """
                    )
                }
                let endpoint = ClefEndpoint.workersAI(accountID: validAccount, model: .clefFlash)
                do {
                    _ = try endpoint.validatedURL()
                } catch {
                    printMissingBanner(
                        title: "INVALID CLOUDFLARE ACCOUNT ID",
                        detail: error.localizedDescription,
                        remediation: """
                          export CLOUDFLARE_ACCOUNT_ID="your-cloudflare-account-id"
                          export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"
                        """
                    )
                }
                let model = ClefLanguageModel(endpoint: endpoint, apiToken: validToken, retryPolicy: retryPolicy)
                return ConfiguredProvider(
                    provider: .clef,
                    endpointSummary: endpoint.url.absoluteString,
                    underlying: .clef(model)
                )
            } else if let customRaw = CLIEnvironment.value(for: "CLEF_URL"), let customURL = URL(string: customRaw) {
                let endpoint = ClefEndpoint.custom(customURL, model: .clefFlash)
                let model = ClefLanguageModel(endpoint: endpoint, retryPolicy: retryPolicy)
                return ConfiguredProvider(
                    provider: .clef,
                    endpointSummary: customURL.absoluteString,
                    underlying: .clef(model)
                )
            } else {
                let port = CLIEnvironment.value(for: "CLEF_LOCAL_PORT").flatMap(Int.init) ?? 8000
                let endpoint = ClefEndpoint.local(port: port, model: .clefFlash)
                let model = ClefLanguageModel(endpoint: endpoint, retryPolicy: retryPolicy)
                return ConfiguredProvider(
                    provider: .clef,
                    endpointSummary: endpoint.url.absoluteString,
                    underlying: .clef(model)
                )
            }

        case .openai:
            guard let apiKey = CLIEnvironment.value(for: "OPENAI_API_KEY") else {
                printMissingBanner(
                    title: "MISSING OPENAI_API_KEY",
                    detail: "OpenAI Decisions API evaluation requires a valid OPENAI_API_KEY.",
                    remediation: """
                      export OPENAI_API_KEY="sk-..."
                      swift run system-one-cli --provider openai ticket-triage
                    """
                )
            }
            let model = OpenAILanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)
            return ConfiguredProvider(
                provider: .openai,
                endpointSummary: OpenAIDecisionsEndpoint.defaultURL.absoluteString,
                underlying: .openai(model)
            )

        case .gemini:
            guard let apiKey = CLIEnvironment.value(for: "GEMINI_API_KEY")
                ?? CLIEnvironment.value(for: "GOOGLE_API_KEY") else {
                printMissingBanner(
                    title: "MISSING GEMINI_API_KEY",
                    detail: "Google Gemini Decisions evaluation requires GEMINI_API_KEY (or GOOGLE_API_KEY).",
                    remediation: """
                      export GEMINI_API_KEY="AIza..."
                      swift run system-one-cli --provider gemini ticket-triage
                    """
                )
            }
            let model = GeminiLanguageModel(apiKey: apiKey, retryPolicy: retryPolicy)
            return ConfiguredProvider(
                provider: .gemini,
                endpointSummary: GeminiDecisionsEndpoint.defaultURL.absoluteString,
                underlying: .gemini(model)
            )

        case .proxy:
            guard let rawURL = CLIEnvironment.value(for: "SYSTEM_ONE_PROXY_URL")
                ?? CLIEnvironment.value(for: "TYPESAFE_PROXY_URL"),
                  let proxyURL = URL(string: rawURL) else {
                printMissingBanner(
                    title: "MISSING SYSTEM_ONE_PROXY_URL",
                    detail: "Reverse proxy evaluation requires SYSTEM_ONE_PROXY_URL (HTTPS or localhost HTTP).",
                    remediation: """
                      export SYSTEM_ONE_PROXY_URL="https://your-gateway.example.com/v1/evaluate"
                      export SYSTEM_ONE_PROXY_TOKEN="optional-bearer-token"
                      swift run system-one-cli --provider proxy ticket-triage
                    """
                )
            }
            do {
                try ProxyEndpointValidator.validate(proxyURL)
            } catch {
                printMissingBanner(
                    title: "INVALID PROXY ENDPOINT",
                    detail: error.localizedDescription,
                    remediation: """
                      export SYSTEM_ONE_PROXY_URL="https://your-gateway.example.com/v1/evaluate"
                    """
                )
            }
            let credential: ProxyCredential
            if let token = CLIEnvironment.value(for: "SYSTEM_ONE_PROXY_TOKEN") {
                credential = .bearer { token }
            } else {
                credential = .custom { _ in }
            }
            let visionFlag = CLIEnvironment.value(for: "SYSTEM_ONE_PROXY_VISION")?.lowercased()
            let supportsVision = (visionFlag != "false" && visionFlag != "0")
            let model = SystemOneLanguageModel(
                proxyEndpoint: proxyURL,
                credential: credential,
                supportsVision: supportsVision,
                retryPolicy: retryPolicy
            )
            return ConfiguredProvider(
                provider: .proxy,
                endpointSummary: proxyURL.absoluteString,
                underlying: .proxy(model)
            )
        }
    }

    private static func printMissingBanner(title: String, detail: String, remediation: String) -> Never {
        print("""
        ================================================================================
          🛑 CONFIGURATION ERROR: \(title)
        ================================================================================
          \(detail)
          Per AGENTS.md Principle 7, synthetic mock fallbacks are strictly prohibited.

          Remediation:
        \(remediation)
        ================================================================================
        """)
        exit(1)
    }
}
