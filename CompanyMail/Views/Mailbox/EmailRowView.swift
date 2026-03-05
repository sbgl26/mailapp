import SwiftUI

struct EmailRowView: View {
    let email: Email

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            AvatarView(initials: email.from.initials, isRead: email.isRead)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Top row: sender + date
                HStack {
                    Text(email.from.displayName.isEmpty ? email.from.email : email.from.displayName)
                        .font(.subheadline)
                        .fontWeight(email.isRead ? .regular : .bold)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        if email.isStarred {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        if email.hasAttachments {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(email.date.emailFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Subject
                Text(email.subject)
                    .font(.subheadline)
                    .fontWeight(email.isRead ? .regular : .semibold)
                    .foregroundStyle(email.isRead ? .secondary : .primary)
                    .lineLimit(1)

                // Snippet
                Text(email.snippet.isEmpty ? email.bodyText.prefix(120).description : email.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .opacity(email.isRead ? 0.85 : 1.0)
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let initials: String
    let isRead: Bool
    var size: CGFloat = 40

    private var backgroundColor: Color {
        // Couleur déterministe basée sur les initiales
        let hash = abs(initials.hashValue)
        let colors: [Color] = [.blue, .purple, .green, .orange, .red, .pink, .teal, .indigo, .mint, .cyan]
        return colors[hash % colors.count]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.gradient)
                .frame(width: size, height: size)

            Text(initials)
                .font(.system(size: size * 0.35, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .topTrailing) {
            if !isRead {
                Circle()
                    .fill(.blue)
                    .frame(width: 10, height: 10)
                    .offset(x: 2, y: -2)
            }
        }
    }
}
