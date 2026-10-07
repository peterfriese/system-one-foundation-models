import Foundation
import Observation
import FactoryKit

@Observable
@MainActor
public final class MailStore {
    @ObservationIgnored
    @Injected(\.triageEngine) private var triageEngine

    @ObservationIgnored
    @Injected(\.backendHealthProbeService) private var healthProbe

    @ObservationIgnored
    @Injected(\.benchmarkTruthStore) private var benchmarkTruthStore

    @ObservationIgnored
    @Injected(\.benchmarkSessionStore) private var benchmarkSessionStore

    public var emails: [Email]
    public var selectedMailbox: Mailbox {
        didSet {
            // Keep selection valid or clear if selected email is not in current view
            if let selectedEmailID, !filteredEmails.contains(where: { $0.id == selectedEmailID }) {
                self.selectedEmailID = filteredEmails.first?.id
            }
        }
    }
    public var selectedEmailID: UUID?
    public var searchText: String = ""
    public var unreadOnly: Bool = false

    // MARK: - Triage Engine State
    public var selectedBackend: TriageBackend = .onDeviceCoreML {
        didSet {
            Task { @MainActor in
                await probeActiveBackend()
            }
        }
    }
    public var isTriagingSingleEmail: Bool = false
    public var isBatchTriaging: Bool = false
    public var batchProgress: (processed: Int, total: Int) = (0, 0)
    public var latestBatchReport: BatchTriageReport? = nil
    public var showingBatchSummary: Bool = false

    // MARK: - Backend Health & Diagnostic State
    public var activeBackendStatus: BackendHealthStatus = .healthy(latencyMs: 0)
    public var activeBackendError: BackendUnreachableError? = nil
    public var showingSettings: Bool = false

    // MARK: - Ground-Truth Benchmark Telemetry
    public var canonicalBenchmarkTruth: BenchmarkTruthPayload? = nil

    public init(emails: [Email] = InboxData.sampleEmails, selectedMailbox: Mailbox = .inbox) {
        self.emails = emails
        self.selectedMailbox = selectedMailbox
        self.selectedEmailID = emails.first(where: { $0.mailbox == selectedMailbox })?.id
        self.canonicalBenchmarkTruth = Container.shared.benchmarkTruthStore().loadTruth()
    }

    /// Reloads the canonical ground-truth benchmark payload from disk.
    public func refreshBenchmarkTruth() {
        self.canonicalBenchmarkTruth = benchmarkTruthStore.loadTruth()
    }

    // MARK: - Computed Properties

    public var selectedEmail: Email? {
        guard let selectedEmailID else { return nil }
        return emails.first(where: { $0.id == selectedEmailID })
    }

    public var totalEmailCount: Int {
        emails.count
    }

    public var filteredEmails: [Email] {
        let base = emails.filter { email in
            matchesMailbox(email: email, mailbox: selectedMailbox)
        }

        let unreadFiltered = unreadOnly ? base.filter(\.isUnread) : base

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return unreadFiltered
        }

        return unreadFiltered.filter { email in
            email.sender.localizedCaseInsensitiveContains(query) ||
            email.senderEmail.localizedCaseInsensitiveContains(query) ||
            email.subject.localizedCaseInsensitiveContains(query) ||
            email.previewSnippet.localizedCaseInsensitiveContains(query) ||
            email.body.localizedCaseInsensitiveContains(query)
        }
    }

    public var totalCountForCurrentMailbox: Int {
        totalCount(for: selectedMailbox)
    }

    public var unreadCountForCurrentMailbox: Int {
        unreadCount(for: selectedMailbox)
    }

    public func totalCount(for mailbox: Mailbox) -> Int {
        emails.filter { matchesMailbox(email: $0, mailbox: mailbox) }.count
    }

    public func unreadCount(for mailbox: Mailbox) -> Int {
        emails.filter { matchesMailbox(email: $0, mailbox: mailbox) && $0.isUnread }.count
    }

    // MARK: - Mailbox Matching Logic

    private func matchesMailbox(email: Email, mailbox: Mailbox) -> Bool {
        switch mailbox {
        case .inbox:
            return email.mailbox == .inbox
        case .vips:
            return email.isVIP && email.mailbox != .archive && email.mailbox != .quarantine
        case .flagged:
            return email.isFlagged && email.mailbox != .archive && email.mailbox != .quarantine
        case .drafts:
            return email.mailbox == .drafts
        case .sent:
            return email.mailbox == .sent
        case .securityAlerts:
            return email.mailbox == .securityAlerts || (email.mailbox == .inbox && email.category == .securityAlerts)
        case .billing:
            return email.mailbox == .billing || (email.mailbox == .inbox && email.category == .billing)
        case .work:
            return email.mailbox == .work || (email.mailbox == .inbox && email.category == .work)
        case .meetings:
            return email.mailbox == .meetings || (email.mailbox == .inbox && email.category == .meetings)
        case .newsletters:
            return email.mailbox == .newsletters || (email.mailbox == .inbox && email.category == .newsletters)
        case .quarantine:
            return email.mailbox == .quarantine || (email.mailbox == .inbox && email.category == .quarantine)
        case .archive:
            return email.mailbox == .archive
        }
    }

    // MARK: - Actions

    public func selectMailbox(_ mailbox: Mailbox) {
        selectedMailbox = mailbox
    }

    public func selectEmail(_ email: Email?) {
        selectedEmailID = email?.id
        if let email, email.isUnread {
            markAsRead(email.id)
        }
    }

    public func toggleUnread(for id: UUID) {
        guard let index = emails.firstIndex(where: { $0.id == id }) else { return }
        emails[index].isUnread.toggle()
    }

    public func markAsRead(_ id: UUID) {
        guard let index = emails.firstIndex(where: { $0.id == id }) else { return }
        emails[index].isUnread = false
    }

    public func markAllAsRead() {
        for index in emails.indices {
            if matchesMailbox(email: emails[index], mailbox: selectedMailbox) {
                emails[index].isUnread = false
            }
        }
    }

    public func toggleFlag(for id: UUID) {
        guard let index = emails.firstIndex(where: { $0.id == id }) else { return }
        emails[index].isFlagged.toggle()
    }

    public func moveToMailbox(_ id: UUID, mailbox: Mailbox) {
        guard let index = emails.firstIndex(where: { $0.id == id }) else { return }
        emails[index].mailbox = mailbox
        if mailbox == .inbox && emails[index].category == .quarantine {
            emails[index].category = nil
        }
        if selectedMailbox != mailbox && selectedEmailID == id {
            if !matchesMailbox(email: emails[index], mailbox: selectedMailbox) {
                selectedEmailID = filteredEmails.first(where: { $0.id != id })?.id
            }
        }
    }

    public func moveToInbox(_ id: UUID) {
        moveToMailbox(id, mailbox: .inbox)
        if selectedMailbox != .inbox && selectedEmailID == id {
            selectedEmailID = filteredEmails.first(where: { $0.id != id })?.id
        }
    }

    public func archiveEmail(_ id: UUID) {
        moveToMailbox(id, mailbox: .archive)
        if selectedEmailID == id {
            selectedEmailID = filteredEmails.first(where: { $0.id != id })?.id
        }
    }

    public func deleteEmail(_ id: UUID) {
        guard let index = emails.firstIndex(where: { $0.id == id }) else { return }
        emails.remove(at: index)
        if selectedEmailID == id {
            selectedEmailID = filteredEmails.first?.id
        }
    }

    /// Sends a newly composed email, appending it to the `.sent` mailbox.
    public func sendEmail(to: String, subject: String, body: String) {
        let snippet = body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let newEmail = Email(
            sender: "Me",
            senderEmail: "me@company.internal",
            recipient: to,
            subject: subject.isEmpty ? "(No Subject)" : subject,
            previewSnippet: String(snippet.prefix(120)),
            body: body,
            date: Date(),
            isUnread: false,
            isFlagged: false,
            isVIP: false,
            mailbox: .sent
        )
        emails.insert(newEmail, at: 0)
    }

    public func resetData() {
        self.emails = InboxData.sampleEmails
        self.selectedMailbox = .inbox
        self.selectedEmailID = emails.first(where: { $0.mailbox == .inbox })?.id
        self.searchText = ""
        self.unreadOnly = false
        self.latestBatchReport = nil
        self.showingBatchSummary = false
    }

    // MARK: - Triage Engine Operations

    /// Probes the currently selected backend and updates active diagnostic status.
    public func probeActiveBackend() async {
        activeBackendStatus = .checking
        let status = await healthProbe.probe(backend: selectedBackend)
        print("⏱️ [MailStore] Active backend (\(selectedBackend.displayName)) probe status: \(status)")
        self.activeBackendStatus = status
        if case .unreachable(let reason, let guidance) = status {
            self.activeBackendError = BackendUnreachableError(
                backend: selectedBackend,
                reason: reason,
                guidance: guidance
            )
        } else {
            self.activeBackendError = nil
        }
    }

    /// Triages the currently selected email using the active backend.
    public func triageSelectedEmail() async {
        guard let id = selectedEmailID else { return }
        await triageEmail(id: id)
    }

    /// Triages a specific email by UUID.
    public func triageEmail(id: UUID) async {
        guard let index = emails.firstIndex(where: { $0.id == id }) else { return }
        isTriagingSingleEmail = true
        defer { isTriagingSingleEmail = false }

        do {
            let email = emails[index]
            let result = try await triageEngine.triage(email: email, backend: selectedBackend)
            benchmarkSessionStore.record(email: email, result: result)

            print("⏱️ [MailStore] Single triage done: email \(email.id.uuidString.prefix(8)) in \(String(format: "%.1f", result.latencyMs)) ms via \(selectedBackend.displayName)")

            // Update health and email properties with result
            activeBackendError = nil
            activeBackendStatus = .healthy(latencyMs: result.latencyMs)

            emails[index].triageResult = result
            emails[index].category = result.decision.category
            emails[index].urgencyScore = result.decision.urgencyScore
            emails[index].requiresAction = result.decision.requiresAction
            emails[index].suggestedAction = result.decision.suggestedAction.displayName

            // Symmetrical auto execution: automatically mutate mailbox or flags if tier is .auto
            if result.routingTier == .auto {
                executeActionSilently(action: result.decision.suggestedAction, for: id)
            }
        } catch let error as BackendUnreachableError {
            activeBackendError = error
            activeBackendStatus = .unreachable(reason: error.reason, guidance: error.guidance)
        } catch {
            activeBackendError = BackendUnreachableError(
                backend: selectedBackend,
                reason: error.localizedDescription,
                guidance: "Evaluation failed: \(error.localizedDescription)"
            )
            activeBackendStatus = .unreachable(reason: error.localizedDescription, guidance: error.localizedDescription)
        }
    }

    /// Triages all untriaged emails concurrently across the current dataset.
    public func triageAllEmails() async {
        guard !isBatchTriaging else { return }
        isBatchTriaging = true
        batchProgress = (0, emails.count)
        defer { isBatchTriaging = false }

        do {
            let report = try await triageEngine.triageBatch(
                emails: emails,
                backend: selectedBackend,
                progress: { [weak self] processed, total in
                    Task { @MainActor in
                        self?.batchProgress = (processed, total)
                    }
                },
                onItemCompleted: { [weak self] completedEmail, result in
                    Task { @MainActor in
                        guard let self else { return }
                        self.benchmarkSessionStore.record(email: completedEmail, result: result)
                        if let index = self.emails.firstIndex(where: { $0.id == completedEmail.id }) {
                            self.emails[index].triageResult = result
                            self.emails[index].category = result.decision.category
                            self.emails[index].urgencyScore = result.decision.urgencyScore
                            self.emails[index].requiresAction = result.decision.requiresAction
                            self.emails[index].suggestedAction = result.decision.suggestedAction.displayName

                            if result.routingTier == .auto {
                                self.executeActionSilently(action: result.decision.suggestedAction, for: completedEmail.id)
                            }
                        }
                    }
                }
            )

            activeBackendError = nil
            activeBackendStatus = .healthy(latencyMs: report.averageLatencyMs)
            self.latestBatchReport = report
            self.showingBatchSummary = true
        } catch let error as BackendUnreachableError {
            activeBackendError = error
            activeBackendStatus = .unreachable(reason: error.reason, guidance: error.guidance)
        } catch {
            activeBackendError = BackendUnreachableError(
                backend: selectedBackend,
                reason: error.localizedDescription,
                guidance: "Evaluation failed: \(error.localizedDescription)"
            )
            activeBackendStatus = .unreachable(reason: error.localizedDescription, guidance: error.localizedDescription)
        }
    }

    /// Executes the suggested triage action for a given email (e.g. from 1-click confirmation pill).
    public func executeSuggestedAction(for emailID: UUID) {
        guard let index = emails.firstIndex(where: { $0.id == emailID }) else { return }
        guard let action = emails[index].triageResult?.decision.suggestedAction else { return }

        switch action {
        case .immediateAlert:
            emails[index].isFlagged = true
            emails[index].isVIP = true
            emails[index].mailbox = .inbox
        case .quarantineThreat:
            moveToMailbox(emailID, mailbox: .quarantine)
        case .scheduleTask:
            emails[index].isFlagged = true
            if emails[index].category == nil {
                emails[index].category = .work
            }
        case .draftReply:
            emails[index].isUnread = false
            emails[index].isFlagged = true
        case .autoArchive:
            moveToMailbox(emailID, mailbox: .archive)
        case .moveToInbox:
            moveToInbox(emailID)
        }
    }

    private func executeActionSilently(action: TriageAction, for emailID: UUID) {
        guard let index = emails.firstIndex(where: { $0.id == emailID }) else { return }
        switch action {
        case .autoArchive:
            emails[index].mailbox = .archive
            if selectedMailbox == .inbox && selectedEmailID == emailID {
                selectedEmailID = filteredEmails.first(where: { $0.id != emailID })?.id
            }
        case .quarantineThreat:
            emails[index].mailbox = .quarantine
            if selectedMailbox == .inbox && selectedEmailID == emailID {
                selectedEmailID = filteredEmails.first(where: { $0.id != emailID })?.id
            }
        case .immediateAlert:
            emails[index].isFlagged = true
            emails[index].isVIP = true
        case .scheduleTask:
            emails[index].isFlagged = true
        case .draftReply:
            emails[index].isFlagged = true
        case .moveToInbox:
            emails[index].mailbox = .inbox
        }
    }
}
