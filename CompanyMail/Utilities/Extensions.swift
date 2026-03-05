import Foundation
import SwiftUI

// MARK: - Date Extensions

extension Date {
    /// Format intelligent pour les listes d'emails
    var emailFormatted: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(self) {
            return "Hier"
        } else if calendar.isDate(self, equalTo: .now, toGranularity: .weekOfYear) {
            return formatted(.dateTime.weekday(.abbreviated))
        } else if calendar.isDate(self, equalTo: .now, toGranularity: .year) {
            return formatted(.dateTime.day().month(.abbreviated))
        } else {
            return formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
        }
    }
}

// MARK: - String Extensions

extension String {
    /// Supprime les balises HTML du texte
    var strippedHTML: String {
        guard let data = data(using: .utf8) else { return self }
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else { return self }
        return attributed.string
    }

    /// Tronque le texte à une longueur max
    func truncated(to length: Int, trailing: String = "...") -> String {
        if count <= length { return self }
        return String(prefix(length)) + trailing
    }
}

// MARK: - Color Extensions

extension Color {
    init(accountColor: AccountColor) {
        switch accountColor {
        case .blue: self = .blue
        case .purple: self = .purple
        case .green: self = .green
        case .orange: self = .orange
        case .red: self = .red
        case .pink: self = .pink
        case .teal: self = .teal
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Applique une condition à un modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Platform Helpers

#if os(iOS)
extension Color {
    static let quaternarySystemFill = Color(uiColor: .quaternarySystemFill)
}
#else
extension Color {
    static let quaternarySystemFill = Color(nsColor: .quaternaryLabelColor)
}
#endif
