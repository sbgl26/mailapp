import SwiftUI

struct MailboxView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: MailboxViewModel
    @ObservedObject var searchVM: SearchViewModel
    @State private var showFilterOptions = false

    var body: some View {
        VStack(spacing: 0) {
            // Barre de filtre
            filterBar

            Divider()

            // Liste des emails
            if viewModel.isLoading && viewModel.emails.isEmpty {
                ProgressView("Chargement...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedItems.isEmpty {
                emptyState
            } else {
                emailList
            }
        }
        .navigationTitle(appState.selectedFolder?.displayName ?? "Emails")
        .searchable(text: $searchVM.query, prompt: "Rechercher des emails")
        .onChange(of: searchVM.query) { _, _ in
            guard let service = appState.currentEmailService(),
                  let folder = appState.selectedFolder else { return }
            searchVM.performSearch(service: service, folder: folder)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MailboxViewModel.FilterMode.allCases, id: \.self) { mode in
                    FilterChip(
                        title: mode.rawValue,
                        isSelected: viewModel.filterMode == mode
                    ) {
                        viewModel.filterMode = mode
                    }
                }

                Divider()
                    .frame(height: 20)

                Menu {
                    ForEach(MailboxViewModel.SortOrder.allCases, id: \.self) { order in
                        Button {
                            viewModel.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if viewModel.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Toggle("Grouper par conversation", isOn: $viewModel.groupByThread)
                } label: {
                    Label("Trier", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Email List

    private var displayedItems: [EmailThread] {
        if !searchVM.query.isEmpty {
            return searchVM.results.map { EmailThread(id: $0.id, emails: [$0]) }
        }
        return viewModel.displayThreads
    }

    private var emailList: some View {
        List(selection: Binding(
            get: { appState.selectedEmail },
            set: { appState.selectedEmail = $0 }
        )) {
            ForEach(displayedItems) { thread in
                if thread.count == 1, let email = thread.emails.first {
                    EmailRowView(email: email)
                        .tag(email)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            trashSwipeAction(email: email)
                            archiveSwipeAction(email: email)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            readSwipeAction(email: email)
                            starSwipeAction(email: email)
                        }
                        .contextMenu { emailContextMenu(email: email) }
                } else {
                    DisclosureGroup {
                        ForEach(thread.emails) { email in
                            EmailRowView(email: email)
                                .tag(email)
                        }
                    } label: {
                        ThreadRowView(thread: thread)
                    }
                }
            }

            // Load more trigger
            if !viewModel.emails.isEmpty {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        guard let service = appState.currentEmailService(),
                              let folder = appState.selectedFolder else { return }
                        Task {
                            await viewModel.loadMore(service: service, folder: folder)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .refreshable {
            guard let service = appState.currentEmailService(),
                  let folder = appState.selectedFolder else { return }
            await viewModel.refresh(service: service, folder: folder)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.filterMode == .all ? "Aucun email" : "Aucun résultat",
                systemImage: viewModel.filterMode == .all ? "tray" : "magnifyingglass"
            )
        } description: {
            if viewModel.filterMode != .all {
                Text("Aucun email ne correspond au filtre \"\(viewModel.filterMode.rawValue)\"")
            } else {
                Text("Ce dossier est vide")
            }
        }
    }

    // MARK: - Swipe Actions

    private func trashSwipeAction(email: Email) -> some View {
        Button(role: .destructive) {
            guard let service = appState.currentEmailService() else { return }
            Task { try? await service.moveToTrash(email) }
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
    }

    private func archiveSwipeAction(email: Email) -> some View {
        Button {
            guard let service = appState.currentEmailService() else { return }
            Task { try? await service.archiveEmail(email) }
        } label: {
            Label("Archiver", systemImage: "archivebox")
        }
        .tint(.purple)
    }

    private func readSwipeAction(email: Email) -> some View {
        Button {
            guard let service = appState.currentEmailService() else { return }
            Task {
                if email.isRead {
                    try? await service.markAsUnread(email)
                } else {
                    try? await service.markAsRead(email)
                }
            }
        } label: {
            Label(
                email.isRead ? "Non lu" : "Lu",
                systemImage: email.isRead ? "envelope.badge" : "envelope.open"
            )
        }
        .tint(.blue)
    }

    private func starSwipeAction(email: Email) -> some View {
        Button {
            guard let service = appState.currentEmailService() else { return }
            Task { try? await service.toggleStar(email) }
        } label: {
            Label(
                email.isStarred ? "Retirer" : "Favori",
                systemImage: email.isStarred ? "star.slash" : "star.fill"
            )
        }
        .tint(.yellow)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func emailContextMenu(email: Email) -> some View {
        Button { appState.reply(to: email) } label: {
            Label("Répondre", systemImage: "arrowshape.turn.up.left")
        }
        Button { appState.replyAll(to: email) } label: {
            Label("Répondre à tous", systemImage: "arrowshape.turn.up.left.2")
        }
        Button { appState.forward(email) } label: {
            Label("Transférer", systemImage: "arrowshape.turn.up.right")
        }

        Divider()

        Button {
            guard let service = appState.currentEmailService() else { return }
            Task { try? await service.toggleStar(email) }
        } label: {
            Label(email.isStarred ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: email.isStarred ? "star.slash" : "star")
        }

        Button {
            guard let service = appState.currentEmailService() else { return }
            Task {
                email.isRead ? try? await service.markAsUnread(email) : try? await service.markAsRead(email)
            }
        } label: {
            Label(email.isRead ? "Marquer non lu" : "Marquer lu", systemImage: email.isRead ? "envelope.badge" : "envelope.open")
        }

        Divider()

        Button {
            guard let service = appState.currentEmailService() else { return }
            Task { try? await service.archiveEmail(email) }
        } label: {
            Label("Archiver", systemImage: "archivebox")
        }

        Button(role: .destructive) {
            guard let service = appState.currentEmailService() else { return }
            Task { try? await service.moveToTrash(email) }
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.quaternarySystemFill))
                .foregroundStyle(isSelected ? .accent : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thread Row

struct ThreadRowView: View {
    let thread: EmailThread

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: thread.from.initials, isRead: thread.isRead)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.from.displayName.isEmpty ? thread.from.email : thread.from.displayName)
                        .font(.subheadline)
                        .fontWeight(thread.isRead ? .regular : .bold)

                    if thread.count > 1 {
                        Text("\(thread.count)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text(thread.latestDate.emailFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(thread.subject)
                    .font(.subheadline)
                    .fontWeight(thread.isRead ? .regular : .semibold)
                    .lineLimit(1)

                Text(thread.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
