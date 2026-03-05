import SwiftUI

@main
struct CompanyMailApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.accounts.isEmpty {
                OnboardingView()
            } else {
                MainView()
            }
        }
        .task {
            await appState.loadAccounts()
        }
    }
}
