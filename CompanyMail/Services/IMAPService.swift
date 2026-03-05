import Foundation
import MailCore2

/// Service IMAP pour la lecture des emails via MailCore2
actor IMAPService {
    private let session: MCOIMAPSession
    private let account: MailAccount

    init(account: MailAccount, password: String) {
        self.account = account
        self.session = MCOIMAPSession()
        session.hostname = account.imapServer
        session.port = UInt32(account.imapPort)
        session.username = account.username
        session.password = password
        session.connectionType = account.useSSL ? .TLS : .startTLS
        session.authType = .saslPlain
        session.timeout = 30
    }

    // MARK: - Connection

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.connectOperation()?.start { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func disconnect() {
        session.disconnectOperation()?.start { _ in }
    }

    // MARK: - Folders

    func fetchFolders() async throws -> [MailFolder] {
        try await withCheckedThrowingContinuation { continuation in
            session.fetchAllFoldersOperation()?.start { error, folders in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let imapFolders = folders as? [MCOIMAPFolder] else {
                    continuation.resume(returning: [])
                    return
                }

                let mailFolders = imapFolders.compactMap { folder -> MailFolder? in
                    guard let path = folder.path else { return nil }
                    // Filtrer les dossiers système inutiles
                    if path.hasPrefix("[") && !path.contains("Gmail") { return nil }

                    let name = path.components(separatedBy: folder.delimiter == 0 ? "/" : String(UnicodeScalar(UInt8(folder.delimiter)))).last ?? path
                    let type = FolderType.detect(from: path)

                    return MailFolder(
                        name: name,
                        path: path,
                        type: type
                    )
                }

                // Trier : inbox en premier, puis les dossiers système, puis custom
                let sorted = mailFolders.sorted { a, b in
                    let order: [FolderType: Int] = [
                        .inbox: 0, .starred: 1, .sent: 2, .drafts: 3,
                        .archive: 4, .spam: 5, .trash: 6, .allMail: 7,
                        .snoozed: 8, .custom: 9
                    ]
                    return (order[a.type] ?? 9) < (order[b.type] ?? 9)
                }

                continuation.resume(returning: sorted)
            }
        }
    }

    // MARK: - Fetch Emails

    func fetchEmails(
        folder: String,
        range: MCORange = MCORange(location: 1, length: 50),
        requestKind: MCOIMAPMessagesRequestKind = [.headers, .flags, .structure, .internalDate, .extraHeaders]
    ) async throws -> [Email] {
        let indexSet = MCOIndexSet(range: range)

        return try await withCheckedThrowingContinuation { continuation in
            let fetchOp = session.fetchMessagesByNumberOperation(
                withFolder: folder,
                requestKind: requestKind,
                numbers: indexSet
            )
            fetchOp?.extraHeaders = ["References", "In-Reply-To"]

            fetchOp?.start { error, messages, vanished in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let imapMessages = messages as? [MCOIMAPMessage] else {
                    continuation.resume(returning: [])
                    return
                }

                let emails = imapMessages.map { msg -> Email in
                    let header = msg.header!
                    let from = EmailAddress(
                        email: header.from?.mailbox ?? "",
                        displayName: header.from?.displayName ?? ""
                    )

                    let to = (header.to?.flatMap { ($0 as? MCOAddress).map { [$0] } ?? [] } ?? [])
                        .map { EmailAddress(email: $0.mailbox ?? "", displayName: $0.displayName ?? "") }

                    let cc = (header.cc?.flatMap { ($0 as? MCOAddress).map { [$0] } ?? [] } ?? [])
                        .map { EmailAddress(email: $0.mailbox ?? "", displayName: $0.displayName ?? "") }

                    let flags = self.convertFlags(msg.flags)
                    let hasAttachments = (msg.attachments()?.count ?? 0) > 0

                    let attachments: [Attachment] = (msg.attachments() as? [MCOIMAPPart] ?? []).map { part in
                        Attachment(
                            filename: part.filename ?? "sans nom",
                            mimeType: part.mimeType ?? "application/octet-stream",
                            size: Int64(part.size),
                            partID: part.partID ?? "",
                            isInline: part.isInlineAttachment,
                            contentId: part.contentID
                        )
                    }

                    return Email(
                        messageId: header.messageID ?? "",
                        uid: msg.uid,
                        from: from,
                        to: to,
                        cc: cc,
                        subject: header.subject ?? "(Sans objet)",
                        date: header.date ?? Date(),
                        snippet: "",
                        isRead: flags.contains(.seen),
                        isStarred: flags.contains(.flagged),
                        hasAttachments: hasAttachments,
                        attachments: attachments,
                        flags: flags,
                        folderPath: folder,
                        accountId: self.account.id,
                        inReplyTo: header.inReplyTo?.first as? String,
                        references: header.references as? [String] ?? []
                    )
                }.sorted { $0.date > $1.date }

                continuation.resume(returning: emails)
            }
        }
    }

    // MARK: - Fetch Email Body

    func fetchEmailBody(uid: UInt32, folder: String) async throws -> (html: String, text: String) {
        try await withCheckedThrowingContinuation { continuation in
            let op = session.fetchMessageOperation(withFolder: folder, uid: uid)
            op?.start { error, data in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data else {
                    continuation.resume(returning: ("", ""))
                    return
                }

                let parser = MCOMessageParser(data: data)
                let html = parser?.htmlRendering(with: nil) ?? ""
                let text = parser?.plainTextRendering() ?? ""

                continuation.resume(returning: (html, text))
            }
        }
    }

    // MARK: - Fetch Attachment

    func fetchAttachment(uid: UInt32, folder: String, partID: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let op = session.fetchMessageAttachmentOperation(
                withFolder: folder,
                uid: uid,
                partID: partID,
                encoding: .encodingBase64
            )
            op?.start { error, data in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }

    // MARK: - Flags

    func setFlags(uid: UInt32, folder: String, flags: MCOMessageFlag, add: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let indexSet = MCOIndexSet(index: UInt64(uid))
            let kind: MCOIMAPStoreFlagsRequestKind = add ? .add : .remove
            let op = session.storeFlagsOperation(
                withFolder: folder,
                uids: indexSet,
                kind: kind,
                flags: flags
            )
            op?.start { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func markAsRead(uid: UInt32, folder: String) async throws {
        try await setFlags(uid: uid, folder: folder, flags: .seen, add: true)
    }

    func markAsUnread(uid: UInt32, folder: String) async throws {
        try await setFlags(uid: uid, folder: folder, flags: .seen, add: false)
    }

    func toggleStar(uid: UInt32, folder: String, starred: Bool) async throws {
        try await setFlags(uid: uid, folder: folder, flags: .flagged, add: starred)
    }

    // MARK: - Move/Delete

    func moveEmail(uid: UInt32, from: String, to: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let indexSet = MCOIndexSet(index: UInt64(uid))
            let op = session.moveMessagesOperation(withFolder: from, uids: indexSet, destFolder: to)
            op?.start { error, _ in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func deleteEmail(uid: UInt32, folder: String, trashFolder: String) async throws {
        try await moveEmail(uid: uid, from: folder, to: trashFolder)
    }

    // MARK: - Search

    func search(query: String, folder: String) async throws -> [UInt32] {
        try await withCheckedThrowingContinuation { continuation in
            let expression = MCOIMAPSearchExpression.search(query)
            let op = session.searchExpressionOperation(withFolder: folder, expression: expression)
            op?.start { error, indexSet in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var uids: [UInt32] = []
                indexSet?.enumerate { idx in
                    uids.append(UInt32(idx))
                }
                continuation.resume(returning: uids)
            }
        }
    }

    // MARK: - IDLE (Push notifications)

    func startIDLE(folder: String, onNewMessage: @escaping () -> Void) {
        let op = session.idleOperation(withFolder: folder, lastKnownUID: 0)
        op?.start { error in
            if error == nil {
                onNewMessage()
            }
        }
    }

    // MARK: - Helpers

    private func convertFlags(_ flags: MCOMessageFlag) -> Set<EmailFlag> {
        var result = Set<EmailFlag>()
        if flags.contains(.seen) { result.insert(.seen) }
        if flags.contains(.answered) { result.insert(.answered) }
        if flags.contains(.flagged) { result.insert(.flagged) }
        if flags.contains(.deleted) { result.insert(.deleted) }
        if flags.contains(.draft) { result.insert(.draft) }
        return result
    }
}
