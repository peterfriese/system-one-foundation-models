import Foundation
import FoundationModels
import UniformTypeIdentifiers
import SystemOneCore
import LayaFoundationModels
import JevFoundationModels
import ClefFoundationModels
import OpenAIFoundationModels
import LayaOnDevice
import FactoryKit

/// Core interface for evaluating email decisions via System One decision models.
public protocol TriageEngineProtocol: Sendable {
    /// Evaluates a single email using the designated backend architecture.
    func triage(email: Email, backend: TriageBackend, skipProbe: Bool) async throws -> TriageResult

    /// Evaluates an array of emails concurrently with bounded worker pool parallelism.
    func triageBatch(
        emails: [Email],
        backend: TriageBackend,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> BatchTriageReport

    /// Evaluates an array of emails concurrently with per-item callback and bounded parallelism.
    func triageBatch(
        emails: [Email],
        backend: TriageBackend,
        progress: (@Sendable (Int, Int) -> Void)?,
        onItemCompleted: (@Sendable (Email, TriageResult) -> Void)?
    ) async throws -> BatchTriageReport
}

extension TriageEngineProtocol {
    public func triage(email: Email, backend: TriageBackend) async throws -> TriageResult {
        try await triage(email: email, backend: backend, skipProbe: false)
    }

    public func triageBatch(
        emails: [Email],
        backend: TriageBackend,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> BatchTriageReport {
        try await triageBatch(emails: emails, backend: backend, progress: progress, onItemCompleted: nil)
    }
}

/// Production implementation of `TriageEngineProtocol`.
/// Executes real inference across Apple Foundation Models, Core ML (ANE),
/// local laya-serve daemon, hosted VPC, and TypeSafe Jev Cloud API.
public final class TriageEngine: TriageEngineProtocol, @unchecked Sendable {
    private let maxParallelism: Int
    private let coreMLEngineLock = NSLock()
    private var cachedCoreMLEngine: (url: URL, engine: LayaCoreMLEngine)?

    @ObservationIgnored
    @Injected(\.backendHealthProbeService) private var healthProbe

    @ObservationIgnored
    @Injected(\.backendConfigurationStore) private var configStore

    @ObservationIgnored
    @Injected(\.keychainService) private var keychainService

    @ObservationIgnored
    @Injected(\.coreMLModelManager) private var coreMLManager

    private let customCoreMLManager: CoreMLModelManager?

    private var activeCoreMLManager: CoreMLModelManager {
        customCoreMLManager ?? coreMLManager
    }

    public init(maxParallelism: Int = 8, coreMLManager: CoreMLModelManager? = nil) {
        self.maxParallelism = maxParallelism
        self.customCoreMLManager = coreMLManager
    }

    // MARK: - Core ML Engine Cache

    private func getOrInitializeCoreMLEngine(modelURL: URL) throws -> LayaCoreMLEngine {
        coreMLEngineLock.lock()
        defer { coreMLEngineLock.unlock() }

        if let cached = cachedCoreMLEngine, cached.url == modelURL {
            return cached.engine
        }

        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        do {
            let engine = try LayaCoreMLEngine(modelURL: modelURL, tokenizer: tokenizer)
            cachedCoreMLEngine = (url: modelURL, engine: engine)
            return engine
        } catch {
            let path = modelURL.path
            let isSafetensors: Bool = {
                if path.contains("safetensors") || modelURL.pathExtension.lowercased() == "safetensors" {
                    return true
                }
                guard FileManager.default.fileExists(atPath: path) else { return false }
                if let handle = try? FileHandle(forReadingFrom: modelURL) {
                    defer { try? handle.close() }
                    if let data = try? handle.read(upToCount: 16), data.count >= 9, data[8] == 0x7B {
                        return true
                    }
                }
                return false
            }()

            if isSafetensors && FileManager.default.fileExists(atPath: path) {
                throw BackendUnreachableError.modelNotAvailable
            }

            throw BackendUnreachableError(
                backend: .onDeviceCoreML,
                reason: "Core ML Model Load Failure: \(error.localizedDescription)",
                guidance: "The on-device model weights could not be loaded. Please open Settings (⌘,) and re-download or re-import the Core ML model."
            )
        }
    }

    public func clearCoreMLCache() {
        coreMLEngineLock.lock()
        cachedCoreMLEngine = nil
        coreMLEngineLock.unlock()
    }

    // MARK: - Single Email Triage

    public func triage(email: Email, backend: TriageBackend, skipProbe: Bool = false) async throws -> TriageResult {
        try Task.checkCancellation()

        // 1. Pre-flight health probe (if not skipped)
        if !skipProbe {
            let health = await healthProbe.probe(backend: backend)
            switch health {
            case .healthy:
                break
            case .unreachable(let reason, let guidance):
                throw BackendUnreachableError(backend: backend, reason: reason, guidance: guidance)
            case .checking:
                throw BackendUnreachableError(
                    backend: backend,
                    reason: "Health probe in progress",
                    guidance: "Please wait a moment and try again."
                )
            }
        }

        try Task.checkCancellation()

        return try await evaluate(email: email, backend: backend)
    }

    private func evaluate(email: Email, backend: TriageBackend) async throws -> TriageResult {
        // 2. Format input prompt
        let prompt = """
        From: \(email.sender) <\(email.senderEmail)>
        Subject: \(email.subject)
        Date: \(email.formattedDate)
        Snippet: \(email.previewSnippet)

        Body:
        \(email.body)
        """

        let clock = ContinuousClock()
        let startTime = clock.now

        // 3. Evaluate real Foundation Models session
        let result: TriageResult
        let latencyMs: Double
        switch backend {
        case .localServe:
            let endpointURL = BackendConfigurationStore.normalizeSystemOneEndpoint(
                configStore.localServeURL,
                defaultURL: BackendConfigurationStore.defaultLocalServeURL
            )
            let model = LayaLanguageModel(endpoint: .custom(endpointURL))
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt, generating: EmailTriageDecision.self)
            latencyMs = startTime.duration(to: clock.now).asMilliseconds
            result = makeTriageResult(response: response, backend: backend, latencyMs: latencyMs)

        case .hostedVPC:
            let endpointURL = BackendConfigurationStore.normalizeSystemOneEndpoint(
                configStore.hostedVpcURL,
                defaultURL: BackendConfigurationStore.defaultHostedVpcURL
            )
            let token = keychainService.string(for: .hostedVpcToken)
            let model = LayaLanguageModel(endpoint: .custom(endpointURL), apiKey: token)
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt, generating: EmailTriageDecision.self)
            latencyMs = startTime.duration(to: clock.now).asMilliseconds
            result = makeTriageResult(response: response, backend: backend, latencyMs: latencyMs)

        case .cloudAPI:
            guard let apiKey = keychainService.string(for: .typesafeApiKey), !apiKey.isEmpty else {
                throw BackendUnreachableError(
                    backend: backend,
                    reason: "Missing TypeSafe API Key",
                    guidance: "Open Settings (⌘,) and paste your TYPESAFE_API_KEY."
                )
            }
            let urlString = configStore.jevCloudURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let endpointURL = URL(string: urlString) ?? URL(string: "https://api.typesafe.ai/v1/systemone")!
            let model = JevLanguageModel(apiKey: apiKey, endpoint: endpointURL)
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt, generating: EmailTriageDecision.self)
            latencyMs = startTime.duration(to: clock.now).asMilliseconds
            result = makeTriageResult(response: response, backend: backend, latencyMs: latencyMs)

        case .cloudflareClef:
            guard let accountID = keychainService.string(for: .cloudflareAccountId)?.trimmingCharacters(in: .whitespacesAndNewlines), !accountID.isEmpty else {
                throw BackendUnreachableError(
                    backend: backend,
                    reason: "Missing Cloudflare Account ID",
                    guidance: "Open Settings (⌘,) and paste your Cloudflare Account ID."
                )
            }
            guard let token = keychainService.string(for: .cloudflareApiToken)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
                throw BackendUnreachableError(
                    backend: backend,
                    reason: "Missing Cloudflare API Token",
                    guidance: "Open Settings (⌘,) and paste your Cloudflare API Token."
                )
            }
            let model = ClefLanguageModel(
                endpoint: .workersAI(accountID: accountID, model: .clefFlash),
                apiToken: token
            )
            let session = LanguageModelSession(model: model)
            let clefPrompt = Prompt {
                "Analyze the following email and any attached documents or screenshots for triage classification, urgency scoring, and suggested response actions."
                "Sender: \(email.sender) <\(email.senderEmail)>"
                "Subject: \(email.subject)"
                "Body:\n\(email.body)"
                for attachment in email.imageAttachments {
                    let imageType = mapMimeTypeToUTType(attachment.mimeType)
                    if let imageAttachment = Attachment(attachment.data, type: imageType) {
                        imageAttachment
                    }
                }
            }
            let response = try await session.respond(to: clefPrompt, generating: EmailTriageDecision.self)
            latencyMs = startTime.duration(to: clock.now).asMilliseconds
            result = makeTriageResult(response: response, backend: backend, latencyMs: latencyMs)

        case .openaiDecisions:
            guard let apiKey = (keychainService.string(for: .openaiApiKey) ?? (configStore.openaiAPIKey.isEmpty ? nil : configStore.openaiAPIKey))?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
                throw BackendUnreachableError(
                    backend: backend,
                    reason: "Missing OpenAI API Key",
                    guidance: "Open Settings (⌘,) and paste your OPENAI_API_KEY."
                )
            }
            let org = configStore.openaiOrganization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : configStore.openaiOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
            let proj = configStore.openaiProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : configStore.openaiProject.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = OpenAIDecisionsLanguageModel(
                endpoint: .hosted(model: "gpt-6-luna", organization: org, project: proj),
                apiKey: apiKey
            )
            let session = LanguageModelSession(model: model)
            let openAIPrompt = Prompt {
                "Analyze the following email and any attached documents or screenshots for triage classification, urgency scoring, and suggested response actions."
                "Sender: \(email.sender) <\(email.senderEmail)>"
                "Subject: \(email.subject)"
                "Body:\n\(email.body)"
                for attachment in email.imageAttachments {
                    let imageType = mapMimeTypeToUTType(attachment.mimeType)
                    if let imageAttachment = Attachment(attachment.data, type: imageType) {
                        imageAttachment
                    }
                }
            }
            do {
                let response = try await session.respond(to: openAIPrompt, generating: EmailTriageDecision.self)
                latencyMs = startTime.duration(to: clock.now).asMilliseconds
                result = makeTriageResult(response: response, backend: backend, latencyMs: latencyMs)
            } catch {
                print("⚠️ [TriageEngine] OpenAI Decisions evaluation failed: \(error)")
                throw error
            }

        case .onDeviceCoreML:
            guard let modelURL = activeCoreMLManager.resolvedModelURL else {
                throw BackendUnreachableError(
                    backend: backend,
                    reason: "Model weights not installed",
                    guidance: "Open Settings (⌘,) and download the Core ML model."
                )
            }
            let engine = try getOrInitializeCoreMLEngine(modelURL: modelURL)
            let model = LayaOnDeviceLanguageModel(engine: engine)
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt, generating: EmailTriageDecision.self)
            latencyMs = startTime.duration(to: clock.now).asMilliseconds
            result = makeTriageResult(response: response, backend: backend, latencyMs: latencyMs)

        case .generativeBaseline:
            switch SystemLanguageModel.default.availability {
            case .available:
                break
            case .unavailable(let reason):
                switch reason {
                case .modelNotReady:
                    throw BackendUnreachableError(
                        backend: backend,
                        reason: "Apple Intelligence Model Preparing (Downloading Assets)",
                        guidance: "Your Mac is eligible and Apple Intelligence is enabled, but macOS is still downloading or preparing the model assets in the background. Check macOS System Settings > Apple Intelligence & Siri."
                    )
                case .appleIntelligenceNotEnabled:
                    throw BackendUnreachableError(
                        backend: backend,
                        reason: "Apple Intelligence is Turned Off",
                        guidance: "Turn on Apple Intelligence in macOS System Settings > Apple Intelligence & Siri."
                    )
                case .deviceNotEligible:
                    throw BackendUnreachableError(
                        backend: backend,
                        reason: "Device Not Eligible for Apple Intelligence",
                        guidance: "Apple Intelligence requires an Apple Silicon Mac (M1 or later)."
                    )
                @unknown default:
                    throw BackendUnreachableError(
                        backend: backend,
                        reason: "Apple Intelligence Unavailable",
                        guidance: "Apple Intelligence is currently unavailable on this system."
                    )
                }
            @unknown default:
                throw BackendUnreachableError(
                    backend: backend,
                    reason: "Apple Intelligence Unavailable",
                    guidance: "Check System Settings."
                )
            }
            let session = LanguageModelSession()
            do {
                let response = try await session.respond(to: prompt, generating: EmailTriageDecision.self)
                latencyMs = startTime.duration(to: clock.now).asMilliseconds
                result = TriageResult(
                    decision: response.content,
                    confidenceScore: nil,
                    decisiveness: nil,
                    routingTier: .confirm,
                    latencyMs: latencyMs,
                    backendUsed: backend
                )
            } catch {
                throw BackendUnreachableError(
                    backend: backend,
                    reason: "Generative evaluation failed: \(error.localizedDescription)",
                    guidance: "Apple Intelligence could not generate the structured decision. Check System Settings."
                )
            }
        }

        print("⏱️ [TriageEngine] Evaluated email \(email.id.uuidString.prefix(8)) via \(backend.displayName): \(String(format: "%.1f", latencyMs)) ms | Category: \(result.decision.category.rawValue) | Urgency: \(result.decision.urgencyScore) | Routing: \(result.routingTier.rawValue)")
        return result
    }

    // MARK: - Batch Triage (Bounded Concurrency)

    public func triageBatch(
        emails: [Email],
        backend: TriageBackend,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        onItemCompleted: (@Sendable (Email, TriageResult) -> Void)? = nil
    ) async throws -> BatchTriageReport {
        let startTime = ContinuousClock.now
        let totalCount = emails.count
        guard totalCount > 0 else {
            return BatchTriageReport(
                totalProcessed: 0,
                totalDurationSeconds: 0,
                averageLatencyMs: 0,
                actionBreakdown: [:],
                routingBreakdown: [:],
                backend: backend
            )
        }

        try Task.checkCancellation()

        // Report initial progress immediately before health probe and task spawning
        progress?(0, totalCount)

        // Fast pre-flight check before spawning batch workers
        let health = await healthProbe.probe(backend: backend)
        switch health {
        case .healthy:
            break
        case .unreachable(let reason, let guidance):
            throw BackendUnreachableError(backend: backend, reason: reason, guidance: guidance)
        case .checking:
            throw BackendUnreachableError(
                backend: backend,
                reason: "Health probe in progress",
                guidance: "Please wait a moment and try again."
            )
        }

        try Task.checkCancellation()

        // Adaptive parallelism: use maxParallelism = 4 for remote cloud backends
        // (.cloudflareClef, .cloudAPI, .openaiDecisions) to prevent rate-limit saturation, while keeping
        // maxParallelism = 8 for local/on-device backends.
        let effectiveParallelism: Int = {
            switch backend {
            case .cloudflareClef, .cloudAPI, .openaiDecisions:
                return min(self.maxParallelism, 4)
            case .onDeviceCoreML, .localServe, .hostedVPC, .generativeBaseline:
                return self.maxParallelism
            }
        }()

        var totalProcessed = 0
        var actionBreakdown: [TriageAction: Int] = [:]
        var routingBreakdown: [RoutingPolicy: Int] = [:]
        var latencies: [Double] = []
        var reports: [TriageResult] = []

        try await withThrowingTaskGroup(of: (Email, TriageResult).self) { group in
            var submittedIndex = 0

            // Fill initial pool up to effectiveParallelism
            while submittedIndex < min(effectiveParallelism, totalCount) {
                if Task.isCancelled {
                    group.cancelAll()
                    throw CancellationError()
                }
                let email = emails[submittedIndex]
                group.addTask {
                    let result = try await self.triage(email: email, backend: backend, skipProbe: true)
                    return (email, result)
                }
                submittedIndex += 1
            }

            // Wrap the worker processing loop with explicit cancellation checking
            do {
                for try await (email, result) in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        throw CancellationError()
                    }

                    totalProcessed += 1
                    latencies.append(result.latencyMs)
                    reports.append(result)
                    actionBreakdown[result.decision.suggestedAction, default: 0] += 1
                    routingBreakdown[result.routingTier, default: 0] += 1

                    progress?(totalProcessed, totalCount)
                    onItemCompleted?(email, result)

                    if Task.isCancelled {
                        group.cancelAll()
                        throw CancellationError()
                    }

                    if submittedIndex < totalCount {
                        let nextEmail = emails[submittedIndex]
                        group.addTask {
                            let nextResult = try await self.triage(email: nextEmail, backend: backend, skipProbe: true)
                            return (nextEmail, nextResult)
                        }
                        submittedIndex += 1
                    }
                }
            } catch {
                group.cancelAll()
                throw error
            }
        }

        let elapsedDuration = startTime.duration(to: .now)
        let totalDurationMs = elapsedDuration.asMilliseconds
        let elapsedSeconds = elapsedDuration.asSeconds
        let totalDurationSeconds = max(elapsedSeconds, 0.001)
        let throughput = Double(reports.count) / totalDurationSeconds
        let meanLatency = latencies.isEmpty ? 0.0 : (latencies.reduce(0.0, +) / Double(latencies.count))

        let sorted = latencies.sorted()
        let p50Index = sorted.isEmpty ? 0 : Int((Double(sorted.count - 1) * 0.50).rounded())
        let p95Index = sorted.isEmpty ? 0 : Int((Double(sorted.count - 1) * 0.95).rounded())
        let p50Latency = sorted.isEmpty ? 0.0 : sorted[p50Index]
        let p95Latency = sorted.isEmpty ? 0.0 : sorted[p95Index]

        print("⏱️ [TriageEngine] Batch Complete: \(reports.count) emails in \(String(format: "%.1f", totalDurationMs)) ms | Mean: \(String(format: "%.1f", meanLatency)) ms/email | P50: \(String(format: "%.1f", p50Latency)) ms | P95: \(String(format: "%.1f", p95Latency)) ms | Throughput: \(String(format: "%.1f", throughput)) emails/sec")

        return BatchTriageReport(
            totalProcessed: totalProcessed,
            totalDurationSeconds: totalDurationSeconds,
            averageLatencyMs: meanLatency,
            actionBreakdown: actionBreakdown,
            routingBreakdown: routingBreakdown,
            backend: backend
        )
    }

    // MARK: - Helpers

    private func mapMimeTypeToUTType(_ mimeType: String) -> UTType {
        let lower = mimeType.lowercased()
        if lower.contains("jpeg") || lower.contains("jpg") {
            return .jpeg
        } else if lower.contains("webp") {
            return .webP
        } else {
            return .png
        }
    }

    private func makeTriageResult(
        response: LanguageModelSession.Response<EmailTriageDecision>,
        backend: TriageBackend,
        latencyMs: Double
    ) -> TriageResult {
        let decision = response.content
        let p = response.probability(for: "requiresAction")
        let conf = response.confidence(for: "suggestedAction")
            ?? response.confidence(for: "category")

        let decisiveness: Double? = p.map { max($0, 1.0 - $0) } ?? conf
        let routingTier: RoutingPolicy
        if let conf {
            routingTier = RoutingPolicy.evaluate(confidence: conf, probability: p)
        } else if let p {
            let decisiveness = max(p, 1.0 - p)
            routingTier = RoutingPolicy.evaluate(confidence: decisiveness, probability: p)
        } else {
            routingTier = .escalate
        }

        return TriageResult(
            decision: decision,
            confidenceScore: conf,
            decisiveness: decisiveness,
            routingTier: routingTier,
            latencyMs: latencyMs,
            backendUsed: backend
        )
    }
}

/// Deterministic mock triage engine for unit testing and SwiftUI previews.
public final class MockTriageEngine: TriageEngineProtocol, @unchecked Sendable {
    public var cannedResult: TriageResult?
    public var shouldThrowError: Error?
    public var latencyMs: Double

    public init(
        cannedResult: TriageResult? = nil,
        shouldThrowError: Error? = nil,
        latencyMs: Double = 2.0
    ) {
        self.cannedResult = cannedResult
        self.shouldThrowError = shouldThrowError
        self.latencyMs = latencyMs
    }

    public func triage(email: Email, backend: TriageBackend, skipProbe: Bool = false) async throws -> TriageResult {
        if let error = shouldThrowError {
            throw error
        }
        if let canned = cannedResult {
            return canned
        }
        let decision = EmailTriageDecision(
            requiresAction: true,
            category: .work,
            urgencyScore: 1,
            suggestedAction: .scheduleTask
        )
        return TriageResult(
            decision: decision,
            confidenceScore: 0.90,
            decisiveness: 0.90,
            routingTier: .auto,
            latencyMs: latencyMs,
            backendUsed: backend
        )
    }

    public func triageBatch(
        emails: [Email],
        backend: TriageBackend,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        onItemCompleted: (@Sendable (Email, TriageResult) -> Void)? = nil
    ) async throws -> BatchTriageReport {
        if let error = shouldThrowError {
            throw error
        }

        var processed = 0
        progress?(0, emails.count)
        for email in emails {
            try Task.checkCancellation()
            let res = try await triage(email: email, backend: backend)
            processed += 1
            progress?(processed, emails.count)
            onItemCompleted?(email, res)
        }

        return BatchTriageReport(
            totalProcessed: emails.count,
            totalDurationSeconds: 0.05,
            averageLatencyMs: latencyMs,
            actionBreakdown: [.scheduleTask: emails.count],
            routingBreakdown: [.auto: emails.count],
            backend: backend
        )
    }
}
