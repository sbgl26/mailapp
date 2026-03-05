import Foundation
import KeychainAccess

/// Service de gestion sécurisée des mots de passe via le Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let keychain: Keychain

    private init() {
        keychain = Keychain(service: "com.companymail.accounts")
            .accessibility(.afterFirstUnlock)
            .synchronizable(true) // Sync via iCloud Keychain entre appareils
    }

    func savePassword(_ password: String, for account: MailAccount) throws {
        try keychain.set(password, key: account.keychainKey)
    }

    func getPassword(for account: MailAccount) throws -> String? {
        try keychain.get(account.keychainKey)
    }

    func deletePassword(for account: MailAccount) throws {
        try keychain.remove(account.keychainKey)
    }
}
