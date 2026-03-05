import SwiftUI
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [Email] = []
    @Published var isSearching = false
    @Published var searchScope: SearchScope = .currentFolder
    @Published var recentSearches: [String] = []

    private var searchTask: Task<Void, Never>?
    private let maxRecentSearches = 10

    enum SearchScope: String, CaseIterable {
        case currentFolder = "Dossier actuel"
        case allFolders = "Tous les dossiers"
    }

    // MARK: - Search with debounce

    func performSearch(service: EmailService, folder: MailFolder?) {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        searchTask = Task {
            // Debounce 300ms
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isSearching = true

            do {
                if let folder, searchScope == .currentFolder {
                    results = try await service.searchEmails(query: query, folder: folder)
                } else {
                    // Recherche dans tous les dossiers
                    var allResults: [Email] = []
                    for f in service.folders {
                        let folderResults = try await service.searchEmails(query: query, folder: f)
                        allResults.append(contentsOf: folderResults)
                    }
                    results = allResults.sorted { $0.date > $1.date }
                }
            } catch {
                if !Task.isCancelled {
                    results = []
                }
            }

            if !Task.isCancelled {
                isSearching = false
                addToRecentSearches(query)
            }
        }
    }

    func clearSearch() {
        query = ""
        results = []
        searchTask?.cancel()
    }

    // MARK: - Recent Searches

    private func addToRecentSearches(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        recentSearches.removeAll { $0 == trimmed }
        recentSearches.insert(trimmed, at: 0)

        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }

        UserDefaults.standard.set(recentSearches, forKey: "companymail.recentSearches")
    }

    func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "companymail.recentSearches") ?? []
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "companymail.recentSearches")
    }
}
