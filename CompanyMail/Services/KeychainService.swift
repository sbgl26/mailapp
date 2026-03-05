import Foundation
import Security

/// Service de gestion sécurisée des mots de passe via le Keychain natif Apple
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.companymail.accounts"

    private init() {}

    func savePassword(_ password: String, for account: MailAccount) throws {
        guard let data = password.data(using: .utf8) else { return }

        // Supprimer l'ancien si existant
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Ajouter le nouveau
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func getPassword(for account: MailAccount) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.readFailed(status)
        }

        return String(data: data, encoding: .utf8)
    }

    func deletePassword(for account: MailAccount) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.keychainKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Erreur sauvegarde Keychain (code: \(status))"
        case .readFailed(let status):
            "Erreur lecture Keychain (code: \(status))"
        case .deleteFailed(let status):
            "Erreur suppression Keychain (code: \(status))"
        }
    }
}
