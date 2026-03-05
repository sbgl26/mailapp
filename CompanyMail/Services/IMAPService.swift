import Foundation
import Network

/// Service IMAP natif utilisant Network.framework (zéro dépendance externe)
actor IMAPService {
    private let account: MailAccount
    private let password: String
    private var connection: NWConnection?
    private var tlsConnection: NWConnection?
    private var isConnected = false
    private var tagCounter = 0
    private var buffer = Data()

    init(account: MailAccount, password: String) {
        self.account = account
        self.password = password
    }

    // MARK: - Connection

    func connect() async throws {
        let host = NWEndpoint.Host(account.imapServer)
        let port = NWEndpoint.Port(integerLiteral: UInt16(account.imapPort))

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

        // Lire le greeting du serveur
        _ = try await readResponse()

        // Login
        let loginResponse = try await sendCommand("LOGIN \"\(account.username)\" \"\(password)\"")
        guard loginResponse.contains("OK") else {
            throw MailError.authenticationFailed
        }

        isConnected = true
    }

    func disconnect() {
        if isConnected {
            Task {
                try? await sendCommand("LOGOUT")
            }
        }
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    // MARK: - Folders

    func fetchFolders() async throws -> [MailFolder] {
        let response = try await sendCommand("LIST \"\" \"*\"")

        var folders: [MailFolder] = []
        let lines = response.components(separatedBy: "\r\n")

        for line in lines {
            guard line.contains("* LIST") else { continue }

            // Parser: * LIST (\Flags) "delimiter" "path"
            if let path = parseListResponse(line) {
                let name = path.components(separatedBy: "/").last ??
                           path.components(separatedBy: ".").last ?? path
                let type = FolderType.detect(from: path)

                // Filtrer les dossiers système inutiles
                guard !path.hasPrefix("[") || path.contains("Gmail") else { continue }

                folders.append(MailFolder(
                    name: name,
                    path: path,
                    type: type
                ))
            }
        }

        // Trier
        let order: [FolderType: Int] = [
            .inbox: 0, .starred: 1, .sent: 2, .drafts: 3,
            .archive: 4, .spam: 5, .trash: 6, .allMail: 7,
            .snoozed: 8, .custom: 9
        ]
        folders.sort { (order[$0.type] ?? 9) < (order[$1.type] ?? 9) }

        return folders
    }

    // MARK: - Fetch Emails

    func fetchEmails(folder: String, range: (start: Int, count: Int) = (1, 50)) async throws -> [Email] {
        // Sélectionner le dossier
        let selectResponse = try await sendCommand("SELECT \"\(folder)\"")

        // Extraire le nombre total de messages
        let existsCount = extractNumber(from: selectResponse, keyword: "EXISTS") ?? 0
        guard existsCount > 0 else { return [] }

        // Calculer la plage (les plus récents en premier)
        let end = max(1, existsCount - range.start + 1)
        let start = max(1, end - range.count + 1)

        // FETCH les headers
        let fetchResponse = try await sendCommand(
            "FETCH \(start):\(end) (UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM TO CC SUBJECT DATE MESSAGE-ID IN-REPLY-TO REFERENCES CONTENT-TYPE)])"
        )

        return parseEmails(from: fetchResponse, folder: folder)
    }

    // MARK: - Fetch Email Body

    func fetchEmailBody(uid: UInt32, folder: String) async throws -> (html: String, text: String) {
        _ = try await sendCommand("SELECT \"\(folder)\"")
        let response = try await sendCommand("UID FETCH \(uid) (BODY[])")

        // Extraire le contenu entre les accolades
        let body = extractBodyContent(from: response)

        // Détecter HTML vs plain text
        if body.contains("<html") || body.contains("<div") || body.contains("<p") {
            let text = body.strippedHTML
            return (html: body, text: text)
        } else {
            // Extraire le texte brut du MIME
            let plainText = extractMIMEPart(from: body, contentType: "text/plain")
            let htmlPart = extractMIMEPart(from: body, contentType: "text/html")
            return (html: htmlPart, text: plainText.isEmpty ? body : plainText)
        }
    }

    // MARK: - Fetch Attachment

    func fetchAttachment(uid: UInt32, folder: String, partID: String) async throws -> Data {
        _ = try await sendCommand("SELECT \"\(folder)\"")
        let response = try await sendCommand("UID FETCH \(uid) (BODY[\(partID)])")

        let content = extractBodyContent(from: response)

        // Tenter le décodage base64
        if let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters) {
            return data
        }

        // Sinon retourner en UTF-8
        return content.data(using: .utf8) ?? Data()
    }

    // MARK: - Flags

    func markAsRead(uid: UInt32, folder: String) async throws {
        _ = try await sendCommand("SELECT \"\(folder)\"")
        _ = try await sendCommand("UID STORE \(uid) +FLAGS (\\Seen)")
    }

    func markAsUnread(uid: UInt32, folder: String) async throws {
        _ = try await sendCommand("SELECT \"\(folder)\"")
        _ = try await sendCommand("UID STORE \(uid) -FLAGS (\\Seen)")
    }

    func toggleStar(uid: UInt32, folder: String, starred: Bool) async throws {
        _ = try await sendCommand("SELECT \"\(folder)\"")
        let op = starred ? "+" : "-"
        _ = try await sendCommand("UID STORE \(uid) \(op)FLAGS (\\Flagged)")
    }

    // MARK: - Move/Delete

    func moveEmail(uid: UInt32, from: String, to: String) async throws {
        _ = try await sendCommand("SELECT \"\(from)\"")
        // Essayer MOVE d'abord (RFC 6851), sinon COPY + DELETE
        let moveResponse = try await sendCommand("UID MOVE \(uid) \"\(to)\"")
        if moveResponse.contains("BAD") || moveResponse.contains("NO") {
            _ = try await sendCommand("UID COPY \(uid) \"\(to)\"")
            _ = try await sendCommand("UID STORE \(uid) +FLAGS (\\Deleted)")
            _ = try await sendCommand("EXPUNGE")
        }
    }

    func deleteEmail(uid: UInt32, folder: String, trashFolder: String) async throws {
        try await moveEmail(uid: uid, from: folder, to: trashFolder)
    }

    // MARK: - Search

    func search(query: String, folder: String) async throws -> [UInt32] {
        _ = try await sendCommand("SELECT \"\(folder)\"")

        // Recherche IMAP : chercher dans FROM, SUBJECT et BODY
        let response = try await sendCommand(
            "UID SEARCH OR OR FROM \"\(query)\" SUBJECT \"\(query)\" BODY \"\(query)\""
        )

        // Parser les UIDs de la réponse "* SEARCH 1 2 3 4"
        var uids: [UInt32] = []
        for line in response.components(separatedBy: "\r\n") {
            if line.hasPrefix("* SEARCH") {
                let parts = line.replacingOccurrences(of: "* SEARCH ", with: "")
                    .components(separatedBy: " ")
                for part in parts {
                    if let uid = UInt32(part.trimmingCharacters(in: .whitespaces)) {
                        uids.append(uid)
                    }
                }
            }
        }

        return uids
    }

    // MARK: - IDLE (Push)

    func startIDLE(folder: String, onNewMessage: @escaping () -> Void) async throws {
        _ = try await sendCommand("SELECT \"\(folder)\"")

        tagCounter += 1
        let tag = "T\(tagCounter)"
        let command = "\(tag) IDLE\r\n"

        guard let data = command.data(using: .utf8) else { return }
        try await sendRaw(data)

        // Écouter les mises à jour EXISTS
        Task {
            while isConnected {
                let response = try await readResponse()
                if response.contains("EXISTS") {
                    onNewMessage()
                }
            }
        }
    }

    // MARK: - Private: Network Communication

    private func nextTag() -> String {
        tagCounter += 1
        return "T\(tagCounter)"
    }

    private func sendCommand(_ command: String) async throws -> String {
        let tag = nextTag()
        let fullCommand = "\(tag) \(command)\r\n"

        guard let data = fullCommand.data(using: .utf8) else {
            throw MailError.buildFailed
        }

        try await sendRaw(data)

        // Lire jusqu'à recevoir la réponse taguée
        var fullResponse = ""
        while true {
            let chunk = try await readResponse()
            fullResponse += chunk

            // Vérifier si on a la réponse finale (tag OK/NO/BAD)
            if chunk.contains("\(tag) OK") || chunk.contains("\(tag) NO") || chunk.contains("\(tag) BAD") {
                break
            }
        }

        // Vérifier les erreurs
        if fullResponse.contains("\(tag) NO") || fullResponse.contains("\(tag) BAD") {
            let errorLine = fullResponse.components(separatedBy: "\r\n")
                .first { $0.contains("\(tag) NO") || $0.contains("\(tag) BAD") }
            throw MailError.connectionFailed(errorLine ?? "Erreur IMAP inconnue")
        }

        return fullResponse
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

    // MARK: - Private: Parsing

    private func parseListResponse(_ line: String) -> String? {
        // Format: * LIST (\flags) "delimiter" "path"
        // Trouver le dernier élément entre guillemets ou après le dernier espace
        let parts = line.components(separatedBy: "\" ")
        if let last = parts.last {
            return last.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    private func parseEmails(from response: String, folder: String) -> [Email] {
        var emails: [Email] = []
        let blocks = response.components(separatedBy: "* ")

        for block in blocks {
            guard block.contains("FETCH") else { continue }

            let uid = extractUID(from: block)
            let flags = extractFlags(from: block)
            let date = extractInternalDate(from: block)

            let headers = extractHeaders(from: block)
            let from = parseEmailAddress(headers["from"] ?? "")
            let to = (headers["to"] ?? "").components(separatedBy: ",").map { parseEmailAddress($0) }
            let cc = (headers["cc"] ?? "").components(separatedBy: ",").map { parseEmailAddress($0) }
            let subject = decodeHeader(headers["subject"] ?? "(Sans objet)")
            let messageId = headers["message-id"] ?? ""
            let inReplyTo = headers["in-reply-to"]
            let references = (headers["references"] ?? "").components(separatedBy: " ").filter { !$0.isEmpty }

            let hasAttachments = block.lowercased().contains("multipart/mixed") ||
                                 block.lowercased().contains("attachment")

            let email = Email(
                messageId: messageId,
                uid: uid,
                from: from,
                to: to.filter { !$0.email.isEmpty },
                cc: cc.filter { !$0.email.isEmpty },
                subject: subject,
                date: date,
                snippet: "",
                isRead: flags.contains(.seen),
                isStarred: flags.contains(.flagged),
                hasAttachments: hasAttachments,
                flags: flags,
                folderPath: folder,
                accountId: account.id,
                inReplyTo: inReplyTo,
                references: references
            )
            emails.append(email)
        }

        return emails.sorted { $0.date > $1.date }
    }

    private func extractUID(from block: String) -> UInt32 {
        if let range = block.range(of: "UID "),
           let endRange = block[range.upperBound...].rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) {
            return UInt32(block[range.upperBound..<endRange.lowerBound]) ?? 0
        }
        return 0
    }

    private func extractFlags(from block: String) -> Set<EmailFlag> {
        var flags = Set<EmailFlag>()
        if let start = block.range(of: "FLAGS ("),
           let end = block[start.upperBound...].range(of: ")") {
            let flagStr = String(block[start.upperBound..<end.lowerBound])
            if flagStr.contains("\\Seen") { flags.insert(.seen) }
            if flagStr.contains("\\Answered") { flags.insert(.answered) }
            if flagStr.contains("\\Flagged") { flags.insert(.flagged) }
            if flagStr.contains("\\Deleted") { flags.insert(.deleted) }
            if flagStr.contains("\\Draft") { flags.insert(.draft) }
        }
        return flags
    }

    private func extractInternalDate(from block: String) -> Date {
        if let start = block.range(of: "INTERNALDATE \""),
           let end = block[start.upperBound...].range(of: "\"") {
            let dateStr = String(block[start.upperBound..<end.lowerBound])
            let formatter = DateFormatter()
            formatter.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.date(from: dateStr) ?? Date()
        }
        return Date()
    }

    private func extractHeaders(from block: String) -> [String: String] {
        var headers: [String: String] = [:]
        // Chercher le bloc de headers dans la réponse FETCH
        let headerBlock: String
        if let start = block.range(of: "BODY[HEADER"),
           let braceStart = block[start.upperBound...].range(of: "\r\n"),
           let end = block[braceStart.upperBound...].range(of: "\r\n\r\n") {
            headerBlock = String(block[braceStart.upperBound..<end.lowerBound])
        } else {
            headerBlock = block
        }

        var currentKey = ""
        var currentValue = ""

        for line in headerBlock.components(separatedBy: "\r\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Continuation du header précédent
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colonIndex = line.firstIndex(of: ":") {
                // Sauvegarder le header précédent
                if !currentKey.isEmpty {
                    headers[currentKey.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
                }
                currentKey = String(line[..<colonIndex])
                currentValue = String(line[line.index(after: colonIndex)...])
            }
        }
        // Sauvegarder le dernier
        if !currentKey.isEmpty {
            headers[currentKey.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
        }

        return headers
    }

    private func parseEmailAddress(_ raw: String) -> EmailAddress {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Format: "Display Name" <email@example.com> ou email@example.com
        if let angleStart = trimmed.range(of: "<"),
           let angleEnd = trimmed.range(of: ">") {
            let email = String(trimmed[angleStart.upperBound..<angleEnd.lowerBound])
            var name = String(trimmed[..<angleStart.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            name = decodeHeader(name)
            return EmailAddress(email: email, displayName: name)
        }
        return EmailAddress(email: trimmed, displayName: "")
    }

    private func decodeHeader(_ header: String) -> String {
        var result = header
        // Décoder les headers RFC 2047 (=?charset?encoding?text?=)
        let pattern = "=\\?([^?]+)\\?([BbQq])\\?([^?]+)\\?="
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }

        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let encodingRange = Range(match.range(at: 2), in: result),
                  let textRange = Range(match.range(at: 3), in: result) else { continue }

            let encoding = String(result[encodingRange]).uppercased()
            let text = String(result[textRange])

            var decoded = ""
            if encoding == "B" {
                if let data = Data(base64Encoded: text),
                   let str = String(data: data, encoding: .utf8) {
                    decoded = str
                }
            } else if encoding == "Q" {
                decoded = text
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "=([0-9A-Fa-f]{2})", with: "", options: .regularExpression)
                // Simple QP decode
                if let data = decoded.data(using: .ascii) {
                    decoded = String(data: data, encoding: .utf8) ?? text
                }
            }

            if !decoded.isEmpty {
                result.replaceSubrange(fullRange, with: decoded)
            }
        }

        return result
    }

    private func extractBodyContent(from response: String) -> String {
        // Extraire le contenu entre les accolades {size}\r\n...
        if let braceStart = response.range(of: "}\r\n") {
            let contentStart = braceStart.upperBound
            // Trouver la fin (avant la dernière ligne taguée)
            if let tagEnd = response.range(of: "\r\nT", options: .backwards, range: contentStart..<response.endIndex) {
                return String(response[contentStart..<tagEnd.lowerBound])
            }
            return String(response[contentStart...])
        }
        return response
    }

    private func extractMIMEPart(from body: String, contentType: String) -> String {
        let lines = body.components(separatedBy: "\r\n")
        var inCorrectPart = false
        var pastHeaders = false
        var result: [String] = []

        for line in lines {
            if line.lowercased().contains("content-type: \(contentType)") {
                inCorrectPart = true
                pastHeaders = false
                continue
            }
            if inCorrectPart && !pastHeaders && line.isEmpty {
                pastHeaders = true
                continue
            }
            if inCorrectPart && pastHeaders {
                if line.hasPrefix("--") {
                    break // Boundary, fin de cette partie
                }
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }

    private func extractNumber(from response: String, keyword: String) -> Int? {
        for line in response.components(separatedBy: "\r\n") {
            if line.contains(keyword) {
                let parts = line.components(separatedBy: " ")
                for part in parts {
                    if let num = Int(part) {
                        return num
                    }
                }
            }
        }
        return nil
    }
}
