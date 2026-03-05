import Foundation
import Network

/// Service SMTP natif utilisant Network.framework (zéro dépendance externe)
actor SMTPService {
    private let account: MailAccount
    private let password: String
    private var connection: NWConnection?
    private var isConnected = false

    init(account: MailAccount, password: String) {
        self.account = account
        self.password = password
    }

    // MARK: - Connection

    func connect() async throws {
        let host = NWEndpoint.Host(account.smtpServer)
        let port = NWEndpoint.Port(integerLiteral: UInt16(account.smtpPort))

        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 30

        let params = NWParameters(tls: account.useSSL ? tlsOptions : nil, tcp: tcpOptions)

        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: MailError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: MailError.connectionFailed("Connexion annulée"))
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        // Lire le greeting
        let greeting = try await readResponse()
        guard greeting.hasPrefix("220") else {
            throw MailError.connectionFailed("Greeting SMTP invalide")
        }

        // EHLO
        let ehloResponse = try await sendCommand("EHLO \(account.smtpServer)")
        guard ehloResponse.contains("250") else {
            throw MailError.connectionFailed("EHLO échoué")
        }

        // AUTH LOGIN
        _ = try await sendCommand("AUTH LOGIN")

        // Envoyer username en base64
        let usernameB64 = Data(account.username.utf8).base64EncodedString()
        _ = try await sendCommand(usernameB64)

        // Envoyer password en base64
        let passwordB64 = Data(password.utf8).base64EncodedString()
        let authResponse = try await sendCommand(passwordB64)

        guard authResponse.contains("235") else {
            throw MailError.authenticationFailed
        }

        isConnected = true
    }

    func disconnect() {
        if isConnected {
            Task {
                try? await sendCommand("QUIT")
            }
        }
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    // MARK: - Check Connection

    func checkConnection() async throws {
        try await connect()
        disconnect()
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
        // S'assurer d'être connecté
        if !isConnected {
            try await connect()
        }

        // MAIL FROM
        let mailFrom = try await sendCommand("MAIL FROM:<\(from.email)>")
        guard mailFrom.contains("250") else {
            throw MailError.buildFailed
        }

        // RCPT TO (tous les destinataires)
        let allRecipients = to + cc + bcc
        for recipient in allRecipients {
            let rcpt = try await sendCommand("RCPT TO:<\(recipient.email)>")
            guard rcpt.contains("250") else {
                throw MailError.connectionFailed("Destinataire refusé: \(recipient.email)")
            }
        }

        // DATA
        let dataResponse = try await sendCommand("DATA")
        guard dataResponse.contains("354") else {
            throw MailError.buildFailed
        }

        // Construire le message MIME
        let message = buildMIMEMessage(
            from: from,
            to: to,
            cc: cc,
            subject: subject,
            htmlBody: htmlBody,
            textBody: textBody,
            attachments: attachments,
            inReplyTo: inReplyTo,
            references: references
        )

        // Envoyer le contenu du message + terminateur
        let messageData = (message + "\r\n.\r\n").data(using: .utf8)!
        try await sendRaw(messageData)
        let sendResponse = try await readResponse()

        guard sendResponse.contains("250") else {
            throw MailError.connectionFailed("Envoi échoué: \(sendResponse)")
        }
    }

    // MARK: - Build MIME Message

    private func buildMIMEMessage(
        from: EmailAddress,
        to: [EmailAddress],
        cc: [EmailAddress],
        subject: String,
        htmlBody: String,
        textBody: String,
        attachments: [Attachment],
        inReplyTo: String?,
        references: [String]
    ) -> String {
        let boundary = "CompanyMail-\(UUID().uuidString)"
        var message = ""

        // Headers
        message += "From: \(formatAddress(from))\r\n"
        message += "To: \(to.map { formatAddress($0) }.joined(separator: ", "))\r\n"
        if !cc.isEmpty {
            message += "Cc: \(cc.map { formatAddress($0) }.joined(separator: ", "))\r\n"
        }
        message += "Subject: \(encodeMIMEHeader(subject))\r\n"
        message += "Date: \(RFC2822DateFormatter.string(from: Date()))\r\n"
        message += "Message-ID: <\(UUID().uuidString)@\(account.email.components(separatedBy: "@").last ?? "companymail")>\r\n"
        message += "MIME-Version: 1.0\r\n"
        message += "X-Mailer: CompanyMail/1.0\r\n"

        if let inReplyTo {
            message += "In-Reply-To: \(inReplyTo)\r\n"
        }
        if !references.isEmpty {
            message += "References: \(references.joined(separator: " "))\r\n"
        }

        // Signature
        var finalHTML = htmlBody
        var finalText = textBody
        if !account.signature.isEmpty {
            finalHTML += "<br><br>--<br>\(account.signature)"
            finalText += "\n\n--\n\(account.signature)"
        }

        if attachments.isEmpty {
            // Message simple multipart/alternative (text + html)
            let altBoundary = "alt-\(boundary)"
            message += "Content-Type: multipart/alternative; boundary=\"\(altBoundary)\"\r\n"
            message += "\r\n"

            // Plain text part
            message += "--\(altBoundary)\r\n"
            message += "Content-Type: text/plain; charset=utf-8\r\n"
            message += "Content-Transfer-Encoding: quoted-printable\r\n"
            message += "\r\n"
            message += encodeQuotedPrintable(finalText)
            message += "\r\n"

            // HTML part
            message += "--\(altBoundary)\r\n"
            message += "Content-Type: text/html; charset=utf-8\r\n"
            message += "Content-Transfer-Encoding: quoted-printable\r\n"
            message += "\r\n"
            message += encodeQuotedPrintable(finalHTML)
            message += "\r\n"

            message += "--\(altBoundary)--\r\n"
        } else {
            // Message avec pièces jointes : multipart/mixed
            message += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n"
            message += "\r\n"

            // Body part (multipart/alternative)
            let altBoundary = "alt-\(boundary)"
            message += "--\(boundary)\r\n"
            message += "Content-Type: multipart/alternative; boundary=\"\(altBoundary)\"\r\n"
            message += "\r\n"

            message += "--\(altBoundary)\r\n"
            message += "Content-Type: text/plain; charset=utf-8\r\n"
            message += "Content-Transfer-Encoding: quoted-printable\r\n"
            message += "\r\n"
            message += encodeQuotedPrintable(finalText)
            message += "\r\n"

            message += "--\(altBoundary)\r\n"
            message += "Content-Type: text/html; charset=utf-8\r\n"
            message += "Content-Transfer-Encoding: quoted-printable\r\n"
            message += "\r\n"
            message += encodeQuotedPrintable(finalHTML)
            message += "\r\n"

            message += "--\(altBoundary)--\r\n"

            // Attachments
            for attachment in attachments {
                guard let data = attachment.data else { continue }

                message += "--\(boundary)\r\n"
                if attachment.isInline, let contentId = attachment.contentId {
                    message += "Content-Type: \(attachment.mimeType); name=\"\(attachment.filename)\"\r\n"
                    message += "Content-Disposition: inline; filename=\"\(attachment.filename)\"\r\n"
                    message += "Content-ID: <\(contentId)>\r\n"
                } else {
                    message += "Content-Type: \(attachment.mimeType); name=\"\(attachment.filename)\"\r\n"
                    message += "Content-Disposition: attachment; filename=\"\(attachment.filename)\"\r\n"
                }
                message += "Content-Transfer-Encoding: base64\r\n"
                message += "\r\n"

                // Encoder en base64 avec retours à la ligne tous les 76 caractères
                let b64 = data.base64EncodedString(options: .lineLength76Characters)
                message += b64
                message += "\r\n"
            }

            message += "--\(boundary)--\r\n"
        }

        return message
    }

    // MARK: - Helpers

    private func formatAddress(_ addr: EmailAddress) -> String {
        if addr.displayName.isEmpty {
            return addr.email
        }
        return "\(encodeMIMEHeader(addr.displayName)) <\(addr.email)>"
    }

    private func encodeMIMEHeader(_ text: String) -> String {
        // Encoder en UTF-8 base64 si caractères non-ASCII
        if text.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return text
        }
        let encoded = Data(text.utf8).base64EncodedString()
        return "=?UTF-8?B?\(encoded)?="
    }

    private func encodeQuotedPrintable(_ text: String) -> String {
        var result = ""
        for char in text.utf8 {
            if char == 0x0D || char == 0x0A {
                result += "\r\n"
            } else if (char >= 33 && char <= 126 && char != 61) || char == 9 || char == 32 {
                result += String(UnicodeScalar(char))
            } else {
                result += String(format: "=%02X", char)
            }
        }
        return result
    }

    private var RFC2822DateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    // MARK: - Network Communication

    private func sendCommand(_ command: String) async throws -> String {
        guard let data = "\(command)\r\n".data(using: .utf8) else {
            throw MailError.buildFailed
        }
        try await sendRaw(data)
        return try await readResponse()
    }

    private func sendRaw(_ data: Data) async throws {
        guard let conn = connection else {
            throw MailError.connectionFailed("Non connecté")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func readResponse() async throws -> String {
        guard let conn = connection else {
            throw MailError.connectionFailed("Non connecté")
        }

        return try await withCheckedThrowingContinuation { continuation in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = content, let response = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: "")
                    return
                }

                continuation.resume(returning: response)
            }
        }
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
