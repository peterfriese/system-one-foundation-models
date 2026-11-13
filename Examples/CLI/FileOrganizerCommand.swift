import Foundation
import FoundationModels
import SystemOneCore
#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Organization Strategy & Dynamic Profile Properties

public enum OrganizationStrategy: String, Sendable, CaseIterable {
    case domain
    case workflow
}

extension SessionPropertyValues {
    @SessionPropertyEntry
    public var organizationStrategy: OrganizationStrategy = .domain

    @SessionPropertyEntry
    public var quarantineSensitive: Bool = true
}

// MARK: - Reusable Dynamic Profile Modifier & Generic Profile

public struct TelemetryAuditModifier: LanguageModelSession.DynamicProfileModifier, Sendable {
    public let auditTag: String
    public let onPrompt: (@Sendable (Transcript.Prompt) -> Void)?
    public let onResponse: (@Sendable (Transcript.Response) -> Void)?

    public init(
        auditTag: String = "dynamic-profile",
        onPrompt: (@Sendable (Transcript.Prompt) -> Void)? = nil,
        onResponse: (@Sendable (Transcript.Response) -> Void)? = nil
    ) {
        self.auditTag = auditTag
        self.onPrompt = onPrompt
        self.onResponse = onResponse
    }

    public func body(content: Content) -> some LanguageModelSession.DynamicProfile {
        content
            .onPrompt { prompt in onPrompt?(prompt) }
            .onResponse { response in onResponse?(response) }
    }
}

public struct DirectoryOrganizerProfile<Model: LanguageModel & Sendable>: LanguageModelSession.DynamicProfile, Sendable {
    @LanguageModelSession.SessionProperty(\.organizationStrategy) var strategy: OrganizationStrategy
    @LanguageModelSession.SessionProperty(\.quarantineSensitive) var quarantineSensitive: Bool

    public let model: Model
    public let auditLogger: TelemetryAuditModifier?

    public init(model: Model, auditLogger: TelemetryAuditModifier? = nil) {
        self.model = model
        self.auditLogger = auditLogger
    }

    public var body: some LanguageModelSession.DynamicProfile {
        if strategy == .workflow {
            LanguageModelSession.Profile {
                Instructions("""
                You are analyzing files to organize them into an actionable workflow hierarchy:
                - Action Required: Invoices needing payment, open bug reports, items awaiting signature or review.
                - Reference: Specifications, architecture documents, code files, and user guides.
                - Archive: Historical agreements, completed task logs, or personal scratchpads.
                - Sensitive Content: Detect any secrets, API keys, private passwords, credentials, or confidential PII.
                """)
            }
            .model(model)
            .historyTransform { Self.isolateCurrentTurn($0) }
            .modifier(auditLogger ?? TelemetryAuditModifier(auditTag: "workflow"))
        } else {
            LanguageModelSession.Profile {
                Instructions("""
                You are analyzing files to organize them into domain-specific knowledge folders:
                - Finance & Billing: Invoices, receipts, payout statements, expense summaries.
                - Engineering & Code: Source files, scripts, architectural specs, API definitions.
                - Legal & Contracts: NDAs, employment agreements, vendor terms, licenses.
                - Documentation: Guides, runbooks, READMEs, project plans.
                - Personal Notes: Quick memos, shopping lists, journals.
                - Sensitive Content: Detect any secrets, API keys, private passwords, credentials, or confidential PII.
                """)
            }
            .model(model)
            .historyTransform { Self.isolateCurrentTurn($0) }
            .modifier(auditLogger ?? TelemetryAuditModifier(auditTag: "domain"))
        }
    }

    public static func isolateCurrentTurn(_ entries: [Transcript.Entry]) -> [Transcript.Entry] {
        let instructions = entries.filter {
            if case .instructions = $0 { return true }
            return false
        }
        if let last = entries.last, case .prompt = last {
            return instructions + [last]
        }
        return entries
    }
}

// MARK: - @Generable Decision Schema

@Generable
enum ContentDomain: String, CaseIterable, Sendable {
    case finance = "finance"
    case engineering = "engineering"
    case legal = "legal"
    case documentation = "documentation"
    case personal = "personal"
}

@Generable
enum WorkflowStage: String, CaseIterable, Sendable {
    case actionRequired = "action_required"
    case reference = "reference"
    case archive = "archive"
}

@Generable
struct FileTriageDecision: Sendable {
    @Guide(description: "The primary semantic topic of the file")
    var domain: ContentDomain

    @Guide(description: "Recommended workflow triage bucket based on immediate actionability")
    var workflowStage: WorkflowStage

    @Guide(description: "True if this file contains sensitive secrets, API keys, passwords, credentials, or private PII")
    var isSensitive: Bool

    @Guide(description: "Decision confidence rating from 0 (ambiguous/uncertain) to 3 (clear definitive match)", .range(0...3))
    var confidenceScore: Int
}

// MARK: - Local Secret Scanner (Privacy Boundary)

enum LocalSecretScanner {
    private static let sensitiveKeywords: [String] = [
        "api_key", "apikey", "secret_key", "secretkey", "private_key",
        "access_key", "bearer ", "aws_secret", "stripe_secret",
        "begin rsa private key", "begin openssh private key",
        "begin private key", "begin ec private key",
        "password=", "passwd=", "database_url=", "jwt_secret", "jwt_signing"
    ]

    private static let sensitiveExtensions: Set<String> = ["env", "pem", "key", "keystore", "p12"]
    private static let sensitiveFilePrefixes: [String] = ["id_rsa", "id_ed25519", "credentials", ".env"]

    static func scan(fileURL: URL, sampleText: String) -> Bool {
        let name = fileURL.lastPathComponent.lowercased()
        let ext = fileURL.pathExtension.lowercased()
        if sensitiveExtensions.contains(ext) { return true }
        for prefix in sensitiveFilePrefixes where name.hasPrefix(prefix) || name.contains(prefix) {
            return true
        }
        let lower = sampleText.lowercased()
        return sensitiveKeywords.contains { lower.contains($0) }
    }

    static func redactSensitiveContent(in text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            let isSensitive = sensitiveKeywords.contains { lower.contains($0) }
            if isSensitive && line.contains("=") {
                let parts = line.split(separator: "=", maxSplits: 1)
                return "\(parts[0])=[REDACTED_SECRET]"
            } else if isSensitive {
                return "[REDACTED_LINE: SENSITIVE_CREDENTIAL]"
            }
            return line
        }.joined(separator: "\n")
    }
}

// MARK: - File Organizer Engine

struct DiscoveredFile: Sendable, Hashable {
    let url: URL
    let relativePath: String
    let sizeInBytes: Int
    let contentSample: String
    let isLocallySensitive: Bool
}

struct OrganizedFile: Sendable {
    let file: DiscoveredFile
    let decision: FileTriageDecision
    let destinationRelativePath: String
    let durationMs: Double
    let serverDurationMs: Double?
    let inputTokens: Int
    let outputTokens: Int
}

struct FileOrganizer: Sendable {
    static let managedDirectoryNames: Set<String> = ["Organized", "Workflow", "Quarantine_Vault", "Review_Queue"]
    let session: LanguageModelSession

    func discoverFiles(in directoryURL: URL) throws -> [DiscoveredFile] {
        var results: [DiscoveredFile] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isHiddenKey, .isSymbolicLinkKey]
        let fm = FileManager.default
        let resolvedDir = directoryURL.resolvingSymlinksInPath()

        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            if values.isDirectory == true {
                if Self.managedDirectoryNames.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, values.isHidden != true else { continue }
            if values.isSymbolicLink == true {
                guard fileURL.resolvingSymlinksInPath().path.hasPrefix(resolvedDir.path) else { continue }
            }

            var relative = fileURL.path.replacingOccurrences(of: directoryURL.path, with: "")
            while relative.hasPrefix("/") { relative.removeFirst() }

            let sample = Self.extractSnippet(from: fileURL, maxBytes: 1_048_576)
            results.append(DiscoveredFile(
                url: fileURL,
                relativePath: relative,
                sizeInBytes: values.fileSize ?? 0,
                contentSample: sample,
                isLocallySensitive: LocalSecretScanner.scan(fileURL: fileURL, sampleText: sample)
            ))
        }
        return results.sorted { $0.relativePath < $1.relativePath }
    }

    private static func extractSnippet(from url: URL, maxBytes: Int) -> String {
        if url.pathExtension.lowercased() == "pdf" {
            #if canImport(PDFKit)
            if let doc = PDFDocument(url: url),
               let page = doc.page(at: 0),
               let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
            #endif
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "(unreadable)" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return "(empty)" }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "(binary)"
    }

    static func resolveDestinationPath(
        for file: DiscoveredFile,
        decision: FileTriageDecision,
        strategy: OrganizationStrategy,
        quarantineSensitive: Bool
    ) -> String {
        let filename = URL(fileURLWithPath: file.relativePath).lastPathComponent
        if quarantineSensitive && decision.isSensitive {
            return "Quarantine_Vault/\(filename)"
        }
        if decision.confidenceScore < 2 {
            return "Review_Queue/\(filename)"
        }
        switch strategy {
        case .workflow:
            switch decision.workflowStage {
            case .actionRequired: return "Workflow/1_Action_Required/\(filename)"
            case .reference: return "Workflow/2_Reference_Material/\(filename)"
            case .archive: return "Workflow/3_Archive/\(filename)"
            }
        case .domain:
            switch decision.domain {
            case .finance: return "Organized/Finance_and_Billing/\(filename)"
            case .engineering: return "Organized/Engineering_and_Code/\(filename)"
            case .legal: return "Organized/Legal_and_Contracts/\(filename)"
            case .documentation: return "Organized/Documentation/\(filename)"
            case .personal: return "Organized/Personal_Notes/\(filename)"
            }
        }
    }

    func organize(
        directoryURL: URL,
        applyChanges: Bool,
        onFileEvaluated: (@Sendable (OrganizedFile, Int, Int) -> Void)? = nil
    ) async throws -> [OrganizedFile] {
        let discovered = try discoverFiles(in: directoryURL)
        var organized: [OrganizedFile] = []

        for (index, file) in discovered.enumerated() {
            try Task.checkCancellation()
            let start = CFAbsoluteTimeGetCurrent()
            let excerpt = file.isLocallySensitive
                ? LocalSecretScanner.redactSensitiveContent(in: file.contentSample)
                : file.contentSample
            let prompt = """
            Evaluate this file:
            - Filename: \(file.relativePath)
            - Size: \(file.sizeInBytes) bytes
            - Content Excerpt:
            \"\"\"
            \(excerpt.prefix(800))
            \"\"\"
            """

            let response = try await session.respond(to: prompt, generating: FileTriageDecision.self)
            let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            var finalDecision = response.content
            if file.isLocallySensitive {
                finalDecision.isSensitive = true
            }

            let destination = Self.resolveDestinationPath(
                for: file,
                decision: finalDecision,
                strategy: session.properties.organizationStrategy,
                quarantineSensitive: session.properties.quarantineSensitive
            )

            let item = OrganizedFile(
                file: file,
                decision: finalDecision,
                destinationRelativePath: destination,
                durationMs: durationMs,
                serverDurationMs: response.serverDurationMs,
                inputTokens: response.usage.input.totalTokenCount,
                outputTokens: response.usage.output.totalTokenCount
            )
            organized.append(item)
            onFileEvaluated?(item, index + 1, discovered.count)

            if applyChanges {
                let fm = FileManager.default
                let baseDest = directoryURL.appendingPathComponent(destination)
                try fm.createDirectory(at: baseDest.deletingLastPathComponent(), withIntermediateDirectories: true)
                let finalDest = uniqueDestinationURL(for: baseDest, in: fm)
                try fm.moveItem(at: file.url, to: finalDest)
            }
        }
        return organized
    }

    private func uniqueDestinationURL(for url: URL, in fm: FileManager) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var counter = 2
        while true {
            let name = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}

// MARK: - Command Runner & Sandbox Samples

enum FileOrganizerCommand {
    static func run(provider: ConfiguredProvider, arguments: [String]) async {
        var targetDirectory: URL?
        var selectedStrategy: OrganizationStrategy = .domain
        var shouldApplyMoves = false
        var isDemoMode = false

        var idx = 0
        while idx < arguments.count {
            let arg = arguments[idx]
            switch arg {
            case "--demo":
                isDemoMode = true
            case "--path":
                if idx + 1 < arguments.count {
                    targetDirectory = URL(fileURLWithPath: arguments[idx + 1])
                    idx += 1
                }
            case "--strategy":
                if idx + 1 < arguments.count {
                    selectedStrategy = OrganizationStrategy(rawValue: arguments[idx + 1]) ?? .domain
                    idx += 1
                }
            case "--apply":
                shouldApplyMoves = true
            case "--dry-run":
                shouldApplyMoves = false
            default:
                break
            }
            idx += 1
        }

        if targetDirectory == nil && !isDemoMode {
            isDemoMode = true
        }

        print("""
        ================================================================================
          System One CLI — Dynamic Profile Directory Organizer
          Provider: \(provider.provider.displayName)
          Endpoint: \(provider.endpointSummary)
        ================================================================================
        """)

        let session = provider.makeProfiledSession(auditLogger: TelemetryAuditModifier(auditTag: "cli-organizer"))
        let organizer = FileOrganizer(session: session)

        do {
            if isDemoMode {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("system-one-organizer-\(UUID().uuidString.prefix(8))")
                try populateSandbox(at: tempDir)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                session.properties.organizationStrategy = .domain
                session.properties.quarantineSensitive = true
                print("\n▶ Pass 1: Evaluating sandbox directory under DOMAIN DynamicProfile...")
                let pass1 = try await organizer.organize(directoryURL: tempDir, applyChanges: false) { item, i, total in
                    print("  [\(i)/\(total)] \(item.file.relativePath) ──► \(item.destinationRelativePath) (\(String(format: "%.0fms", item.durationMs)))")
                }
                printAuditTable(pass1)

                print("\n🔄 Live Adaptation: Switching session.properties.organizationStrategy = .workflow (same session!)")
                session.properties.organizationStrategy = .workflow
                let pass2 = try await organizer.organize(directoryURL: tempDir, applyChanges: false) { item, i, total in
                    print("  [\(i)/\(total)] \(item.file.relativePath) ──► \(item.destinationRelativePath) (\(String(format: "%.0fms", item.durationMs)))")
                }
                printAuditTable(pass2)
            } else if let dir = targetDirectory {
                session.properties.organizationStrategy = selectedStrategy
                session.properties.quarantineSensitive = true
                let results = try await organizer.organize(directoryURL: dir, applyChanges: shouldApplyMoves) { item, i, total in
                    print("  [\(i)/\(total)] \(item.file.relativePath) ──► \(item.destinationRelativePath) (\(String(format: "%.0fms", item.durationMs)))")
                }
                printAuditTable(results)
                print(shouldApplyMoves
                    ? "✅ Files moved into organized hierarchy."
                    : "ℹ️ Dry-run complete. Pass --apply to move files on disk.")
            }
        } catch {
            provider.failFastOnError(error)
        }
    }

    private static func printAuditTable(_ files: [OrganizedFile]) {
        print("┌───────────────────────────────────┬──────────────┬──────────────┬───────────┬──────┬───────────────────────────────┐")
        print("│ File                              │ Domain       │ Workflow     │ Sensitive │ Conf │ Destination Path              │")
        print("├───────────────────────────────────┼──────────────┼──────────────┼───────────┼──────┼───────────────────────────────┤")
        for o in files {
            let f = String(o.file.relativePath.prefix(33)).padding(toLength: 33, withPad: " ", startingAt: 0)
            let d = String(o.decision.domain.rawValue.prefix(12)).padding(toLength: 12, withPad: " ", startingAt: 0)
            let w = String(o.decision.workflowStage.rawValue.prefix(12)).padding(toLength: 12, withPad: " ", startingAt: 0)
            let s = (o.decision.isSensitive ? "⚠️  YES" : "   No ").padding(toLength: 9, withPad: " ", startingAt: 0)
            let c = " \(o.decision.confidenceScore)/3  "
            let dest = String(o.destinationRelativePath.prefix(29)).padding(toLength: 29, withPad: " ", startingAt: 0)
            print("│ \(f) │ \(d) │ \(w) │ \(s) │\(c)│ \(dest) │")
        }
        print("└───────────────────────────────────┴──────────────┴──────────────┴───────────┴──────┴───────────────────────────────┘")
    }

    private static func populateSandbox(at dir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let samples: [(String, String)] = [
            ("Invoice_INV-2026-9041.txt", "INVOICE: INV-2026-9041\nBILL TO: Acme Corp\nTOTAL DUE: $18,750.00 USD (ACTION REQUIRED)"),
            ("production_credentials.env", "ENVIRONMENT=production\nAWS_SECRET_ACCESS_KEY=example_secret\nDATABASE_URL=postgres://admin:secret@db/main"),
            ("master_services_agreement.txt", "MASTER SERVICES AGREEMENT & MUTUAL NONDISCLOSURE\nGoverning Law: State of California. Signed and executed."),
            ("TokenAuthMiddleware.swift", "import Foundation\npublic actor TokenAuthMiddleware {\n    public func authenticate(header: String?) -> Bool { header != nil }\n}"),
            ("weekend_groceries.txt", "Grocery List: Organic oat milk, avocados, coffee beans, sourdough loaf.")
        ]
        for (name, content) in samples {
            try content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }
}
