import Foundation

/// Service coordinateur qui gère IMAP + SMTP pour un compte
@MainActor
final class EmailService: ObservableObject {
    let account: MailAccount

    @Published var folders: [MailFolder] = []
    @Published var emails: [String: [Email]] = [:] // folderPath -> emails
    @Published var isConnected = false
    @Published var isSyncing = false
    @Published var lastError: String?

    private var imapService: IMAPService?
    private var smtpService: SMTPService?

    init(account: MailAccount) {
        self.account = account
    }

    // MARK: - Connection

    func connect() async throws {
        guard let password = try KeychainService.shared.getPassword(for: account) else {
            throw MailError.noPassword
        }

        imapService = IMAPService(account: account, password: password)
        smtpService = SMTPService(account: account, password: password)

        try await imapService?.connect()
        isConnected = true
    }

    func disconnect() async {
        await imapService?.disconnect()
        isConnected = false
    }

    // MARK: - Folders

    func fetchFolders() async throws -> [MailFolder] {
        guard let imap = imapService else { throw MailError.connectionFailed("Non connecté") }
        folders = try await imap.fetchFolders()
        return folders
    }

    // MARK: - Emails

    func fetchEmails(folder: MailFolder, page: Int = 0, pageSize: Int = 50) async throws -> [Email] {
        guard let imap = imapService else { throw MailError.connectionFailed("Non connecté") }

        isSyncing = true
        defer { isSyncing = false }

        let start = max(1, page * pageSize + 1)
        let fetchedEmails = try await imap.fetchEmails(folder: folder.path, range: (start: start, count: pageSize))
        emails[folder.path] = fetchedEmails
        return fetchedEmails
    }

    func fetchEmailBody(email: Email) async throws -> Email {
        guard let imap = imapService else { throw MailError.connectionFailed("Non connecté") }

        let body = try await imap.fetchEmailBody(uid: email.uid, folder: email.folderPath)

        var updated = email
        updated.bodyHTML = body.html
        updated.bodyText = body.text

        // Mettre à jour dans le cache
        if var folderEmails = emails[email.folderPath],
           let index = folderEmails.firstIndex(where: { $0.uid == email.uid }) {
            folderEmails[index] = updated
            emails[email.folderPath] = folderEmails
        }

        return updated
    }

    func fetchAttachment(email: Email, attachment: Attachment) async throws -> Data {
        guard let imap = imapService else { throw MailError.connectionFailed("Non connecté") }
        return try await imap.fetchAttachment(uid: email.uid, folder: email.folderPath, partID: attachment.partID)
    }

    // MARK: - Send

    func sendEmail(
        to: [EmailAddress],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        subject: String,
        htmlBody: String,
        textBody: String,
        attachments: [Attachment] = [],
        inReplyTo: String? = nil,
        references: [String] = []
    ) async throws {
        guard let smtp = smtpService else { throw MailError.connectionFailed("Non connecté") }

        let from = EmailAddress(email: account.email, displayName: account.displayName)

        try await smtp.sendEmail(
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            htmlBody: htmlBody,
            textBody: textBody,
            attachments: attachments,
            inReplyTo: inReplyTo,
            references: references
        )
    }

    // MARK: - Actions

    func markAsRead(_ email: Email) async throws {
        guard let imap = imapService else { return }
        try await imap.markAsRead(uid: email.uid, folder: email.folderPath)
        updateEmailInCache(email) { $0.isRead = true }
    }

    func markAsUnread(_ email: Email) async throws {
        guard let imap = imapService else { return }
        try await imap.markAsUnread(uid: email.uid, folder: email.folderPath)
        updateEmailInCache(email) { $0.isRead = false }
    }

    func toggleStar(_ email: Email) async throws {
        guard let imap = imapService else { return }
        let newState = !email.isStarred
        try await imap.toggleStar(uid: email.uid, folder: email.folderPath, starred: newState)
        updateEmailInCache(email) { $0.isStarred = newState }
    }

    func moveToTrash(_ email: Email) async throws {
        guard let imap = imapService else { return }
        let trashFolder = folders.first(where: { $0.type == .trash })?.path ?? "Trash"
        try await imap.deleteEmail(uid: email.uid, folder: email.folderPath, trashFolder: trashFolder)
        removeEmailFromCache(email)
    }

    func moveEmail(_ email: Email, to folder: MailFolder) async throws {
        guard let imap = imapService else { return }
        try await imap.moveEmail(uid: email.uid, from: email.folderPath, to: folder.path)
        removeEmailFromCache(email)
    }

    func archiveEmail(_ email: Email) async throws {
        guard let imap = imapService else { return }
        let archiveFolder = folders.first(where: { $0.type == .archive })?.path ?? "Archives"
        try await imap.moveEmail(uid: email.uid, from: email.folderPath, to: archiveFolder)
        removeEmailFromCache(email)
    }

    // MARK: - Search

    func searchEmails(query: String, folder: MailFolder) async throws -> [Email] {
        guard let imap = imapService else { throw MailError.connectionFailed("Non connecté") }
        let uids = try await imap.search(query: query, folder: folder.path)
        guard !uids.isEmpty else { return [] }
        // Re-fetch les emails trouvés
        return try await imap.fetchEmails(folder: folder.path, range: (start: 1, count: uids.count))
    }

    // MARK: - Snooze

    func snoozeEmail(_ email: Email, until date: Date) async throws {
        updateEmailInCache(email) {
            $0.isSnoozed = true
            $0.snoozeDate = date
        }
        await NotificationService.shared.scheduleSnoozeNotification(for: email, at: date)
    }

    // MARK: - Cache Helpers

    private func updateEmailInCache(_ email: Email, update: (inout Email) -> Void) {
        if var folderEmails = emails[email.folderPath],
           let index = folderEmails.firstIndex(where: { $0.uid == email.uid }) {
            var updated = folderEmails[index]
            update(&updated)
            folderEmails[index] = updated
            emails[email.folderPath] = folderEmails
        }
    }

    private func removeEmailFromCache(_ email: Email) {
        if var folderEmails = emails[email.folderPath] {
            folderEmails.removeAll { $0.uid == email.uid }
            emails[email.folderPath] = folderEmails
        }
    }
}
