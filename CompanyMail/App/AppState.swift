import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var accounts: [MailAccount] = []
    @Published var selectedAccount: MailAccount?
    @Published var selectedFolder: MailFolder?
    @Published var selectedEmail: Email?
    @Published var isComposing = false
    @Published var composeContext: ComposeContext?
    @Published var unreadCount: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let accountStore = AccountStore()
    private var emailServices: [String: EmailService] = [:]

    // MARK: - Account Management

    func loadAccounts() async {
        accounts = accountStore.loadAccounts()
        if let first = accounts.first {
            selectedAccount = first
            await connectAccount(first)
        }
    }

    func addAccount(_ account: MailAccount) async {
        accountStore.saveAccount(account)
        accounts.append(account)
        selectedAccount = account
        await connectAccount(account)
    }

    func removeAccount(_ account: MailAccount) {
        accountStore.deleteAccount(account)
        accounts.removeAll { $0.id == account.id }
        emailServices.removeValue(forKey: account.id)
        if selectedAccount?.id == account.id {
            selectedAccount = accounts.first
        }
    }

    // MARK: - Email Service

    func connectAccount(_ account: MailAccount) async {
        let service = EmailService(account: account)
        emailServices[account.id] = service
        do {
            try await service.connect()
            let folders = try await service.fetchFolders()
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index].folders = folders
            }
            // Sélectionner la boîte de réception par défaut
            if let inbox = folders.first(where: { $0.type == .inbox }) {
                selectedFolder = inbox
            }
        } catch {
            errorMessage = "Erreur de connexion: \(error.localizedDescription)"
        }
    }

    func emailService(for account: MailAccount) -> EmailService? {
        emailServices[account.id]
    }

    func currentEmailService() -> EmailService? {
        guard let account = selectedAccount else { return nil }
        return emailServices[account.id]
    }

    // MARK: - Compose

    func composeNewEmail() {
        composeContext = ComposeContext(mode: .new)
        isComposing = true
    }

    func reply(to email: Email) {
        composeContext = ComposeContext(mode: .reply(email))
        isComposing = true
    }

    func replyAll(to email: Email) {
        composeContext = ComposeContext(mode: .replyAll(email))
        isComposing = true
    }

    func forward(_ email: Email) {
        composeContext = ComposeContext(mode: .forward(email))
        isComposing = true
    }
}

// MARK: - Compose Context

struct ComposeContext {
    enum Mode {
        case new
        case reply(Email)
        case replyAll(Email)
        case forward(Email)
    }

    let mode: Mode

    var to: [String] {
        switch mode {
        case .new:
            return []
        case .reply(let email):
            return [email.from.email]
        case .replyAll(let email):
            var recipients = email.to.map(\.email) + [email.from.email]
            // Remove duplicates
            return Array(Set(recipients))
        case .forward:
            return []
        }
    }

    var subject: String {
        switch mode {
        case .new:
            return ""
        case .reply(let email), .replyAll(let email):
            let subject = email.subject
            return subject.hasPrefix("Re:") ? subject : "Re: \(subject)"
        case .forward(let email):
            let subject = email.subject
            return subject.hasPrefix("Fwd:") ? subject : "Fwd: \(subject)"
        }
    }

    var body: String {
        switch mode {
        case .new:
            return ""
        case .reply(let email), .replyAll(let email):
            return "\n\n---\nLe \(email.date.formatted()), \(email.from.displayName) a écrit :\n\n\(email.bodyText)"
        case .forward(let email):
            return "\n\n---\nMessage transféré :\nDe: \(email.from.displayName) <\(email.from.email)>\nDate: \(email.date.formatted())\nObjet: \(email.subject)\n\n\(email.bodyText)"
        }
    }
}
