import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: OnboardingStep = .welcome
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var imapServer = "ssl0.ovh.net"
    @State private var imapPort = "993"
    @State private var smtpServer = "ssl0.ovh.net"
    @State private var smtpPort = "465"
    @State private var useSSL = true
    @State private var showAdvanced = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    enum OnboardingStep {
        case welcome
        case credentials
        case connecting
        case success
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                switch step {
                case .welcome:
                    welcomeView
                case .credentials:
                    credentialsView
                case .connecting:
                    connectingView
                case .success:
                    successView
                }
            }
            .padding(32)
            .frame(maxWidth: 500)
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 500)
            #endif
            .toolbar {
                if !appState.accounts.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)

            Text("CompanyMail")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("L'email professionnel,\nsimple et efficace.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    // Pré-remplir pour OVH
                    imapServer = "ssl0.ovh.net"
                    imapPort = "993"
                    smtpServer = "ssl0.ovh.net"
                    smtpPort = "465"
                    useSSL = true
                    step = .credentials
                } label: {
                    HStack {
                        Image(systemName: "server.rack")
                        Text("Configurer avec OVH")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    showAdvanced = true
                    step = .credentials
                } label: {
                    Text("Autre serveur IMAP")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Credentials

    private var credentialsView: some View {
        VStack(spacing: 20) {
            Text("Connexion")
                .font(.title)
                .fontWeight(.bold)

            Text("Entrez vos identifiants OVH")
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nom affiché")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Jean Dupont", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Adresse email")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("jean@votresociete.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mot de passe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Mot de passe", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                // Advanced settings
                if showAdvanced {
                    advancedSettings
                }

                if !showAdvanced {
                    Button {
                        showAdvanced.toggle()
                    } label: {
                        HStack {
                            Text("Paramètres avancés")
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding()
                .background(.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            HStack {
                Button {
                    step = .welcome
                } label: {
                    Text("Retour")
                }

                Spacer()

                Button {
                    connectAccount()
                } label: {
                    Text("Se connecter")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(email.isEmpty || password.isEmpty || isConnecting)
            }
        }
    }

    private var advancedSettings: some View {
        VStack(spacing: 12) {
            Divider()

            Text("Serveur IMAP")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                TextField("Serveur IMAP", text: $imapServer)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $imapPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            Text("Serveur SMTP")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                TextField("Serveur SMTP", text: $smtpServer)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $smtpPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            Toggle("Utiliser SSL/TLS", isOn: $useSSL)
        }
    }

    // MARK: - Connecting

    private var connectingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Connexion en cours...")
                .font(.title3)

            Text("Vérification des paramètres IMAP/SMTP")
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Connecté !")
                .font(.title)
                .fontWeight(.bold)

            Text("Votre compte \(email) est prêt.")
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Commencer")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Connect

    private func connectAccount() {
        isConnecting = true
        errorMessage = nil
        step = .connecting

        let account = MailAccount(
            displayName: displayName,
            email: email,
            imapServer: imapServer,
            imapPort: Int(imapPort) ?? 993,
            smtpServer: smtpServer,
            smtpPort: Int(smtpPort) ?? 465,
            username: email,
            useSSL: useSSL
        )

        Task {
            do {
                // Sauvegarder le mot de passe dans le Keychain
                try KeychainService.shared.savePassword(password, for: account)

                // Tenter la connexion
                await appState.addAccount(account)

                step = .success
            } catch {
                errorMessage = error.localizedDescription
                step = .credentials
            }
            isConnecting = false
        }
    }
}
