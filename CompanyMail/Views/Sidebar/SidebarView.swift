import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var isAddingAccount = false

    var body: some View {
        List(selection: $appState.selectedFolder) {
            if appState.accounts.count > 1 {
                // Multi-compte : afficher par compte
                ForEach(appState.accounts) { account in
                    Section(account.displayName) {
                        ForEach(account.folders) { folder in
                            FolderRowView(folder: folder)
                                .tag(folder)
                        }
                    }
                }
            } else if let account = appState.accounts.first {
                // Mono-compte : afficher directement
                Section("Boîte mail") {
                    ForEach(systemFolders(for: account)) { folder in
                        FolderRowView(folder: folder)
                            .tag(folder)
                    }
                }

                let custom = customFolders(for: account)
                if !custom.isEmpty {
                    Section("Dossiers") {
                        ForEach(custom) { folder in
                            FolderRowView(folder: folder)
                                .tag(folder)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("CompanyMail")
        #if os(macOS)
        .frame(minWidth: 200)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                accountMenu
            }
            #else
            ToolbarItem {
                accountMenu
            }
            #endif
        }
        .sheet(isPresented: $isAddingAccount) {
            OnboardingView()
        }
    }

    private var accountMenu: some View {
        Menu {
            if appState.accounts.count > 1 {
                ForEach(appState.accounts) { account in
                    Button {
                        appState.selectedAccount = account
                    } label: {
                        Label(account.email, systemImage: account.id == appState.selectedAccount?.id ? "checkmark.circle.fill" : "person.circle")
                    }
                }
                Divider()
            }

            Button {
                isAddingAccount = true
            } label: {
                Label("Ajouter un compte", systemImage: "plus.circle")
            }

            Divider()

            NavigationLink {
                SettingsView()
            } label: {
                Label("Réglages", systemImage: "gear")
            }
        } label: {
            Label("Compte", systemImage: "person.circle")
        }
    }

    private func systemFolders(for account: MailAccount) -> [MailFolder] {
        account.folders.filter { $0.type != .custom }
    }

    private func customFolders(for account: MailAccount) -> [MailFolder] {
        account.folders.filter { $0.type == .custom }
    }
}

struct FolderRowView: View {
    let folder: MailFolder

    var body: some View {
        HStack {
            Image(systemName: folder.icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(folder.displayName)

            Spacer()

            if folder.unreadCount > 0 {
                Text("\(folder.unreadCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    private var iconColor: Color {
        switch folder.type {
        case .inbox: .blue
        case .sent: .green
        case .drafts: .orange
        case .trash: .red
        case .spam: .yellow
        case .archive: .purple
        case .starred: .yellow
        case .snoozed: .orange
        default: .secondary
        }
    }
}
