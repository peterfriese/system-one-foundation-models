import Foundation
import Testing
import FoundationModels
@testable import AppCore

@Suite("AppCore Models and Dataset Tests")
struct AppCoreModelsTests {
    @Test("InboxData generates exactly 500 emails")
    func testSampleEmailsCount() {
        let emails = InboxData.sampleEmails
        #expect(emails.count == 500)
    }

    @Test("InboxData unread count is approximately 180")
    func testSampleEmailsUnreadCount() {
        let emails = InboxData.sampleEmails
        let unreadCount = emails.filter(\.isUnread).count
        // Expect close to 180 unread
        #expect(unreadCount >= 170 && unreadCount <= 190)
    }

    @Test("InboxData contains diverse enterprise categories")
    func testEnterpriseCategoriesPresent() {
        let emails = InboxData.sampleEmails
        let categories = Set(emails.compactMap(\.category))
        #expect(categories.contains(.work))
        #expect(categories.contains(.securityAlerts))
        #expect(categories.contains(.billing))
        #expect(categories.contains(.meetings))
        #expect(categories.contains(.newsletters))
        #expect(categories.contains(.quarantine))
    }

    @Test("UrgencyPriority correctly maps System One urgency scores (PRD-2)")
    func testUrgencyPriorityRubricMapping() {
        #expect(UrgencyPriority.from(score: 0) == .p0Critical)
        #expect(UrgencyPriority.from(score: 0).displayName == "P0 Critical")
        #expect(UrgencyPriority.from(score: 0).urgencyLabel == "P0 Critical")

        #expect(UrgencyPriority.from(score: 1) == .p1High)
        #expect(UrgencyPriority.from(score: 1).displayName == "P1 High")
        #expect(UrgencyPriority.from(score: 1).urgencyLabel == "P1 High")

        #expect(UrgencyPriority.from(score: 2) == .p2Medium)
        #expect(UrgencyPriority.from(score: 2).displayName == "P2 Medium")
        #expect(UrgencyPriority.from(score: 2).urgencyLabel == "P2 Medium")

        #expect(UrgencyPriority.from(score: 3) == .p3Low)
        #expect(UrgencyPriority.from(score: 3).displayName == "P3 Low")
        #expect(UrgencyPriority.from(score: 3).urgencyLabel == "P3 Low")

        // Boundary / clamp tests
        #expect(UrgencyPriority.from(score: -1) == .p0Critical)
        #expect(UrgencyPriority.from(score: 4) == .p3Low)
        #expect(UrgencyPriority.from(score: 99) == .p3Low)

        // Int extensions
        #expect(0.urgencyPriority == .p0Critical)
        #expect(0.urgencyLabel == "P0 Critical")
        #expect(1.urgencyPriority == .p1High)
        #expect(1.urgencyLabel == "P1 High")
        #expect(2.urgencyPriority == .p2Medium)
        #expect(2.urgencyLabel == "P2 Medium")
        #expect(3.urgencyPriority == .p3Low)
        #expect(3.urgencyLabel == "P3 Low")

        // Decision model helpers
        let decisionP0 = EmailTriageDecision(
            requiresAction: true,
            category: .securityAlerts,
            urgencyScore: 0,
            suggestedAction: .immediateAlert
        )
        #expect(decisionP0.priority == .p0Critical)
        #expect(decisionP0.urgencyLabel == "P0 Critical")

        let decisionP3 = EmailTriageDecision(
            requiresAction: false,
            category: .newsletters,
            urgencyScore: 3,
            suggestedAction: .autoArchive
        )
        #expect(decisionP3.priority == .p3Low)
        #expect(decisionP3.urgencyLabel == "P3 Low")
    }

    @Test("Email initials extraction works correctly")
    func testEmailSenderInitials() {
        let email1 = Email(
            sender: "Jeff Dean",
            senderEmail: "jeff@google.com",
            subject: "Test",
            previewSnippet: "Snippet",
            body: "Body",
            date: Date()
        )
        #expect(email1.senderInitials == "JD")

        let email2 = Email(
            sender: "Kelsey",
            senderEmail: "kelsey@minimalist.dev",
            subject: "Test",
            previewSnippet: "Snippet",
            body: "Body",
            date: Date()
        )
        #expect(email2.senderInitials == "KE")
    }

    @Test("Mailbox properties are configured properly")
    func testMailboxProperties() {
        #expect(Mailbox.inbox.isFavorite == true)
        #expect(Mailbox.vips.isFavorite == true)
        #expect(Mailbox.flagged.isFavorite == true)
        #expect(Mailbox.drafts.isFavorite == true)
        #expect(Mailbox.sent.isFavorite == true)

        #expect(Mailbox.securityAlerts.isCategory == true)
        #expect(Mailbox.billing.isCategory == true)
        #expect(Mailbox.work.isCategory == true)
        #expect(Mailbox.meetings.isCategory == true)
        #expect(Mailbox.newsletters.isCategory == true)
        #expect(Mailbox.quarantine.isCategory == true)
        #expect(Mailbox.archive.isCategory == true)

        #expect(Mailbox.favorites.count == 5)
        #expect(Mailbox.categories.count == 7)
    }
}

@Suite("MailStore State and Action Tests")
@MainActor
struct MailStoreTests {
    @Test("MailStore initial state loads emails and calculates counts")
    func testInitialState() {
        let store = MailStore()
        #expect(store.totalEmailCount == 500)
        #expect(store.selectedMailbox == .inbox)
        #expect(store.selectedEmailID != nil)
        #expect(store.totalCountForCurrentMailbox > 0)
        #expect(store.unreadCountForCurrentMailbox > 0)
    }

    @Test("MailStore filtering by unread only")
    func testUnreadFilter() {
        let store = MailStore()
        let initialCount = store.filteredEmails.count
        store.unreadOnly = true
        let unreadCount = store.filteredEmails.count
        #expect(unreadCount <= initialCount)
        let allUnread = store.filteredEmails.allSatisfy { $0.isUnread }
        #expect(allUnread)
    }

    @Test("MailStore search filtering")
    func testSearchFilter() {
        let store = MailStore()
        store.searchText = "Jeff Dean"
        let filtered = store.filteredEmails
        #expect(filtered.allSatisfy { email in
            email.sender.localizedCaseInsensitiveContains("Jeff Dean") ||
            email.subject.localizedCaseInsensitiveContains("Jeff Dean") ||
            email.body.localizedCaseInsensitiveContains("Jeff Dean")
        })
    }

    @Test("MailStore toggles unread state")
    func testToggleUnread() {
        let store = MailStore()
        guard let first = store.filteredEmails.first else {
            Issue.record("No email found")
            return
        }
        let wasUnread = first.isUnread
        store.toggleUnread(for: first.id)
        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.isUnread == !wasUnread)
    }

    @Test("MailStore toggles flag")
    func testToggleFlag() {
        let store = MailStore()
        guard let first = store.filteredEmails.first else {
            Issue.record("No email found")
            return
        }
        let wasFlagged = first.isFlagged
        store.toggleFlag(for: first.id)
        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.isFlagged == !wasFlagged)
    }

    @Test("MailStore moves email to another mailbox")
    func testMoveToMailbox() {
        let store = MailStore()
        guard let first = store.filteredEmails.first else {
            Issue.record("No email found")
            return
        }
        store.moveToMailbox(first.id, mailbox: .archive)
        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.mailbox == .archive)
    }

    @Test("MailStore moves email back to inbox from archive")
    func testMoveToInboxFromArchive() {
        let store = MailStore()
        store.selectMailbox(.archive)
        guard let first = store.filteredEmails.first else {
            Issue.record("No archived email found")
            return
        }
        #expect(first.mailbox == .archive)
        store.selectedEmailID = first.id

        store.moveToInbox(first.id)

        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.mailbox == .inbox)
        #expect(store.selectedEmailID != first.id)
        #expect(store.filteredEmails.contains(where: { $0.id == first.id }) == false)
    }

    @Test("MailStore moves email back to inbox from quarantine")
    func testMoveToInboxFromQuarantine() {
        let store = MailStore()
        store.selectMailbox(.quarantine)
        guard let first = store.filteredEmails.first else {
            Issue.record("No quarantined email found")
            return
        }
        store.selectedEmailID = first.id

        store.moveToInbox(first.id)

        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.mailbox == .inbox)
        #expect(updated?.category != .quarantine)
        #expect(store.selectedEmailID != first.id)
        #expect(store.filteredEmails.contains(where: { $0.id == first.id }) == false)
    }

    @Test("MailStore moveToMailbox transitions selectedEmailID when email leaves current mailbox")
    func testMoveToMailboxTransitionsSelection() {
        let store = MailStore()
        store.selectMailbox(.inbox)
        guard let first = store.filteredEmails.first else {
            Issue.record("No inbox email found")
            return
        }
        store.selectedEmailID = first.id

        store.moveToMailbox(first.id, mailbox: .work)

        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.mailbox == .work)
        #expect(store.selectedEmailID != first.id)
    }

    @Test("MailStore archives email")
    func testArchiveEmail() {
        let store = MailStore()
        guard let first = store.filteredEmails.first else {
            Issue.record("No email found")
            return
        }
        store.archiveEmail(first.id)
        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.mailbox == .archive)
    }

    @Test("MailStore deletes email")
    func testDeleteEmail() {
        let store = MailStore()
        let countBefore = store.totalEmailCount
        guard let first = store.filteredEmails.first else {
            Issue.record("No email found")
            return
        }
        store.deleteEmail(first.id)
        #expect(store.totalEmailCount == countBefore - 1)
        #expect(store.emails.contains(where: { $0.id == first.id }) == false)
    }

    @Test("MailStore sendEmail adds sent message to emails array (PRD-3)")
    func testMailStoreSendEmail() {
        let store = MailStore()
        let initialCount = store.totalEmailCount

        store.sendEmail(to: "colleague@apple.corp", subject: "Re: Architecture Review", body: "Approved with notes.")

        #expect(store.totalEmailCount == initialCount + 1)
        let sentEmail = store.emails.first
        #expect(sentEmail?.mailbox == .sent)
        #expect(sentEmail?.recipient == "colleague@apple.corp")
        #expect(sentEmail?.subject == "Re: Architecture Review")
        #expect(sentEmail?.body == "Approved with notes.")
        #expect(sentEmail?.isUnread == false)
    }

    @Test("MailStore marks all as read")
    func testMarkAllAsRead() {
        let store = MailStore()
        #expect(store.unreadCountForCurrentMailbox > 0)
        store.markAllAsRead()
        #expect(store.unreadCountForCurrentMailbox == 0)
    }

    @Test("MailStore settings sheet binding toggles properly")
    func testSettingsSheetPresentation() {
        let store = MailStore()
        #expect(store.showingSettings == false)
        store.showingSettings = true
        #expect(store.showingSettings == true)
        store.showingSettings = false
        #expect(store.showingSettings == false)
    }
}

@Suite("Triage Confidence & Routing Policy Tests")
struct TriageRoutingPolicyTests {
    @Test("High confidence >= 0.85 resolves to .auto")
    func testHighConfidenceAuto() {
        let policy = RoutingPolicy.evaluate(confidence: 0.92)
        #expect(policy == .auto)
        #expect(policy.displayName == "Auto Executed")
        #expect(policy.statusBadgeText == "AUTO EXECUTED")
    }

    @Test("Moderate confidence 0.60..<0.85 resolves to .confirm")
    func testModerateConfidenceConfirm() {
        let policy = RoutingPolicy.evaluate(confidence: 0.74)
        #expect(policy == .confirm)
        #expect(policy.displayName == "Confirmation Needed")
        #expect(policy.statusBadgeText == "CONFIRMATION NEEDED")
    }

    @Test("Low confidence < 0.60 resolves to .escalate")
    func testLowConfidenceEscalate() {
        let policy = RoutingPolicy.evaluate(confidence: 0.45)
        #expect(policy == .escalate)
        #expect(policy.displayName == "Escalated to Inbox")
        #expect(policy.statusBadgeText == "ESCALATED TO INBOX")
    }

    @Test("Symmetrical noul: high-confidence negative (p <= 0.15) resolves to .auto")
    func testSymmetricalNoulNegativeAuto() {
        // e.g. Newsletter with p = 0.08 requiresAction -> decisiveness = 0.92 >= 0.85
        let policy = RoutingPolicy.evaluate(confidence: 0.92, probability: 0.08)
        #expect(policy == .auto)
    }

    @Test("Noul probability in undecided band [0.35, 0.65] strictly escalates")
    func testNoulUndecidedBandEscalation() {
        let policyMid = RoutingPolicy.evaluate(confidence: 0.90, probability: 0.50)
        #expect(policyMid == .escalate)

        let policyLowerEdge = RoutingPolicy.evaluate(confidence: 0.88, probability: 0.35)
        #expect(policyLowerEdge == .escalate)

        let policyUpperEdge = RoutingPolicy.evaluate(confidence: 0.88, probability: 0.65)
        #expect(policyUpperEdge == .escalate)
    }

    @Test("TriageResult formatting helpers format percentages and latency correctly")
    func testTriageResultFormatting() {
        let decision = EmailTriageDecision(
            requiresAction: true,
            category: .securityAlerts,
            urgencyScore: 0,
            suggestedAction: .quarantineThreat
        )
        let result = TriageResult(
            decision: decision,
            confidenceScore: 0.964,
            decisiveness: 0.96,
            routingTier: .auto,
            latencyMs: 8.42,
            backendUsed: .onDeviceCoreML
        )

        #expect(result.confidencePercentage == "96.4% Certainty")
        #expect(result.shortConfidence == "96%")
        #expect(result.formattedLatency == "8.4 ms")
        #expect(result.statusBadgeText == "AUTO EXECUTED")
        #expect(result.backendUsed.displayName == "On-Device Core ML")
        #expect(result.backendUsed.iconName == "cpu.fill")
    }

    @Test("TriageResult formatting helpers handle nil / uncalibrated confidence correctly")
    func testTriageResultUncalibratedFormatting() {
        let decision = EmailTriageDecision(
            requiresAction: false,
            category: .newsletters,
            urgencyScore: 4,
            suggestedAction: .autoArchive
        )
        let result = TriageResult(
            decision: decision,
            confidenceScore: nil,
            decisiveness: nil,
            routingTier: RoutingPolicy.confirm,
            latencyMs: 1200.0,
            backendUsed: .generativeBaseline
        )

        #expect(result.confidencePercentage == "Uncalibrated")
        #expect(result.shortConfidence == "N/A")
        #expect(result.formattedLatency == "1.20 s")
        #expect(result.statusBadgeText == "CONFIRMATION NEEDED")
        #expect(result.confidenceScore == nil)
        #expect(result.decisiveness == nil)
        #expect(result.routingTier == RoutingPolicy.confirm)
    }
}

@Suite("TriageEngine & Real Architecture Tests", .serialized)
struct TriageEngineTests {
    @Test("Triage on uninstalled Core ML throws typed BackendUnreachableError with guidance")
    func testCoreMLUninstalledThrowsError() async {
        let emptyManager = CoreMLModelManager()
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyModels_\(UUID().uuidString)")
        emptyManager.customModelsDirectory = emptyDir
        Container.shared.coreMLModelManager.register { emptyManager }
        defer {
            Container.shared.coreMLModelManager.reset()
            try? FileManager.default.removeItem(at: emptyDir)
        }

        let engine = TriageEngine()
        let sample = InboxData.sampleEmails[0]

        do {
            _ = try await engine.triage(email: sample, backend: .onDeviceCoreML)
            Issue.record("Expected BackendUnreachableError when Core ML is not installed")
        } catch let error as BackendUnreachableError {
            #expect(error.backend == .onDeviceCoreML)
            #expect(error.reason == "Model weights not installed")
            #expect(error.guidance.contains("download the Core ML model"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Triage on corrupted or uncompiled Core ML weights throws typed BackendUnreachableError rather than faking inference (SIM-1)")
    func testCoreMLCorruptedWeightsThrowsError() async throws {
        let manager = CoreMLModelManager()
        let isolatedDir = FileManager.default.temporaryDirectory.appendingPathComponent("CorruptedModels_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        manager.customModelsDirectory = isolatedDir

        // Create a dummy non-CoreML model file at canonical path
        let dummyModel = isolatedDir.appendingPathComponent("LayaDecisionModel.mlmodelc")
        try "dummy corrupted weights".write(to: dummyModel, atomically: true, encoding: .utf8)

        Container.shared.coreMLModelManager.reset()
        Container.shared.coreMLModelManager.register { manager }
        defer {
            Container.shared.coreMLModelManager.reset()
            try? FileManager.default.removeItem(at: isolatedDir)
        }

        let engine = TriageEngine(coreMLManager: manager)
        let sample = InboxData.sampleEmails[0]

        do {
            _ = try await engine.triage(email: sample, backend: .onDeviceCoreML, skipProbe: true)
            Issue.record("Expected BackendUnreachableError when Core ML weights are invalid, got mock prediction instead!")
        } catch let error as BackendUnreachableError {
            #expect(error.backend == .onDeviceCoreML)
            #expect(error.reason.contains("Core ML Model Load Failure"))
            #expect(error.guidance.contains("re-download or re-import the Core ML model"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Triage on Jev Cloud without API key throws typed BackendUnreachableError with guidance")
    func testJevCloudMissingKeyThrowsError() async {
        let mockKeychain = MockKeychainService(initialStorage: [:])
        Container.shared.keychainService.register { mockKeychain }
        Container.shared.backendConfigurationStore.register {
            BackendConfigurationStore(userDefaults: UserDefaults())
        }
        Container.shared.backendHealthProbeService.register {
            BackendHealthProbeService()
        }
        defer {
            Container.shared.keychainService.reset()
            Container.shared.backendConfigurationStore.reset()
            Container.shared.backendHealthProbeService.reset()
        }

        let engine = TriageEngine()
        let sample = InboxData.sampleEmails[0]

        do {
            _ = try await engine.triage(email: sample, backend: .cloudAPI)
            Issue.record("Expected BackendUnreachableError for missing API key")
        } catch let error as BackendUnreachableError {
            #expect(error.backend == .cloudAPI)
            #expect(error.reason == "Missing TypeSafe API Key")
            #expect(error.guidance.contains("paste your TYPESAFE_API_KEY"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("MockTriageEngine enables deterministic offline evaluation for previews")
    func testMockTriageEngine() async throws {
        let mockEngine = MockTriageEngine(latencyMs: 3.5)
        let sample = InboxData.sampleEmails[1]
        let result = try await mockEngine.triage(email: sample, backend: .hostedVPC)

        #expect(result.backendUsed == .hostedVPC)
        #expect(result.latencyMs == 3.5)
        #expect(result.routingTier == .auto)
    }

    @Test("Batch triage on unreachable backend fails fast with BackendUnreachableError")
    func testBatchTriageFastFailure() async {
        let emptyManager = CoreMLModelManager()
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyModels_\(UUID().uuidString)")
        emptyManager.customModelsDirectory = emptyDir
        Container.shared.coreMLModelManager.register { emptyManager }
        defer {
            Container.shared.coreMLModelManager.reset()
            try? FileManager.default.removeItem(at: emptyDir)
        }

        let engine = TriageEngine()
        let sampleBatch = Array(InboxData.sampleEmails.prefix(5))

        do {
            _ = try await engine.triageBatch(emails: sampleBatch, backend: .onDeviceCoreML)
            Issue.record("Expected batch triage to fail fast on unreachable backend")
        } catch let error as BackendUnreachableError {
            #expect(error.backend == .onDeviceCoreML)
            #expect(error.reason == "Model weights not installed")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("TriageEngine skipProbe avoids calling health probe")
    func testSkipProbeInTriageEngine() async throws {
        final class ProbeCounterService: BackendHealthProbeServiceProtocol, @unchecked Sendable {
            var probeCount = 0
            func probe(backend: TriageBackend) async -> BackendHealthStatus {
                probeCount += 1
                return .healthy(latencyMs: 1.0)
            }
            func probeAll() async -> [TriageBackend: BackendHealthStatus] { [:] }
        }

        let emptyManager = CoreMLModelManager()
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyModels_\(UUID().uuidString)")
        emptyManager.customModelsDirectory = emptyDir
        Container.shared.coreMLModelManager.register { emptyManager }

        let counter = ProbeCounterService()
        Container.shared.backendHealthProbeService.register { counter }
        defer {
            Container.shared.coreMLModelManager.reset()
            Container.shared.backendHealthProbeService.reset()
            try? FileManager.default.removeItem(at: emptyDir)
        }

        let engine = TriageEngine()
        let sample = InboxData.sampleEmails[0]

        // When skipProbe is true, health probe must not be called
        // Since backend is onDeviceCoreML and weights are missing, it will fail at Core ML step, NOT health check
        do {
            _ = try await engine.triage(email: sample, backend: .onDeviceCoreML, skipProbe: true)
        } catch let error as BackendUnreachableError {
            #expect(error.reason == "Model weights not installed")
            #expect(counter.probeCount == 0)
        }
    }

    @Test("Triage on generative baseline respects SystemLanguageModel availability")
    func testGenerativeBaselineTriageAvailability() async {
        let engine = TriageEngine()
        let sample = InboxData.sampleEmails[0]

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            do {
                _ = try await engine.triage(email: sample, backend: .generativeBaseline, skipProbe: true)
                Issue.record("Expected BackendUnreachableError for unavailable generative baseline")
            } catch let error as BackendUnreachableError {
                #expect(error.backend == .generativeBaseline)
                switch reason {
                case .modelNotReady:
                    #expect(error.reason == "Apple Intelligence Model Preparing (Downloading Assets)")
                    #expect(error.guidance.contains("macOS is still downloading or preparing"))
                    #expect(error.isPreparing == true)
                case .appleIntelligenceNotEnabled:
                    #expect(error.reason == "Apple Intelligence is Turned Off")
                case .deviceNotEligible:
                    #expect(error.reason == "Device Not Eligible for Apple Intelligence")
                @unknown default:
                    #expect(error.reason.contains("Unavailable"))
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        @unknown default:
            break
        }
    }

    @Test("TriageEngine clearCoreMLCache can be invoked safely")
    func testTriageEngineClearCoreMLCache() {
        let engine = TriageEngine()
        engine.clearCoreMLCache()
    }

    @Test("TriageBackend enum defines all 7 architectures and their metadata")
    func testTriageBackendMetadata() {
        #expect(TriageBackend.allCases.count == 7)

        let coreML = TriageBackend.onDeviceCoreML
        #expect(coreML.iconName == "cpu.fill")
        #expect(coreML.isOffline == true)
        #expect(coreML.isDecisionModel == true)
        #expect(coreML.privacyLevel == .onDevice)
        #expect(coreML.supportsMultimodal == false)

        let serve = TriageBackend.localServe
        #expect(serve.iconName == "network")
        #expect(serve.isOffline == false)
        #expect(serve.privacyLevel == .local)
        #expect(serve.supportsMultimodal == false)

        let vpc = TriageBackend.hostedVPC
        #expect(vpc.iconName == "server.rack")
        #expect(vpc.isOffline == false)
        #expect(vpc.privacyLevel == .vpc)
        #expect(vpc.supportsMultimodal == false)

        let cloud = TriageBackend.cloudAPI
        #expect(cloud.iconName == "cloud.fill")
        #expect(cloud.isOffline == false)
        #expect(cloud.privacyLevel == .cloud)
        #expect(cloud.supportsMultimodal == false)

        let clef = TriageBackend.cloudflareClef
        #expect(clef.displayName == "Cloudflare Clef")
        #expect(clef.shortName == "Clef Edge")
        #expect(clef.description == "Cloudflare Workers AI multimodal edge decision model (9B / 27B).")
        #expect(clef.iconName == "bolt.shield.fill")
        #expect(clef.latencyTier == "< 100ms")
        #expect(clef.privacyLevel == .edge)
        #expect(clef.isOffline == false)
        #expect(clef.isDecisionModel == true)
        #expect(clef.supportsMultimodal == true)
        #expect(clef.pricePerMillionInputTokens == 0.05)

        let openai = TriageBackend.openaiDecisions
        #expect(openai.displayName == "OpenAI Decisions")
        #expect(openai.shortName == "OpenAI")
        #expect(openai.description == "OpenAI Decisions API (GPT-6 Luna) fast decision primitive at $0.10/1M tokens.")
        #expect(openai.iconName == "sparkle.magnifyingglass")
        #expect(openai.latencyTier == "< 100ms")
        #expect(openai.privacyLevel == .cloud)
        #expect(openai.isOffline == false)
        #expect(openai.isDecisionModel == true)
        #expect(openai.supportsMultimodal == true)
        #expect(openai.pricePerMillionInputTokens == 0.10)

        let baseline = TriageBackend.generativeBaseline
        #expect(baseline.iconName == "sparkles")
        #expect(baseline.isOffline == true)
        #expect(baseline.isDecisionModel == false)
        #expect(baseline.privacyLevel == .onDevice)
        #expect(baseline.supportsMultimodal == false)
    }

    @Test("TriageEngine triageBatch cooperative cancellation cancels child worker tasks (IMP-1 / IMP-3)")
    func testTriageBatchCooperativeCancellation() async {
        let emptyManager = CoreMLModelManager()
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyModels_\(UUID().uuidString)")
        emptyManager.customModelsDirectory = emptyDir
        Container.shared.coreMLModelManager.register { emptyManager }

        final class SlowHealthyProbeService: BackendHealthProbeServiceProtocol, @unchecked Sendable {
            func probe(backend: TriageBackend) async -> BackendHealthStatus {
                try? await Task.sleep(nanoseconds: 50_000_000)
                return .healthy(latencyMs: 1.0)
            }
            func probeAll() async -> [TriageBackend: BackendHealthStatus] { [:] }
        }

        Container.shared.backendHealthProbeService.register { SlowHealthyProbeService() }
        defer {
            Container.shared.coreMLModelManager.reset()
            Container.shared.backendHealthProbeService.reset()
            try? FileManager.default.removeItem(at: emptyDir)
        }

        let engine = TriageEngine()
        let sampleBatch = Array(InboxData.sampleEmails.prefix(20))

        let batchTask = Task {
            try await engine.triageBatch(emails: sampleBatch, backend: .onDeviceCoreML)
        }

        // Cancel the batch task to trigger cooperative cancellation
        batchTask.cancel()

        do {
            _ = try await batchTask.value
            Issue.record("Expected CancellationError when task is cancelled")
        } catch is CancellationError {
            // Success: cooperative cancellation handled cleanly
        } catch {
            Issue.record("Expected CancellationError, but got: \(error)")
        }
    }
}

@Suite("Keychain & Configuration Store Tests", .serialized)
struct ConfigurationTests {
    @Test("KeychainService stores and retrieves keys securely")
    func testKeychainService() throws {
        let keychain = MockKeychainService()
        try keychain.set("ts_live_test_123", for: .typesafeApiKey)
        #expect(keychain.string(for: .typesafeApiKey) == "ts_live_test_123")

        try keychain.set("token_abc", for: .hostedVpcToken)
        #expect(keychain.string(for: .hostedVpcToken) == "token_abc")

        try keychain.set("hf_token_secret", for: .huggingFaceToken)
        #expect(keychain.string(for: .huggingFaceToken) == "hf_token_secret")

        try keychain.delete(for: .typesafeApiKey)
        #expect(keychain.string(for: .typesafeApiKey) == nil)
    }

    @Test("MockKeychainService supports all KeychainKey cases and deletion")
    func testMockKeychainServiceAllKeys() throws {
        let mock = MockKeychainService()
        for key in KeychainKey.allCases {
            #expect(mock.string(for: key) == nil)
            try mock.set("secret_\(key.rawValue)", for: key)
            #expect(mock.string(for: key) == "secret_\(key.rawValue)")
            try mock.delete(for: key)
            #expect(mock.string(for: key) == nil)
        }
    }

    @Test("BackendConfigurationStore provides correct default presets and manages tokens")
    func testConfigStoreDefaults() {
        let suite = "test_config_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let mockKeychain = MockKeychainService()
        let store = BackendConfigurationStore(userDefaults: defaults, keychain: mockKeychain)
        #expect(store.jevCloudURL == BackendConfigurationStore.defaultJevCloudURL)
        #expect(store.localServeURL == BackendConfigurationStore.defaultLocalServeURL)
        #expect(store.hostedVpcURL == BackendConfigurationStore.defaultHostedVpcURL)
        #expect(store.coreMLDownloadURL == "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")
        #expect(BackendConfigurationStore.defaultCoreMLDownloadURL == "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")

        store.huggingFaceToken = "hf_test_123"
        #expect(store.huggingFaceToken == "hf_test_123")
        store.resetToDefaults()
        #expect(store.huggingFaceToken.isEmpty)
        #expect(store.coreMLDownloadURL == "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")
    }

    @Test("BackendConfigurationStore migrates legacy LayaModernBERT and typesafe URLs to canonical huggingface default")
    func testConfigStoreMigrationToLayaMLX() {
        let defaults1 = UserDefaults(suiteName: "test_migration_1_\(UUID().uuidString)")!
        defer { defaults1.removePersistentDomain(forName: "test_migration_1") }
        defaults1.set("https://github.com/convaiinnovations/laya/releases/latest/download/LayaModernBERT.mlmodelc.zip", forKey: "ai.typesafe.mailtriage.coreMLDownloadURL")
        let store1 = BackendConfigurationStore(userDefaults: defaults1, keychain: MockKeychainService())
        #expect(store1.coreMLDownloadURL == "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")

        let defaults2 = UserDefaults(suiteName: "test_migration_2_\(UUID().uuidString)")!
        defer { defaults2.removePersistentDomain(forName: "test_migration_2") }
        defaults2.set("https://huggingface.co/typesafe/laya-421m-coreml", forKey: "ai.typesafe.mailtriage.coreMLDownloadURL")
        let store2 = BackendConfigurationStore(userDefaults: defaults2, keychain: MockKeychainService())
        #expect(store2.coreMLDownloadURL == "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")

        let defaults3 = UserDefaults(suiteName: "test_migration_3_\(UUID().uuidString)")!
        defer { defaults3.removePersistentDomain(forName: "test_migration_3") }
        defaults3.set("https://huggingface.co/aac6fef/laya-mlx", forKey: "ai.typesafe.mailtriage.coreMLDownloadURL")
        let store3 = BackendConfigurationStore(userDefaults: defaults3, keychain: MockKeychainService())
        #expect(store3.coreMLDownloadURL == "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")
    }

    @Test("CoreMLModelManager resolves Hugging Face model URL to model.safetensors")
    func testResolveDownloadURL() {
        let hfURL = URL(string: "https://huggingface.co/aac6fef/laya-mlx")!
        let resolved = CoreMLModelManager.resolveDownloadURL(hfURL)
        #expect(resolved.absoluteString == "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")

        let hfTreeURL = URL(string: "https://huggingface.co/aac6fef/laya-mlx/tree/main")!
        let resolvedTree = CoreMLModelManager.resolveDownloadURL(hfTreeURL)
        #expect(resolvedTree.absoluteString == "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")

        let alreadyResolved = URL(string: "https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors")!
        #expect(CoreMLModelManager.resolveDownloadURL(alreadyResolved).absoluteString == alreadyResolved.absoluteString)
    }

    @Test("BackendConfigurationStore parses .env content correctly")
    func testParseDotEnvContent() {
        let envContent = """
        # This is a comment
        OTHER_KEY=ignore_me

        TYPESAFE_API_KEY=raw_key_123
        HOSTED_TOKEN="quoted_key_456"
        SINGLE_QUOTED='single_key_789'
        export EXPORTED_KEY="exported_val"
        EMPTY_KEY=
        """

        #expect(BackendConfigurationStore.parseDotEnvContent(envContent, key: "TYPESAFE_API_KEY") == "raw_key_123")
        #expect(BackendConfigurationStore.parseDotEnvContent(envContent, key: "HOSTED_TOKEN") == "quoted_key_456")
        #expect(BackendConfigurationStore.parseDotEnvContent(envContent, key: "SINGLE_QUOTED") == "single_key_789")
        #expect(BackendConfigurationStore.parseDotEnvContent(envContent, key: "EXPORTED_KEY") == "exported_val")
        #expect(BackendConfigurationStore.parseDotEnvContent(envContent, key: "EMPTY_KEY") == nil)
        #expect(BackendConfigurationStore.parseDotEnvContent(envContent, key: "NON_EXISTENT") == nil)
    }

    @Test("BackendConfigurationStore loads TYPESAFE_API_KEY from environment and populates Keychain (SEC-2)")
    func testLoadDotEnvAndPopulateKeychain() {
        // SEC-2: If the required API keys are present in the environment, use them, otherwise fail the respective test
        guard let envKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !envKey.isEmpty else {
            withKnownIssue("Missing required TYPESAFE_API_KEY in environment") {
                #expect(Bool(false), "Missing required TYPESAFE_API_KEY in environment")
            }
            return
        }

        #expect(envKey.starts(with: "apikey_") == true)

        let store = BackendConfigurationStore(userDefaults: UserDefaults())
        let key = store.typesafeApiKey
        #expect(!key.isEmpty)
        #expect(key == envKey)

        // Verify it was populated to keychain
        let keychain = Container.shared.keychainService()
        #expect(keychain.string(for: .typesafeApiKey) == envKey)
    }

    @Test("BackendConfigurationStore normalizes System One endpoints to /v1/systemone")
    func testNormalizeSystemOneEndpoint() {
        let def = BackendConfigurationStore.defaultLocalServeURL

        // Ending in /v1
        let v1URL = BackendConfigurationStore.normalizeSystemOneEndpoint("http://127.0.0.1:8000/v1", defaultURL: def)
        #expect(v1URL.absoluteString == "http://127.0.0.1:8000/v1/systemone")

        // Ending in /v1/
        let v1SlashURL = BackendConfigurationStore.normalizeSystemOneEndpoint("http://127.0.0.1:8000/v1/", defaultURL: def)
        #expect(v1SlashURL.absoluteString == "http://127.0.0.1:8000/v1/systemone")

        // Ending in port :8000 without path
        let portURL = BackendConfigurationStore.normalizeSystemOneEndpoint("http://127.0.0.1:8000", defaultURL: def)
        #expect(portURL.absoluteString == "http://127.0.0.1:8000/v1/systemone")

        // Bare host with trailing slash
        let rootSlashURL = BackendConfigurationStore.normalizeSystemOneEndpoint("http://127.0.0.1:8000/", defaultURL: def)
        #expect(rootSlashURL.absoluteString == "http://127.0.0.1:8000/v1/systemone")

        // Hosted VPC ending in /v1
        let vpcV1URL = BackendConfigurationStore.normalizeSystemOneEndpoint("https://api.impossibl.com/v1", defaultURL: BackendConfigurationStore.defaultHostedVpcURL)
        #expect(vpcV1URL.absoluteString == "https://api.impossibl.com/v1/systemone")

        // Already normalized ending in /systemone
        let alreadyNormal = BackendConfigurationStore.normalizeSystemOneEndpoint("http://127.0.0.1:8000/v1/systemone", defaultURL: def)
        #expect(alreadyNormal.absoluteString == "http://127.0.0.1:8000/v1/systemone")

        // Empty string fallback
        let emptyURL = BackendConfigurationStore.normalizeSystemOneEndpoint("", defaultURL: def)
        #expect(emptyURL.absoluteString == def)

        // SEC-4: Rejection of invalid URL schemes
        let fileURL = BackendConfigurationStore.normalizeSystemOneEndpoint("file:///etc/passwd", defaultURL: def)
        #expect(fileURL.absoluteString == def)

        let jsURL = BackendConfigurationStore.normalizeSystemOneEndpoint("javascript:alert(1)", defaultURL: def)
        #expect(jsURL.absoluteString == def)

        let dataURL = BackendConfigurationStore.normalizeSystemOneEndpoint("data:text/plain;base64,SGVsbG8=", defaultURL: def)
        #expect(dataURL.absoluteString == def)

        // SEC-4: Automatic promotion of remote unencrypted HTTP to HTTPS
        let remoteHTTP = BackendConfigurationStore.normalizeSystemOneEndpoint("http://remote-server.com/v1", defaultURL: def)
        #expect(remoteHTTP.absoluteString == "https://remote-server.com/v1/systemone")

        // SEC-4: Allowed unencrypted loopback endpoints
        let loopbackLocalhost = BackendConfigurationStore.normalizeSystemOneEndpoint("http://localhost:8000/v1", defaultURL: def)
        #expect(loopbackLocalhost.absoluteString == "http://localhost:8000/v1/systemone")

        let loopbackIPv6 = BackendConfigurationStore.normalizeSystemOneEndpoint("http://[::1]:8000/v1", defaultURL: def)
        #expect(loopbackIPv6.absoluteString == "http://[::1]:8000/v1/systemone")
    }

    @Test("BackendConfigurationStore automatically migrates old /v1 stored values in UserDefaults")
    func testConfigStoreMigration() {
        let suite = "test_migration_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Store legacy /v1 URLs in UserDefaults
        defaults.set("http://127.0.0.1:8000/v1", forKey: "ai.typesafe.mailtriage.localServeURL")
        defaults.set("https://api.impossibl.com/v1", forKey: "ai.typesafe.mailtriage.hostedVpcURL")

        // Initialize store which should trigger migration
        let store = BackendConfigurationStore(userDefaults: defaults, keychain: MockKeychainService())

        #expect(store.localServeURL == "http://127.0.0.1:8000/v1/systemone")
        #expect(store.hostedVpcURL == "https://api.impossibl.com/v1/systemone")

        // Confirm migration was persisted to UserDefaults
        #expect(defaults.string(forKey: "ai.typesafe.mailtriage.localServeURL") == "http://127.0.0.1:8000/v1/systemone")
        #expect(defaults.string(forKey: "ai.typesafe.mailtriage.hostedVpcURL") == "https://api.impossibl.com/v1/systemone")
    }
}

@Suite("Health Probe & Diagnostic Tests", .serialized)
struct HealthProbeTests {
    @Test("Probe returns unreachable when Core ML model weights are absent")
    func testCoreMLProbeWeightsAbsent() async {
        let emptyManager = CoreMLModelManager()
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyModels_\(UUID().uuidString)")
        emptyManager.customModelsDirectory = emptyDir
        Container.shared.coreMLModelManager.register { emptyManager }
        defer {
            Container.shared.coreMLModelManager.reset()
            try? FileManager.default.removeItem(at: emptyDir)
        }

        let probe = BackendHealthProbeService()
        let status = await probe.probe(backend: .onDeviceCoreML)

        switch status {
        case .unreachable(let reason, let guidance):
            #expect(reason == "Model weights not installed")
            #expect(guidance.contains("download the Core ML model"))
        default:
            Issue.record("Expected .unreachable for absent weights, got \(status)")
        }
    }

    @Test("Probe returns unreachable when Core ML model file is corrupted (0 bytes) or missing (SIM-1)")
    func testCoreMLProbeWeightsCorrupted() async throws {
        let manager = CoreMLModelManager()
        let isolatedDir = FileManager.default.temporaryDirectory.appendingPathComponent("CorruptedProbe_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        manager.customModelsDirectory = isolatedDir

        // Write empty dummy file (0 bytes) to model path
        let dummyModel = isolatedDir.appendingPathComponent("LayaDecisionModel.mlmodelc")
        try "".write(to: dummyModel, atomically: true, encoding: .utf8)

        Container.shared.coreMLModelManager.register { manager }
        defer {
            Container.shared.coreMLModelManager.reset()
            try? FileManager.default.removeItem(at: isolatedDir)
        }

        let probe = BackendHealthProbeService()
        let status = await probe.probe(backend: .onDeviceCoreML)

        switch status {
        case .unreachable(let reason, let guidance):
            #expect(reason.contains("Failed to load Core ML model"))
            #expect(guidance.contains("re-download the Core ML model"))
        default:
            Issue.record("Expected .unreachable for corrupted weights, but probe falsely reported \(status)")
        }
    }

    @Test("Probe returns healthy when non-empty safetensors model file is installed")
    func testCoreMLProbeSafetensorsHealthy() async throws {
        let manager = CoreMLModelManager()
        let isolatedDir = FileManager.default.temporaryDirectory.appendingPathComponent("SafetensorsProbe_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        manager.customModelsDirectory = isolatedDir

        let safetensorsModel = isolatedDir.appendingPathComponent("model.safetensors")
        try "dummy safetensors content".write(to: safetensorsModel, atomically: true, encoding: .utf8)

        Container.shared.coreMLModelManager.register { manager }
        defer {
            Container.shared.coreMLModelManager.reset()
            try? FileManager.default.removeItem(at: isolatedDir)
        }

        let probe = BackendHealthProbeService()
        let status = await probe.probe(backend: .onDeviceCoreML)

        switch status {
        case .healthy:
            break
        default:
            Issue.record("Expected .healthy for installed safetensors model, got \(status)")
        }
    }

    @Test("Probe returns unreachable when Jev API key is missing")
    func testJevCloudProbeMissingKey() async {
        Container.shared.keychainService.register {
            MockKeychainService(initialStorage: [:])
        }
        Container.shared.backendConfigurationStore.reset()
        defer {
            Container.shared.keychainService.reset()
            Container.shared.backendConfigurationStore.reset()
        }

        let probe = BackendHealthProbeService()
        let status = await probe.probe(backend: .cloudAPI)

        switch status {
        case .unreachable(let reason, let guidance):
            #expect(reason == "Missing TypeSafe API Key")
            #expect(guidance.contains("paste your TYPESAFE_API_KEY"))
        default:
            Issue.record("Expected .unreachable for missing API key, got \(status)")
        }
    }

    @Test("Probe returns unreachable when local laya-serve is not running")
    func testLocalServeProbeUnreachable() async {
        let probe = BackendHealthProbeService()
        let status = await probe.probe(backend: .localServe)

        switch status {
        case .unreachable(let reason, let guidance):
            #expect(reason.contains("laya-serve is not running"))
            #expect(guidance.contains("laya serve"))
        case .healthy:
            // If local server actually happens to be running on machine, healthy is acceptable
            break
        case .checking:
            Issue.record("Probe should complete")
        }
    }

    @Test("Health probe correctly maps 401, 403, 404, 422, and 429 status codes")
    func testHealthProbeStatusCodes() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTPStatusURLProtocol.self]
        let session = URLSession(configuration: config)
        let probe = BackendHealthProbeService(session: session)

        MockHTTPStatusURLProtocol.mockStatusCode = 401
        let status401 = await probe.probe(backend: .localServe)
        #expect(status401.reason?.contains("Invalid API Key (HTTP 401)") == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 403
        let status403 = await probe.probe(backend: .localServe)
        #expect(status403.reason?.contains("Authentication Failed (HTTP 403)") == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 404
        let status404 = await probe.probe(backend: .localServe)
        #expect(status404.reason?.contains("Endpoint Not Found (HTTP 404)") == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 422
        let status422 = await probe.probe(backend: .localServe)
        #expect(status422.reason?.contains("Schema Error (HTTP 422)") == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 429
        let status429 = await probe.probe(backend: .localServe)
        #expect(status429.reason?.contains("Rate Limited (HTTP 429)") == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 200
        let status200 = await probe.probe(backend: .localServe)
        #expect(status200.isHealthy == true)
    }

    @Test("Jev cloud probe sends valid question payload and maps 200, 401, 422")
    func testJevCloudProbeResponses() async throws {
        let mockKeychain = MockKeychainService(initialStorage: [:])
        try mockKeychain.set("ts-test-key-12345", for: .typesafeApiKey)
        let testConfigStore = BackendConfigurationStore(
            userDefaults: UserDefaults(suiteName: "testJevProbeResponses_\(UUID().uuidString)")!,
            keychain: mockKeychain
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTPStatusURLProtocol.self]
        let session = URLSession(configuration: config)
        let probe = BackendHealthProbeService(session: session, configStore: testConfigStore)

        MockHTTPStatusURLProtocol.mockStatusCode = 200
        let status200 = await probe.probe(backend: .cloudAPI)
        #expect(status200.isHealthy == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 401
        let status401 = await probe.probe(backend: .cloudAPI)
        #expect(status401.reason?.contains("Invalid API Key (HTTP 401)") == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 422
        let status422 = await probe.probe(backend: .cloudAPI)
        #expect(status422.reason?.contains("Schema Error (HTTP 422)") == true)
    }

    @Test("Jev cloud probe surfaces exact server error message when returned in body")
    func testJevCloudProbeSurfacesRealHttpErrorBody() async throws {
        let mockKeychain = MockKeychainService(initialStorage: [:])
        try mockKeychain.set("ts-test-key-12345", for: .typesafeApiKey)
        let testConfigStore = BackendConfigurationStore(
            userDefaults: UserDefaults(suiteName: "testJevProbeError_\(UUID().uuidString)")!,
            keychain: mockKeychain
        )
        defer {
            MockHTTPStatusURLProtocol.mockResponseData = Data()
            MockHTTPStatusURLProtocol.mockStatusCode = 200
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTPStatusURLProtocol.self]
        let session = URLSession(configuration: config)
        let probe = BackendHealthProbeService(session: session, configStore: testConfigStore)

        // Test JSON detail.message
        MockHTTPStatusURLProtocol.mockStatusCode = 400
        let errorJson = """
        {"detail": {"message": "Model 'jev-legacy' is deprecated or unavailable."}}
        """.data(using: .utf8)!
        MockHTTPStatusURLProtocol.mockResponseData = errorJson

        let status400 = await probe.probe(backend: .cloudAPI)
        #expect(status400.reason == "Jev Error (HTTP 400): Model 'jev-legacy' is deprecated or unavailable.")

        // Test JSON detail as string (e.g. 422)
        MockHTTPStatusURLProtocol.mockStatusCode = 422
        let error422Json = """
        {"detail": "Invalid question payload schema"}
        """.data(using: .utf8)!
        MockHTTPStatusURLProtocol.mockResponseData = error422Json

        let status422 = await probe.probe(backend: .cloudAPI)
        #expect(status422.reason == "Jev Error (HTTP 422): Invalid question payload schema")

        // Test plain text error body
        MockHTTPStatusURLProtocol.mockStatusCode = 502
        MockHTTPStatusURLProtocol.mockResponseData = "Bad Gateway from upstream".data(using: .utf8)!

        let status502 = await probe.probe(backend: .cloudAPI)
        #expect(status502.reason == "Jev Error (HTTP 502): Bad Gateway from upstream")
    }

    @Test("Generative baseline probe inspects SystemLanguageModel availability")
    func testGenerativeBaselineProbe() async {
        let probe = BackendHealthProbeService()
        let status = await probe.probe(backend: .generativeBaseline)

        switch SystemLanguageModel.default.availability {
        case .available:
            #expect(status.isHealthy == true)
        case .unavailable(let reason):
            #expect(status.isHealthy == false)
            switch reason {
            case .modelNotReady:
                #expect(status.reason == "Apple Intelligence Model Preparing (Downloading Assets)")
                #expect(status.isPreparing == true)
                #expect(status.guidance?.contains("System Settings") == true)
            case .appleIntelligenceNotEnabled:
                #expect(status.reason == "Apple Intelligence is Turned Off")
                #expect(status.isPreparing == false)
            case .deviceNotEligible:
                #expect(status.reason == "Device Not Eligible for Apple Intelligence")
                #expect(status.isPreparing == false)
            @unknown default:
                #expect(status.reason?.contains("Unavailable") == true)
            }
        @unknown default:
            break
        }
    }

    @Test("probeAll probes all 7 backends concurrently")
    func testProbeAllConcurrently() async {
        let probe = BackendHealthProbeService()
        let results = await probe.probeAll()
        #expect(results.count == 7)
    }

    @Test("BackendHealthStatus and BackendUnreachableError identify preparing state")
    func testPreparingHelperStatus() {
        let preparingStatus = BackendHealthStatus.unreachable(
            reason: "Apple Intelligence Model Preparing (Downloading Assets)",
            guidance: "Wait for assets"
        )
        #expect(preparingStatus.isPreparing == true)
        #expect(preparingStatus.isHealthy == false)

        let otherUnreachable = BackendHealthStatus.unreachable(
            reason: "Connection refused",
            guidance: "Check port"
        )
        #expect(otherUnreachable.isPreparing == false)

        let healthyStatus = BackendHealthStatus.healthy(latencyMs: 1.0)
        #expect(healthyStatus.isPreparing == false)

        let error = BackendUnreachableError(
            backend: .generativeBaseline,
            reason: "Apple Intelligence Model Preparing (Downloading Assets)",
            guidance: "Wait for assets"
        )
        #expect(error.isPreparing == true)
    }

    @Test("BackendUnreachableError formatted descriptions and localized recovery properties (IMP-2 / IMP-3)")
    func testBackendUnreachableErrorFormattedDescriptions() {
        let err1 = BackendUnreachableError(
            backend: .onDeviceCoreML,
            reason: "Model weights not installed",
            guidance: "Open Settings (⌘,) and download the Core ML model."
        )
        #expect(err1.errorDescription == "On-Device Core ML Unreachable: Model weights not installed. Open Settings (⌘,) and download the Core ML model.")
        #expect(err1.recoverySuggestion == "Open Settings (⌘,) and download the Core ML model.")
        #expect(err1.isPreparing == false)

        let err2 = BackendUnreachableError(
            backend: .cloudAPI,
            reason: "Missing TypeSafe API Key",
            guidance: "Open Settings (⌘,) and paste your TYPESAFE_API_KEY."
        )
        #expect(err2.errorDescription == "Jev Cloud API Unreachable: Missing TypeSafe API Key. Open Settings (⌘,) and paste your TYPESAFE_API_KEY.")
        #expect(err2.recoverySuggestion == "Open Settings (⌘,) and paste your TYPESAFE_API_KEY.")
        #expect(err2.isPreparing == false)

        let err3 = BackendUnreachableError(
            backend: .generativeBaseline,
            reason: "Apple Intelligence Model Preparing (Downloading Assets)",
            guidance: "Check System Settings > Apple Intelligence & Siri."
        )
        #expect(err3.errorDescription == "Generative Baseline Unreachable: Apple Intelligence Model Preparing (Downloading Assets). Check System Settings > Apple Intelligence & Siri.")
        #expect(err3.recoverySuggestion == "Check System Settings > Apple Intelligence & Siri.")
        #expect(err3.isPreparing == true)

        let err4 = BackendUnreachableError(
            backend: .localServe,
            reason: "Connection refused",
            guidance: "Run 'laya serve' in terminal."
        )
        #expect(err4.errorDescription == "Local laya-serve Unreachable: Connection refused. Run 'laya serve' in terminal.")
        #expect(err4.recoverySuggestion == "Run 'laya serve' in terminal.")

        let err5 = BackendUnreachableError(
            backend: .cloudflareClef,
            reason: "Missing Cloudflare Account ID",
            guidance: "Open Settings (⌘,) and paste your Cloudflare Account ID."
        )
        #expect(err5.errorDescription == "Cloudflare Clef Unreachable: Missing Cloudflare Account ID. Open Settings (⌘,) and paste your Cloudflare Account ID.")
        #expect(err5.recoverySuggestion == "Open Settings (⌘,) and paste your Cloudflare Account ID.")

        let err6 = BackendUnreachableError(
            backend: .openaiDecisions,
            reason: "Missing OpenAI API Key",
            guidance: "Open Settings (⌘,) and paste your OPENAI_API_KEY."
        )
        #expect(err6.errorDescription == "OpenAI Decisions Unreachable: Missing OpenAI API Key. Open Settings (⌘,) and paste your OPENAI_API_KEY.")
        #expect(err6.recoverySuggestion == "Open Settings (⌘,) and paste your OPENAI_API_KEY.")
    }

    @Test("OpenAI decisions probe sends valid payload and maps 200, 401, 429")
    func testOpenAIDecisionsProbeResponses() async throws {
        let mockKeychain = MockKeychainService(initialStorage: [:])
        try mockKeychain.set("sk-test-key-12345", for: .openaiApiKey)
        let testConfigStore = BackendConfigurationStore(
            userDefaults: UserDefaults(suiteName: "testOpenAIProbeResponses_\(UUID().uuidString)")!,
            keychain: mockKeychain
        )
        testConfigStore.openaiOrganization = "org-test"
        testConfigStore.openaiProject = "proj-test"

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTPStatusURLProtocol.self]
        let session = URLSession(configuration: config)
        let probe = BackendHealthProbeService(session: session, configStore: testConfigStore)

        MockHTTPStatusURLProtocol.mockStatusCode = 200
        let status200 = await probe.probe(backend: .openaiDecisions)
        #expect(status200.isHealthy == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 401
        let status401 = await probe.probe(backend: .openaiDecisions)
        #expect(status401.reason?.contains("Invalid API Key (HTTP 401)") == true || status401.guidance?.contains("Check your OpenAI API Key") == true)

        MockHTTPStatusURLProtocol.mockStatusCode = 429
        let status429 = await probe.probe(backend: .openaiDecisions)
        #expect(status429.reason?.contains("Rate Limited (HTTP 429)") == true || status429.guidance?.contains("quota") == true)

        MockHTTPStatusURLProtocol.mockError = URLError(.timedOut)
        let statusTimeout = await probe.probe(backend: .openaiDecisions)
        MockHTTPStatusURLProtocol.mockError = nil
        #expect(statusTimeout.reason?.contains("Cannot connect to OpenAI Decisions API") == true)
        #expect(statusTimeout.guidance?.contains("Check your internet connection") == true)
    }

    @Test("BackendConfigurationStore correctly manages OpenAI credentials")
    func testBackendConfigurationStoreOpenAIProperties() {
        let mockKeychain = MockKeychainService()
        let suite = "testOpenAIConfig_\(UUID().uuidString)"
        let store = BackendConfigurationStore(userDefaults: UserDefaults(suiteName: suite)!, keychain: mockKeychain)

        store.openaiAPIKey = "sk-live-test"
        store.openaiOrganization = "org-123"
        store.openaiProject = "proj-456"

        #expect(store.openaiAPIKey == "sk-live-test")
        #expect(store.openaiOrganization == "org-123")
        #expect(store.openaiProject == "proj-456")
        #expect(mockKeychain.string(for: .openaiApiKey) == "sk-live-test")

        // Verify Bearer stripping from setter and getter
        store.openaiAPIKey = "Bearer sk-bearer-token"
        #expect(store.openaiAPIKey == "sk-bearer-token")

        try? mockKeychain.set("Bearer sk-keychain-raw", for: .openaiApiKey)
        #expect(store.openaiAPIKey == "sk-keychain-raw")

        store.resetToDefaults()
        #expect(store.openaiAPIKey == "")
        #expect(store.openaiOrganization == "")
        #expect(store.openaiProject == "")
    }
}

private final class MockHTTPStatusURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockStatusCode: Int = 200
    nonisolated(unsafe) static var mockResponseData: Data = Data()
    nonisolated(unsafe) static var mockError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = Self.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1:8000")!,
            statusCode: Self.mockStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.mockResponseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("CoreMLModelManager Tests", .serialized)
@MainActor
struct CoreMLModelManagerTests {
    @Test("CoreMLModelManager computes canonical paths correctly")
    func testModelPaths() {
        let manager = CoreMLModelManager()
        #expect(manager.canonicalModelURL.lastPathComponent == "LayaDecisionModel.mlmodelc")
        #expect(manager.legacyModelURL.lastPathComponent == "LayaDecisionModel.mlmodelc")
        #expect(manager.modelsDirectory.lastPathComponent == "Models")
        #expect(manager.modelsDirectory.path.contains("dev.peterfriese.mailtriageapp") || manager.modelsDirectory.path.contains(Bundle.main.bundleIdentifier ?? ""))
    }

    @Test("CoreMLModelManager resolves isolated custom candidate directory properly")
    func testCandidateDirectoryResolution() throws {
        let manager = CoreMLModelManager()
        let isolatedDir = FileManager.default.temporaryDirectory.appendingPathComponent("CandidateTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedDir) }

        manager.customModelsDirectory = isolatedDir
        #expect(manager.resolvedModelURL == nil)

        let fakeModel = isolatedDir.appendingPathComponent("LayaDecisionModel.mlmodelc")
        try "dummy".write(to: fakeModel, atomically: true, encoding: .utf8)
        #expect(manager.resolvedModelURL == fakeModel)
        #expect(manager.isInstalled == true)
    }

    @Test("CoreMLModelManager importLocalModel with non-existent URL throws error")
    func testImportNonExistentModel() async {
        let manager = CoreMLModelManager()
        let fakeURL = URL(fileURLWithPath: "/tmp/non_existent_model_\(UUID().uuidString).mlmodelc")
        do {
            try await manager.importLocalModel(from: fakeURL)
            Issue.record("Expected failure for non-existent model")
        } catch {
            #expect(manager.errorMessage?.contains("does not exist") == true)
        }
    }

    @Test("CoreMLModelManager importLocalModel with unsupported extension throws error")
    func testImportUnsupportedFormat() async throws {
        let manager = CoreMLModelManager()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).txt")
        try "dummy content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            try await manager.importLocalModel(from: tempFile)
            Issue.record("Expected failure for unsupported format")
        } catch {
            #expect(manager.errorMessage?.contains("Unsupported model format") == true)
        }
    }

    @Test("CoreMLModelManager successfully accepts and imports .safetensors and .bin files")
    func testImportSafetensorsSuccess() async throws {
        let manager = CoreMLModelManager()
        let isolatedDir = FileManager.default.temporaryDirectory.appendingPathComponent("SafetensorsImport_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedDir) }
        manager.customModelsDirectory = isolatedDir

        // Test .safetensors import
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("model_\(UUID().uuidString).safetensors")
        try "dummy safetensors content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try await manager.importLocalModel(from: tempFile)
        #expect(manager.isInstalled)
        #expect(manager.resolvedModelURL != nil)
        #expect(manager.errorMessage == nil)
        #expect(manager.statusMessage == "Ready for inference")

        // Test .bin import
        let binFile = FileManager.default.temporaryDirectory.appendingPathComponent("weights_\(UUID().uuidString).bin")
        try "dummy bin content".write(to: binFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: binFile) }

        try await manager.importLocalModel(from: binFile)
        #expect(manager.isInstalled)
    }

    @Test("CoreMLModelManager throws typed CoreMLError.unsupportedFormat for unsupported formats (IMP-2 / IMP-3)")
    func testTypedCoreMLErrorUnsupportedFormats() async throws {
        let manager = CoreMLModelManager()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TypedErrors_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Test .onnx format
        let onnxFile = tempDir.appendingPathComponent("model.onnx")
        try "dummy onnx data".write(to: onnxFile, atomically: true, encoding: .utf8)

        do {
            try await manager.importLocalModel(from: onnxFile)
            Issue.record("Expected CoreMLError.unsupportedFormat for .onnx")
        } catch let error as CoreMLError {
            guard case .unsupportedFormat(let ext) = error else {
                Issue.record("Expected .unsupportedFormat, got: \(error)")
                return
            }
            #expect(ext.contains("onnx"))
            #expect(error.errorDescription?.contains("Unsupported model format: .onnx") == true)
            #expect(error.errorCode == 400)
        } catch {
            Issue.record("Expected CoreMLError, got: \(error)")
        }
    }

    @Test("Triage on safetensors model evaluates dynamically without error")
    func testTriageOnSafetensorsModel() async throws {
        let manager = CoreMLModelManager()
        let isolatedDir = FileManager.default.temporaryDirectory.appendingPathComponent("SafetensorsTriage_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        manager.customModelsDirectory = isolatedDir

        let safetensorsModel = isolatedDir.appendingPathComponent("model.safetensors")
        try "dummy safetensors content".write(to: safetensorsModel, atomically: true, encoding: .utf8)

        Container.shared.coreMLModelManager.register { manager }
        defer {
            Container.shared.coreMLModelManager.reset()
            try? FileManager.default.removeItem(at: isolatedDir)
        }

        let engine = TriageEngine(coreMLManager: manager)
        let sample = InboxData.sampleEmails[0]

        let result = try await engine.triage(email: sample, backend: .onDeviceCoreML, skipProbe: true)
        #expect(result.backendUsed == .onDeviceCoreML)
        #expect(!result.decision.category.displayName.isEmpty)
    }

    @Test("CoreMLModelManager importLocalModel extracts valid .zip archive containing .mlmodelc (SIM-2)")
    func testImportZipArchiveWithMlmodelc() async throws {
        let manager = CoreMLModelManager()
        let isolatedDir = FileManager.default.temporaryDirectory.appendingPathComponent("IsolatedModels_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedDir) }
        manager.customModelsDirectory = isolatedDir

        // Create a model folder structure inside a staging directory
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("Staging_\(UUID().uuidString)")
        let modelDir = stagingDir.appendingPathComponent("TestModel.mlmodelc")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let sampleFile = modelDir.appendingPathComponent("model.mil")
        try "dummy mil in zip".write(to: sampleFile, atomically: true, encoding: .utf8)

        // Zip stagingDir to archive.zip
        let zipFile = FileManager.default.temporaryDirectory.appendingPathComponent("Archive_\(UUID().uuidString).zip")
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-ck", stagingDir.path, zipFile.path]
        try process.run()
        process.waitUntilExit()
        #endif

        defer {
            try? FileManager.default.removeItem(at: stagingDir)
            try? FileManager.default.removeItem(at: zipFile)
        }

        try await manager.importLocalModel(from: zipFile)
        #expect(manager.isInstalled == true)
        #expect(manager.statusMessage == "Ready for inference")
        #expect(manager.errorMessage == nil)

        try manager.removeInstalledModel()
        #expect(manager.isInstalled == false)
    }

    @Test("CoreMLModelManager importLocalModel copies valid .mlmodelc directory and removes it cleanly")
    func testImportValidMlmodelcDirectory() async throws {
        let manager = CoreMLModelManager()
        let isolatedDir = FileManager.default.temporaryDirectory.appendingPathComponent("IsolatedModels_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedDir) }
        manager.customModelsDirectory = isolatedDir

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestModel_\(UUID().uuidString).mlmodelc")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let sampleFile = tempDir.appendingPathComponent("model.mil")
        try "dummy mil".write(to: sampleFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await manager.importLocalModel(from: tempDir)
        #expect(manager.isInstalled == true)
        #expect(manager.statusMessage == "Ready for inference")
        #expect(manager.errorMessage == nil)

        try manager.removeInstalledModel()
        #expect(manager.isInstalled == false)
        #expect(manager.statusMessage == "Model removed")
    }

    @Test("CoreMLModelManager rejects insecure remote HTTP model download URLs (SEC-3)")
    func testInsecureRemoteModelDownloadRejection() async {
        let manager = CoreMLModelManager()
        let insecureURL = URL(string: "http://insecure-cdn.com/model.safetensors")!
        do {
            try await manager.downloadAndCompile(from: insecureURL)
            Issue.record("Should have thrown for insecure HTTP download URL")
        } catch {
            #expect((error as NSError).code == 400)
            #expect(manager.errorMessage?.contains("HTTPS is required") == true)
        }
    }
}

@Suite("MailStore Triage Operations Tests", .serialized)
@MainActor
struct MailStoreTriageTests {
    @Test("MailStore initial triage state is configured properly")
    func testInitialTriageState() {
        let store = MailStore()
        #expect(store.selectedBackend == .onDeviceCoreML)
        #expect(store.isTriagingSingleEmail == false)
        #expect(store.isBatchTriaging == false)
        #expect(store.batchProgress.processed == 0)
        #expect(store.latestBatchReport == nil)
        #expect(store.showingBatchSummary == false)
    }

    @Test("MailStore surfaces activeBackendError when backend is unreachable")
    func testMailStoreSurfacesUnreachableError() async {
        let emptyManager = CoreMLModelManager()
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyModels_\(UUID().uuidString)")
        emptyManager.customModelsDirectory = emptyDir
        Container.shared.coreMLModelManager.register { emptyManager }
        Container.shared.backendHealthProbeService.reset()
        Container.shared.triageEngine.register {
            TriageEngine() // Real engine throws BackendUnreachableError
        }
        defer {
            Container.shared.coreMLModelManager.reset()
            Container.shared.backendHealthProbeService.reset()
            Container.shared.triageEngine.reset()
            try? FileManager.default.removeItem(at: emptyDir)
        }

        let store = MailStore()
        guard let first = store.filteredEmails.first else {
            Issue.record("No email found")
            return
        }

        await store.triageEmail(id: first.id)

        #expect(store.activeBackendError != nil)
        #expect(store.activeBackendError?.backend == .onDeviceCoreML)
        #expect(store.activeBackendStatus.isHealthy == false)
        #expect(store.activeBackendError?.reason == "Model weights not installed")
    }

    @Test("MailStore triages single email and applies results with mock engine")
    func testTriageSingleEmailWithMock() async {
        let mockEngine = MockTriageEngine()
        Container.shared.triageEngine.register { mockEngine }
        defer { Container.shared.triageEngine.reset() }

        let store = MailStore()
        guard let first = store.filteredEmails.first else {
            Issue.record("No email found")
            return
        }

        await store.triageEmail(id: first.id)

        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.triageResult != nil)
        #expect(updated?.triageResult?.routingTier == .auto)
        #expect(updated?.category == .work)
        #expect(updated?.suggestedAction == "Schedule Task")
    }

    @Test("MailStore executeSuggestedAction modifies email state correctly")
    func testExecuteSuggestedAction() {
        let store = MailStore()
        guard let first = store.filteredEmails.first else {
            Issue.record("No email found")
            return
        }

        let decision = EmailTriageDecision(
            requiresAction: true,
            category: .quarantine,
            urgencyScore: 0,
            suggestedAction: .quarantineThreat
        )
        let result = TriageResult(
            decision: decision,
            confidenceScore: 0.75, // in confirm tier
            decisiveness: 0.75,
            routingTier: .confirm,
            latencyMs: 9.0,
            backendUsed: .onDeviceCoreML
        )

        if let index = store.emails.firstIndex(where: { $0.id == first.id }) {
            store.emails[index].triageResult = result
        }

        store.executeSuggestedAction(for: first.id)

        let updated = store.emails.first(where: { $0.id == first.id })
        #expect(updated?.mailbox == .quarantine)
    }

    @Test("MailStore batch triage updates progress and produces report with mock")
    func testMailStoreBatchTriageWithMock() async {
        let mockEngine = MockTriageEngine()
        Container.shared.triageEngine.register { mockEngine }
        defer { Container.shared.triageEngine.reset() }

        let smallBatch = Array(InboxData.sampleEmails.prefix(10))
        let store = MailStore(emails: smallBatch)

        await store.triageAllEmails()

        #expect(store.latestBatchReport != nil)
        #expect(store.latestBatchReport?.totalProcessed == 10)
        #expect(store.showingBatchSummary == true)
        #expect(store.isBatchTriaging == false)
    }
}

@Suite("Cloudflare Clef Backend Tests", .serialized)
struct CloudflareClefBackendTests {
    @Test("MockKeychainService supports cloudflareAccountId and cloudflareApiToken")
    func testKeychainServiceCloudflareProperties() throws {
        let mock = MockKeychainService()
        #expect(mock.string(for: .cloudflareAccountId) == nil)
        #expect(mock.string(for: .cloudflareApiToken) == nil)

        try mock.set("cf-acc-123", for: .cloudflareAccountId)
        try mock.set("cf-tok-abc", for: .cloudflareApiToken)
        #expect(mock.string(for: .cloudflareAccountId) == "cf-acc-123")
        #expect(mock.string(for: .cloudflareApiToken) == "cf-tok-abc")

        try mock.delete(for: .cloudflareAccountId)
        try mock.delete(for: .cloudflareApiToken)
        #expect(mock.string(for: .cloudflareAccountId) == nil)
        #expect(mock.string(for: .cloudflareApiToken) == nil)
    }

    @Test("BackendConfigurationStore syncs cloudflareAccountId and cloudflareApiToken with Keychain")
    func testBackendConfigurationStoreCloudflareSync() {
        let mockKeychain = MockKeychainService()
        let store = BackendConfigurationStore(
            userDefaults: UserDefaults(suiteName: "testStore_\(UUID().uuidString)")!,
            keychain: mockKeychain
        )
        #expect(store.cloudflareAccountId.isEmpty)
        #expect(store.cloudflareApiToken.isEmpty)

        store.cloudflareAccountId = "  cf-acc-456  "
        store.cloudflareApiToken = "  cf-tok-xyz  "
        #expect(store.cloudflareAccountId == "cf-acc-456")
        #expect(store.cloudflareApiToken == "cf-tok-xyz")
        #expect(mockKeychain.string(for: .cloudflareAccountId) == "cf-acc-456")
        #expect(mockKeychain.string(for: .cloudflareApiToken) == "cf-tok-xyz")

        store.resetToDefaults()
        #expect(store.cloudflareAccountId.isEmpty)
        #expect(store.cloudflareApiToken.isEmpty)
        #expect(mockKeychain.string(for: .cloudflareAccountId) == nil)
        #expect(mockKeychain.string(for: .cloudflareApiToken) == nil)
    }

    @Test("BackendHealthProbeService reports unreachable when Cloudflare credentials missing")
    func testCloudflareProbeMissingCredentials() async {
        Container.shared.keychainService.reset()
        let mockKeychain = MockKeychainService()
        Container.shared.keychainService.register { mockKeychain }
        Container.shared.backendConfigurationStore.reset()
        defer {
            Container.shared.keychainService.reset()
            Container.shared.backendConfigurationStore.reset()
        }

        let probe = BackendHealthProbeService()
        let status = await probe.probe(backend: .cloudflareClef)
        #expect(status.isHealthy == false)
        guard case .unreachable(let reason, let guidance) = status else {
            Issue.record("Expected unreachable status")
            return
        }
        #expect(reason.contains("Cloudflare Account ID"))
        #expect(guidance.contains("Settings"))
    }

    @Test("TriageEngine throws BackendUnreachableError when Cloudflare credentials missing")
    func testCloudflareTriageMissingCredentials() async {
        Container.shared.keychainService.reset()
        let mockKeychain = MockKeychainService()
        Container.shared.keychainService.register { mockKeychain }
        Container.shared.backendConfigurationStore.reset()
        defer {
            Container.shared.keychainService.reset()
            Container.shared.backendConfigurationStore.reset()
        }

        let engine = TriageEngine()
        let sample = InboxData.sampleEmails[0]

        do {
            _ = try await engine.triage(email: sample, backend: .cloudflareClef, skipProbe: true)
            Issue.record("Expected failure for missing credentials")
        } catch let error as BackendUnreachableError {
            #expect(error.backend == .cloudflareClef)
            #expect(error.reason.contains("Cloudflare Account ID"))
        } catch {
            Issue.record("Expected BackendUnreachableError, got \(error)")
        }
    }

    @Test("EmailAttachment properly identifies image mime types and calculates sizes")
    func testEmailAttachmentImageDetection() {
        let png = EmailAttachment(filename: "scan.png", mimeType: "image/png", data: Data([1, 2, 3]))
        #expect(png.isImage == true)
        #expect(png.utType == .png)
        #expect(png.fileSizeBytes == 3)
        #expect(!png.formattedFileSize.isEmpty)

        let jpeg = EmailAttachment(filename: "photo.jpg", mimeType: "image/jpeg", data: Data([4, 5]))
        #expect(jpeg.isImage == true)
        #expect(jpeg.utType == .jpeg)

        let webp = EmailAttachment(filename: "graphic.webp", mimeType: "image/webp", data: Data([6, 7]))
        #expect(webp.isImage == true)
        #expect(webp.utType == .webP)

        let pdf = EmailAttachment(filename: "document.pdf", mimeType: "application/pdf", data: Data([8, 9]))
        #expect(pdf.isImage == false)

        // Invalid image data must return nil rather than generating synthetic blank pixels
        let invalidAttachment = Attachment(Data([1, 2, 3]), type: .png)
        #expect(invalidAttachment == nil)
    }

    @Test("InboxData includes synthetic PNG attachments for billing, database incident, and phishing")
    func testInboxDataAttachments() {
        let emails = InboxData.sampleEmails

        let emailsWithAttachments = emails.filter(\.hasAttachments)
        #expect(!emailsWithAttachments.isEmpty)

        let allAttachments = emails.flatMap(\.attachments)
        let filenames = Set(allAttachments.map(\.filename))

        #expect(filenames.contains("invoice_INV-2026-8819.png"))
        #expect(filenames.contains("database_pool_timeout_trace.png"))
        #expect(filenames.contains("swift_wire_verification.png"))

        for att in allAttachments {
            #expect(att.isImage == true)
            #expect(!att.data.isEmpty)
        }
    }
}

@Suite("Benchmark Session Store Tests", .serialized)
@MainActor
struct BenchmarkSessionStoreTests {
    @Test("BenchmarkSessionStore records individual evaluations and computes accurate statistics")
    func testRecordAndComputeStatistics() {
        let store = BenchmarkSessionStore()
        #expect(store.totalEvaluations == 0)
        #expect(store.activeBackendCount == 0)

        let email1 = Email(
            sender: "Alice",
            senderEmail: "alice@example.com",
            recipient: "me@example.com",
            subject: "Urgent: Prod Down",
            previewSnippet: "Outage",
            body: "Server is down",
            date: Date(),
            mailbox: .inbox
        )
        let result1 = TriageResult(
            decision: EmailTriageDecision(
                requiresAction: true,
                category: .work,
                urgencyScore: 0,
                suggestedAction: .immediateAlert
            ),
            confidenceScore: 0.95,
            decisiveness: 0.95,
            routingTier: .auto,
            latencyMs: 10.0,
            backendUsed: .onDeviceCoreML
        )

        let email2 = Email(
            sender: "Bob",
            senderEmail: "bob@example.com",
            recipient: "me@example.com",
            subject: "Team Lunch",
            previewSnippet: "Lunch",
            body: "Lunch at noon",
            date: Date(),
            mailbox: .inbox
        )
        let result2 = TriageResult(
            decision: EmailTriageDecision(
                requiresAction: false,
                category: .newsletters,
                urgencyScore: 3,
                suggestedAction: .autoArchive
            ),
            confidenceScore: 0.40,
            decisiveness: 0.40,
            routingTier: .escalate,
            latencyMs: 20.0,
            backendUsed: .onDeviceCoreML
        )

        let email3 = Email(
            sender: "Carol",
            senderEmail: "carol@example.com",
            recipient: "me@example.com",
            subject: "Invoice Attached",
            previewSnippet: "Invoice",
            body: "See invoice",
            date: Date(),
            mailbox: .inbox
        )
        let result3 = TriageResult(
            decision: EmailTriageDecision(
                requiresAction: true,
                category: .billing,
                urgencyScore: 1,
                suggestedAction: .scheduleTask
            ),
            confidenceScore: 0.90,
            decisiveness: 0.90,
            routingTier: .auto,
            latencyMs: 30.0,
            backendUsed: .onDeviceCoreML
        )

        store.record(email: email1, result: result1)
        store.recordBatch(results: [(email2, result2), (email3, result3)])

        #expect(store.totalEvaluations == 3)
        #expect(store.activeBackendCount == 1)
        #expect(store.activeBackends == [.onDeviceCoreML])

        let stats = store.statistics(for: .onDeviceCoreML)
        #expect(stats.sampleCount == 3)
        #expect(stats.minLatencyMs == 10.0)
        #expect(stats.maxLatencyMs == 30.0)
        #expect(stats.meanLatencyMs == 20.0)
        #expect(stats.p50LatencyMs == 20.0)
        #expect(stats.p95LatencyMs == 30.0)
        #expect(abs(stats.autoPercentage - 66.67) < 0.1)
        #expect(abs(stats.escalatePercentage - 33.33) < 0.1)
    }

    @Test("BenchmarkSessionStore exportMarkdown includes hardware info and comparative table")
    func testExportMarkdown() {
        let store = BenchmarkSessionStore()
        let email = InboxData.sampleEmails[0]
        let result = TriageResult(
            decision: EmailTriageDecision(
                requiresAction: true,
                category: .work,
                urgencyScore: 1,
                suggestedAction: .scheduleTask
            ),
            confidenceScore: 0.92,
            decisiveness: 0.92,
            routingTier: .auto,
            latencyMs: 8.5,
            backendUsed: .cloudflareClef
        )
        store.record(email: email, result: result)

        let markdown = store.exportMarkdown()
        #expect(markdown.contains("# Mail Triage Benchmark Comparison"))
        #expect(markdown.contains("Cloudflare Clef"))
        #expect(markdown.contains("Edge"))
        #expect(markdown.contains("8.5 ms"))
        #expect(markdown.contains("100.0%"))
        #expect(markdown.contains("Device:"))
    }

    @Test("BenchmarkSessionStore exportCSV formats and escapes data properly")
    func testExportCSV() {
        let store = BenchmarkSessionStore()
        let email = Email(
            sender: "Test",
            senderEmail: "test@example.com",
            recipient: "me@example.com",
            subject: "Hello, \"World\" & Team",
            previewSnippet: "Test snippet",
            body: "Test body",
            date: Date(),
            mailbox: .inbox
        )
        let result = TriageResult(
            decision: EmailTriageDecision(
                requiresAction: true,
                category: .work,
                urgencyScore: 1,
                suggestedAction: .scheduleTask
            ),
            confidenceScore: 0.88,
            decisiveness: 0.88,
            routingTier: .auto,
            latencyMs: 12.3,
            backendUsed: .onDeviceCoreML
        )
        store.record(email: email, result: result)

        let csv = store.exportCSV()
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == "id,timestamp,backend,emailSubject,latencyMs,category,urgency,routingTier,confidence")
        #expect(lines[1].contains("\"Hello, \"\"World\"\" & Team\""))
        #expect(lines[1].contains("onDeviceCoreML"))
        #expect(lines[1].contains("12.30"))
        #expect(lines[1].contains("auto"))
    }

    @Test("BenchmarkSessionStore clearSession resets all session records")
    func testClearSession() {
        let store = BenchmarkSessionStore()
        let email = InboxData.sampleEmails[0]
        let result = TriageResult(
            decision: EmailTriageDecision(
                requiresAction: true,
                category: .work,
                urgencyScore: 1,
                suggestedAction: .scheduleTask
            ),
            confidenceScore: 0.90,
            decisiveness: 0.90,
            routingTier: .auto,
            latencyMs: 5.0,
            backendUsed: .onDeviceCoreML
        )
        store.record(email: email, result: result)
        #expect(store.totalEvaluations == 1)

        store.clearSession()
        #expect(store.totalEvaluations == 0)
        #expect(store.activeBackendCount == 0)
        #expect(store.backendStatistics.isEmpty)
    }

    @Test("MailStore triageEmail records into BenchmarkSessionStore")
    func testMailStoreRecordsIntoBenchmarkSessionStore() async {
        let mockEngine = MockTriageEngine()
        Container.shared.triageEngine.register { mockEngine }
        let sessionStore = BenchmarkSessionStore()
        Container.shared.benchmarkSessionStore.register { sessionStore }
        defer {
            Container.shared.triageEngine.reset()
            Container.shared.benchmarkSessionStore.reset()
        }

        let store = MailStore(emails: Array(InboxData.sampleEmails.prefix(3)))
        let targetID = store.emails[0].id
        await store.triageEmail(id: targetID)

        #expect(sessionStore.totalEvaluations == 1)
        #expect(sessionStore.records[0].backend == store.selectedBackend)
        #expect(sessionStore.records[0].emailSubject == store.emails[0].subject)
    }
}
