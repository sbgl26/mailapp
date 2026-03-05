import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var to: [String] = []
    @Published var cc: [String] = []
    @Published var bcc: [String] = []
    @Published var subject = ""
    @Published var bodyHTML = ""
    @Published var bodyText = ""
    @Published var attachments: [Attachment] = []
    @Published var isSending = false
    @Published var showCC = false
    @Published var showBCC = false
    @Published var errorMessage: String?
    @Published var isSent = false

    // Champ de saisie temporaire
    @Published var toInput = ""
    @Published var ccInput = ""
    @Published var bccInput = ""

    private var inReplyTo: String?
    private var references: [String] = []

    // MARK: - Init from context

    func configure(from context: ComposeContext, account: MailAccount) {
        to = context.to
        subject = context.subject
        bodyText = context.body

        // Ajouter signature
        if !account.signature.isEmpty {
            bodyText += "\n\n--\n\(account.signature)"
        }

        // Reply headers
        switch context.mode {
        case .reply(let email), .replyAll(let email):
            inReplyTo = email.messageId
            references = email.references + [email.messageId]
        case .forward(let email):
            references = email.references
        case .new:
            break
        }

        showCC = !cc.isEmpty
        showBCC = !bcc.isEmpty
    }

    // MARK: - Recipients

    func addRecipient(_ email: String, to field: inout [String]) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@"), !field.contains(trimmed) else { return }
        field.append(trimmed)
    }

    func removeRecipient(_ email: String, from field: inout [String]) {
        field.removeAll { $0 == email }
    }

    // MARK: - Attachments

    func addAttachment(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else { return }

        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

        let attachment = Attachment(
            filename: url.lastPathComponent,
            mimeType: mimeType,
            size: Int64(data.count),
            data: data
        )
        attachments.append(attachment)
    }

    func removeAttachment(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    var totalAttachmentSize: Int64 {
        attachments.reduce(0) { $0 + $1.size }
    }

    var formattedAttachmentSize: String {
        ByteCountFormatter.string(fromByteCount: totalAttachmentSize, countStyle: .file)
    }

    // MARK: - Send

    func send(service: EmailService) async {
        guard !to.isEmpty else {
            errorMessage = "Ajoutez au moins un destinataire"
            return
        }

        isSending = true
        errorMessage = nil

        let toAddresses = to.map { EmailAddress(email: $0, displayName: "") }
        let ccAddresses = cc.map { EmailAddress(email: $0, displayName: "") }
        let bccAddresses = bcc.map { EmailAddress(email: $0, displayName: "") }

        // Convertir le texte brut en HTML simple
        let html = bodyText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        do {
            try await service.sendEmail(
                to: toAddresses,
                cc: ccAddresses,
                bcc: bccAddresses,
                subject: subject,
                htmlBody: "<html><body>\(html)</body></html>",
                textBody: bodyText,
                attachments: attachments,
                inReplyTo: inReplyTo,
                references: references
            )
            isSent = true
        } catch {
            errorMessage = "Erreur d'envoi: \(error.localizedDescription)"
        }

        isSending = false
    }

    // MARK: - Draft

    var isDirty: Bool {
        !to.isEmpty || !subject.isEmpty || !bodyText.isEmpty || !attachments.isEmpty
    }

    func saveDraft(service: EmailService) async {
        // TODO: Sauvegarder dans le dossier Brouillons via IMAP APPEND
    }
}
