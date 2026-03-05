import SwiftUI
import UniformTypeIdentifiers

struct ComposeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ComposeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showAttachmentPicker = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Recipients
                recipientFields

                Divider()

                // Subject
                HStack {
                    Text("Objet:")
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)

                    TextField("Objet du message", text: $viewModel.subject)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Attachments bar
                if !viewModel.attachments.isEmpty {
                    attachmentsBar
                    Divider()
                }

                // Body
                TextEditor(text: $viewModel.bodyText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
            }
            .navigationTitle("Nouveau message")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if viewModel.isDirty {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sendEmail()
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Envoyer", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(viewModel.to.isEmpty || viewModel.isSending)
                    .keyboardShortcut(.return, modifiers: .command)
                }

                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        showAttachmentPicker = true
                    } label: {
                        Label("Joindre", systemImage: "paperclip")
                    }
                }
                #else
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button {
                            showAttachmentPicker = true
                        } label: {
                            Image(systemName: "paperclip")
                        }

                        Spacer()

                        if !viewModel.attachments.isEmpty {
                            Text("\(viewModel.attachments.count) pièce(s) jointe(s) - \(viewModel.formattedAttachmentSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                #endif
            }
            .alert("Supprimer le brouillon ?", isPresented: $showDiscardAlert) {
                Button("Supprimer", role: .destructive) { dismiss() }
                Button("Continuer l'édition", role: .cancel) {}
            }
            .alert("Erreur", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .fileImporter(
                isPresented: $showAttachmentPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        viewModel.addAttachment(url: url)
                    }
                }
            }
            .onChange(of: viewModel.isSent) { _, sent in
                if sent { dismiss() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
        .onAppear {
            if let context = appState.composeContext, let account = appState.selectedAccount {
                viewModel.configure(from: context, account: account)
            }
        }
    }

    // MARK: - Recipient Fields

    private var recipientFields: some View {
        VStack(spacing: 0) {
            // To
            recipientField(label: "À:", recipients: $viewModel.to, input: $viewModel.toInput)

            if viewModel.showCC {
                Divider()
                recipientField(label: "Cc:", recipients: $viewModel.cc, input: $viewModel.ccInput)
            }

            if viewModel.showBCC {
                Divider()
                recipientField(label: "Cci:", recipients: $viewModel.bcc, input: $viewModel.bccInput)
            }

            if !viewModel.showCC || !viewModel.showBCC {
                HStack {
                    Spacer()
                    if !viewModel.showCC {
                        Button("Cc") { viewModel.showCC = true }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    if !viewModel.showBCC {
                        Button("Cci") { viewModel.showBCC = true }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                .padding(.trailing)
                .padding(.bottom, 4)
            }
        }
    }

    private func recipientField(label: String, recipients: Binding<[String]>, input: Binding<String>) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
                .padding(.top, 10)

            FlowLayout(spacing: 4) {
                ForEach(recipients.wrappedValue, id: \.self) { recipient in
                    RecipientChip(email: recipient) {
                        viewModel.removeRecipient(recipient, from: &recipients.wrappedValue)
                    }
                }

                TextField("", text: input)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 150)
                    .onSubmit {
                        viewModel.addRecipient(input.wrappedValue, to: &recipients.wrappedValue)
                        input.wrappedValue = ""
                    }
            }
            .padding(8)
        }
        .padding(.horizontal)
    }

    // MARK: - Attachments Bar

    private var attachmentsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.attachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: attachment.icon)
                            .font(.caption)

                        Text(attachment.filename)
                            .font(.caption)
                            .lineLimit(1)

                        Text(attachment.formattedSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            viewModel.removeAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Send

    private func sendEmail() {
        guard let service = appState.currentEmailService() else { return }
        Task {
            await viewModel.send(service: service)
        }
    }
}

// MARK: - Recipient Chip

struct RecipientChip: View {
    let email: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(email)
                .font(.caption)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.accent.opacity(0.1))
        .foregroundStyle(.accent)
        .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (
            CGSize(width: maxWidth, height: currentY + lineHeight),
            positions
        )
    }
}
