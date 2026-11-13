import SwiftUI
import AppCore
import FactoryKit

public struct MailSplitView: View {
    @Injected(\.mailStore) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {}

    public var body: some View {
        @Bindable var boundStore = store
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MailSidebarView(store: store)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                #endif
        } content: {
            MailListView(store: store)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 380, ideal: 440, max: 620)
                #endif
        } detail: {
            MailDetailView(store: store)
                #if os(macOS)
                .frame(minWidth: 460)
                #endif
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .frame(minWidth: 940, minHeight: 600)
        #endif
        .sheet(isPresented: $boundStore.showingBatchSummary) {
            if let report = store.latestBatchReport {
                BatchSummarySheet(report: report)
            }
        }
        .sheet(isPresented: $boundStore.showingSettings) {
            SettingsView()
        }
    }
}

#Preview {
    let _ = Container.shared.mailStore.register {
        MailStore(emails: InboxData.sampleEmails)
    }
    MailSplitView()
}
