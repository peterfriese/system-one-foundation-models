import SwiftUI
import AppCore
import FactoryKit

public struct MailListView: View {
    @Bindable public var store: MailStore
    @Injected(\.backendConfigurationStore) private var configStore
    @State private var showingBenchmarkComparison: Bool = false

    public init(store: MailStore) {
        self.store = store
    }

    public var body: some View {
        List(selection: $store.selectedEmailID) {
            ForEach(store.filteredEmails) { email in
                MailRowView(email: email)
                    .tag(email.id)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                store.toggleUnread(for: email.id)
                            }
                        } label: {
                            Label(
                                email.isUnread ? "Mark as Read" : "Mark as Unread",
                                systemImage: email.isUnread ? "envelope.open" : "envelope.badge"
                            )
                        }
                        .tint(.blue)

                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                store.toggleFlag(for: email.id)
                            }
                        } label: {
                            Label(
                                email.isFlagged ? "Unflag" : "Flag",
                                systemImage: email.isFlagged ? "flag.slash" : "flag.fill"
                            )
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if store.selectedMailbox != .inbox {
                            Button {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    store.moveToInbox(email.id)
                                }
                            } label: {
                                Label("Move to Inbox", systemImage: "tray.and.arrow.down")
                            }
                            .tint(.blue)
                        }

                        Button(role: .destructive) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                store.archiveEmail(email.id)
                            }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.gray)
                    }
                    .contextMenu {
                        if email.mailbox != .inbox || store.selectedMailbox != .inbox {
                            Button("Move to Inbox", systemImage: "tray.and.arrow.down") {
                                withAnimation {
                                    store.moveToInbox(email.id)
                                }
                            }
                        }

                        Button {
                            store.toggleUnread(for: email.id)
                        } label: {
                            Label(
                                email.isUnread ? "Mark as Read" : "Mark as Unread",
                                systemImage: email.isUnread ? "envelope.open" : "envelope.badge"
                            )
                        }

                        Button {
                            store.toggleFlag(for: email.id)
                        } label: {
                            Label(
                                email.isFlagged ? "Unflag" : "Flag",
                                systemImage: email.isFlagged ? "flag.slash" : "flag.fill"
                            )
                        }

                        Divider()

                        Menu("Move to...") {
                            Button("Inbox", systemImage: "tray") {
                                withAnimation {
                                    store.moveToInbox(email.id)
                                }
                            }

                            Divider()

                            ForEach(Mailbox.categories) { mb in
                                Button(mb.title) {
                                    withAnimation {
                                        store.moveToMailbox(email.id, mailbox: mb)
                                    }
                                }
                            }
                        }

                        Button(role: .destructive) {
                            store.archiveEmail(email.id)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }

                        Button(role: .destructive) {
                            store.deleteEmail(email.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(store.selectedMailbox.title)
        #if os(macOS)
        .navigationSubtitle("\(store.totalCount(for: store.selectedMailbox)) messages, \(store.unreadCount(for: store.selectedMailbox)) unread")
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search")
        #else
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.searchText, prompt: "Search \(store.selectedMailbox.title)")
        #endif
        .overlay {
            if store.filteredEmails.isEmpty {
                ContentUnavailableView {
                    Label("No Messages", systemImage: "tray")
                } description: {
                    if !store.searchText.isEmpty {
                        Text("No emails matching \"\(store.searchText)\" in \(store.selectedMailbox.title).")
                    } else if store.unreadOnly {
                        Text("No unread emails in \(store.selectedMailbox.title).")
                    } else {
                        Text("This mailbox is currently empty.")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Group 1: Approach Dropdown + Sparkly Triage All Button
                ControlGroup {
                    // Approach dropdown menu
                    Menu {
                        Section("Decision Model Topologies") {
                            ForEach(TriageBackend.allCases.filter(\.isDecisionModel)) { backend in
                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        store.selectedBackend = backend
                                    }
                                } label: {
                                    HStack {
                                        Label(backend.displayName, systemImage: backend.iconName)
                                        if store.selectedBackend == backend {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        Section("Baseline Comparison") {
                            ForEach(TriageBackend.allCases.filter { !$0.isDecisionModel }) { backend in
                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        store.selectedBackend = backend
                                    }
                                } label: {
                                    HStack {
                                        Label(backend.displayName, systemImage: backend.iconName)
                                        if store.selectedBackend == backend {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: store.selectedBackend.iconName)
                            Text(store.selectedBackend.shortName)
                                .font(.caption.weight(.medium))
                        }
                    }
                    .help("Select Triage Approach: \(store.selectedBackend.displayName)")

                    // Sparkly Triage All Button
                    Button {
                        if !store.isBatchTriaging {
                            Task {
                                await store.triageAllEmails()
                            }
                        }
                    } label: {
                        if store.isBatchTriaging {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("\(store.batchProgress.processed)/\(store.batchProgress.total)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                            .padding(.horizontal, 4)
                        } else {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .disabled(store.isBatchTriaging)
                    .help(store.isBatchTriaging ? "Triaging Inbox..." : "Triage All with \(store.selectedBackend.displayName)")
                }

                Spacer()

                // Benchmark Comparison Button
                Button {
                    showingBenchmarkComparison = true
                } label: {
                    Label("Benchmark Comparison", systemImage: "chart.bar.xaxis")
                }
                .help("Compare All Model Timings & Accuracy")

                // Group 2: Filter Icon + Three-Dotted Menu
                ControlGroup {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            store.unreadOnly.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundStyle(store.unreadOnly ? Color.accentColor : Color.primary)
                    }
                    .help(store.unreadOnly ? "Show All Messages" : "Filter by Unread Only")

                    Menu {
                        Button {
                            showingBenchmarkComparison = true
                        } label: {
                            Label("Benchmark Comparison...", systemImage: "chart.bar.xaxis")
                        }
                        Divider()
                        Toggle("Filter by Unread Only", isOn: $store.unreadOnly)
                        Divider()
                        Button("Mark All as Read") {
                            withAnimation {
                                store.markAllAsRead()
                            }
                        }
                        Divider()
                        Button("Reset Inbox & Triage State", systemImage: "arrow.counterclockwise") {
                            withAnimation {
                                store.resetData()
                            }
                        }
                        Divider()
                        Button("Settings...", systemImage: "gearshape") {
                            openSettings()
                        }
                        .keyboardShortcut(",", modifiers: .command)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .help("More Options")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if let error = store.activeBackendError {
                    backendWarningBanner(error: error)
                }
                if store.isBatchTriaging {
                    batchProgressHeader
                }
                #if os(iOS)
                filterStatusHeader
                #endif
            }
        }
        .task {
            await store.probeActiveBackend()
        }
        .onChange(of: configStore.cloudflareAccountId) { _, _ in
            Task { await store.probeActiveBackend() }
        }
        .onChange(of: configStore.cloudflareApiToken) { _, _ in
            Task { await store.probeActiveBackend() }
        }
        .onChange(of: configStore.typesafeApiKey) { _, _ in
            Task { await store.probeActiveBackend() }
        }
        .sheet(isPresented: $showingBenchmarkComparison) {
            BenchmarkComparisonSheet()
        }
    }

    private func backendWarningBanner(error: BackendUnreachableError) -> some View {
        let isPreparing = error.isPreparing
        let themeColor: Color = isPreparing ? .orange : .red
        let iconName = isPreparing ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill"
        let titleText = isPreparing ? "\(error.backend.displayName) Preparing" : "\(error.backend.displayName) Unreachable"

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(.white)
                    .font(.body.weight(.bold))
                    .padding(6)
                    .background(themeColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(titleText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            Task { await store.probeActiveBackend() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Retry Health Probe")
                    }

                    Text(error.reason)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeColor)

                    Text(error.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Spacer()

                Button {
                    Task { await store.probeActiveBackend() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-check")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Open Settings (⌘,)") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(themeColor.opacity(0.08))
        .overlay(
            Rectangle()
                .stroke(themeColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func openSettings() {
        store.showingSettings = true
    }

    private var batchProgressHeader: some View {
        VStack(spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Triaging Inbox with \(store.selectedBackend.shortName)...")
                        .font(.caption.weight(.medium))
                }
                Spacer()
                Text("\(store.batchProgress.processed) of \(store.batchProgress.total)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: Double(store.batchProgress.processed),
                total: Double(max(store.batchProgress.total, 1))
            )
            .progressViewStyle(.linear)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Divider(), alignment: .bottom
        )
    }

    #if os(iOS)
    private var filterStatusHeader: some View {
        HStack {
            Text("\(store.totalCountForCurrentMailbox) messages, \(store.unreadCountForCurrentMailbox) unread")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if store.unreadOnly {
                Text("Filtered: Unread Only")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
    #endif
}

#Preview {
    let store = MailStore(emails: InboxData.sampleEmails)
    NavigationStack {
        MailListView(store: store)
    }
}
