import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        #if os(macOS)
        TabView {
            AccountsSettingsView()
                .tabItem {
                    Label("Comptes", systemImage: "person.2")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("Général", systemImage: "gear")
                }

            NotificationSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Apparence", systemImage: "paintbrush")
                }
        }
        .frame(width: 500, height: 400)
        #else
        NavigationStack {
            List {
                Section("Comptes") {
                    ForEach(appState.accounts) { account in
                        NavigationLink {
                            AccountDetailSettingsView(account: account)
                        } label: {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading) {
                                    Text(account.displayName)
                                    Text(account.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    NavigationLink {
                        OnboardingView()
                    } label: {
                        Label("Ajouter un compte", systemImage: "plus.circle")
                    }
                }

                Section("Général") {
                    NavigationLink { GeneralSettingsView() } label: {
                        Label("Général", systemImage: "gear")
                    }
                    NavigationLink { NotificationSettingsView() } label: {
                        Label("Notifications", systemImage: "bell")
                    }
                    NavigationLink { AppearanceSettingsView() } label: {
                        Label("Apparence", systemImage: "paintbrush")
                    }
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Réglages")
        }
        #endif
    }
}

// MARK: - Accounts Settings

struct AccountsSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            ForEach(appState.accounts) { account in
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.displayName)
                            .fontWeight(.medium)
                        Text(account.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(account.imapServer):\(account.imapPort)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        appState.removeAccount(account)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Account Detail Settings

struct AccountDetailSettingsView: View {
    @EnvironmentObject var appState: AppState
    let account: MailAccount
    @State private var displayName: String
    @State private var signature: String
    @State private var showDeleteAlert = false

    init(account: MailAccount) {
        self.account = account
        _displayName = State(initialValue: account.displayName)
        _signature = State(initialValue: account.signature)
    }

    var body: some View {
        Form {
            Section("Identité") {
                TextField("Nom affiché", text: $displayName)

                LabeledContent("Email") {
                    Text(account.email)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Signature") {
                TextEditor(text: $signature)
                    .frame(minHeight: 100)
            }

            Section("Serveur") {
                LabeledContent("IMAP") {
                    Text("\(account.imapServer):\(account.imapPort)")
                }
                LabeledContent("SMTP") {
                    Text("\(account.smtpServer):\(account.smtpPort)")
                }
                LabeledContent("SSL") {
                    Text(account.useSSL ? "Activé" : "Désactivé")
                }
            }

            Section {
                Button("Supprimer ce compte", role: .destructive) {
                    showDeleteAlert = true
                }
            }
        }
        .navigationTitle(account.email)
        .alert("Supprimer le compte ?", isPresented: $showDeleteAlert) {
            Button("Supprimer", role: .destructive) {
                appState.removeAccount(account)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action supprimera le compte \(account.email) de l'application. Vos emails ne seront pas supprimés du serveur.")
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("companymail.defaultAccount") private var defaultAccountId = ""
    @AppStorage("companymail.fetchInterval") private var fetchInterval = 5
    @AppStorage("companymail.groupByThread") private var groupByThread = true
    @AppStorage("companymail.confirmDelete") private var confirmDelete = true
    @AppStorage("companymail.markReadDelay") private var markReadDelay = 1.0

    var body: some View {
        Form {
            Section("Synchronisation") {
                Picker("Vérifier les nouveaux messages", selection: $fetchInterval) {
                    Text("Toutes les minutes").tag(1)
                    Text("Toutes les 5 minutes").tag(5)
                    Text("Toutes les 15 minutes").tag(15)
                    Text("Toutes les 30 minutes").tag(30)
                    Text("Manuellement").tag(0)
                }
            }

            Section("Comportement") {
                Toggle("Grouper par conversation", isOn: $groupByThread)

                Toggle("Confirmer avant suppression", isOn: $confirmDelete)

                Picker("Marquer comme lu après", selection: $markReadDelay) {
                    Text("Immédiatement").tag(0.0)
                    Text("1 seconde").tag(1.0)
                    Text("3 secondes").tag(3.0)
                    Text("5 secondes").tag(5.0)
                }
            }
        }
        .padding()
        .navigationTitle("Général")
    }
}

// MARK: - Notification Settings

struct NotificationSettingsView: View {
    @AppStorage("companymail.notifyNewEmail") private var notifyNewEmail = true
    @AppStorage("companymail.notifySound") private var notifySound = true
    @AppStorage("companymail.notifyBadge") private var notifyBadge = true

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Nouveaux emails", isOn: $notifyNewEmail)
                Toggle("Son", isOn: $notifySound)
                Toggle("Badge sur l'icône", isOn: $notifyBadge)
            }
        }
        .padding()
        .navigationTitle("Notifications")
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("companymail.theme") private var theme = "system"
    @AppStorage("companymail.density") private var density = "comfortable"
    @AppStorage("companymail.previewLines") private var previewLines = 2

    var body: some View {
        Form {
            Section("Thème") {
                Picker("Apparence", selection: $theme) {
                    Text("Système").tag("system")
                    Text("Clair").tag("light")
                    Text("Sombre").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Densité") {
                Picker("Densité de la liste", selection: $density) {
                    Text("Compact").tag("compact")
                    Text("Confortable").tag("comfortable")
                    Text("Spacieux").tag("spacious")
                }
                .pickerStyle(.segmented)
            }

            Section("Aperçu") {
                Stepper("Lignes d'aperçu: \(previewLines)", value: $previewLines, in: 0...4)
            }
        }
        .padding()
        .navigationTitle("Apparence")
    }
}
