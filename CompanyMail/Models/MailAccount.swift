import Foundation

struct MailAccount: Identifiable, Codable, Hashable {
    let id: String
    var displayName: String
    var email: String
    var imapServer: String
    var imapPort: Int
    var smtpServer: String
    var smtpPort: Int
    var username: String
    var useSSL: Bool
    var signature: String
    var color: AccountColor
    var folders: [MailFolder]

    // Le mot de passe est stocké dans le Keychain, pas dans le modèle
    var keychainKey: String { "companymail.account.\(id)" }

    init(
        displayName: String,
        email: String,
        imapServer: String = "ssl0.ovh.net",
        imapPort: Int = 993,
        smtpServer: String = "ssl0.ovh.net",
        smtpPort: Int = 465,
        username: String,
        useSSL: Bool = true,
        signature: String = "",
        color: AccountColor = .blue
    ) {
        self.id = UUID().uuidString
        self.displayName = displayName
        self.email = email
        self.imapServer = imapServer
        self.imapPort = imapPort
        self.smtpServer = smtpServer
        self.smtpPort = smtpPort
        self.username = username
        self.useSSL = useSSL
        self.signature = signature
        self.color = color
        self.folders = []
    }

    /// Pré-configuration OVH pour simplifier l'onboarding
    static func ovhPreset(email: String, displayName: String, password: String) -> (MailAccount, String) {
        let account = MailAccount(
            displayName: displayName,
            email: email,
            imapServer: "ssl0.ovh.net",
            imapPort: 993,
            smtpServer: "ssl0.ovh.net",
            smtpPort: 465,
            username: email,
            useSSL: true
        )
        return (account, password)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MailAccount, rhs: MailAccount) -> Bool {
        lhs.id == rhs.id
    }
}

enum AccountColor: String, Codable, CaseIterable {
    case blue, purple, green, orange, red, pink, teal

    var displayName: String {
        switch self {
        case .blue: "Bleu"
        case .purple: "Violet"
        case .green: "Vert"
        case .orange: "Orange"
        case .red: "Rouge"
        case .pink: "Rose"
        case .teal: "Turquoise"
        }
    }
}
