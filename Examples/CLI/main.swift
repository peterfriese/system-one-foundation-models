import Foundation

// MARK: - Unified System One CLI Entry Point

func printCLIHelp() {
    print("""
    System One CLI (`system-one-cli`) ⚡️
    Unified multi-provider showcase for System One for Apple Foundation Models.

    USAGE:
      swift run system-one-cli [--provider <provider>] <subcommand> [options]

    PROVIDERS (--provider / -p or SYSTEM_ONE_PROVIDER env var, default: jev):
      jev             TypeSafe Jev Cloud (requires TYPESAFE_API_KEY)
      laya            Self-hosted laya-serve HTTP daemon (LAYA_SERVE_URL or localhost:8000)
      laya-ondevice   On-device Core ML / ANE Laya engine (requires LAYA_MODEL_PATH)
      clef            Cloudflare Clef Multimodal (CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN or localhost:8000)
      openai          OpenAI Decisions API (requires OPENAI_API_KEY)
      gemini          Google Gemini Decisions API (requires GEMINI_API_KEY or GOOGLE_API_KEY)
      proxy           Universal Reverse Proxy via SystemOneProxyBackend (requires SYSTEM_ONE_PROXY_URL)

    SUBCOMMANDS:
      ticket-triage [TEXT...]      Evaluate customer inquiry urgency, routing & frustration score
      duplicate-article            Run 2-layer deterministic + concurrent semantic deduplication
      file-organizer [OPTIONS]     Organize files with DynamicProfile & local secret redaction
                                     --demo | --path <dir> | --strategy <domain|workflow> | --apply | --dry-run
      vision-inspect [IMAGE_PATH]  Evaluate multimodal VisualInspectionDecision on a real image
                                     (Supported with --provider clef, openai, gemini, or proxy)

    GLOBAL FLAGS:
      -p, --provider <name>        Select execution provider
      -h, --help                   Show this help banner

    EXAMPLES:
      TYPESAFE_API_KEY="..." swift run system-one-cli --provider jev ticket-triage
      OPENAI_API_KEY="..."   swift run system-one-cli --provider openai duplicate-article
      GEMINI_API_KEY="..."   swift run system-one-cli --provider gemini vision-inspect
      swift run system-one-cli --provider laya file-organizer --demo
    """)
}

let rawArgs = Array(CommandLine.arguments.dropFirst())

if rawArgs.isEmpty || rawArgs.contains("--help") || rawArgs.contains("-h") || rawArgs.first == "help" {
    printCLIHelp()
    exit(0)
}

var selectedProviderRaw: String? = CLIEnvironment.value(for: "SYSTEM_ONE_PROVIDER")
var subcommand: String?
var subcommandArgs: [String] = []

var index = 0
while index < rawArgs.count {
    let arg = rawArgs[index]
    if arg == "--provider" || (arg == "-p" && subcommand == nil) {
        guard index + 1 < rawArgs.count else {
            print("❌ Error: Missing value for \(arg). Run `swift run system-one-cli --help`.")
            exit(1)
        }
        selectedProviderRaw = rawArgs[index + 1]
        index += 2
        continue
    } else if arg.hasPrefix("--provider=") {
        selectedProviderRaw = String(arg.dropFirst("--provider=".count))
        index += 1
        continue
    }

    if subcommand == nil {
        subcommand = arg
    } else {
        subcommandArgs.append(arg)
    }
    index += 1
}

let providerKey = selectedProviderRaw ?? "jev"
guard let cliProvider = CLIProvider.parse(providerKey) else {
    print("""
    ❌ Unknown provider '\(providerKey)'.
    Supported providers: \(CLIProvider.allCases.map(\.rawValue).joined(separator: ", "))
    Run `swift run system-one-cli --help` for usage.
    """)
    exit(1)
}

guard let command = subcommand?.lowercased() else {
    print("❌ Missing subcommand. Choose one of: ticket-triage, duplicate-article, file-organizer, vision-inspect.")
    print("Run `swift run system-one-cli --help` for usage.")
    exit(1)
}

switch command {
case "ticket-triage":
    let configured = ProviderFactory.build(provider: cliProvider)
    await TicketTriageCommand.run(provider: configured, arguments: subcommandArgs)

case "duplicate-article":
    let configured = ProviderFactory.build(provider: cliProvider)
    await DuplicateArticleCommand.run(provider: configured, arguments: subcommandArgs)

case "file-organizer":
    let configured = ProviderFactory.build(provider: cliProvider)
    await FileOrganizerCommand.run(provider: configured, arguments: subcommandArgs)

case "vision-inspect":
    // Validate subcommand vision support even before credential resolution when text-only provider is requested
    if !cliProvider.supportsVision {
        print("""
        ================================================================================
          🛑 UNSUPPORTED CAPABILITY: \(cliProvider.displayName.uppercased()) IS TEXT-ONLY
        ================================================================================
          The 'vision-inspect' subcommand attaches real image pixels and requires a
          vision-capable System One provider (Clef, OpenAI, Gemini, or Vision Proxy).

          Remediation — choose a vision-capable provider:
            swift run system-one-cli --provider clef vision-inspect
            swift run system-one-cli --provider openai vision-inspect
            swift run system-one-cli --provider gemini vision-inspect
            swift run system-one-cli --provider proxy vision-inspect
        ================================================================================
        """)
        exit(1)
    }
    let configured = ProviderFactory.build(provider: cliProvider)
    await VisionInspectCommand.run(provider: configured, arguments: subcommandArgs)

default:
    print("""
    ❌ Unknown subcommand '\(command)'.
    Supported subcommands: ticket-triage, duplicate-article, file-organizer, vision-inspect
    Run `swift run system-one-cli --help` for usage.
    """)
    exit(1)
}
