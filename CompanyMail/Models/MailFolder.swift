import Foundation

struct MailFolder: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var path: String
    var type: FolderType
    var unreadCount: Int
    var totalCount: Int
    var children: [MailFolder]

    init(
        name: String,
        path: String,
        type: FolderType = .custom,
        unreadCount: Int = 0,
        totalCount: Int = 0,
        children: [MailFolder] = []
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.type = type
        self.unreadCount = unreadCount
        self.totalCount = totalCount
        self.children = children
    }

    var icon: String {
        switch type {
        case .inbox: "tray.fill"
        case .sent: "paperplane.fill"
        case .drafts: "doc.fill"
        case .trash: "trash.fill"
        case .spam: "exclamationmark.shield.fill"
        case .archive: "archivebox.fill"
        case .starred: "star.fill"
        case .allMail: "tray.2.fill"
        case .custom: "folder.fill"
        case .snoozed: "clock.fill"
        }
    }

    var displayName: String {
        switch type {
        case .inbox: "Boîte de réception"
        case .sent: "Envoyés"
        case .drafts: "Brouillons"
        case .trash: "Corbeille"
        case .spam: "Spam"
        case .archive: "Archives"
        case .starred: "Favoris"
        case .allMail: "Tous les mails"
        case .snoozed: "Rappels"
        case .custom: name
        }
    }
}

enum FolderType: String, Codable {
    case inbox
    case sent
    case drafts
    case trash
    case spam
    case archive
    case starred
    case allMail
    case snoozed
    case custom

    /// Détecte le type de dossier à partir de son chemin (compatible OVH)
    static func detect(from path: String) -> FolderType {
        let lower = path.lowercased()
        if lower == "inbox" { return .inbox }
        if lower.contains("sent") || lower.contains("envoy") { return .sent }
        if lower.contains("draft") || lower.contains("brouillon") { return .drafts }
        if lower.contains("trash") || lower.contains("corbeille") || lower.contains("deleted") { return .trash }
        if lower.contains("spam") || lower.contains("junk") || lower.contains("indésirable") { return .spam }
        if lower.contains("archive") { return .archive }
        if lower.contains("starred") || lower.contains("flagged") { return .starred }
        if lower.contains("all") { return .allMail }
        return .custom
    }
}
