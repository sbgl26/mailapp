import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var mailboxVM = MailboxViewModel()
    @StateObject private var searchVM = SearchViewModel()

    #if os(iOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    #endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            SidebarView()
        } content: {
            MailboxView(viewModel: mailboxVM, searchVM: searchVM)
        } detail: {
            if let email = appState.selectedEmail {
                EmailDetailView(email: email)
            } else {
                ContentUnavailableView(
                    "Sélectionnez un email",
                    systemImage: "envelope",
                    description: Text("Choisissez un message dans la liste")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            mainToolbar
        }
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            MailboxView(viewModel: mailboxVM, searchVM: searchVM)
        } detail: {
            if let email = appState.selectedEmail {
                EmailDetailView(email: email)
            } else {
                ContentUnavailableView(
                    "Sélectionnez un email",
                    systemImage: "envelope",
                    description: Text("Choisissez un message dans la liste")
                )
            }
        }
        .toolbar {
            mainToolbar
        }
        #endif
        .sheet(isPresented: $appState.isComposing) {
            ComposeView()
        }
        .onChange(of: appState.selectedFolder) { _, folder in
            guard let folder, let service = appState.currentEmailService() else { return }
            Task {
                await mailboxVM.loadEmails(service: service, folder: folder)
            }
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.composeNewEmail()
            } label: {
                Label("Nouveau message", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button {
                guard let folder = appState.selectedFolder,
                      let service = appState.currentEmailService() else { return }
                Task {
                    await mailboxVM.refresh(service: service, folder: folder)
                }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        #endif
    }
}
