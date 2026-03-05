import Foundation

struct Email: Identifiable, Hashable {
    let id: String
    let messageId: String
    let uid: UInt32
    var from: EmailAddress
    var to: [EmailAddress]
    var cc: [EmailAddress]
    var bcc: [EmailAddress]
    var subject: String
    var date: Date
    var bodyHTML: String
    var bodyText: String
    var snippet: String
    var isRead: Bool
    var isStarred: Bool
    var isSnoozed: Bool
    var snoozeDate: Date?
    var hasAttachments: Bool
    var attachments: [Attachment]
    var flags: Set<EmailFlag>
    var folderPath: String
    var accountId: String
    var inReplyTo: String?
    var references: [String]

    init(
        messageId: String = "",
        uid: UInt32 = 0,
        from: EmailAddress,
        to: [EmailAddress] = [],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        subject: String = "",
        date: Date = .now,
        bodyHTML: String = "",
        bodyText: String = "",
        snippet: String = "",
        isRead: Bool = false,
        isStarred: Bool = false,
        hasAttachments: Bool = false,
        attachments: [Attachment] = [],
        flags: Set<EmailFlag> = [],
        folderPath: String = "INBOX",
        accountId: String = "",
        inReplyTo: String? = nil,
        references: [String] = []
    ) {
        self.id = UUID().uuidString
        self.messageId = messageId
        self.uid = uid
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.date = date
        self.bodyHTML = bodyHTML
        self.bodyText = bodyText
        self.snippet = snippet
        self.isRead = isRead
        self.isStarred = isStarred
        self.isSnoozed = false
        self.snoozeDate = nil
        self.hasAttachments = hasAttachments
        self.attachments = attachments
        self.flags = flags
        self.folderPath = folderPath
        self.accountId = accountId
        self.inReplyTo = inReplyTo
        self.references = references
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Email, rhs: Email) -> Bool {
        lhs.id == rhs.id
    }
}

struct EmailAddress: Codable, Hashable {
    let email: String
    let displayName: String

    var formatted: String {
        if displayName.isEmpty {
            return email
        }
        return "\(displayName) <\(email)>"
    }

    var initials: String {
        let parts = displayName.isEmpty ? email.components(separatedBy: "@").first?.components(separatedBy: ".") ?? ["?"] : displayName.components(separatedBy: " ")
        let first = parts.first?.prefix(1).uppercased() ?? "?"
        let last = parts.count > 1 ? String(parts.last!.prefix(1)).uppercased() : ""
        return first + last
    }
}

enum EmailFlag: String, Codable, Hashable {
    case seen
    case answered
    case flagged
    case deleted
    case draft
    case recent
}

// MARK: - Thread grouping

struct EmailThread: Identifiable {
    let id: String
    var emails: [Email]

    var subject: String { emails.first?.subject ?? "" }
    var latestDate: Date { emails.map(\.date).max() ?? .now }
    var from: EmailAddress { emails.last?.from ?? EmailAddress(email: "", displayName: "") }
    var snippet: String { emails.last?.snippet ?? "" }
    var isRead: Bool { emails.allSatisfy(\.isRead) }
    var isStarred: Bool { emails.contains(where: \.isStarred) }
    var hasAttachments: Bool { emails.contains(where: \.hasAttachments) }
    var count: Int { emails.count }
}
