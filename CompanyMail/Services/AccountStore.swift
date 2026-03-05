import Foundation

/// Persistance des comptes mail (sans mots de passe)
final class AccountStore {
    private let userDefaultsKey = "companymail.accounts"

    func loadAccounts() -> [MailAccount] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([MailAccount].self, from: data)
        } catch {
            print("Erreur chargement comptes: \(error)")
            return []
        }
    }

    func saveAccount(_ account: MailAccount) {
        var accounts = loadAccounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        saveAll(accounts)
    }

    func deleteAccount(_ account: MailAccount) {
        var accounts = loadAccounts()
        accounts.removeAll { $0.id == account.id }
        saveAll(accounts)
        try? KeychainService.shared.deletePassword(for: account)
    }

    func saveAll(_ accounts: [MailAccount]) {
        do {
            let data = try JSONEncoder().encode(accounts)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Erreur sauvegarde comptes: \(error)")
        }
    }
}
