import Foundation
import SwiftUI
import FoundationModels
import SystemOneCore

@main
enum SecureAppCheckLauncher {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--cli") || args.contains("--help") || args.contains("-h") {
            Task {
                let exitCode = await SecureAppCheckCLI.run(arguments: args)
                Foundation.exit(exitCode)
            }
            dispatchMain()
        } else {
            MainActor.assumeIsolated {
                SecureAppCheckApp.main()
            }
        }
    }
}

struct SecureAppCheckApp: App {
    var body: some Scene {
        WindowGroup {
            SecureTriageView()
        }
    }
}

// MARK: - Headless Async CLI Runner (Zero MainActor Semaphore Blocking)

enum SecureAppCheckCLI {
    private enum TargetMode: Sendable {
        case emulator(explicit: Bool)
        case live
    }

    private struct CLIConfiguration: Sendable {
        var mode: TargetMode = .emulator(explicit: false)
        var provider: SecureProxyProvider = .jev
        var projectID: String = "my-secure-project"
        var appCheckToken: String = "debug-app-check-token-local"
    }

    static func run(arguments: [String]) async -> Int32 {
        let config: CLIConfiguration
        switch parseArguments(arguments) {
        case .help:
            printUsage()
            return 0
        case .invalid(let message):
            print("Error: \(message)\n")
            printUsage()
            return 1
        case .parsed(let parsed):
            config = parsed
        }

        print("=== 05-SecureAppCheckApp: Multi-Provider App Check Proxy Demo (CLI) ===")

        let targetURL: URL
        switch config.mode {
        case .live:
            do {
                targetURL = try ProxyEnvironment.production.endpoint(
                    projectID: config.projectID,
                    provider: config.provider
                )
            } catch {
                print("""
                ================================================================================
                  🛑 CONFIGURATION ERROR: INVALID FIREBASE PROJECT ID
                ================================================================================
                  \(error.localizedDescription)

                  Remediation:
                    Pass a valid Firebase Project ID (alphanumeric & hyphens, e.g. my-project-id):
                    swift run --package-path Examples/TraitSamples/05-SecureAppCheckApp SecureAppCheckApp --cli --live --provider \(config.provider.rawValue) --project my-project-id
                ================================================================================
                """)
                return 1
            }
            print("Target mode: Live Production Gateway (--live)")

        case .emulator(let explicit):
            let emulatorURL: URL
            do {
                emulatorURL = try ProxyEnvironment.localEmulator.endpoint(
                    projectID: config.projectID,
                    provider: config.provider
                )
            } catch {
                print("""
                ================================================================================
                  🛑 CONFIGURATION ERROR: INVALID FIREBASE PROJECT ID
                ================================================================================
                  \(error.localizedDescription)

                  Remediation:
                    Pass a valid Firebase Project ID (alphanumeric & hyphens, e.g. my-secure-project):
                    swift run --package-path Examples/TraitSamples/05-SecureAppCheckApp SecureAppCheckApp --cli --emulator --provider \(config.provider.rawValue) --project my-secure-project
                ================================================================================
                """)
                return 1
            }
            let modeLabel = explicit ? "Local Firebase Emulator (--emulator)" : "Local Firebase Emulator (default)"
            if await isEmulatorOnline() {
                targetURL = emulatorURL
                print("Target mode: \(modeLabel) (\(emulatorURL.absoluteString))")
            } else {
                print("""
                ================================================================================
                  ⚠️  CONFIGURATION ERROR: FIREBASE EMULATOR NOT REACHABLE
                ================================================================================
                  The Firebase Local Emulator is required on port 5001 to evaluate the
                  App Check secure proxy (\(config.provider.displayTitle)).
                  Synthetic mock bypasses are not permitted.

                  Remediation:
                    # Configure upstream credential (\(config.provider.requiredServerSecretSummary)), then run:
                    ./Examples/TraitSamples/05-SecureAppCheckApp/run-emulator-and-cli.sh --provider \(config.provider.rawValue)
                    # Or start manually:
                    # cd Examples/TraitSamples/05-SecureAppCheckApp/backend
                    # firebase emulators:start --only functions
                ================================================================================
                """)
                return 1
            }
        }

        let token = config.appCheckToken
        let urlSession: URLSession = {
            let urlConfig = URLSessionConfiguration.ephemeral
            urlConfig.timeoutIntervalForRequest = 15.0
            return URLSession(configuration: urlConfig)
        }()
        let session = config.provider.makeSession(
            proxyEndpoint: targetURL,
            credential: .appCheck { token },
            urlSession: urlSession
        )

        let alertText = "Customer database dump leaked on public forum with session tokens."

        print("Provider: \(config.provider.displayTitle)")
        print("Endpoint: \(targetURL.absoluteString)")
        print("Alert: \(alertText)")
        print("Evaluating via LanguageModelSession.choice...")

        do {
            let choice = try await session.choice(
                "Classify the incoming alert to determine response protocol",
                from: SecureTriageCategory.self,
                state: alertText
            )

            print("\n--- Evaluation Result ---")
            print("Provider: \(config.provider.rawValue)")
            print("Winner: \(choice.value.rawValue)")
            print("Confidence: \(String(format: "%.1f%%", choice.confidence * 100))")
            print("Distribution:")
            for category in SecureTriageCategory.allCases {
                let prob = choice.probability(of: category)
                print("  - \(category.rawValue): \(String(format: "%.2f%%", prob * 100))")
            }
            print("-------------------------\n")
            return 0
        } catch {
            print("\n[ERROR] Evaluation failed: \(error.localizedDescription)\n")
            return 1
        }
    }

    private enum ParseOutcome {
        case help
        case invalid(String)
        case parsed(CLIConfiguration)
    }

    private static func parseArguments(_ arguments: [String]) -> ParseOutcome {
        var config = CLIConfiguration()
        var sawEmulator = false
        var sawLive = false

        var iterator = arguments.dropFirst().makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--cli":
                continue
            case "--emulator":
                sawEmulator = true
                config.mode = .emulator(explicit: true)
            case "--live":
                sawLive = true
                config.mode = .live
            case "--provider":
                guard let val = iterator.next()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                      !val.isEmpty else {
                    return .invalid("Missing value after --provider. Expected: jev | laya | clef | openai | gemini | gateway.")
                }
                guard let provider = SecureProxyProvider(rawValue: val) else {
                    return .invalid("Unknown provider '\(val)'. Expected: jev | laya | clef | openai | gemini | gateway.")
                }
                config.provider = provider
            case "--project":
                guard let val = iterator.next(), !val.isEmpty else {
                    return .invalid("Missing value after --project.")
                }
                config.projectID = val
            case "--token":
                guard let val = iterator.next(), !val.isEmpty else {
                    return .invalid("Missing value after --token.")
                }
                config.appCheckToken = val
            case "--help", "-h":
                return .help
            default:
                if arg.hasPrefix("-") {
                    return .invalid("Unknown flag '\(arg)'.")
                }
            }
        }

        if sawEmulator && sawLive {
            return .invalid("Flags --emulator and --live are mutually exclusive.")
        }

        return .parsed(config)
    }

    private static func printUsage() {
        print("""
        05-SecureAppCheckApp — Multi-Provider App Check Proxy Demonstrator

        USAGE:
          SecureAppCheckApp [--cli] [--emulator | --live] [--provider <name>] [--project <id>] [--token <token>]

        OPTIONS:
          --cli                Run headless CLI evaluation instead of launching the SwiftUI window
          --emulator           Target local Firebase Functions Emulator on 127.0.0.1:5001 (default in --cli)
          --live               Target deployed Cloud Functions production gateway
          --provider <name>    jev | laya | clef | openai | gemini | gateway (default: jev)
                                 - jev/laya/clef/openai/gemini: Pattern A (<Provider>LanguageModel)
                                 - gateway: Pattern B (SystemOneLanguageModel canonical gateway)
          --project <id>       Firebase Project ID (default: my-secure-project)
          --token <token>      App Check token or local debug secret
          -h, --help           Show this help message
        """)
    }

    private static func isEmulatorOnline(timeout: TimeInterval = 0.5) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:5001/") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        do {
            _ = try await session.data(for: request)
            return true
        } catch {
            return false
        }
    }
}
