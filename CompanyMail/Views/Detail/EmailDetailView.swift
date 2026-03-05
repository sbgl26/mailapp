import SwiftUI
import WebKit

struct EmailDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var email: Email
    @State private var isLoadingBody = false
    @State private var showAllRecipients = false
    @State private var showMoveSheet = false
    @State private var showSnoozeSheet = false

    init(email: Email) {
        _email = State(initialValue: email)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                emailHeader

                Divider()

                // Body
                if isLoadingBody {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if !email.bodyHTML.isEmpty {
                    HTMLEmailView(html: email.bodyHTML)
                        .frame(minHeight: 300)
                } else {
                    Text(email.bodyText)
                        .font(.body)
                        .padding()
                        .textSelection(.enabled)
                }

                // Attachments
                if !email.attachments.isEmpty {
                    attachmentsSection
                }
            }
        }
        .toolbar {
            detailToolbar
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToFolderView(email: email)
        }
        .sheet(isPresented: $showSnoozeSheet) {
            SnoozeView(email: email)
        }
        .task {
            await loadBody()
        }
        .onChange(of: appState.selectedEmail) { _, newEmail in
            if let newEmail {
                email = newEmail
                Task { await loadBody() }
            }
        }
    }

    // MARK: - Header

    private var emailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subject
            Text(email.subject)
                .font(.title2)
                .fontWeight(.bold)
                .textSelection(.enabled)

            // From
            HStack(spacing: 12) {
                AvatarView(initials: email.from.initials, isRead: true, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(email.from.displayName.isEmpty ? email.from.email : email.from.displayName)
                        .font(.headline)

                    Text(email.from.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(email.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Recipients
            if showAllRecipients {
                recipientDetails
            } else {
                Button {
                    showAllRecipients.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("À: \(email.to.map(\.displayName).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !email.cc.isEmpty {
                            Text("+ \(email.cc.count) en copie")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var recipientDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            recipientRow(label: "De", addresses: [email.from])
            recipientRow(label: "À", addresses: email.to)
            if !email.cc.isEmpty {
                recipientRow(label: "Cc", addresses: email.cc)
            }

            Button {
                showAllRecipients = false
            } label: {
                Text("Masquer les détails")
                    .font(.caption)
            }
        }
    }

    private func recipientRow(label: String, addresses: [EmailAddress]) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(addresses.map(\.formatted).joined(separator: ", "))
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    // MARK: - Attachments

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Pièces jointes (\(email.attachments.count))")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(email.attachments) { attachment in
                        AttachmentCardView(
                            attachment: attachment,
                            email: email
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { appState.reply(to: email) } label: {
                Label("Répondre", systemImage: "arrowshape.turn.up.left")
            }
            .keyboardShortcut("r", modifiers: .command)

            Button { appState.replyAll(to: email) } label: {
                Label("Répondre à tous", systemImage: "arrowshape.turn.up.left.2")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button { appState.forward(email) } label: {
                Label("Transférer", systemImage: "arrowshape.turn.up.right")
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                guard let service = appState.currentEmailService() else { return }
                Task { try? await service.archiveEmail(email) }
            } label: {
                Label("Archiver", systemImage: "archivebox")
            }

            Button {
                guard let service = appState.currentEmailService() else { return }
                Task { try? await service.moveToTrash(email) }
            } label: {
                Label("Supprimer", systemImage: "trash")
            }

            Button { showMoveSheet = true } label: {
                Label("Déplacer", systemImage: "folder")
            }

            Button { showSnoozeSheet = true } label: {
                Label("Rappel", systemImage: "clock")
            }

            Button {
                guard let service = appState.currentEmailService() else { return }
                Task { try? await service.toggleStar(email) }
            } label: {
                Label(
                    email.isStarred ? "Retirer favori" : "Favori",
                    systemImage: email.isStarred ? "star.fill" : "star"
                )
            }
        }
    }

    // MARK: - Load Body

    private func loadBody() async {
        guard email.bodyHTML.isEmpty && email.bodyText.isEmpty else { return }
        guard let service = appState.currentEmailService() else { return }

        isLoadingBody = true
        do {
            email = try await service.fetchEmailBody(email: email)
            // Marquer comme lu
            if !email.isRead {
                try? await service.markAsRead(email)
            }
        } catch {
            print("Erreur chargement body: \(error)")
        }
        isLoadingBody = false
    }
}

// MARK: - HTML Email View (WKWebView wrapper)

#if os(macOS)
struct HTMLEmailView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let styledHTML = wrapHTML(html)
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }
}
#else
struct HTMLEmailView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styledHTML = wrapHTML(html)
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }
}
#endif

private func wrapHTML(_ html: String) -> String {
    """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 15px;
            line-height: 1.5;
            color: #1a1a1a;
            padding: 16px;
            margin: 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #e0e0e0; background-color: transparent; }
            a { color: #5ba3f5; }
        }
        img { max-width: 100%; height: auto; }
        blockquote {
            border-left: 3px solid #ccc;
            margin: 8px 0;
            padding-left: 12px;
            color: #666;
        }
        pre { overflow-x: auto; }
        table { max-width: 100%; }
    </style>
    </head>
    <body>\(html)</body>
    </html>
    """
}

// MARK: - Attachment Card

struct AttachmentCardView: View {
    let attachment: Attachment
    let email: Email
    @EnvironmentObject var appState: AppState
    @State private var isDownloading = false

    var body: some View {
        Button {
            downloadAttachment()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: attachment.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 2) {
                    Text(attachment.filename)
                        .font(.caption)
                        .lineLimit(1)

                    Text(attachment.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 90)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isDownloading {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func downloadAttachment() {
        guard let service = appState.currentEmailService() else { return }
        isDownloading = true
        Task {
            do {
                let data = try await service.fetchAttachment(email: email, attachment: attachment)
                await saveAttachment(data: data, filename: attachment.filename)
            } catch {
                print("Erreur téléchargement: \(error)")
            }
            isDownloading = false
        }
    }

    @MainActor
    private func saveAttachment(data: Data, filename: String) async {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
        #else
        // Sur iOS, sauvegarder dans le dossier Documents
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        try? data.write(to: fileURL)
        #endif
    }
}

// MARK: - Move To Folder

struct MoveToFolderView: View {
    let email: Email
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let account = appState.selectedAccount {
                    ForEach(account.folders) { folder in
                        Button {
                            moveToFolder(folder)
                        } label: {
                            HStack {
                                Image(systemName: folder.icon)
                                Text(folder.displayName)
                                Spacer()
                                if folder.path == email.folderPath {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .disabled(folder.path == email.folderPath)
                    }
                }
            }
            .navigationTitle("Déplacer vers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 300, height: 400)
        #endif
    }

    private func moveToFolder(_ folder: MailFolder) {
        guard let service = appState.currentEmailService() else { return }
        Task {
            try? await service.moveEmail(email, to: folder)
            dismiss()
        }
    }
}

// MARK: - Snooze View

struct SnoozeView: View {
    let email: Email
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var snoozeDate = Date()

    private let presets: [(String, Date)] = {
        let cal = Calendar.current
        let now = Date()
        return [
            ("Plus tard aujourd'hui", cal.date(byAdding: .hour, value: 3, to: now)!),
            ("Demain matin", cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: now)!)!),
            ("Lundi prochain", {
                var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                components.weekday = 2 // Monday
                components.hour = 9
                return cal.nextDate(after: now, matching: DateComponents(hour: 9, weekday: 2), matchingPolicy: .nextTime)!
            }()),
            ("Semaine prochaine", cal.date(byAdding: .weekOfYear, value: 1, to: now)!),
        ]
    }()

    var body: some View {
        NavigationStack {
            List {
                Section("Rappels rapides") {
                    ForEach(presets, id: \.0) { preset in
                        Button {
                            snooze(until: preset.1)
                        } label: {
                            HStack {
                                Text(preset.0)
                                Spacer()
                                Text(preset.1.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Date personnalisée") {
                    DatePicker("Rappel", selection: $snoozeDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])

                    Button("Programmer") {
                        snooze(until: snoozeDate)
                    }
                }
            }
            .navigationTitle("Rappel")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 350, height: 400)
        #endif
    }

    private func snooze(until date: Date) {
        guard let service = appState.currentEmailService() else { return }
        Task {
            try? await service.snoozeEmail(email, until: date)
            dismiss()
        }
    }
}
