import Testing
import SwiftUI
import AppCore
import FactoryKit
@testable import AppUI

@Suite("AppUI Tests")
@MainActor
struct AppUITests {
    @Test("MailRowView renders email correctly")
    func testMailRowView() {
        let email = InboxData.sampleEmails[0]
        let rowView = MailRowView(email: email)
        #expect(rowView.email.id == email.id)
        #expect(rowView.email.sender == email.sender)
    }

    @Test("MailSidebarView initialization with store")
    func testMailSidebarView() {
        let store = MailStore(emails: InboxData.sampleEmails)
        let sidebar = MailSidebarView(store: store)
        #expect(sidebar.store.selectedMailbox == .inbox)
    }

    @Test("MailListView initialization with store")
    func testMailListView() {
        let store = MailStore(emails: InboxData.sampleEmails)
        let listView = MailListView(store: store)
        #expect(listView.store.filteredEmails.count > 0)
    }

    @Test("MailDetailView empty state and selected state")
    func testMailDetailView() {
        let store = MailStore(emails: InboxData.sampleEmails)
        let detailView = MailDetailView(store: store)
        #expect(detailView.store.selectedEmail != nil)

        store.selectedEmailID = nil
        #expect(detailView.store.selectedEmail == nil)
    }

    @Test("MailDetailView with non-inbox email")
    func testMailDetailViewNonInbox() {
        let store = MailStore(emails: InboxData.sampleEmails, selectedMailbox: .archive)
        let detailView = MailDetailView(store: store)
        #expect(detailView.store.selectedEmail?.mailbox == .archive)
    }

    @Test("MailSplitView initialization with Factory")
    func testMailSplitView() {
        Container.shared.mailStore.register {
            MailStore(emails: InboxData.sampleEmails)
        }
        let splitView = MailSplitView()
        #expect(type(of: splitView) == MailSplitView.self)
    }

    @Test("BatchSummarySheet initializes with report")
    func testBatchSummarySheet() {
        let report = BatchTriageReport(
            totalProcessed: 50,
            totalDurationSeconds: 1.2,
            averageLatencyMs: 8.4,
            actionBreakdown: [.scheduleTask: 30, .autoArchive: 20],
            backend: .onDeviceCoreML
        )
        let sheet = BatchSummarySheet(report: report)
        #expect(sheet.report.totalProcessed == 50)
        #expect(sheet.report.backend == .onDeviceCoreML)
    }

    @Test("BatchSummarySheet initializes with report and ground-truth")
    func testBatchSummarySheetWithGroundTruth() {
        let report = BatchTriageReport(
            totalProcessed: 50,
            totalDurationSeconds: 1.2,
            averageLatencyMs: 8.4,
            actionBreakdown: [.scheduleTask: 30, .autoArchive: 20],
            backend: .onDeviceCoreML
        )

        let hardware = BenchmarkHardwareInfo(deviceModel: "Apple Silicon Mac", chipName: "Apple Silicon Reference Hardware", osVersion: "macOS 15")
        let canonicalResult = BenchmarkBackendResult(
            backendName: "On-Device Core ML",
            endpointOrModel: "LayaDecisionModel.mlmodelc",
            sampleCount: 50,
            totalDurationSeconds: 0.44,
            throughputPerSecond: 113.6,
            meanLatencyMs: 8.8,
            p50LatencyMs: 8.5,
            p95LatencyMs: 12.1,
            totalTokens: 0,
            sampleDecisions: []
        )
        let groundTruth = BenchmarkTruthPayload(
            version: "1.0",
            generatedAt: Date(),
            hardwareInfo: hardware,
            sampleCount: 50,
            results: [.onDeviceCoreML: canonicalResult],
            isSyntheticReference: true
        )

        let sheet = BatchSummarySheet(report: report, groundTruth: groundTruth)
        #expect(sheet.report.totalProcessed == 50)
        #expect(sheet.report.backend == .onDeviceCoreML)
    }

    @Test("MailListView store reset updates state")
    func testMailListViewResetData() {
        let store = MailStore(emails: InboxData.sampleEmails)
        store.selectedMailbox = .archive
        store.unreadOnly = true
        store.searchText = "urgent"

        store.resetData()

        #expect(store.selectedMailbox == .inbox)
        #expect(!store.unreadOnly)
        #expect(store.searchText.isEmpty)
        #expect(store.filteredEmails.count == store.emails.filter { $0.mailbox == .inbox }.count)
    }

    @Test("SettingsView tab cases and initialization")
    func testSettingsViewTabs() {
        #expect(SettingsView.Tab.allCases.count == 4)
        #expect(SettingsView.Tab.backends.id == "Backends")
        #expect(SettingsView.Tab.backends.iconName == "server.rack")
        #expect(SettingsView.Tab.coreML.id == "On-Device Model")
        #expect(SettingsView.Tab.coreML.iconName == "cpu.fill")
        #expect(SettingsView.Tab.confidenceRouting.id == "Confidence Routing")
        #expect(SettingsView.Tab.confidenceRouting.iconName == "slider.horizontal.3")
        #expect(SettingsView.Tab.about.id == "About & Telemetry")
        #expect(SettingsView.Tab.about.iconName == "info.circle")

        let view = SettingsView()
        #expect(type(of: view) == SettingsView.self)
    }

    @Test("SettingsView adopts KeychainStorage and loads configured credentials")
    func testSettingsViewKeychainStorage() {
        let mockKeychain = MockKeychainService()
        try? mockKeychain.set("ts_key_test_123", for: .typesafeApiKey)
        try? mockKeychain.set("vpc_token_test_456", for: .hostedVpcToken)
        try? mockKeychain.set("cf_acc_test_789", for: .cloudflareAccountId)
        try? mockKeychain.set("cf_tok_test_012", for: .cloudflareApiToken)

        Container.shared.keychainService.register { mockKeychain }
        defer { Container.shared.keychainService.reset() }

        let view = SettingsView()
        #expect(type(of: view) == SettingsView.self)
    }

    @Test("UrgencyPriority SwiftUI colors and labels map canonically (PRD-2)")
    func testUrgencyPrioritySwiftUIMapping() {
        #expect(UrgencyPriority.p0Critical.displayName == "P0 Critical")
        #expect(UrgencyPriority.p0Critical.color == .red)

        #expect(UrgencyPriority.p1High.displayName == "P1 High")
        #expect(UrgencyPriority.p1High.color == .orange)

        #expect(UrgencyPriority.p2Medium.displayName == "P2 Medium")
        #expect(UrgencyPriority.p2Medium.color == .blue)

        #expect(UrgencyPriority.p3Low.displayName == "P3 Low")
        #expect(UrgencyPriority.p3Low.color == .secondary)

        // Int extensions in SwiftUI
        #expect(0.urgencyPriority == .p0Critical)
        #expect(0.urgencyColor == .red)
        #expect(3.urgencyPriority == .p3Low)
        #expect(3.urgencyColor == .secondary)
    }

    @Test("ComposeMessageSheet initializes with pre-filled Reply / Forward parameters (PRD-3)")
    func testComposeMessageSheetInitialization() {
        let store = MailStore(emails: InboxData.sampleEmails)
        let sheet = ComposeMessageSheet(
            store: store,
            to: "sender@example.com",
            subject: "Re: Meeting notes",
            initialBody: "\n> Previous body"
        )
        #expect(sheet.toText == "sender@example.com")
        #expect(sheet.subjectText == "Re: Meeting notes")
        #expect(sheet.bodyText == "\n> Previous body")
        #expect(sheet.store === store)
    }

    @Test("MailRowView renders email with attachment correctly")
    func testMailRowViewWithAttachment() {
        guard let emailWithAttachment = InboxData.sampleEmails.first(where: { $0.hasAttachments }) else {
            Issue.record("Expected sample email with attachments")
            return
        }
        let rowView = MailRowView(email: emailWithAttachment)
        #expect(rowView.email.hasAttachments)
        #expect(!rowView.email.attachments.isEmpty)
    }

    @Test("MailDetailView renders attachments section for email with attachments")
    func testMailDetailViewWithAttachment() {
        guard let emailWithAttachment = InboxData.sampleEmails.first(where: { $0.hasAttachments }) else {
            Issue.record("Expected sample email with attachments")
            return
        }
        let store = MailStore(emails: [emailWithAttachment])
        let detailView = MailDetailView(store: store)
        #expect(detailView.store.selectedEmail?.hasAttachments == true)
        #expect(detailView.store.selectedEmail?.attachments.count == emailWithAttachment.attachments.count)
    }

    @Test("AttachmentPreviewSheet initializes properly with attachment")
    func testAttachmentPreviewSheet() {
        let attachment = EmailAttachment(
            filename: "invoice_test.png",
            mimeType: "image/png",
            data: InboxData.generateInvoicePNG()
        )
        let sheet = AttachmentPreviewSheet(attachment: attachment)
        #expect(sheet.attachment.filename == "invoice_test.png")
        #expect(sheet.attachment.isImage == true)
    }

    @Test("BenchmarkComparisonSheet initializes and renders properly with empty session")
    func testBenchmarkComparisonSheetEmpty() {
        let sessionStore = BenchmarkSessionStore()
        Container.shared.benchmarkSessionStore.register { sessionStore }
        defer { Container.shared.benchmarkSessionStore.reset() }

        let sheet = BenchmarkComparisonSheet()
        #expect(type(of: sheet) == BenchmarkComparisonSheet.self)
    }

    @Test("BenchmarkComparisonSheet initializes with populated session store")
    func testBenchmarkComparisonSheetPopulated() {
        let sessionStore = BenchmarkSessionStore()
        let email = InboxData.sampleEmails[0]
        let result1 = TriageResult(
            decision: EmailTriageDecision(
                requiresAction: true,
                category: .work,
                urgencyScore: 1,
                suggestedAction: .scheduleTask
            ),
            confidenceScore: 0.95,
            decisiveness: 0.95,
            routingTier: .auto,
            latencyMs: 5.0,
            backendUsed: .onDeviceCoreML
        )
        let result2 = TriageResult(
            decision: EmailTriageDecision(
                requiresAction: true,
                category: .securityAlerts,
                urgencyScore: 0,
                suggestedAction: .immediateAlert
            ),
            confidenceScore: 0.91,
            decisiveness: 0.91,
            routingTier: .auto,
            latencyMs: 45.0,
            backendUsed: .cloudflareClef
        )
        sessionStore.record(email: email, result: result1)
        sessionStore.record(email: email, result: result2)

        Container.shared.benchmarkSessionStore.register { sessionStore }
        defer { Container.shared.benchmarkSessionStore.reset() }

        let sheet = BenchmarkComparisonSheet()
        #expect(type(of: sheet) == BenchmarkComparisonSheet.self)
        #expect(sessionStore.totalEvaluations == 2)
        #expect(sessionStore.activeBackendCount == 2)
    }

    @Test("BenchmarkSortColumn cases, display titles, and default directions")
    func testBenchmarkSortColumnProperties() {
        #expect(BenchmarkSortColumn.allCases.count == 8)
        #expect(BenchmarkSortColumn.backend.title == "Backend")
        #expect(BenchmarkSortColumn.mode.title == "Mode")
        #expect(BenchmarkSortColumn.samples.title == "Samples")
        #expect(BenchmarkSortColumn.meanLatency.title == "Mean Latency")
        #expect(BenchmarkSortColumn.p50.title == "P50")
        #expect(BenchmarkSortColumn.p95.title == "P95")
        #expect(BenchmarkSortColumn.autoRate.title == "Auto %")
        #expect(BenchmarkSortColumn.escalateRate.title == "Escalate %")

        // Latencies and text default to ascending
        #expect(BenchmarkSortColumn.backend.defaultAscending == true)
        #expect(BenchmarkSortColumn.mode.defaultAscending == true)
        #expect(BenchmarkSortColumn.meanLatency.defaultAscending == true)
        #expect(BenchmarkSortColumn.p50.defaultAscending == true)
        #expect(BenchmarkSortColumn.p95.defaultAscending == true)

        // Counts and rates default to descending
        #expect(BenchmarkSortColumn.samples.defaultAscending == false)
        #expect(BenchmarkSortColumn.autoRate.defaultAscending == false)
        #expect(BenchmarkSortColumn.escalateRate.defaultAscending == false)
    }

    @Test("BenchmarkComparisonSheet sortedStatistics prioritizes active backends and respects sort column")
    func testBenchmarkComparisonSheetSorting() {
        let sessionStore = BenchmarkSessionStore()
        let email = InboxData.sampleEmails[0]

        // Fast backend (5.0 ms)
        let fastResult = TriageResult(
            decision: EmailTriageDecision(requiresAction: true, category: .work, urgencyScore: 1, suggestedAction: .scheduleTask),
            confidenceScore: 0.95,
            decisiveness: 0.95,
            routingTier: .auto,
            latencyMs: 5.0,
            backendUsed: .onDeviceCoreML
        )
        // Slower backend (120.0 ms)
        let slowResult = TriageResult(
            decision: EmailTriageDecision(requiresAction: true, category: .newsletters, urgencyScore: 3, suggestedAction: .autoArchive),
            confidenceScore: 0.88,
            decisiveness: 0.88,
            routingTier: .confirm,
            latencyMs: 120.0,
            backendUsed: .cloudAPI
        )
        // Mid backend (45.0 ms)
        let midResult = TriageResult(
            decision: EmailTriageDecision(requiresAction: true, category: .billing, urgencyScore: 2, suggestedAction: .moveToInbox),
            confidenceScore: 0.92,
            decisiveness: 0.92,
            routingTier: .auto,
            latencyMs: 45.0,
            backendUsed: .cloudflareClef
        )

        sessionStore.record(email: email, result: fastResult)
        sessionStore.record(email: email, result: slowResult)
        sessionStore.record(email: email, result: midResult)

        Container.shared.benchmarkSessionStore.register { sessionStore }
        defer { Container.shared.benchmarkSessionStore.reset() }

        // Default: meanLatency ascending (fastest first, 0-sample backends last)
        let defaultSheet = BenchmarkComparisonSheet(sortColumn: .meanLatency, sortAscending: true)
        let defaultSorted = defaultSheet.sortedStatistics

        // The first 3 should be the sampled backends
        #expect(defaultSorted.count == sessionStore.backendStatistics.count)
        let sampled = defaultSorted.filter { $0.sampleCount > 0 }
        #expect(sampled.count == 3)
        #expect(sampled[0].backend == .onDeviceCoreML)
        #expect(sampled[1].backend == .cloudflareClef)
        #expect(sampled[2].backend == .cloudAPI)

        // 0-sample backends must come after all sampled backends
        let unsampled = defaultSorted.filter { $0.sampleCount == 0 }
        #expect(unsampled.count == sessionStore.backendStatistics.count - 3)
        for i in 0..<sampled.count {
            #expect(defaultSorted[i].sampleCount > 0)
        }

        // Descending meanLatency: slowest first among sampled backends
        let descendingSheet = BenchmarkComparisonSheet(sortColumn: .meanLatency, sortAscending: false)
        let descendingSorted = descendingSheet.sortedStatistics
        let sampledDesc = descendingSorted.filter { $0.sampleCount > 0 }
        #expect(sampledDesc[0].backend == .cloudAPI)
        #expect(sampledDesc[1].backend == .cloudflareClef)
        #expect(sampledDesc[2].backend == .onDeviceCoreML)

        // 0-sample backends still come after all sampled backends even when descending
        for i in 0..<sampledDesc.count {
            #expect(descendingSorted[i].sampleCount > 0)
        }

        // Sort by backend name ascending
        let backendNameSheet = BenchmarkComparisonSheet(sortColumn: .backend, sortAscending: true)
        let backendSorted = backendNameSheet.sortedStatistics
        let sampledBackend = backendSorted.filter { $0.sampleCount > 0 }
        #expect(sampledBackend[0].backend.displayName < sampledBackend[1].backend.displayName)
        #expect(sampledBackend[1].backend.displayName < sampledBackend[2].backend.displayName)
    }
}
