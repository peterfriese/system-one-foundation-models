import Foundation

public struct Email: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var sender: String
    public var senderEmail: String
    public var recipient: String
    public var subject: String
    public var previewSnippet: String
    public var body: String
    public var date: Date
    public var isUnread: Bool
    public var isFlagged: Bool
    public var isVIP: Bool
    public var mailbox: Mailbox

    // Attachments
    public var attachments: [EmailAttachment] = []
    public var hasAttachments: Bool { !attachments.isEmpty }
    public var imageAttachments: [EmailAttachment] { attachments.filter { $0.isImage } }

    // Optional triage metadata
    public var category: EmailCategory?
    public var urgencyScore: Int?
    public var requiresAction: Bool?
    public var suggestedAction: TriageAction?
    public var triageResult: TriageResult?

    public init(
        id: UUID = UUID(),
        sender: String,
        senderEmail: String,
        recipient: String = "developer@apple.com",
        subject: String,
        previewSnippet: String,
        body: String,
        date: Date,
        isUnread: Bool = true,
        isFlagged: Bool = false,
        isVIP: Bool = false,
        mailbox: Mailbox = .inbox,
        category: EmailCategory? = nil,
        urgencyScore: Int? = nil,
        requiresAction: Bool? = nil,
        suggestedAction: TriageAction? = nil,
        triageResult: TriageResult? = nil,
        attachments: [EmailAttachment] = []
    ) {
        self.id = id
        self.sender = sender
        self.senderEmail = senderEmail
        self.recipient = recipient
        self.subject = subject
        self.previewSnippet = previewSnippet
        self.body = body
        self.date = date
        self.isUnread = isUnread
        self.isFlagged = isFlagged
        self.isVIP = isVIP
        self.mailbox = mailbox
        self.category = category
        self.urgencyScore = urgencyScore
        self.requiresAction = requiresAction
        self.suggestedAction = suggestedAction
        self.triageResult = triageResult
        self.attachments = attachments
    }

    /// Extracted initials for avatar monogram rendering (e.g. "JD" for "Jeff Dean")
    public var senderInitials: String {
        let parts = sender
            .split(separator: " ")
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let last = parts[parts.count - 1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let first = parts.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return "EM"
    }

    /// User-facing formatted timestamp
    public var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
