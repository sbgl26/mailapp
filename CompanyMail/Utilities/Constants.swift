import Foundation

enum AppConstants {
    static let appName = "CompanyMail"
    static let bundleId = "com.companymail.app"

    enum OVH {
        static let imapServer = "ssl0.ovh.net"
        static let imapPort = 993
        static let smtpServer = "ssl0.ovh.net"
        static let smtpPort = 465
        static let useSSL = true
    }

    enum Sync {
        static let defaultPageSize = 50
        static let maxPageSize = 200
        static let defaultFetchInterval: TimeInterval = 300 // 5 minutes
        static let idleTimeout: TimeInterval = 1680 // 28 minutes (RFC recommends < 29)
    }

    enum UI {
        static let sidebarMinWidth: CGFloat = 200
        static let listMinWidth: CGFloat = 300
        static let detailMinWidth: CGFloat = 400
        static let avatarSize: CGFloat = 40
        static let avatarSizeLarge: CGFloat = 48
    }

    enum Keychain {
        static let serviceIdentifier = "com.companymail.accounts"
    }
}
