import SwiftUI
import AppCore

public struct MailSidebarView: View {
    @Bindable public var store: MailStore

    public init(store: MailStore) {
        self.store = store
    }

    public var body: some View {
        List(selection: selectedMailboxBinding) {
            Section("Favorites") {
                ForEach(Mailbox.favorites) { mailbox in
                    sidebarRow(for: mailbox)
                        .tag(mailbox)
                }
            }

            Section("Categories") {
                ForEach(Mailbox.categories) { mailbox in
                    sidebarRow(for: mailbox)
                        .tag(mailbox)
                }
            }
        }
        .listStyle(.sidebar)
        #if os(macOS)
        .navigationTitle("")
        #else
        .navigationTitle("Mailboxes")
        #endif
        .safeAreaInset(edge: .bottom) {
            calmStatusFooter
        }
    }

    @ViewBuilder
    private func sidebarRow(for mailbox: Mailbox) -> some View {
        HStack {
            Label {
                Text(mailbox.title)
            } icon: {
                Image(systemName: mailbox.iconName)
                    .foregroundStyle(iconColor(for: mailbox))
            }

            Spacer()

            let unread = store.unreadCount(for: mailbox)
            if unread > 0 {
                Text("\(unread)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    private var selectedMailboxBinding: Binding<Mailbox?> {
        Binding(
            get: { store.selectedMailbox },
            set: { if let newValue = $0 { store.selectedMailbox = newValue } }
        )
    }

    private var calmStatusFooter: some View {
        VStack(spacing: 2) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Updated Just Now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(store.totalEmailCount) Messages")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func iconColor(for mailbox: Mailbox) -> Color {
        switch mailbox {
        case .inbox:
            return .blue
        case .vips:
            return .yellow
        case .flagged:
            return .orange
        case .drafts:
            return .teal
        case .sent:
            return .cyan
        case .securityAlerts:
            return .red
        case .billing:
            return .green
        case .work:
            return .indigo
        case .meetings:
            return .purple
        case .newsletters:
            return .mint
        case .quarantine:
            return .orange
        case .archive:
            return .gray
        }
    }
}

#Preview {
    let store = MailStore(emails: InboxData.sampleEmails)
    MailSidebarView(store: store)
}
