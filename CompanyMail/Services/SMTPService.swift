import Foundation
import MailCore2

/// Service SMTP pour l'envoi d'emails via MailCore2
actor SMTPService {
    private let session: MCOSMTPSession
    private let account: MailAccount

    init(account: MailAccount, password: String) {
        self.account = account
        self.session = MCOSMTPSession()
        session.hostname = account.smtpServer
        session.port = UInt32(account.smtpPort)
        session.username = account.username
        session.password = password
        session.connectionType = account.useSSL ? .TLS : .startTLS
        session.authType = .saslPlain
        session.timeout = 30
    }

    // MARK: - Connection check

    func checkConnection() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.checkAccountOperation()?.start { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Send Email

    func sendEmail(
        from: EmailAddress,
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
        let builder = MCOMessageBuilder()

        // From
        let fromAddress = MCOAddress(displayName: from.displayName, mailbox: from.email)
        builder.header.from = fromAddress

        // To
        builder.header.to = to.map { MCOAddress(displayName: $0.displayName, mailbox: $0.email) as Any }

        // CC
        if !cc.isEmpty {
            builder.header.cc = cc.map { MCOAddress(displayName: $0.displayName, mailbox: $0.email) as Any }
        }

        // BCC
        if !bcc.isEmpty {
            builder.header.bcc = bcc.map { MCOAddress(displayName: $0.displayName, mailbox: $0.email) as Any }
        }

        // Subject
        builder.header.subject = subject

        // Body
        builder.htmlBody = htmlBody
        builder.textBody = textBody

        // Reply headers
        if let inReplyTo {
            builder.header.inReplyTo = [inReplyTo]
        }
        if !references.isEmpty {
            builder.header.references = references as [AnyObject]
        }

        // Attachments
        for attachment in attachments {
            if let data = attachment.data {
                let mcAttachment = MCOAttachment()
                mcAttachment.filename = attachment.filename
                mcAttachment.mimeType = attachment.mimeType
                mcAttachment.data = data
                if attachment.isInline {
                    mcAttachment.isInlineAttachment = true
                    mcAttachment.contentID = attachment.contentId
                    builder.addRelatedAttachment(mcAttachment)
                } else {
                    builder.addAttachment(mcAttachment)
                }
            }
        }

        // Signature
        if !account.signature.isEmpty {
            let currentHTML = builder.htmlBody ?? ""
            builder.htmlBody = currentHTML + "<br><br>--<br>" + account.signature
        }

        guard let data = builder.data() else {
            throw MailError.buildFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = session.sendOperation(with: data)
            op?.start { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Save to Sent folder (via IMAP)

    static func saveSentMessage(data: Data, imapService: IMAPService, sentFolder: String) async throws {
        // This is handled by the EmailService coordinator
    }
}

// MARK: - Mail Errors

enum MailError: LocalizedError {
    case buildFailed
    case connectionFailed(String)
    case authenticationFailed
    case folderNotFound(String)
    case messageFetchFailed
    case noPassword

    var errorDescription: String? {
        switch self {
        case .buildFailed:
            "Impossible de construire le message"
        case .connectionFailed(let detail):
            "Erreur de connexion: \(detail)"
        case .authenticationFailed:
            "Authentification échouée. Vérifiez vos identifiants."
        case .folderNotFound(let name):
            "Dossier introuvable: \(name)"
        case .messageFetchFailed:
            "Impossible de récupérer le message"
        case .noPassword:
            "Mot de passe introuvable dans le trousseau"
        }
    }
}
