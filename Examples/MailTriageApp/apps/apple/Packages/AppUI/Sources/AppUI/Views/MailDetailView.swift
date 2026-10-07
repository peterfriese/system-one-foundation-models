import SwiftUI
import AppCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct MailDetailView: View {
    @Bindable public var store: MailStore
    @State private var showingComposeSheet = false
    @State private var composeTo = ""
    @State private var composeSubject = ""
    @State private var composeBody = ""
    @State private var previewAttachment: EmailAttachment? = nil

    public init(store: MailStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let email = store.selectedEmail {
                emailContentView(email)
            } else {
                ContentUnavailableView(
                    "No Message Selected",
                    systemImage: "envelope",
                    description: Text("Choose an email from the message list to view its contents.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Triage with Model Button
                Button {
                    Task {
                        await store.triageSelectedEmail()
                    }
                } label: {
                    if store.isTriagingSingleEmail {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .disabled(store.selectedEmail == nil || store.isTriagingSingleEmail)
                .help("Triage with \(store.selectedBackend.displayName)")

                // Compose
                Button {
                    openCompose(to: "", subject: "", body: "")
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Message")

                // Reply Actions
                Button {
                    if let email = store.selectedEmail {
                        let quote = "\n\nOn \(email.date.formatted(date: .abbreviated, time: .shortened)), \(email.sender) wrote:\n> \(email.body.replacingOccurrences(of: "\n", with: "\n> "))"
                        openCompose(to: email.senderEmail, subject: "Re: \(email.subject)", body: quote)
                    }
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                .disabled(store.selectedEmail == nil)
                .help("Reply")

                Button {
                    if let email = store.selectedEmail {
                        let toField = email.recipient.isEmpty || email.recipient == email.senderEmail
                            ? email.senderEmail
                            : "\(email.senderEmail), \(email.recipient)"
                        let quote = "\n\nOn \(email.date.formatted(date: .abbreviated, time: .shortened)), \(email.sender) wrote:\n> \(email.body.replacingOccurrences(of: "\n", with: "\n> "))"
                        openCompose(to: toField, subject: "Re: \(email.subject)", body: quote)
                    }
                } label: {
                    Image(systemName: "arrowshape.turn.up.left.2")
                }
                .disabled(store.selectedEmail == nil)
                .help("Reply All")

                Button {
                    if let email = store.selectedEmail {
                        let forwardQuote = """


---------- Forwarded message ---------
From: \(email.sender) <\(email.senderEmail)>
Date: \(email.date.formatted(date: .abbreviated, time: .shortened))
Subject: \(email.subject)
To: \(email.recipient)

\(email.body)
"""
                        openCompose(to: "", subject: "Fwd: \(email.subject)", body: forwardQuote)
                    }
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                }
                .disabled(store.selectedEmail == nil)
                .help("Forward")

                // Management Actions
                if let email = store.selectedEmail, email.mailbox != .inbox {
                    Button {
                        withAnimation {
                            store.moveToInbox(email.id)
                        }
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .help("Move to Inbox")
                }

                Button {
                    if let id = store.selectedEmailID {
                        withAnimation {
                            store.archiveEmail(id)
                        }
                    }
                } label: {
                    Image(systemName: "archivebox")
                }
                .disabled(store.selectedEmail == nil)
                .help("Archive Message")

                Button(role: .destructive) {
                    if let id = store.selectedEmailID {
                        withAnimation {
                            store.deleteEmail(id)
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.selectedEmail == nil)
                .help("Delete Message")

                Menu {
                    Button {
                        if let id = store.selectedEmailID {
                            withAnimation {
                                store.moveToInbox(id)
                            }
                        }
                    } label: {
                        Label("Inbox", systemImage: "tray")
                    }

                    Divider()

                    ForEach(Mailbox.categories) { mb in
                        Button(mb.title) {
                            if let id = store.selectedEmailID {
                                withAnimation {
                                    store.moveToMailbox(id, mailbox: mb)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(store.selectedEmail == nil)
                .help("Move to Folder")

                Button {
                    if let id = store.selectedEmailID {
                        withAnimation {
                            store.toggleFlag(for: id)
                        }
                    }
                } label: {
                    let isFlagged = store.selectedEmail?.isFlagged ?? false
                    Image(systemName: isFlagged ? "flag.fill" : "flag")
                        .foregroundStyle(isFlagged ? .orange : .primary)
                }
                .disabled(store.selectedEmail == nil)
                .help(store.selectedEmail?.isFlagged == true ? "Remove Flag" : "Flag Message")

                Button {
                    if let id = store.selectedEmailID {
                        withAnimation {
                            store.toggleUnread(for: id)
                        }
                    }
                } label: {
                    let isUnread = store.selectedEmail?.isUnread ?? false
                    Image(systemName: isUnread ? "envelope.open" : "envelope.badge")
                }
                .disabled(store.selectedEmail == nil)
                .help(store.selectedEmail?.isUnread == true ? "Mark as Read" : "Mark as Unread")
            }
        }
        .sheet(isPresented: $showingComposeSheet) {
            ComposeMessageSheet(
                store: store,
                to: composeTo,
                subject: composeSubject,
                initialBody: composeBody
            )
            .id("\(composeTo)-\(composeSubject)-\(showingComposeSheet)")
        }
        .sheet(item: $previewAttachment) { attachment in
            AttachmentPreviewSheet(attachment: attachment)
        }
    }

    @ViewBuilder
    private func emailContentView(_ email: Email) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Subject header
                Text(email.subject)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                // Sender & Metadata row
                HStack(alignment: .center, spacing: 14) {
                    // Avatar monogram
                    ZStack {
                        Circle()
                            .fill(avatarColor(for: email.sender))
                            .frame(width: 44, height: 44)
                        Text(email.senderInitials)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(email.sender)
                                .font(.headline)
                            if email.isVIP {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text(email.senderEmail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("To: \(email.recipient)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(email.date, format: .dateTime.month().day().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if email.isFlagged {
                            Label("Flagged", systemImage: "flag.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Triage Decision Banner (if triage metadata present or not in inbox)
                if email.category != nil || email.urgencyScore != nil || email.suggestedAction != nil || email.mailbox != .inbox {
                    triageBanner(for: email)
                }

                Divider()

                // Email Body
                Text(email.body)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Attachments Section
                if email.hasAttachments {
                    Divider()
                    attachmentsSection(for: email)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func attachmentsSection(for email: Email) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .foregroundStyle(Color.accentColor)
                    .font(.subheadline.weight(.semibold))
                Text("Attachments (\(email.attachments.count))")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(email.attachments) { attachment in
                        attachmentCard(for: attachment)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func attachmentCard(for attachment: EmailAttachment) -> some View {
        Button {
            previewAttachment = attachment
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail preview area
                ZStack {
                    Color.primary.opacity(0.04)

                    #if os(macOS)
                    if let nsImage = NSImage(data: attachment.data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                    }
                    #elseif os(iOS)
                    if let uiImage = UIImage(data: attachment.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }
                .frame(width: 220, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider()

                // Metadata footer
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: attachment.isImage ? "photo.fill" : "doc.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Text(attachment.formattedFileSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(width: 220)
            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func triageBanner(for email: Email) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let category = email.category {
                    Label(category.displayName, systemImage: category.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5)
                        )
                } else if email.mailbox != .inbox {
                    Label(email.mailbox.title, systemImage: email.mailbox.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                }

                if let score = email.urgencyScore {
                    let priority = UrgencyPriority.from(score: score)
                    Text(priority.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(priority.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(priority.color.opacity(0.14), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(priority.color.opacity(0.25), lineWidth: 0.5)
                        )
                }

                Spacer()

                if email.mailbox != .inbox || email.category == .quarantine {
                    Button {
                        withAnimation {
                            store.moveToInbox(email.id)
                        }
                    } label: {
                        Label("Move to Inbox", systemImage: "tray.and.arrow.down")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let action = email.suggestedAction {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                        .font(.caption)
                    Text("Suggested: \(action)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func openCompose(to: String, subject: String, body: String) {
        composeTo = to
        composeSubject = subject
        composeBody = body
        showingComposeSheet = true
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .indigo, .teal, .green, .orange, .pink]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

public struct ComposeMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    public var store: MailStore?
    @State public var toText: String
    @State public var subjectText: String
    @State public var bodyText: String

    public init(
        store: MailStore? = nil,
        to: String = "",
        subject: String = "",
        initialBody: String = ""
    ) {
        self.store = store
        _toText = State(initialValue: to)
        _subjectText = State(initialValue: subject)
        _bodyText = State(initialValue: initialBody)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("To:", text: $toText)
                    TextField("Subject:", text: $subjectText)
                }
                Section {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Message")
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 340)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        store?.sendEmail(to: toText, subject: subjectText, body: bodyText)
                        dismiss()
                    }
                    .disabled(toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

public struct AttachmentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let attachment: EmailAttachment

    public init(attachment: EmailAttachment) {
        self.attachment = attachment
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                #if os(macOS)
                if let nsImage = NSImage(data: attachment.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                        .padding()
                } else {
                    ContentUnavailableView(
                        attachment.filename,
                        systemImage: "doc.fill",
                        description: Text("Binary Attachment (\(attachment.formattedFileSize))")
                    )
                }
                #elseif os(iOS)
                if let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                        .padding()
                } else {
                    ContentUnavailableView(
                        attachment.filename,
                        systemImage: "doc.fill",
                        description: Text("Binary Attachment (\(attachment.formattedFileSize))")
                    )
                }
                #endif

                HStack {
                    Image(systemName: attachment.isImage ? "photo.fill" : "doc.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(attachment.filename)
                        .font(.headline)
                    Spacer()
                    Text(attachment.formattedFileSize)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle(attachment.filename)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 420)
        #endif
    }
}

#Preview {
    let store = MailStore(emails: InboxData.sampleEmails)
    MailDetailView(store: store)
}
