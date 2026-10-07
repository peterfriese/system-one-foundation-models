import SwiftUI
import AppCore

public struct MailRowView: View {
    public let email: Email

    public init(email: Email) {
        self.email = email
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: Unread indicator, Sender, Date, Flag
            HStack(alignment: .center, spacing: 6) {
                if email.isUnread {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 8, height: 8)
                }

                Text(email.sender)
                    .font(.subheadline)
                    .fontWeight(email.isUnread ? .bold : .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if email.isFlagged {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if email.hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(formattedDate(email.date))
                    .font(.caption2)
                    .foregroundStyle(email.isUnread ? Color.accentColor : .secondary)
            }

            // Line 2: Subject
            Text(email.subject)
                .font(.subheadline)
                .fontWeight(email.isUnread ? .medium : .regular)
                .foregroundStyle(email.isUnread ? .primary : .secondary)
                .lineLimit(1)
                .padding(.leading, 14)

            // Line 3: Snippet
            Text(email.previewSnippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.leading, 14)

            // Line 4 (Optional): Subtle category or triage pill
            if let category = email.category {
                HStack(spacing: 4) {
                    Image(systemName: category.iconName)
                        .font(.system(size: 9))
                    Text(category.displayName)
                        .font(.system(size: 10, weight: .medium))

                    if let score = email.urgencyScore {
                        let priority = UrgencyPriority.from(score: score)
                        if priority == .p0Critical || priority == .p1High {
                            Text("•")
                                .font(.system(size: 8))
                            Text(priority.displayName)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(priority.color)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .padding(.leading, 14)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    let email = InboxData.sampleEmails[0]
    List {
        MailRowView(email: email)
    }
}
