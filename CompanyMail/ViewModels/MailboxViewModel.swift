import SwiftUI
import Combine

@MainActor
final class MailboxViewModel: ObservableObject {
    @Published var emails: [Email] = []
    @Published var threads: [EmailThread] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var selectedEmails: Set<String> = []
    @Published var sortOrder: SortOrder = .dateDescending
    @Published var filterMode: FilterMode = .all
    @Published var groupByThread = true

    private var currentPage = 0
    private var hasMorePages = true

    enum SortOrder: String, CaseIterable {
        case dateDescending = "Plus récent"
        case dateAscending = "Plus ancien"
        case senderAZ = "Expéditeur A-Z"
        case senderZA = "Expéditeur Z-A"
    }

    enum FilterMode: String, CaseIterable {
        case all = "Tous"
        case unread = "Non lus"
        case starred = "Favoris"
        case attachments = "Pièces jointes"
    }

    var filteredEmails: [Email] {
        var result = emails

        switch filterMode {
        case .all: break
        case .unread: result = result.filter { !$0.isRead }
        case .starred: result = result.filter { $0.isStarred }
        case .attachments: result = result.filter { $0.hasAttachments }
        }

        switch sortOrder {
        case .dateDescending: result.sort { $0.date > $1.date }
        case .dateAscending: result.sort { $0.date < $1.date }
        case .senderAZ: result.sort { $0.from.displayName < $1.from.displayName }
        case .senderZA: result.sort { $0.from.displayName > $1.from.displayName }
        }

        return result
    }

    var displayThreads: [EmailThread] {
        guard groupByThread else {
            return filteredEmails.map { EmailThread(id: $0.id, emails: [$0]) }
        }

        var threadMap: [String: [Email]] = [:]
        for email in filteredEmails {
            let key = normalizeSubject(email.subject)
            threadMap[key, default: []].append(email)
        }

        return threadMap.map { key, emails in
            EmailThread(id: key, emails: emails.sorted { $0.date < $1.date })
        }.sorted { $0.latestDate > $1.latestDate }
    }

    // MARK: - Loading

    func loadEmails(service: EmailService, folder: MailFolder) async {
        isLoading = true
        errorMessage = nil
        currentPage = 0

        do {
            emails = try await service.fetchEmails(folder: folder, page: 0)
            hasMorePages = emails.count >= 50
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh(service: EmailService, folder: MailFolder) async {
        isRefreshing = true
        currentPage = 0

        do {
            emails = try await service.fetchEmails(folder: folder, page: 0)
            hasMorePages = emails.count >= 50
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    func loadMore(service: EmailService, folder: MailFolder) async {
        guard hasMorePages, !isLoading else { return }

        currentPage += 1
        do {
            let more = try await service.fetchEmails(folder: folder, page: currentPage)
            emails.append(contentsOf: more)
            hasMorePages = more.count >= 50
        } catch {
            currentPage -= 1
        }
    }

    // MARK: - Batch Actions

    func markSelectedAsRead(service: EmailService) async {
        for id in selectedEmails {
            if let email = emails.first(where: { $0.id == id }) {
                try? await service.markAsRead(email)
            }
        }
        selectedEmails.removeAll()
    }

    func deleteSelected(service: EmailService) async {
        for id in selectedEmails {
            if let email = emails.first(where: { $0.id == id }) {
                try? await service.moveToTrash(email)
                emails.removeAll { $0.id == id }
            }
        }
        selectedEmails.removeAll()
    }

    func archiveSelected(service: EmailService) async {
        for id in selectedEmails {
            if let email = emails.first(where: { $0.id == id }) {
                try? await service.archiveEmail(email)
                emails.removeAll { $0.id == id }
            }
        }
        selectedEmails.removeAll()
    }

    // MARK: - Helpers

    private func normalizeSubject(_ subject: String) -> String {
        var s = subject
        let prefixes = ["Re:", "RE:", "Fwd:", "FWD:", "Fw:", "FW:", "re:", "fwd:", "fw:"]
        for prefix in prefixes {
            while s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return s
    }
}
